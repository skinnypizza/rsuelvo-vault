-- RSUELVO SQL source patch 103 — payment RPC authorization hardening.
-- NOT APPLIED. Validate the complete migration and external-side-effect neutralization on STAGING first.
-- Source function bodies were checked against current production pg_proc.prosrc hashes on 2026-09-24.
-- fn_iniciar_verificacion is service-role/backend-only because p_forzar can affect credit enforcement.
-- fn_confirmar_pago / fn_rechazar_verificacion preserve Flutter cashier/admin use via fn_puede_verificar.
-- Legacy global phone lookups remain unusable to anon/authenticated; WF14 must be replaced before Python authority.
BEGIN;

-- Harden actor authorization: fn_iniciar_verificacion
CREATE OR REPLACE FUNCTION rsuelvo.fn_iniciar_verificacion(p_id_comprobante uuid, p_codigo_servicio text DEFAULT 'VERIFICACION_COMPROBANTE'::text, p_forzar boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'rsuelvo', 'public'
    AS $$
declare
  v_comp tbl_comprobantes_pago%rowtype;
  v_serv tbl_servicios_creditos%rowtype;
  v_ver uuid;
  v_costo bigint;
begin
  select * into v_comp from tbl_comprobantes_pago
  where id_comprobante=p_id_comprobante for update;

  if not found then
    raise exception 'Comprobante inexistente';
  end if;

  if v_comp.estado not in ('RECIBIDO') then
    return jsonb_build_object('resultado','ESTADO_NO_VERIFICABLE','estado',v_comp.estado);
  end if;

  select * into v_serv from tbl_servicios_creditos
  where codigo=p_codigo_servicio and activo for share;

  if not found then
    raise exception 'Servicio de créditos inexistente: %',p_codigo_servicio;
  end if;
  v_costo := v_serv.costo_creditos;

  insert into tbl_verificaciones(
    id_comercio,id_comprobante,id_pedido,tipo_verificacion,estado,fecha_inicio
  )
  values(
    v_comp.id_comercio,p_id_comprobante,v_comp.id_pedido,
    p_codigo_servicio,'PROCESANDO',now()
  )
  returning id_verificacion into v_ver;

  begin
    perform 1 from tbl_cuentas_creditos
    where id_comercio=v_comp.id_comercio for update;

    if (select coalesce(saldo_actual,0) from tbl_cuentas_creditos
        where id_comercio=v_comp.id_comercio) < v_costo then
      raise exception 'SALDO_INSUFICIENTE';
    end if;

    perform fn_consumir_creditos(v_comp.id_comercio,v_serv.id_servicio,v_ver);

  exception
    when others then
      if sqlerrm='SALDO_INSUFICIENTE' and not p_forzar then
        update tbl_verificaciones
        set estado='BLOQUEADA',
            resultado=jsonb_build_object('motivo','SIN_CREDITOS'),
            fecha_fin=now()
        where id_verificacion=v_ver;

        return jsonb_build_object(
          'resultado','SIN_CREDITOS',
          'id_verificacion',v_ver,
          'mensaje','Recibimos tu comprobante. El comercio no puede completar la verificación en este momento.'
        );
      else
        update tbl_verificaciones
        set estado='ERROR',
            resultado=jsonb_build_object('error',sqlerrm),
            fecha_fin=now()
        where id_verificacion=v_ver;
        raise;
      end if;
  end;

  update tbl_comprobantes_pago
  set estado='PROCESANDO'
  where id_comprobante=p_id_comprobante;

  return jsonb_build_object('resultado','VERIFICACION_INICIADA','id_verificacion',v_ver);
end;
$$;

-- Harden actor authorization: fn_confirmar_pago
CREATE OR REPLACE FUNCTION rsuelvo.fn_confirmar_pago(p_id_verificacion uuid, p_resultado jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'rsuelvo', 'public'
    AS $$
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

  IF NOT rsuelvo.fn_puede_verificar(v_ver.id_comercio) THEN
    RAISE EXCEPTION 'Sin permiso para verificar pagos en este comercio' USING ERRCODE = '42501';
  END IF;

  -- H-01 (migración 22): guarda de idempotencia por verificación
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

  -- H-12 (migración 25): el pedido no debe confirmarse dos veces
  if exists (select 1 from tbl_pedidos where id_pedido=v_ver.id_pedido and estado='PAGADO') then
    return jsonb_build_object(
      'resultado','YA_PROCESADO',
      'id_pedido', v_ver.id_pedido,
      'mensaje','El pedido ya estaba pagado; no se repiten efectos de inventario.'
    );
  end if;

  -- H-12 (migración 25): la reserva debe seguir viva para poder convertirse en venta
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

  -- D14 (migración 27): consume 1 crédito por venta confirmada en la misma transacción
  -- (SD-1: nunca bloquea la venta; SD-5: los rechazos no consumen; SD-6: aplica a toda venta)
  PERFORM rsuelvo.fn_consumir_credito_venta(v_res.id_comercio, v_ver.id_pedido);

  return jsonb_build_object(
    'resultado','PAGO_CONFIRMADO',
    'id_pedido',v_ver.id_pedido,
    'id_reserva',v_res.id_reserva
  );
end;
$$;

-- Harden actor authorization: fn_rechazar_verificacion
CREATE OR REPLACE FUNCTION rsuelvo.fn_rechazar_verificacion(p_id_verificacion uuid, p_resultado jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'rsuelvo', 'public'
    AS $$
declare
  v_ver tbl_verificaciones%rowtype;
begin
  select * into v_ver
  from tbl_verificaciones
  where id_verificacion=p_id_verificacion
  for update;

  if not found then
    raise exception 'Verificación inexistente';
  end if;

  IF NOT rsuelvo.fn_puede_verificar(v_ver.id_comercio) THEN
    RAISE EXCEPTION 'Sin permiso para verificar pagos en este comercio' USING ERRCODE = '42501';
  END IF;

  update tbl_verificaciones
  set estado='COMPLETADA',
      resultado=p_resultado,
      fecha_fin=now()
  where id_verificacion=p_id_verificacion;

  update tbl_comprobantes_pago
  set estado='INVALIDO'
  where id_comprobante=v_ver.id_comprobante;

  update tbl_pedidos
  set estado='ESPERANDO_PAGO'
  where id_pedido=v_ver.id_pedido
    and estado in ('ESPERANDO_PAGO','PAGO_RECIBIDO','PAGO_VALIDANDO');

  return jsonb_build_object(
    'resultado','PAGO_RECHAZADO',
    'id_pedido',v_ver.id_pedido,
    'pedido','ESPERANDO_PAGO',
    'puede_reenviar',true
  );
end;
$$;

-- No anonymous/PUBLIC access to payment-definer RPCs.
REVOKE ALL ON FUNCTION rsuelvo.fn_iniciar_verificacion(uuid, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rsuelvo.fn_iniciar_verificacion(uuid, text, boolean) TO service_role;
REVOKE ALL ON FUNCTION rsuelvo.fn_confirmar_pago(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rsuelvo.fn_confirmar_pago(uuid, jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION rsuelvo.fn_rechazar_verificacion(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rsuelvo.fn_rechazar_verificacion(uuid, jsonb) TO authenticated, service_role;

-- Legacy lookups resolve customer globally by phone. Keep only server-side execution until WF14 migration.
REVOKE ALL ON FUNCTION rsuelvo.fn_aceptar_pendiente_lista(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rsuelvo.fn_aceptar_pendiente_lista(text) TO service_role;
REVOKE ALL ON FUNCTION rsuelvo.fn_rechazar_pendiente_lista(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rsuelvo.fn_rechazar_pendiente_lista(text) TO service_role;

COMMIT;

-- Verified production source body hashes: fn_iniciar_verificacion: 315894f9e073c2a6724f3af6943c36df, fn_confirmar_pago: 48cb6a2f6aec3f7f732568857616a19c, fn_rechazar_verificacion: 1db070cdf1eb93fb0a74a6e2a11d61e1
