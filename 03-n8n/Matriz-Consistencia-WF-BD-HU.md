# Matriz de Consistencia — Workflows n8n ↔ BD ↔ HU ↔ Flujos

> **Fecha:** 2026-08-24 · **Base:** [[workflows]] v1.0 × schema SQL **v2** × [[01-Backlog-Historias-de-Usuario]] (148 HU) × diagramas de flujo (ERD §13, workflows §69-83) × wireframes.
> **Regla de oro verificada:** n8n orquesta; PostgreSQL decide. Cada WF crítico llama exactamente a una RPC transaccional.

## 0. IDs reales en la cuenta n8n ACTIVA (migración rsuelvotest 2026-09-09)

> ⚙️ **Migración 2026-09-09:** cuenta activa = `rsuelvotest.app.n8n.cloud` — los IDs de §0 son los nuevos (`kXui…`, `xFcZ…`, etc.). Los IDs `NpZym…/ACKpE…/…` (cuenta anterior) subsisten como histórico en las filas de §1.



> ⚠️ **H-08 (Auditoría 2026-08-29):** tras la migración a la cuenta trial nueva `rsuelvo.app.n8n.cloud` (ivanluiscardenas), los workflows fueron re-importados y **obtuvieron IDs nuevos**. Los IDs antiguos (`Kem88sByaFk6bUNO`, `TSC1otHnDCr0ADiW`, …) pertenecen a la cuenta agotada `rsuelvo2026.app.n8n.cloud` y se citan en esta matriz solo como histórico de builds. **Los IDs válidos para depuración son los de la tabla siguiente:**

| WF | Nombre | ID real (cuenta activa) | Estado |
|----|--------|------------------------|--------|
| WF-02 | RSU \| 02 \| WhatsApp Meta Incoming | `kXuiHOMTxgR1Lo1O` | ✅ (H-02 corregido; fix eventos stuck 2026-09-08) |
| WF-03 | RSU \| 03 \| WhatsApp Normalizer | `sxmtEb1j2BlwoYXf` | ✅ |
| WF-04 | RSU \| 04 \| WhatsApp Conversational Router | `0fw2ymvAY1hHoV9M` | ✅ |
| WF-10 | RSU \| 10 \| Ventas \| Reserva SKU | `xFcZMG8Hip0Z6aH5` | ✅ |
| WF-12 | RSU \| 12 \| Lista de Espera | `n9VUH43N8i7s9Rn2` | ✅ |
| WF-13 | RSU \| 13 \| Notificar Lista Espera | `Qnr8SYR8sKGnzYKL` | ✅ |
| WF-14 | RSU \| 14 \| Lista \| Aceptar Oportunidad | `JOT4yRctEcogiYzV` | ✅ (Momentos 1 y 2) |
| WF-20 | RSU \| 20 \| Pago \| Generar QR | `1FYWXdVw2swlFYcg` | ✅ |
| WF-21 | RSU \| 21 \| Pago \| Comprobante Entrante | `nJCQI6MfFSjUhywB` | ✅ (H-20 corregido) |
| WF-22 | RSU \| 22 \| Pago \| OCR Comprobante (Gemini) | `53xUuvoriN3fqvHD` | ✅ |
| WF-23 | RSU \| 23 \| Pago \| Verificar Comprobante | `okF8Ayhp5CicRpVU` | ✅ |
| WF-24 | RSU \| 24 \| Pago \| Confirmar Pedido | `JU4QtP0vkAC7m3n1` | ✅ |
| WF-25-A | RSU \| 25 \| Entrega \| A: Solicitar Datos | `gVmvGYVPMlQKWk6z` | ✅ |
| WF-25-B | RSU \| 25 \| Entrega \| B: Registrar Datos | `9doLr3FSewZofRoN` | ✅ (reconstruido 2026-09-08) |
| WF-25-C | RSU \| 25 \| Entrega \| C: Notificar Estado | `2DzqPBe4xtHIuvHA` | ✅ (dedup Regla 7) |
| WF-30 | RSU \| 30 \| Expirar Reservas | `CF7FO9bxV1n9qoKD` | 🗄️ ARCHIVADO (superseded por pg_cron m26) — NO exportar |
| WF-80 | RSU \| 80 \| WhatsApp Gateway | `7V6MIPuGbdx9s0lT` | ✅ |

