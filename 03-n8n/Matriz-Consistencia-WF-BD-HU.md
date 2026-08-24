# Matriz de Consistencia — Workflows n8n ↔ BD ↔ HU ↔ Flujos

> **Fecha:** 2026-08-24 · **Base:** [[workflows]] v1.0 × schema SQL **v2** × [[01-Backlog-Historias-de-Usuario]] (148 HU) × diagramas de flujo (ERD §13, workflows §69-83) × wireframes.
> **Regla de oro verificada:** n8n orquesta; PostgreSQL decide. Cada WF crítico llama exactamente a una RPC transaccional.

## 1. Matriz principal

| WF | Responsabilidad | Tablas | Funciones/RPC (schema v2) | HU | Flujo/Diagrama | Wireframes | Estado |
|----|----------------|--------|---------------------------|-----|----------------|------------|--------|
| **00** Error Handler Global | Captura 4xx/5xx/timeout; backoff 1/2/4/8 s; error técnico ≠ pago inválido | `tbl_logs_auditoria` | `fn_auditar_cambio` (triggers) | 126, 146 | §61-64 | — | ✅ |
| **01** OpenWA Incoming | Webhook POST `/webhooks/whatsapp/openwa` | `tbl_whatsapp_eventos` | `fn_registrar_evento_whatsapp` | 120, 143 | §8 / diagrama §2 | — | ✅ v2 (antes sin idempotencia) |
| **02** Meta Incoming | GET verify + POST →200 inmediato | `tbl_whatsapp_eventos` | `fn_registrar_evento_whatsapp` | 121, 143 | §9-11 | — | ✅ v2 |
| **03** Normalizador | Contrato único {provider, message_id, phone, type…} | — (transformación) | — | 122 | §12 | — | ✅ |
| **04** Router Conversacional | imagen→21 · texto→SKU/reserva/ayuda; estados IDLE…PEDIDO_CONFIRMADO | `tbl_canal_whatsapp`, `tbl_usuario_comercio` | `fn_identificar_comercio_por_whatsapp` ⭐v2 | 123 | §14-17 | — | ✅ v2 (A2 resuelto) |
| **10** Solicitud SKU | Normaliza SKU→RPC atómica | `tbl_inventario`,`tbl_reservas`,`tbl_pedidos` | `fn_solicitar_reserva` (+`fn_upsert_cliente`) | 037–041 | §18-21 / ERD §13 | — | ✅ |
| **11** Crear Reserva | (fusionado en 10 vía RPC) | idem | idem | 041, 050 | §22 | — | ✅ |
| **12** Lista de espera | SIN_STOCK → alta con posición | `tbl_lista_espera` | `fn_agregar_lista_espera` | 043–044 | §23-25 | — | ✅ |
| **13** Notificar lista | Al liberarse stock: posición #1 NOTIFICADO | `tbl_lista_espera` | `fn_notificar_siguiente_lista_espera` (`SKIP LOCKED`) | 045 | §26-28 | 13 | ✅ |
| **14** Aceptar oportunidad | "SI" → reserva atómica o VENCIDO | `tbl_lista_espera` | `fn_aceptar_lista_espera` | 046–049 | §29 | 28 | ✅ |
| **20** Generar QR | Cobro del pedido; envía QR estático tienda | `tbl_qr_cobros`,`tbl_metodos_pago` | `fn_generar_cobro` ⭐v2 | 056, 042 | §30-31 | 05, 23 | ✅ v2 (A4 resuelto) |
| **21** Recibir comprobante | Media→Storage→comprobante RECIBIDO | Storage + `tbl_comprobantes_pago` | insert directo (service_role) o `fn_upsert_cliente` previo | 057–058 | §32-36 | 24 | ✅ |
| **22** GPT-4o Vision | Extracción estructurada JSON (NO decide) | `tbl_verificaciones` | resultado vía 23/24 | 059 | §37-39 | 06 | ✅ |
| **23** Verificar comprobante | Orquesta: iniciar → IA → validar → resolver | `tbl_verificaciones` | `fn_iniciar_verificacion` ⭐v2 + `fn_confirmar_pago`/`fn_rechazar_verificacion` | 060–064, **141** | §40-46 | 07, 25, 08 | ✅ v2 (A3/A9 resueltos) |
| **24** Confirmar pedido | VALIDO → PAGADO → pedir datos envío | `tbl_pedidos` | dentro de `fn_confirmar_pago` | 078–081, 076 | §46-47 | 07 | ✅ |
| **30** Expiración reservas | Schedule 1 min → RPC única | `tbl_reservas` | `fn_procesar_reservas_vencidas` (cron 12) | 052 | §51-53 | 28 | ✅ v2 (A8: pg_cron activo) |
| **31** Liberación y siguiente | Por variante liberada → siguiente cliente | inventario+lista | `fn_expirar_reserva` + `fn_notificar_siguiente_lista_espera` | 049, 053 | §52 | 28, 34 | ✅ |
| **40** Solicitar datos envío | Estado ESPERANDO_DIRECCION; parse nombre/dir/ref/tel | `tbl_clientes` | `fn_upsert_cliente` | 076–077 | §48 | — | ✅ |
| **41** Crear envío | Solo pedido PAGADO | `tbl_envios` | `fn_crear_envio` | 086 | §49 | 17 | ✅ |
| **42** Seguimiento | Cambios de estado con historial | `tbl_env_seguimiento_estados` | `fn_actualizar_estado_envio` ⭐v2 (máquina de estados) | 092–094, 096 | §50 | 16, 30, 19 | ✅ v2 (A5 resuelto) |
| **50** Verificar saldo | Consulta para app/n8n | `tbl_cuentas_creditos` | select RLS admin | 066 | §17 créditos | 14, 03 | ✅ |
| **51** Consumo | Descuento atómico al verificar | cuentas+movimientos | `fn_consumir_creditos` (usado por `fn_iniciar_verificacion`) | 067–069 | §43 | 08 | ✅ |
| **52** Devolución | Fallo técnico devuelve crédito | movimientos | `fn_acreditar_creditos(DEVOLUCION)` | **146**, 070 | §63 | — | ✅ (HU añadida) |
| **60** Auditoría | Toda operación crítica | `tbl_logs_auditoria` | triggers `trg_audit_*` ⭐v2 activos | 127–131 | §65 | — | ✅ v2 (A12) |
| **70** Health Check | Supabase/n8n/OpenWA/Meta/OpenAI | — (infra) | — | 114 | §observabilidad | — | ✅ |
| **80** Send WhatsApp | Único punto de salida; cola+rate-limit+breaker; respeta opt-out | `tbl_contact_preferences`, cola lógica | `fn_cliente_optado` ⭐v2 (check pre-envío) | 124, 142, 144–145 | política §9-14 | — | ✅ v2 (G1/G3 parcialmente en BD; cola/breaker = capa n8n) |

