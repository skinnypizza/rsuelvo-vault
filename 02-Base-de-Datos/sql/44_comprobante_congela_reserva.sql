-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 44 (2026-09-11)
-- El comprobante congela el reloj de la reserva (PAGO_VALIDANDO)
-- ============================================================
-- Decisión del dueño: los 10 minutos corren hasta que llega el comprobante;
-- desde entonces la reserva queda PAGO_VALIDANDO (inmune a
-- fn_procesar_reservas_vencidas, que solo expira ACTIVA) hasta que el cajero
-- confirme/rechace. fn_confirmar_pago ya aceptaba ACTIVA/PAGO_VALIDANDO.
-- Si la reserva venció ANTES de llegar el comprobante, NO revive (stock ya
-- liberado; el comprador reserva de nuevo). Aplica también al reenvío
-- (misma operación, mismo pedido; guardado por WHERE estado='ACTIVA').
-- Nota técnica: UPDATEs calificados con alias (r.) porque RETURNS TABLE expone
-- id_comprobante/id_pedido como OUT params y el nombre desnudo es ambiguo.
-- Validado E2E sintético: reserva ACTIVA → comprobante → PAGO_VALIDANDO.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_comprobante(p_id_comercio uuid, p_id_cliente uuid, p_tipo_archivo text, p_archivo_url text, p_monto_detectado numeric DEFAULT NULL, p_fecha_detectada timestamp with time zone DEFAULT NULL, p_numero_operacion text DEFAULT NULL, p_nombre_pagador text DEFAULT NULL, p_estado rsuelvo.estado_comprobante DEFAULT 'RECIBIDO', p_id_pedido uuid DEFAULT NULL)
 RETURNS TABLE(id_comprobante uuid, id_pedido uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_id_comprobante uuid := gen_random_uuid();
  v_id_pedido uuid := p_id_pedido;
  v_existente uuid;
  v_pedido_existente uuid;
BEGIN
  IF NOT fn_tiene_acceso_comercio(p_id_comercio) THEN
    RAISE EXCEPTION 'Sin acceso al comercio';
  END IF;
  IF v_id_pedido IS NULL THEN
    SELECT p.id_pedido INTO v_id_pedido
    FROM tbl_pedidos p
    JOIN tbl_reservas r ON r.id_pedido = p.id_pedido AND r.estado = 'ACTIVA'
    WHERE p.id_comercio = p_id_comercio
      AND p.id_cliente = p_id_cliente
      AND p.estado = 'ESPERANDO_PAGO'
    ORDER BY p.created_at DESC
    LIMIT 1;
    IF v_id_pedido IS NULL THEN
      SELECT p.id_pedido INTO v_id_pedido
      FROM tbl_pedidos p
      WHERE p.id_comercio = p_id_comercio
        AND p.id_cliente = p_id_cliente
        AND p.estado = 'ESPERANDO_PAGO'
      ORDER BY p.created_at DESC
      LIMIT 1;
    END IF;
  END IF;
  IF v_id_pedido IS NULL THEN
    RAISE EXCEPTION 'No se encontro pedido en espera de pago para vincular el comprobante';
  END IF;
  IF p_numero_operacion IS NOT NULL THEN
    SELECT c.id_comprobante, c.id_pedido
      INTO v_existente, v_pedido_existente
      FROM tbl_comprobantes_pago c
      WHERE c.id_comercio = p_id_comercio
        AND c.numero_operacion = p_numero_operacion
      LIMIT 1;
    IF v_existente IS NOT NULL THEN
      IF v_pedido_existente = v_id_pedido THEN
        UPDATE tbl_comprobantes_pago AS c
           SET tipo_archivo     = p_tipo_archivo,
               archivo_url      = p_archivo_url,
               monto_detectado  = COALESCE(p_monto_detectado, c.monto_detectado),
               fecha_detectada  = COALESCE(p_fecha_detectada, c.fecha_detectada),
               nombre_pagador   = COALESCE(p_nombre_pagador, c.nombre_pagador),
               estado           = p_estado
         WHERE c.id_comprobante = v_existente;
        UPDATE tbl_reservas AS r
        SET estado='PAGO_VALIDANDO'
        WHERE r.id_pedido=v_id_pedido AND r.estado='ACTIVA';
        RETURN QUERY SELECT v_existente, v_id_pedido;
        RETURN;
      ELSE
        RAISE EXCEPTION 'COMPROBANTE_DUPLICADO: el numero de operacion % ya fue registrado para otro pedido', p_numero_operacion;
      END IF;
    END IF;
  END IF;
  INSERT INTO tbl_comprobantes_pago (
    id_comprobante, id_comercio, id_pedido, id_cliente,
    tipo_archivo, archivo_url, monto_detectado, fecha_detectada,
    numero_operacion, nombre_pagador, estado
  ) VALUES (
    v_id_comprobante, p_id_comercio, v_id_pedido, p_id_cliente,
    p_tipo_archivo, p_archivo_url, p_monto_detectado, p_fecha_detectada,
    p_numero_operacion, p_nombre_pagador, p_estado
  );
  UPDATE tbl_reservas AS r
  SET estado='PAGO_VALIDANDO'
  WHERE r.id_pedido=v_id_pedido AND r.estado='ACTIVA';
  RETURN QUERY SELECT v_id_comprobante, v_id_pedido;
END;
$function$;