## 1. Matriz principal

| WF | Responsabilidad | Tablas | Funciones/RPC (schema v2) | HU | Flujo/Diagrama | Wireframes | Estado |
|----|----------------|--------|---------------------------|-----|----------------|------------|--------|
| **00** Error Handler Global | Captura 4xx/5xx/timeout; backoff 1/2/4/8 s; error técnico ≠ pago inválido | `tbl_logs_auditoria` | `fn_auditar_cambio` (triggers) | 126, 146 | §61-64 | — | ✅ |
| **01** OpenWA Incoming | Webhook POST `/webhooks/whatsapp/openwa` | `tbl_whatsapp_eventos` | `fn_registrar_evento_whatsapp` | 120, 143 | §8 / diagrama §2 | — | ✅ v2 (antes sin idempotencia) |
| **02** Meta Incoming | GET verify + POST →200 inmediato | `tbl_whatsapp_eventos` | `fn_registrar_evento_whatsapp` | 121, 143 | §9-11 | — | ✅ v2 |
| **03** Normalizador | Contrato único {provider, message_id, phone, type…} | — (transformación) | — | 122 | §12 | — | ✅ |
| **04** Router Conversacional | Recibe mensaje canónico de WF-03; identifica comercio por Meta PNID o número OpenWA; registra opt-out; enruta imagen/documento→WF-21, SKU→WF-10, SI/NO de oportunidad→WF-14 (**Momento 2 OBS-001**: IF combinator `or` — `is_acceptance` ∨ `text='NO'` — pasa `text` original del mensaje), texto→ayuda. **Bloqueo H3:** no existe `fn_*` canónica de estado conversacional en schema v2; routing actual por tipo/SKU. | `tbl_canal_whatsapp`, `tbl_contact_preferences` | `fn_identificar_comercio_por_phone_number_id` (Meta) · `fn_identificar_comercio_por_whatsapp` (OpenWA) · `fn_registrar_opt_out` (opt-out) | 123, 142 | §14-17 | — | ✅ v2 (H1-H7 aplicados; WF-00 pendiente) |
| **10** Solicitud SKU | Normaliza SKU→resolución RPC→reserva atómica; retorna RESERVA_CREADA / SIN_STOCK / **RESERVA_YA_EXISTENTE** (mismo cliente, reintento sin duplicar). Opción B (H-2): una reserva activa POR CLIENTE por (sucursal,variante); clientes distintos reservan en paralelo mientras haya stock. | `tbl_variantes`,`tbl_inventario`,`tbl_reservas`,`tbl_pedidos` | `fn_resolver_variante_por_sku` + `fn_solicitar_reserva` (+`fn_upsert_cliente`) | 037–041 | §18-21 / ERD §13 · **orquesta→WF-20 (sub-workflow) en rama RESERVA_CREADA; rama SIN_STOCK→**pregunta SI/NO (Momento 1 OBS-001, m35: `fn_pendiente_lista` + msg_payload)**; WF-12 solo se invoca desde WF-14 al responder SI** | — | ✅ v2.15 · OBS-002 msg reserva unificado en WF-20 (v `a7fea328`) · Momento 1 v `fa2dc31b` |
| **11** Crear Reserva | (fusionado en 10 vía RPC) | idem | idem | 041, 050 | §22 | — | ✅ |
| **12** Lista de espera | SIN_STOCK (desde WF-10) → alta atómica con posición (PG; raise `LISTA_DE_ESPERA_LLENA`) | `tbl_lista_espera` | `fn_agregar_lista_espera` (SECURITY DEFINER) | 043–044 | §23-25 | ←WF-14 (Momento 1 SI, m35) | ✅ build publicado `cbFrDQ4awnTHRl48` v`84fff237` · OBS-002 msg "Producto ya reservado" v `eb06f845` (sin mención "sin stock") |
| **13** Notificar lista | Al liberarse stock: posición #1 NOTIFICADO | `tbl_lista_espera` | `fn_notificar_siguiente_lista_espera` (`SKIP LOCKED`) | 045 | §26-28 | 13 | ✅ build publicado VADWZuYe7MsPXIBd v7f530a76-ecf1-41b7-8d42-6a176c1837de · OBS-002 msg oportunidad v `5632aa56` (sku/variante/precio + minutos desde config) |
| **14** Aceptar/rechazar oportunidad | "SI" → reserva atómica o VENCIDO; **"NO" → turno liberado (Momento 2 OBS-001)**: Parse Decision clasifica ACEPTAR/RECHAZAR → RECHAZADO via `fn_rechazar_lista_espera` + notifica siguiente + msg "turno liberado" → WF-80 | `tbl_lista_espera` | `fn_aceptar_lista_espera` · `fn_rechazar_lista_espera` ⭐m31 · `fn_notificar_siguiente_lista_espera` ⭐m32 (turno único) | 046–049 | §29 | 28 | ✅ Momento 2 validado E2E · **Momento 1 (m35)**: sin oportunidad → SI→WF-12 agrega (`fn_aceptar_pendiente_lista`, guarda YA_EN_LISTA) / NO→`fn_rechazar_pendiente_lista` · v `0c31654e` |
| **20** Generar QR | **Sub-workflow de WF-10** (rama RESERVA_CREADA); crea pedido + cobro y envía instrucciones de pago **vía WF-80 (D11)**. | `tbl_reservas`,`tbl_pedidos`,`tbl_pedido_detalles`,`tbl_qr_cobros`,`tbl_metodos_pago` | `fn_crear_pedido_desde_reserva` → `fn_generar_cobro` (ENCADENADAS, ambas transaccionales, SECURITY DEFINER) | 056, 042 | §30-31 | 05, 23 | ✅ v2 (A4 resuelto) |
| **21** Recibir comprobante | Media→Storage→comprobante RECIBIDO; **orquesta→WF-22 (OCR)→WF-23 (verificar)→WF-24 (confirmar)** | Storage + `tbl_comprobantes_pago`, `tbl_pedidos`, `tbl_clientes` | `fn_upsert_cliente` (id_cliente) + **`fn_registrar_comprobante`** (RPC, SECURITY DEFINER, anon — reemplaza INSERT directo; resuelve id_pedido ESPERANDO_PAGO) + `fn_iniciar_verificacion`(p_forzar=false) | 057–058 | §32-36 · **orquesta→WF-22 (`spc0XkjO9b3REguW`)→WF-23 (`Cg7r8oNlCVDSdoXb`)→WF-24 (`xvbVZJl8gdolFY54`)** | 24 | ✅ v2 rewired 21→22→23→24 (publicado `7cdVw8JhbW5JJJtf` v`563e52dc`; fix E2E: URLs absolutas + media_url Meta + filtro id_cliente) |
| **22** GPT-4o Vision | Extracción estructurada JSON (NO decide) — **sub-workflow de WF-21** | `tbl_verificaciones` | resultado vía 23/24; lee `media_url` | 059 | §37-39 · sub-workflow `spc0XkjO9b3REguW` | 06 | 🟡 build creado `spc0XkjO9b3REguW` (inactivo; pendiente publicar) |
| **23** Verificar comprobante | **Sub-workflow de WF-21**: recibe contexto OCR → decide CONFIRMAR/RECHAZAR/MANUAL → `fn_confirmar_pago`/`fn_rechazar_verificacion`; CONFIRMAR encadena WF-24 | `tbl_verificaciones` | `fn_iniciar_verificacion` ⭐v2 + `fn_confirmar_pago`/`fn_rechazar_verificacion` | 060–064, **141** | §40-46 · sub-workflow `Cg7r8oNlCVDSdoXb` | 07, 25, 08 | 🟡 build creado `Cg7r8oNlCVDSdoXb` (inactivo; pendiente publicar) |
| **24** Confirmar pedido | **Sub-workflow de WF-23**: `fn_confirmar_pago` → PAGADO → pide datos envío vía WF-80 | `tbl_pedidos` | dentro de `fn_confirmar_pago` | 078–081, 076 | §46-47 · sub-workflow `xvbVZJl8gdolFY54` | 07 | 🟡 build creado `xvbVZJl8gdolFY54` (inactivo; pendiente publicar) |
| **30** Expiración reservas | Schedule 1 min → RPC única | `tbl_reservas` | `fn_procesar_reservas_vencidas` (cron 12) | 052 | §51-53 | 28 | ✅ v2 (A8: pg_cron NO activo en nube → WF-30 n8n es alternativa canonica 12_cron.sql) · build publicado Sy5hoHc0HzFEgzcl v d3b5ebd3-a644-4f35-82a3-d6d7e5174de5 |
| **31** Liberación y siguiente | Por variante liberada → siguiente cliente | inventario+lista | `fn_expirar_reserva` + `fn_notificar_siguiente_lista_espera` | 049, 053 | §52 | 28, 34 | ✅ cubierto por WF-13 (fn_notificar_siguiente_lista_espera + WF-80) + WF-30 (fn_procesar_reservas_vencidas libera stock) — el notify-next lo hace WF-13 (no hay WF-31 separado) |
| **40** Solicitar datos envío | **Implementado como WF-25-A** (solicitud event-driven tras PAGADO). OBS-003 m33: pide el NOMBRE y luego opciones de punto | `tbl_clientes` | `fn_upsert_cliente` | 076–077 | §48 | — | ✅ · OBS-003 reescribe flujo (selección guiada) |
| **41** Crear envío | **Implementado como WF-25-B** (datos de entrega). OBS-003 m33: registro por `id_punto_entrega` (`fn_registrar_entrega` v2) — sin dirección libre | `tbl_envios`, `tbl_puntos_entrega` ⭐m33 | `fn_registrar_entrega` ⭐v2 m33 | 086 | §49 | 17 | ✅ · m33 pendiente rewrite n8n |
| **42** Seguimiento | Cambios de estado con historial (WF-25-C notifica) | `tbl_env_seguimiento_estados` | `fn_actualizar_estado_envio` ⭐v3 m33 (saltos hacia adelante permitidos — OBS-003) | 092–094, 096 | §50 | 16, 30, 19 | ✅ v3 (m33) |
| **25-A** Entrega Request Datos | Event-driven: trigger pg_net en pedido→PAGADO → pide NOMBRE al comprador (m33: luego opciones de punto) | `tbl_pedidos`, `tbl_logs_auditoria` | — (trigger m30) | 076 | workflows F5 | — | ✅ · rewrite m33 pendiente |
| **25-B** Entrega Registrar Datos | Captura datos → crea envío. **m33/OBS-003: selección guiada** — muestra opciones de `fn_listar_puntos_entrega`, comprador elige número, registro vía `fn_registrar_entrega` v2 (id_punto_entrega). Estado conversacional = pedido PAGADO sin envío (BD decide, sin estado en n8n) | `tbl_envios`, `tbl_puntos_entrega` ⭐m33, `tbl_clientes` | `fn_registrar_entrega` ⭐v2 m33 · `fn_upsert_cliente` | 077, 086 | workflows F5 | — | 🟡 rewrite m33 en curso |
| **25-C** Entrega Notificar Estado | Event-driven: trigger pg_net en envío→estado → notifica al comprador | `tbl_envios`, `tbl_env_seguimiento_estados` | — (trigger m30) | 092–094 | workflows F5 | 16, 30, 19 | ✅ |
| **50** Verificar saldo | Consulta para app/n8n | `tbl_cuentas_creditos` | select RLS admin | 066 | §17 créditos | 14, 03 | ✅ |
| **51** Consumo | Descuento atómico al verificar | cuentas+movimientos | `fn_consumir_creditos` (usado por `fn_iniciar_verificacion`) | 067–069 | §43 | 08 | ✅ |
| **52** Devolución | Fallo técnico devuelve crédito | movimientos | `fn_acreditar_creditos(DEVOLUCION)` | **146**, 070 | §63 | — | ✅ (HU añadida) |
| **60** Auditoría | Toda operación crítica | `tbl_logs_auditoria` | triggers `trg_audit_*` ⭐v2 activos | 127–131 | §65 | — | ✅ v2 (A12) |
| **70** Health Check | Supabase/n8n/OpenWA/Meta/OpenAI | — (infra) | — | 114 | §observabilidad | — | ✅ |
| **80** Send WhatsApp | ÚNICO punto de salida (D11); opt-out sagrado vía `fn_cliente_optado` (Regla 8); **F7 hardening: circuit breaker por provider + rate-limit 20/60s por comercio en static data nativa n8n** (D9); routing Meta/OpenWA por item; envío Graph API Meta/OpenWA por n8n (no MCP Meta, D12) | `tbl_contact_preferences` (opt-out), `tbl_comercio_config` (límites, usado en v2 P2), `tbl_canal_whatsapp` (phone_number_id), `tbl_logs_auditoria` (registro CIRCUIT_OPEN/CLOSED/RATE_LIMIT/whatsapp_send) | `fn_cliente_optado` ⭐v2 (check pre-envío, vía credencial Postgres con bypassrls/U3) | 124, 142, 144–145 | política §9-14 | — | ✅ **F7 hardening PUBLICADO v6 `6f0949bc-6766-4644-82eb-3117636d57ca`** (validado E2E meta+openwa; circuit breaker por provider + rate-limit 20/60s por comercio en static data n8n; routing Meta/OpenWA por item; opt-out/idempotencia intactos). Cola física (tabla+worker) y RL por comercio desde `tbl_comercio_config` = follow-up P2. ID `ISxev9AssaAvQa8z`. |

