-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 47 (2026-09-11)
-- Push v1: 6 eventos (despachador + triggers + cron por-vencer)
-- ============================================================
-- Decisión del dueño: notificar (1) reserva nueva, (2) comprobante recibido,
-- (3) reserva por vencer, (4) envío asignado, (5) stock bajo/agotado,
-- (6) pago confirmado y entrega completada. Teléfono del comprador SOLO para
-- ADMIN; sin horario silencioso.
-- Diseño: triggers AFTER no-mutantes (solo pg_net) + Edge Function
-- `notificar-reserva-sucursal` v2 despachadora por motivo. Secreto solo en
-- supabase_vault (nombre fijo) + secreto de entorno de la EF; nunca en archivos.
-- NO INTERFERENCIA n8n (verificado): ninguna fn_* existente modificada (solo la
-- trigger-fn propia de m46, que n8n no llama); triggers nuevos coexisten con
-- audit/tenant/updated_at y con trg_pedido_pagado_notifica/trg_envio_estado_notifica;
-- el cron es un job nuevo (el existente intacto); la EF es la misma slug.
-- Evento 3: banda 60-120s (≈1 tick normal). Reenvío de comprobante (UPDATE) no
-- dispara evento 2 en v1 (solo INSERT); seguimiento futuro.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_push_evento(p_motivo text, p_payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name='rsuelvo_push_webhook_secret'
  limit 1;
  if v_secret is null then
    return;
  end if;
  perform net.http_post(
    url     => 'https://iwfaktlxebxtocmswdvv.supabase.co/functions/v1/notificar-reserva-sucursal',
    body    => jsonb_build_object('motivo', p_motivo) || coalesce(p_payload, '{}'::jsonb),
    headers => jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret)
  );
exception when others then
  return;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_notificar_reserva_push()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('reserva_nueva', jsonb_build_object('id_reserva', NEW.id_reserva));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_comprobante()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('comprobante_recibido', jsonb_build_object('id_comprobante', NEW.id_comprobante));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_envio()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  if NEW.estado = 'ASIGNADO' then
    perform rsuelvo.fn_push_evento('envio_asignado', jsonb_build_object('id_envio', NEW.id_envio));
  elsif NEW.estado = 'ENTREGADO' then
    perform rsuelvo.fn_push_evento('entrega_completada', jsonb_build_object('id_envio', NEW.id_envio));
  end if;
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('pago_confirmado', jsonb_build_object('id_pedido', NEW.id_pedido));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_stock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('stock_bajo', jsonb_build_object(
    'id_sucursal', NEW.id_sucursal,
    'id_variante', NEW.id_variante,
    'disponible', (NEW.stock_actual - NEW.stock_reservado)
  ));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_cron_notificar_por_vencer()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select id_reserva from tbl_reservas
    where estado='ACTIVA'
      and fecha_expiracion > now() + interval '60 seconds'
      and fecha_expiracion <= now() + interval '120 seconds'
    order by fecha_expiracion
    limit 50
    for update skip locked
  loop
    perform rsuelvo.fn_push_evento('reserva_por_vencer', jsonb_build_object('id_reserva', r.id_reserva));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

-- == TRIGGERS ==
DROP TRIGGER IF EXISTS trg_push_comprobante ON rsuelvo.tbl_comprobantes_pago;
CREATE TRIGGER trg_push_comprobante
AFTER INSERT ON rsuelvo.tbl_comprobantes_pago
FOR EACH ROW
EXECUTE FUNCTION rsuelvo.fn_push_comprobante();

DROP TRIGGER IF EXISTS trg_push_envio ON rsuelvo.tbl_envios;
CREATE TRIGGER trg_push_envio
AFTER UPDATE ON rsuelvo.tbl_envios
FOR EACH ROW
WHEN (NEW.estado IN ('ASIGNADO','ENTREGADO') AND OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION rsuelvo.fn_push_envio();

DROP TRIGGER IF EXISTS trg_push_pedido ON rsuelvo.tbl_pedidos;
CREATE TRIGGER trg_push_pedido
AFTER UPDATE ON rsuelvo.tbl_pedidos
FOR EACH ROW
WHEN (NEW.estado = 'PAGADO' AND OLD.estado IS DISTINCT FROM 'PAGADO')
EXECUTE FUNCTION rsuelvo.fn_push_pedido();

DROP TRIGGER IF EXISTS trg_push_stock ON rsuelvo.tbl_inventario;
CREATE TRIGGER trg_push_stock
AFTER UPDATE ON rsuelvo.tbl_inventario
FOR EACH ROW
WHEN ((NEW.stock_actual - NEW.stock_reservado) <= 5 AND (OLD.stock_actual - OLD.stock_reservado) > 5)
EXECUTE FUNCTION rsuelvo.fn_push_stock();

-- == CRON ==
-- select cron.schedule('rsuelvo_push_por_vencer', '* * * * *',
--   $$select rsuelvo.fn_cron_notificar_por_vencer();$$);
-- (job creado en cloud; espejo en 12_cron.sql)
