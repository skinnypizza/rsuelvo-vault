-- Migración 26 (2026-08-31): expiración + notificación de lista de espera 100% event-driven
-- Aud-H-03/H-05-WF: pg_cron ya expira reservas en la BD (0 ejecuciones n8n). Esta migración:
--   1. Instala pg_net (HTTP async desde la BD)
--   2. Crea rsuelvo.fn_cron_expirar_y_notificar(): expira reservas y, SOLO si hay grupos
--      en lista de espera con stock disponible, dispara un webhook a n8n (WF-13)
--   3. Reprograma el cron job 1 a la nueva función
-- Resultado: WF-30 se desactiva y WF-13 pasa de polling 1/min a webhook event-driven
-- (~2,880 ejecuciones n8n/día → ~5-10). Regla 3 intacta: la BD decide, n8n orquesta.
-- El webhook lleva un token que WF-13 debe verificar contra $vars.LISTA_ESPERA_TOKEN
-- (valor actual: RSU_lst_notify_9f3Kz71XqW — rotar en producción).
-- Requiere: pg_cron activo con job 1 (12_cron.sql) y WF-13 con Webhook trigger
-- en path `webhooks/lista-espera/notify`.

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION rsuelvo.fn_cron_expirar_y_notificar()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_expiradas integer;
  v_notificables boolean;
  v_http bigint;
BEGIN
  -- 1) Expira reservas vencidas (libera stock, registra movimientos)
  v_expiradas := rsuelvo.fn_procesar_reservas_vencidas(200);

  -- 2) ¿Hay grupos en lista de espera que ya tienen stock disponible?
  SELECT EXISTS (
    SELECT 1
    FROM tbl_lista_espera le
    JOIN tbl_inventario i
      ON i.id_sucursal = le.id_sucursal
     AND i.id_variante = le.id_variante
    WHERE le.estado = 'ESPERANDO'
      AND (i.stock_actual - i.stock_reservado) >= 1
  ) INTO v_notificables;

  -- 3) Si hay trabajo, despierta a WF-13 (event-driven, no polling)
  IF v_notificables THEN
    SELECT net.http_post(
      url    => 'https://rsuelvotest.app.n8n.cloud/webhook/webhooks/lista-espera/notify',
      body   => jsonb_build_object(
        'token', 'RSU_lst_notify_9f3Kz71XqW',
        'motivo', 'waitlist_stock_disponible',
        'fecha', to_char(now() AT TIME ZONE 'America/La_Paz', 'YYYY-MM-DD HH24:MI:SS')
      ),
      headers => jsonb_build_object('Content-Type', 'application/json')
    ) INTO v_http;
  END IF;

  RETURN jsonb_build_object(
    'expiradas', v_expiradas,
    'notificables', v_notificables,
    'http_request_id', v_http
  );
END;
$function$;

-- Reprograma el cron job existente a la función wrapper
SELECT cron.alter_job(1, command => 'select rsuelvo.fn_cron_expirar_y_notificar();');