⭐ = función añadida/existente modificada en el schema v2.

## 2. Cobertura cruzada resumida

| Dimensión | Cobertura |
|---|---|
| 26 workflows definidos ↔ matriz | **26/26 mapeados** a tablas+función+HU |
| HU de sistema/backend (E07,E09-E14,E19-E21) | cubiertas por ≥1 WF o RPC |
| Funciones v2 (36) usadas por workflows | todas las operativas; helpers tenancy/RLS son internos |
| Estados conversacionales §16 ↔ flujos | ESPERANDO_SKU→RESERVA_ACTIVA→ESPERANDO_COMPROBANTE→PAGO_VALIDANDO→ESPERANDO_DIRECCION→PEDIDO_CONFIRMADO: cada transición tiene WF+RPC ✅ |

## 3. Inconsistencias que esta matriz cierra (heredadas de auditorías)

| Antes (workflows v1.0) | Ahora (schema v2) |
|---|---|
| WF-04 sin forma de resolver comercio por número (A2) | `tbl_canal_whatsapp` + `fn_identificar_comercio_por_whatsapp` |
| WF-23 dependía de `fn_procesar_verificacion_ia_atomica` inexistente (A3) | `fn_iniciar_verificacion` transaccional |
| WF-20 sin RPC de cobro (A4) | `fn_generar_cobro` con referencia `RS-{numero_pedido}` |
| WF-42 insertaba seguimiento sin validar máquina de estados (A5) | `fn_actualizar_estado_envio` con transiciones válidas |
| Webhooks duplicados sin control (A6) | `tbl_whatsapp_eventos` + `fn_registrar_evento_whatsapp` |
| Rechazo cancelaba pedido (A9) vs reenvío (HU-065) | pedido vuelve a `ESPERANDO_PAGO` con `puede_reenviar=true` |
| n8n/service_role fallaba checks de tenancy dentro de funciones | `fn_es_service_role()` como bypass controlado |

## 4. Pendientes fuera del alcance BD (documentados, no bloquean)

- Cola física + rate limiter + circuit breaker: implementación n8n/app (HU-144/145); la BD ya expone opt-out y eventos.
- Decisión I4 (alta self-service vs SuperAdmin) antes de habilitar HU-002 en producción.
- HU-147 expiración de créditos: requiere decisión comercial (enum EXPIRACION ya soportado).
