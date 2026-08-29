-- ============================================================
-- RSUELVO v2 :: 15. FIX RESERVA_YA_EXISTENTE
-- Migración: rsuelvo_v2_15_fix_reserva_ya_existente
-- WF-10 / HU-037..041 / HU-041 / D2
-- Propósito: evitar duplicar la reserva activa cuando WF-10 reintenta o el
-- comprador envía el SKU dos veces. La constraint uq_reserva_activa_variante_sucursal
-- es (id_sucursal, id_variante) SIN id_cliente, por eso el WHERE no lo incluye.
-- ============================================================

set search_path = rsuelvo, public;

create or replace function fn_solicitar_reserva(
  p_id_comercio uuid,
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_id_cliente uuid,
  p_cantidad integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_inv tbl_inventario%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_reserva uuid;
  v_pedido uuid;
  v_precio numeric(14,2);
  v_reserva_existente uuid;
  v_fecha_expiracion timestamptz;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0';
  end if;

  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;

  select * into v_cfg
  from tbl_comercio_config
  where id_comercio=p_id_comercio;

  if not found then
    raise exception 'El comercio no tiene configuración';
  end if;

  select v.precio into v_precio
  from tbl_variantes v
  join tbl_productos p on p.id_producto=v.id_producto
  where v.id_variante=p_id_variante
    and p.id_comercio=p_id_comercio
    and v.activo
    and p.activo;

  if v_precio is null then
    raise exception 'SKU/variante inválida para el comercio';
  end if;

  -- (15/RESERVA_YA_EXISTENTE) Detección temprana SIN tocar inventario: si ya existe
  -- una reserva activa para la misma (sucursal, variante) — coincidente con la
  -- constraint uq_reserva_activa_variante_sucursal, que NO incluye id_cliente —
  -- devolvemos la existente. FOR UPDATE serializa contra fn_expirar_reserva sobre la
  -- misma fila y evita doble retorno en reintentos concurrentes.
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  for update;

  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;

  -- Bloqueo pesimista: solo una transacción modifica esta fila. Este lock serializa
  -- la carrera primera-reserva/reintento para la misma variante+sucursal.
  select * into v_inv
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;

  if not found then
    return jsonb_build_object(
      'resultado','SIN_STOCK',
      'motivo','NO_EXISTE_INVENTARIO'
    );
  end if;

  -- (15/RESERVA_YA_EXISTENTE) Re-verificación DENTRO del lock de inventario: una
  -- transacción concurrente pudo crear la reserva activa mientras esta esperaba el
  -- lock. Sin esto, la carrera primer-reserva/reintento duplicaría filas (la unique
  -- parcial solo las prohibiría con un error feo). Cerramos la carrera con retorno
  -- elegante y sin mutar inventario.
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  limit 1;

  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;

  if (v_inv.stock_actual-v_inv.stock_reservado) >= p_cantidad then

    update tbl_inventario
    set stock_reservado=stock_reservado+p_cantidad
    where id_inventario=v_inv.id_inventario;

    insert into tbl_reservas(
      id_comercio,id_sucursal,id_variante,id_cliente,
      origen,estado,cantidad,fecha_inicio,fecha_expiracion
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,
      'DIRECTA','ACTIVA',p_cantidad,now(),
      now() + make_interval(mins=>v_cfg.tiempo_reserva_minutos)
    )
    returning id_reserva into v_reserva;

    insert into tbl_inventario_movimientos(
      id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,'RESERVA',
      p_cantidad,'RESERVA',v_reserva,fn_current_usuario_id()
    );

    return jsonb_build_object(
      'resultado','RESERVA_CREADA',
      'id_reserva',v_reserva,
      'fecha_expiracion',(
        select fecha_expiracion from tbl_reservas where id_reserva=v_reserva
      )
    );
  end if;

  return jsonb_build_object(
    'resultado','SIN_STOCK',
    'motivo','PRODUCTO_RESERVADO_O_AGOTADO'
  );
end;
$$;

comment on function fn_solicitar_reserva(uuid,uuid,uuid,uuid,integer) is
  'Reserva atómica de una variante en una sucursal. Retorna RESERVA_CREADA, SIN_STOCK, o RESERVA_YA_EXISTENTE (si ya hay reserva activa para la misma sucursal+variante, sin duplicar ni tocar inventario).';