⭐ = función añadida/existente modificada en el schema v2.

## 2. Cobertura cruzada resumida

| Dimensión                                   | Cobertura                                                                                                                               |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| 26 workflows definidos ↔ matriz             | **26/26 mapeados** a tablas+función+HU                                                                                                  |
| HU de sistema/backend (E07,E09-E14,E19-E21) | cubiertas por ≥1 WF o RPC                                                                                                               |
| Funciones v2 (36) usadas por workflows      | todas las operativas; helpers tenancy/RLS son internos                                                                                  |
| Estados conversacionales §16 ↔ flujos       | ESPERANDO_SKU→RESERVA_ACTIVA→ESPERANDO_COMPROBANTE→PAGO_VALIDANDO→ESPERANDO_DIRECCION→PEDIDO_CONFIRMADO: cada transición tiene WF+RPC ✅ |

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
| WF-10 creaba reserva duplicada en reintentos/carrera primer-reserva (HU-041) | `fn_solicitar_reserva` devuelve **RESERVA_YA_EXISTENTE** (migración 15 + 18, opción B H-2): retorna la reserva activa del MISMO cliente por (sucursal,variante,cliente) sin duplicar filas ni mutar inventario; clientes distintos NO colisionan (reservan en paralelo mientras haya stock) |

## 4. Pendientes fuera del alcance BD (documentados, no bloquean)

