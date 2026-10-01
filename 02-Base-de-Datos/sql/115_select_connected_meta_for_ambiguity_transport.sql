CREATE OR REPLACE FUNCTION rsuelvo.fn_contexto_por_telefono_v3(p_telefono text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'rsuelvo', 'pg_temp'
AS $function$
DECLARE
  v_tel text := nullif(pg_catalog.btrim(coalesce(p_telefono, '')), '');
  v_context_count integer := 0;
  v_transport_commerce uuid;
  v_transport_count integer := 0;
  v_result jsonb;
BEGIN
  IF v_tel IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('origen', 'DESCONOCIDO');
  END IF;

  WITH matched AS (
    SELECT cl.id_cliente, cl.id_comercio
    FROM rsuelvo.tbl_clientes cl
    JOIN rsuelvo.tbl_comercios co ON co.id_comercio = cl.id_comercio
    WHERE coalesce(cl.telefono_whatsapp, cl.telefono) = v_tel
      AND co.estado = 'ACTIVO'
  ),
  contexts AS (
    SELECT DISTINCT m.id_comercio, m.id_cliente
    FROM matched m
    WHERE EXISTS (
      SELECT 1
      FROM rsuelvo.tbl_pedidos p
      WHERE p.id_comercio = m.id_comercio
        AND p.id_cliente = m.id_cliente
        AND p.estado = 'PAGADO'
        AND NOT EXISTS (SELECT 1 FROM rsuelvo.tbl_envios e WHERE e.id_pedido = p.id_pedido)
        AND EXISTS (SELECT 1 FROM rsuelvo.tbl_entrega_captura ec WHERE ec.id_pedido = p.id_pedido)
    )
    OR EXISTS (
      SELECT 1
      FROM rsuelvo.tbl_lista_pendiente lp
      JOIN rsuelvo.tbl_sucursales su ON su.id_sucursal = lp.id_sucursal
      WHERE lp.id_cliente = m.id_cliente AND su.id_comercio = m.id_comercio
    )
    OR EXISTS (
      SELECT 1
      FROM rsuelvo.tbl_lista_espera le
      WHERE le.id_comercio = m.id_comercio
        AND le.id_cliente = m.id_cliente
        AND le.estado = 'NOTIFICADO'
        AND le.fecha_expiracion > pg_catalog.now()
    )
    OR EXISTS (
      SELECT 1
      FROM rsuelvo.tbl_reservas re
      WHERE re.id_comercio = m.id_comercio
        AND re.id_cliente = m.id_cliente
        AND re.estado IN ('ACTIVA', 'PAGO_VALIDANDO')
    )
    OR EXISTS (
      SELECT 1
      FROM rsuelvo.tbl_pedidos p
      WHERE p.id_comercio = m.id_comercio
        AND p.id_cliente = m.id_cliente
        AND p.estado = 'ESPERANDO_PAGO'
    )
  )
  SELECT pg_catalog.count(*)::integer INTO v_context_count FROM contexts;

  IF v_context_count > 1 THEN
    SELECT pg_catalog.count(DISTINCT ch.id_comercio)::integer,
           (pg_catalog.array_agg(DISTINCT ch.id_comercio))[1]
      INTO v_transport_count, v_transport_commerce
    FROM rsuelvo.tbl_canal_whatsapp ch
    WHERE ch.activo IS TRUE AND ch.provider = 'META' AND ch.status = 'ACTIVO'
      AND ch.provider_phone_number_id IS NOT NULL;

    RETURN pg_catalog.jsonb_build_object(
      'origen', 'AMBIGUO',
      'id_comercio', NULL,
      'transport_commerce_id',
        CASE WHEN v_transport_count = 1 THEN v_transport_commerce ELSE NULL END
    );
  END IF;

  v_result := rsuelvo.fn_contexto_por_telefono(v_tel);
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION rsuelvo.fn_contexto_por_telefono_v3(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rsuelvo.fn_contexto_por_telefono_v3(text) TO service_role;
