-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 46 (2026-09-11)
-- Trigger: push al crearse una reserva ACTIVA (Fase 2 notificaciones)
-- ============================================================
-- Cada INSERT de reserva ACTIVA dispara pg_net (fire-and-forget) a la Edge
-- Function interna `notificar-reserva-sucursal`, que avisa por FCM a los
-- ADMIN/CAJERO con vínculo activo a (comercio, sucursal).
-- SECRETOS (nunca en archivos): el trigger lee `rsuelvo_push_webhook_secret`
-- desde supabase_vault (por nombre); la EF valida contra su secreto de entorno
-- PUSH_WEBHOOK_SECRET + FCM_SERVICE_ACCOUNT_JSON (ambos se pegan en el
-- dashboard: Edge Functions → Secrets). Sin n8n (D11 intacto).
-- El push JAMÁS bloquea una venta: cualquier fallo se traga en el EXCEPTION.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_notificar_reserva_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name='rsuelvo_push_webhook_secret'
  limit 1;
  if v_secret is null then
    return new;
  end if;
  perform net.http_post(
    url     => 'https://iwfaktlxebxtocmswdvv.supabase.co/functions/v1/notificar-reserva-sucursal',
    body    => jsonb_build_object('id_reserva', NEW.id_reserva),
    headers => jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret)
  );
  return new;
exception when others then
  return new;
end;
$function$;

-- == TRIGGERS ==
DROP TRIGGER IF EXISTS trg_reserva_push ON rsuelvo.tbl_reservas;
CREATE TRIGGER trg_reserva_push
AFTER INSERT ON rsuelvo.tbl_reservas
FOR EACH ROW
WHEN (NEW.estado = 'ACTIVA')
EXECUTE FUNCTION rsuelvo.fn_notificar_reserva_push();