- **Rate limiter + circuit breaker (HU-144/145): IMPLEMENTADOS en WF-80 (F7 hardening v6)** en static data nativa n8n — CB por provider (`cb_<provider>`: 5 fallos → abierto 60s; 401/403 abre directo; cierra tras éxito y loguea CIRCUIT_OPEN/CLOSED) y RL por comercio (`rl_<id_comercio>`: 20 envíos/60s, devuelve `rate_limited` y loguea RATE_LIMIT). **Pendiente P2:** cola física (tabla + worker) y RL por comercio leído desde `tbl_comercio_config` (hoy constante hardcodeada 20/60s en el nodo Pre-send Guard, tolerable MVP). La BD ya expone opt-out y eventos.
- Decisión I4 (alta self-service vs SuperAdmin) antes de habilitar HU-002 en producción.
- HU-147 expiración de créditos: **DESCARTADA** (D7). Valor `EXPIRACION` reservado en enum `mov. créditos`.

## 5. Decisiones de diseño resueltas (H-n)

| ID | Decisión | Afecta | Referencia |
|----|----------|--------|------------|
| **H-2 (B)** | Reservas: **una reserva activa POR CLIENTE** por (sucursal, variante). Clientes distintos pueden reservar el mismo SKU en paralelo mientras haya stock disponible (no se bloquean entre sí). Idempotencia se mantiene para el MISMO cliente+SKU: reintentos devuelven `RESERVA_YA_EXISTENTE` con la reserva existente. | `fn_solicitar_reserva` (índice único parcial `uq_reserva_activa_variante_sucursal` ahora `(id_sucursal,id_variante,id_cliente)`), WF-10 (`TSC1otHnDCr0ADiW`), HU-037..041, Regla de Oro 2 | migración `18_reservas_por_cliente` (2026-08-27) |

