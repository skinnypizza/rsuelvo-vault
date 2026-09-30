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
