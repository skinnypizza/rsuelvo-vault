-- Migración 22 (2026-08-29): hallazgos H-01/H-05/H-07 de Auditoría-RSUELVO-2026-08-29
-- H-01 (BLOQUEANTE, Regla de Oro 2): guarda de idempotencia en fn_confirmar_pago —
--   una re-invocación de la misma verificación ya COMPLETADA no repite efectos de inventario.
-- H-05 (Regla de Oro 10): columna de configuración para el rate-limit de WF-80 (antes hardcodeado 20/60s).
-- H-07 (Regla de Oro 9): INSERT directo en tbl_logs_auditoría solo para superadmin;
--   la auditoría normal entra por el trigger fn_auditar_cambio (SECURITY DEFINER) o roles BYPASSRLS.

-- 2.1 Guarda de idempotencia en fn_confirmar_pago (H-01)
CREATE OR REPLACE FUNCTION rsuelvo.fn_confirmar_pago(p_id_verificacion uuid, p_resultado jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
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

  -- H-01: guarda de idempotencia. Si ya se proceso esta verificacion, no repetir efectos de negocio.
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
$function$;

-- 2.2 Config de rate-limit de WhatsApp por comercio (H-05; WF-80 debe leer esto en vez de la constante 20/60s)
ALTER TABLE rsuelvo.tbl_comercio_config
  ADD COLUMN IF NOT EXISTS rate_limit_whatsapp_por_minuto integer NOT NULL DEFAULT 20
    CHECK (rate_limit_whatsapp_por_minuto > 0);

COMMENT ON COLUMN rsuelvo.tbl_comercio_config.rate_limit_whatsapp_por_minuto IS
  'Límite de mensajes salientes de WhatsApp por comercio por ventana de 60s. Usado por WF-80 (Regla de Oro #10 — H-05).';

-- 2.3 Endurecer INSERT de auditoría (H-07): restringe alta directa de logs a superadmin;
--     el resto de la auditoría entra via el trigger fn_auditar_cambio (SECURITY DEFINER)
--     o via roles BYPASSRLS (service_role/postgres usados por n8n).
DROP POLICY IF EXISTS audit_insert ON rsuelvo.tbl_logs_auditoria;
CREATE POLICY audit_insert ON rsuelvo.tbl_logs_auditoria
  FOR INSERT
  WITH CHECK (rsuelvo.fn_es_superadmin());