## 6. Incidencias / Hallazgos H-* (pendientes, por rsuelvo-qa)

> Añadidas por el auditor **rsuelvo-qa** al aplicar H-3/H-4. No bloquean la operación actual de WF-10/WF-20, pero deben cerrarse antes del hardening (F7). Los IDs H-1/H-2 de esta sección son *incidencias* y se distinguen de las decisiones de diseño resueltas en §5.

| ID | Incidencia | Afecta | Estado |
|----|-----------|--------|--------|
| **H-1** | `fn_crear_pedido_desde_reserva` ya **idempotente** (migración 19): reintentos de WF-20 tras fallo parcial no duplican pedido/cobro. WF-20 además envía el QR como **imagen** vía WF-80 (D11). | WF-20 (`BopJBfl3CQ9Ck2YL`, publicado v2 `2947625b`), `fn_crear_pedido_desde_reserva`, `tbl_pedidos`, `tbl_pedido_detalles` | ✅ CERRADO (migración 19) |
| **H-2** | WF-10 ahora dispara WF-20 también en la rama **RESERVA_YA_EXISTENTE** (IF `¿Reserva ya existente?` → `Call WF-20`), reenviando el QR de pago en reintentos; SIN_STOCK sigue sin llamar a WF-20. WF-20 publicado envía la **imagen** del QR (`type:'image'` + `media_url` pública) vía WF-80. | WF-10 (`TSC1otHnDCr0ADiW`, publicado v2 `9f04d398`), WF-20 (`BopJBfl3CQ9Ck2YL`), `fn_solicitar_reserva` | ✅ CERRADO (H-2 en WF-10 + imagen WF-20) |

