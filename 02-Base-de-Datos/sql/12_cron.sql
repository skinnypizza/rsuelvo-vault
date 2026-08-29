-- ============================================================
-- RSUELVO v2 :: 12. CRON — EXPIRACIÓN DE RESERVAS
-- ============================================================

set search_path = rsuelvo, public;

select cron.schedule(
  'rsuelvo_expirar_reservas',
  '* * * * *',
  $$select rsuelvo.fn_procesar_reservas_vencidas(200);$$
);

-- Alternativa n8n: WF-30 (Schedule) -> RPC fn_procesar_reservas_vencidas()
--                  WF-31 -> fn_notificar_siguiente_lista_espera() por variante liberada.
-- Nunca implementar expiración/liberación dentro de n8n.

comment on function fn_solicitar_reserva is
'Reserva atómica de inventario (v2/15). Retorna RESERVA_CREADA, SIN_STOCK, o RESERVA_YA_EXISTENTE cuando ya hay una reserva activa para la misma (sucursal,variante) — sin duplicar filas ni mutar inventario. Bloquea inventario con FOR UPDATE; debe llamarse vía RPC desde n8n/Backend.';

comment on function fn_expirar_reserva is
'Libera stock de una reserva vencida de forma transaccional.';

comment on function fn_notificar_siguiente_lista_espera is
'Selecciona la siguiente posición de la lista con bloqueo SKIP LOCKED y crea la oportunidad de notificación.';

comment on function fn_consumir_creditos is
'Consume créditos de forma atómica usando bloqueo de la cuenta y registra el ledger.';

comment on function fn_confirmar_pago is
'Confirma pago, actualiza pedido/reserva e inventario en una única transacción.';


comment on function fn_identificar_comercio_por_whatsapp is 'Resuelve comercio/sucursal desde el número WhatsApp destino (WF-04). Solo service_role.';
comment on function fn_iniciar_verificacion is 'Crea la verificación y consume créditos en una sola transacción (SIN_CREDITOS -> BLOQUEADA).';
comment on function fn_actualizar_estado_envio is 'Máquina de estados logística validada + registro de seguimiento.';
comment on function fn_generar_cobro is 'Crea el cobro QR con referencia única RS-XXXXXXXX.';
comment on table tbl_variantes is 'SKU v2: 6 caracteres [3 tienda][3 producto] base36. id_comercio denormalizado por trigger.';
comment on table tbl_canal_whatsapp is '1 WhatsApp = 1 tienda. Soporta OpenWA y Meta (política §17).';
comment on table tbl_contact_preferences is 'Opt-out del comprador (política §16 / HU-142).';

commit;
