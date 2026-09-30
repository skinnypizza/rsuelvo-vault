# QA de flujos n8n en producción — 2026-09-30

## Alcance y resultado

Se está validando el recorrido WhatsApp de RSUELVO en producción con los tenants de prueba Prueba RSUELVO y Celulares. Los mensajes de salida de las pruebas usan destinatarios sintéticos interceptados por WF-80. La auditoría no registra envíos reales para esos destinatarios.

**Estado: en curso; E2E integral no certificado.** No marcar los flujos como perfectos ni cerrar QA hasta completar entrada SKU, comprobante, aprobación de cajero, callbacks de entrega y lista de espera con ejecución observable.

## Hechos comprobados en esta continuación

- WF-80 (`7V6MIPuGbdx9s0lT`) quedó publicado en versión `8b6c840a-d5fb-4e29-9c2c-64666d9e1a8c`, sin warnings. El modo simulado acepta solo Prueba RSUELVO + `QA_SIM_PRUEBA_01` y Celulares + `QA_SIM_CELULARES_01`. Las parejas sintéticas reservadas se simulan aunque falte `simulation_mode`; el flag con tenant o destinatario incorrecto se rechaza antes del HTTP a Meta.
- Dos ejecuciones del arnés manual inactivo `QA-IAM10-DIRECT-PG-SMOKE` dieron, por auditoría de Supabase, dos `whatsapp_send_simulated` y dos `whatsapp_simulation_rejected` cada una. No hubo `whatsapp_send` para los casos QA.
- La resolución de SKU en Supabase mapea `FERA01` a Prueba RSUELVO y `FEE001` a Celulares. El inventario leído antes de probar era FERA01: 5 disponibles/0 reservados; FEE001: 3/0. La consulta de producción no mostró clientes QA con los teléfonos reservados.
- Se agregó un branch al draft QA inactivo para construir mensajes SKU y llamar al WF-04. El MCP contestó `started` (ID reportado 154), pero `search_workflow_executions` devolvió cero y `get_workflow_execution` no encontró la ejecución. Supabase no mostró clientes/reservas/pedidos creados por ese branch. No contar esta llamada como prueba del router ni atribuir un resultado a sus nodos hijos.
- `prepare-community.sh`, `verify-community-package.py` y `py_compile` pasan en el paquete local: 18 workflows, 391 nodos, 94 Code, 25 Postgres y 40 guardas WF-80. Pasan las matrices sintéticas de WF-80, WF-21, WF-02 y WF-22. `scripts/test_local.sh` previamente terminó con 344 passed; es cobertura local de backend, no E2E n8n.

## Pendientes para cerrar

1. Conseguir observabilidad de ejecuciones manuales/subworkflows y completar SKU → reserva → pedido/QR en Prueba RSUELVO y Celulares; comprobar estado por consultas antes/después y no dejar stock reservado.
2. Recorrer comprobante entrante → archivo/OCR o revisión manual → aprobación por cajero → confirmación WhatsApp. No descargar media desde Meta en un test sintético salvo que el medio de prueba sea válido; usar el comprobante de prueba autorizado con el vínculo tenant/pedido correcto.
3. Probar callbacks de entrega repetidos y cada estado relevante con pedido fixture. El riesgo de deduplicación/outbox documentado en la auditoría sigue requiriendo una ruta durable para fallos ambiguos.
4. Crear un único registro sintético elegible de lista de espera y verificar alta idempotente, aviso al siguiente y cron/callback; confirmar que el aviso sale solo por la pareja sintética. El estado consultado antes de esta ronda no tenía filas `ESPERANDO` activas.
5. Reconciliar auditoría de salida (simulados/rechazados/envíos reales) y registros de negocio tras cada caso; retirar fixtures temporales y verificar inventario neto sin cambios.
6. Repetir lint, verificador de paquete y suites locales tras correcciones; después documentar versiones, evidencias y cualquier riesgo restante.

La bitácora técnica detallada está en `/home/nico/rsuelvo-n8n-local/AUDIT-2026-09-29.md` (sección “Continuación de QA — 2026-09-30 13:07 UTC”).

## Ampliación E2E — 2026-09-30 14:18 UTC

- Mediante el webhook POST de WF-02 con payload Meta sintético completé SKU→reserva→pedido/QR→WF-80 en dos tenants: FERA01→Prueba RSUELVO y FEE001→Celulares. Ambos eventos quedaron `PROCESADO` y cada mensaje saliente fue `simulated`. Repetir la misma WAMID de FERA01 no creó otra reserva/pedido ni otro log de salida.
- Las reservas temporales expiraron: stock final FERA01 5/0 reservado y FEE001 3/0 reservado. Quedan dos pedidos QA `ESPERANDO_PAGO` con cobros QR `GENERADO`, ligados a reservas vencidas. La función de aprobación impide confirmar venta con reserva vencida (`RESERVA_VENCIDA`); no existe RPC de cancelación identificada, así que los pedidos sintéticos se conservan para trazabilidad y no se editaron directamente.
- Una prueba con imagen y `media_id` inválido mostró que la respuesta de error podía salir por WF-80 mientras el evento quedaba `PROCESANDO`. Corregí y publiqué WF-02: `Close Event Error1` usa el item original estable y `Route to WF-03` entrega un item vacío cuando el hijo no devuelve resultados. Una segunda prueba cerró el evento `PROCESADO` con respuesta simulada. WF-02 activa `1eaa683d-fd9f-445a-875c-4380a8b47a79`; WF-80 activa `8b6c840a-d5fb-4e29-9c2c-64666d9e1a8c`; ambas coinciden con el borrador.
- Probé lista de espera de punta a punta: FERI01 sin stock creó una pendiente; `SI` registró `ESPERANDO`; una entrada/restauración neta de inventario QA hizo elegible el grupo; WF-13 notificó y WF-80 registró `simulated`; `NO` dejó el turno `RECHAZADO`. Verifiqué tanto el disparo funcional de pg_net (HTTP 200) como el job programado `rsuelvo_expirar_reservas` cada minuto: el job de las 14:18 notificó el único cliente sintético elegible, pg_net obtuvo HTTP 200 (respuesta 155) y WF-80 auditó `simulated`. Un segundo ciclo durante el turno activo devolvió `notificables=false` y no duplicó el envío. El inventario FERI01 terminó en 0/0 y no quedaron entradas activas de espera.
- Entre los smoke/E2E de la sesión hay 17 logs `whatsapp_send_simulated` y 0 logs `whatsapp_send` para los destinatarios reservados. Dos ejecuciones previas de imagen malformada quedaron cerradas como `ERROR` mediante la RPC oficial; la nueva prueba posterior al arreglo quedó `PROCESADO`.
- Continúan pendientes el comprobante válido→OCR/revisión manual→aprobación de cajero→confirmación al comprador y los callbacks de cada estado de entrega. El arnés n8n sigue sin conservar detalle de ejecuciones, por lo que se verificaron cambios con estados/auditoría Supabase. No marcar el QA general como completo.

El orquestador OpenCode fue contactado en su sesión guardada tres veces; respondió error interno de servidor en los tres intentos. El usuario ya había autorizado documentar, hacer commit y push del vault; al fallar OpenCode, el commit `321ea39` se hizo directamente y se subió a `origin/main`. Esta ampliación todavía requiere su siguiente commit/push.