### 6.b Hallazgos del test E2E OBS-001 Momento 2 (2026-09-07)

| ID | Hallazgo | Afecta | Estado |
|----|----------|--------|--------|
| **H-16** | El cron despertaba WF-13 para un grupo que **ya tenía turno NOTIFICADO vigente** → notificaciones paralelas (FERA01 pos#2 notificada a las 14:48:01 con el turno de pos#1 activo hasta 14:57:40) | `fn_cron_expirar_y_notificar` (guarda del EXISTS) | ✅ RESUELTO — migración 32 (NOT EXISTS turno en vuelo) |
| **H-17** | Un cliente podía acumular **ofertas activas en varias variantes** → SI/NO ambiguo por WhatsApp → "Resolve Opportunity" de WF-14 resolvía arbitrario (`ORDER BY fecha_expiracion ASC`) y **rechazó la oferta equivocada** (FERD01 en vez de FERA01) | `fn_notificar_siguiente_lista_espera` (raíz, BD) + WF-14 `MLgnwfXbg7HnWVHC` (mitigación n8n) | ✅ RESUELTO raíz — migración 32 (salta clientes con oferta activa). 🟡 Mitigación pendiente en WF-14: `ORDER BY fecha_notificacion DESC` (defensa en profundidad) |
| **H-18** | Los turnos NOTIFICADO **nunca vencían a VENCIDO** → ofertas zombis (FERB01 atascada 3 días desde el 04-09) que realimentaban H-17 | `fn_cron_expirar_y_notificar` | ✅ RESUELTO — migración 32 (paso 0: NOTIFICADO + `fecha_expiracion <= now()` → VENCIDO). Validado en vivo: 3 zombis vencidas por el primer tick (15:04:00) |

## 6. Hallazgos de auditoría externa (Auditoría-RSUELVO-2026-08-29)

> Emitida por Claude (conectores Supabase MCP + n8n MCP; Capa C/vault NO verificada por repo privado). Los IDs de estos hallazgos (`Aud-H-xx`) NO colisionan con las incidencias H-1/H-2 de §5. Reporte completo en `~/Escritorio/Auditoria-RSUELVO-2026-08-29.md`.

| ID | Severidad | Resumen | Estado |
|----|-----------|---------|--------|
| **Aud-H-01** | BLOQUEANTE | `fn_confirmar_pago` sin guarda de idempotencia → doble invocación duplicaba stock/movimiento VENTA (Regla 2) | ✅ RESUELTO — migración 22 (guarda `YA_PROCESADO` si verificación `COMPLETADA`) |
| **Aud-H-02** | BLOQUEANTE | WF-02 (`kWGXKtmjdsL2Nrkc`): nodo `Route to WF-03` con éxito y error fusionados en main[0] → `Close Event Error` se ejecuta también en camino feliz (Regla 7) | ⬜ ABIERTO — fix manual n8n (recablear salida error) |
| **Aud-H-03** | ALTO | `pg_cron` SÍ activo (job 1, `* * * * *`, `fn_procesar_reservas_vencidas(200)`) — contradice bitácora previa; decide fuente única de expiración | ⬜ ABIERTO — recomendación: mantener pg_cron (canon `12_cron.sql`) y desactivar WF-30 |
| **Aud-H-04** | ALTO | WF-30 (`CF7FO9bxV1n9qoKD`) Schedule Trigger `field:hours` sin intervalo → dispara cada 1h, no cada 1min | ⬜ ABIERTO — obsoleto si se adopta Aud-H-03(a) |
| **Aud-H-05** | ALTO | WF-80 rate-limit hardcodeado 20/60s (Regla 10) | 🟡 BD RESUELTO — migración 22 columna `rate_limit_whatsapp_por_minuto`; edición WF-80 (leer config) = P2 manual |
| **Aud-H-06** | MEDIO | WF-80: 5 nodos Postgres arman SQL por concatenación JS (historia: binding `queryReplacement` falló en smoke 6; interpolación fue fix deliberado) | ⬜ ABIERTO P2 — reintentar query params con hardening de `esc()` |
| **Aud-H-07** | MEDIO | `audit_insert` permitía INSERT a cualquier usuario con acceso al comercio (log falso, Regla 9) | ✅ RESUELTO — migración 22 (`fn_es_superadmin()` only; n8n usa roles BYPASSRLS, sin impacto) |
| **Aud-H-08** | BAJO | IDs de WFs en docs obsoletos tras re-import | ✅ RESUELTO — §0 de esta matriz |
| **Aud-H-09** | BAJO | Migraciones 20/21 verificadas correctas en cloud (idempotencia reenvío comprobante) | ✅ CONFIRMADO |
| **Aud-H-10** | BAJO | Umbral de confianza OCR 0.8/0.5 hardcodeado en Code node de WF-23 (Regla 10) | ⬜ ABIERTO P2 — proponer columnas config + edición WF-23 |
| **Aud-H-11** | BLOQUEANTE | Triggers `trg_*_updated_at` sobre `tbl_verificaciones`/`tbl_metodos_pago` sin la columna → `record "new" has no field "updated_at"` en el primer INSERT real (dormía desde F0) | ✅ RESUELTO — migración 23 (columnas añadidas) |
| **Aud-H-12** | ALTO | `fn_registrar_comprobante` ligaba comprobantes a pedidos con reserva vencida → confirmaba sobre stock inexistente | ✅ RESUELTO — migración 24 (prefiere pedido con reserva ACTIVA) |
| **Aud-H-13** | BLOQUEANTE | `fn_confirmar_pago` sin validar estado/vigencia de la reserva ni pedido ya PAGADO | ✅ RESUELTO — migración 25 (`RESERVA_VENCIDA` / `YA_PROCESADO`) |
| **Aud-H-14** | MEDIO | WF-22 usaba un **mock de OCR** hardcodeado (TXN123456/Juan Pérez/0.95); nunca hubo IA real | ✅ RESUELTO — extractor real Google Gemini (`gemini-3.6-flash` vía HTTP, `$vars.GEMINI_API_KEY`); Regla 4 intacta. Pendiente: actualizar refs "GPT-4o" del PROMPT §1/§6 |

**Pendientes de auditoría (sin acceso al vault ese día):** inspección profunda de WF-03/04/10/12/13/14/20/21/22; búsqueda de salidas HTTP a Graph API fuera de WF-80 (D11); `get_advisors`; Capa C (Matriz↔realidad) — parcialmente cubierta por esta actualización.
