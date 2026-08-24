-- ============================================================
-- RSUELVO :: CRON / EXPIRACIONES PROGRAMADAS
-- Archivo 12/12 del schema separado
-- Ejecutar en orden. Idempotente. Esquema: rsuelvo
-- ============================================================

set search_path = rsuelvo, public;

-- Alternativa A (recomendada): pg_cron llama directo a la función transaccional.
select cron.schedule(
  'rsuelvo_expirar_reservas',
  '* * * * *',
  $$select rsuelvo.fn_procesar_reservas_vencidas(200);$$
);

-- Alternativa B: Schedule Trigger de n8n (WF-30) -> RPC fn_procesar_reservas_vencidas()
-- y luego WF-31 -> fn_notificar_siguiente_lista_espera() por variante liberada.
-- Nunca implementar la lógica de expiración dentro de n8n.
