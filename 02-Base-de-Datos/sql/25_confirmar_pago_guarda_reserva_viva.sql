-- Migración 25 (2026-08-31): guardas de negocio en fn_confirmar_pago (Regla de Oro 2)
-- H-12: la función no validaba el ESTADO de la reserva ni su vigencia:
--   * confirmaba pedidos cuya reserva ya estaba VENCIDA/LIBERADA (stock ya devuelto)
--   * el decremento de inventario es por pool (sucursal+variante): si otra reserva
--     sostenía el stock, "funcionaba" pero consumiendo el stock de OTRO; si el pool
--     estaba en 0, fallaba con "Inconsistencia de inventario" aunque el error real
--     fuera que la reserva del pedido ya no existía.
-- Guardas añadidas:
--   1. Pedido ya PAGADO → YA_PROCESADO (idempotencia a nivel pedido)
--   2. Reserva debe estar ACTIVA/PAGO_VALIDANDO y NO vencida → si no, RESERVA_VENCIDA
--      (el comprador debe solicitar el SKU de nuevo; WF-23/WF-24 pueden mapear el mensaje)
-- Requiere migraciones previas: 22 (guarda YA_PROCESADO por verificación).

create or replace function fn_confirmar_pago(
  p_id_verificacion uuid,
  p_resultado jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_ver tbl_verificaciones%rowtype;
  v_res tbl_reservas%rowtype;
begin
  select * into v_ver
  from tbl_verificaciones
  where id_verificacion=p_id_verificacion
  for update;

  if not found then
    raise exception 'Verificación inexistente';
  end if;

  -- H-01: guarda de idempotencia por verificación
  if v_ver.estado = 'COMPLETADA' then
    return jsonb_build_object(
      'resultado','YA_PROCESADO',
      'id_pedido', v_ver.id_pedido,
      'mensaje','Esta verificación ya fue confirmada previamente; no se repiten efectos de inventario.'
    );
  end if;

  select * into v_res
  from tbl_reservas
  where id_pedido=v_ver.id_pedido
  for update;

  if not found then
    raise exception 'No existe reserva asociada al pedido';
  end if;

  -- H-12: el pedido no debe confirmarse dos veces
  if exists (select 1 from tbl_pedidos where id_pedido=v_ver.id_pedido and estado='PAGADO') then
    return jsonb_build_object(
      'resultado','YA_PROCESADO',
      'id_pedido', v_ver.id_pedido,
      'mensaje','El pedido ya estaba pagado; no se repiten efectos de inventario.'
    );
  end if;

  -- H-12: la reserva debe seguir viva para poder convertirse en venta
  if v_res.estado not in ('ACTIVA','PAGO_VALIDANDO') or v_res.fecha_expiracion < now() then
    return jsonb_build_object(
      'resultado','RESERVA_VENCIDA',
      'id_pedido', v_ver.id_pedido,
      'mensaje','La reserva expiró. El comprador debe solicitar el SKU nuevamente.'
    );
  end if;

  update tbl_verificaciones
  set estado='COMPLETADA',
      resultado=p_resultado,
      fecha_fin=now()
  where id_verificacion=p_id_verificacion;

  update tbl_comprobantes_pago
  set estado='VALIDO'
  where id_comprobante=v_ver.id_comprobante;

  update tbl_pedidos
  set estado='PAGADO',
      fecha_confirmacion=now()
  where id_pedido=v_ver.id_pedido;

  update tbl_reservas
  set estado='CONFIRMADA',
      fecha_finalizacion=now()
  where id_reserva=v_res.id_reserva;

  update tbl_inventario
  set stock_reservado=stock_reservado-v_res.cantidad,
      stock_actual=stock_actual-v_res.cantidad
  where id_sucursal=v_res.id_sucursal
    and id_variante=v_res.id_variante
    and stock_reservado >= v_res.cantidad
    and stock_actual >= v_res.cantidad;

  if not found then
    raise exception 'Inconsistencia de inventario al confirmar venta';
  end if;

  insert into tbl_inventario_movimientos(
    id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id
  )
  values(
    v_res.id_comercio,v_res.id_sucursal,v_res.id_variante,
    'VENTA',v_res.cantidad,'PEDIDO',v_ver.id_pedido
  );

  return jsonb_build_object(
    'resultado','PAGO_CONFIRMADO',
    'id_pedido',v_ver.id_pedido,
    'id_reserva',v_res.id_reserva
  );
end;
$$;

grant execute on function fn_confirmar_pago(uuid, jsonb) to anon, authenticated, service_role;
