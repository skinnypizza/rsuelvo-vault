# D-IAM-SECURITY-EVENTS — IAM-10 Security Events (REV2 contractual)

**Estado:** CONTRATO REV2 PARA APROBACIÓN · NO IMPLEMENTADO · sin cambios funcionales
**Auditoría:** 2026-09-23 · Vault `728d06f`; Flutter `b3ebaa95c8e4c950a98637835094bea573c0b2bf`; Web `2c4eb51bf440072dafc276488156559ddb975e1a`.
**Entorno LIVE inspeccionado en solo lectura:** Supabase `iwfaktlxebxtocmswdvv` (RSUELVO, ACTIVE_HEALTHY, PostgreSQL 17.6.1.155, plan Free).

> SecurityEvent responde «¿qué evento relevante de seguridad ocurrió?». `tbl_logs_auditoria` continúa respondiendo «¿qué operación de negocio/administrativa ocurrió, quién la ejecutó y sobre qué recurso?» Son fuentes separadas; SecurityEvent no replica cada AuditLog ni cada error.

## 1. Resumen de auditoría real

| Área | Estado encontrado | Consecuencia para IAM-10 |
|---|---|---|
| Repositorios | Los tres `main` están limpios y en los SHAs arriba indicados; IAM-9 documental en `origin/main` (`728d06f`). | Auditoría sobre las ramas canónicas; no se modificaron Flutter ni Web. |
| Auth | Flutter y Web usan Supabase Auth directamente para login, logout y MFA; Web implementa recuperación/cambio de contraseña. No hay sink propio de SecurityEvent en clientes. | El cliente no será productor autorizado. Eventos fallidos requieren proveedor/infra; no atribuir al cliente una fuente autoritativa. |
| Auth audit DB | Existe `auth.audit_log_entries` (`id`, `payload`, `created_at`, `ip_address`), pero tenía **0 filas** en la consulta LIVE. La causa de ese estado/configuración no queda demostrada por el SQL disponible. | No afirmar que Auth audit ya alimenta la aplicación ni que su retención esté configurada. |
| Auth state | LIVE tenía 11 `auth.users`, 12 `auth.sessions`, 2 factores MFA verificados, 2 filas MFA challenge y 0 usuarios con `banned_until` futuro. Solo son conteos; no se leyeron secretos ni datos personales. | Hay estado útil para guards, no un feed SecurityEvent consumido por RSUELVO. |
| Auth Hooks / log drains | No se encontró configuración o productor en los tres repos ni migraciones. Supabase documenta hooks de password/MFA attempt solo para Team/Enterprise; el proyecto observado es Free. Log Drains requieren Pro o superior. | Fallos de password/MFA no son capturables de forma confiable por el SecurityEvent DB actual. Hooks/log drain dependen de plan y una decisión de infraestructura futura. |
| AuditLog | `rsuelvo.tbl_logs_auditoria`, RLS activa (no FORCE), 11 columnas; **2.132 filas**, desde 2026-08-27 hasta 2026-09-22. 18 tablas tenían triggers `fn_auditar_cambio` en LIVE. | Es un registro activo de cambios, amplio y de dominio; no es un registro de eventos de seguridad tipado. |
| Rate limit | `tbl_registro_intentos` tiene `id`, `email`, `ip`, `created_at`, RLS activa y grants de `service_role`; 17 filas en LIVE, 2026-09-22. Sin política de purga encontrada. La misma tabla la usan registro y `qr-entrega`. | Es un contador operacional ad hoc con PII; no es SecurityEvent ni debe reutilizarse sin rediseño. |
| Seguridad IAM | RPCs y triggers ya escriben AuditLog para invitaciones, membership, ownership y verificación. `fn_tiene_aal2()`/`fn_es_service_role()` evalúan JWT y conservan fallback intencional para conexiones directas confiables sin JWT (IAM10-H1 §1.1). Existe `fn_verificar_guards_sanos()`. | SecurityEvent debería guardar solo un resumen tipado de eventos relevantes y referencia al recurso/operación, no duplicar snapshots. |
| Account lock | Hay estado `SUSPENDED`/`REVOKED` para membership y Auth tiene `banned_until`; no encontramos un `security_lock` de cuenta propio ni un productor actual que use `banned_until`. | No declarar que RSUELVO implementa un bloqueo de seguridad global. |
| Monitoreo de guard | La función `fn_verificar_guards_sanos()` existe, pero no se encontró job cron LIVE que la ejecute como monitor ni que emita incidentes. | `SECURITY.GUARD_HEALTH_FAILURE` no tiene productor actual; queda fuera de V1 hasta diseñar monitor fiable. |
| Alertas | No encontramos canal que consuma señales IAM como alertas de seguridad. | Storage y alerting permanecen decisiones separadas. |

**IAM10-H1 / IAM5-CERT (resultado de certificación abajo):** la definición LIVE de `rsuelvo.fn_es_service_role()` es `SECURITY DEFINER` y tiene fallback `auth.jwt() IS NULL AND current_user IN ('postgres','service_role')`; `fn_tiene_aal2()` tiene fallback equivalente. La migración 87 explica el propósito: JWT presente manda; el fallback aplica solo a conexión directa sin JWT para backend/n8n. El incidente P0 histórico fue un `current_user` OR independiente aun con JWT, patrón distinto. SQL Editor confirma el contexto directo (JWT NULL y helper TRUE), pero eso no prueba una petición PostgREST. Se encontró consumidor PostgreSQL directo real en n8n y la llamada anon HTTP probó que PostgREST no cae en fallback. No se modificaron guards.

## 1.1 IAM10-H1 / IAM5-CERT — frontera PostgREST vs PostgreSQL directo

**Migración 87 canónica:** inspeccionada junto con la función LIVE. Lógica desplegada:

- `fn_es_service_role()`: JWT `role=service_role` concede; si `auth.jwt()` es NULL, permite solo `current_user IN ('postgres','service_role')`.
- `fn_tiene_aal2()`: sin JWT permite solo los roles PostgreSQL anteriores; JWT service_role pasa por identidad backend; cualquier otro JWT recibe AAL2 únicamente si claim `aal='aal2'`.
- No-JWT en SQL Editor es `DIRECT_PG_TRUSTED_CONTEXT`, un contexto backend privilegiado esperado bajo el diseño actual. El helper se probó allí como TRUE; esto por sí solo no indica bypass HTTP.

### Inventario real de consumidores PostgreSQL directos

El n8n conectado muestra 16 workflows activos. Inspeccioné las versiones activas completas y la metadata de credenciales (sin secretos): **8 workflows tienen 25 nodos `n8n-nodes-base.postgres`** con una credencial `postgres` compartida llamada `Postgres account`:

- WF-10 (3 nodos), WF-12 (1), WF-13 (3), WF-14 (5), WF-20 (4), WF-21 (1), WF-25-C (1), WF-80 (7).
- Entre las operaciones llamadas están `fn_upsert_cliente`, `fn_solicitar_reserva`, `fn_agregar_lista_espera_v2`, `fn_crear_pedido_desde_reserva`, `fn_generar_cobro` y consultas/logs de WF-80.
- Bitácora canónica de n8n registra `Postgres account` apuntando al proyecto `iwfaktlxebxtocmswdvv` con rol `bypassrls`; entradas de 2026-09-19 describen que n8n usa usuario `postgres` por conexión PG sin JWT y que quitar esa identidad rompió RPCs PG-node. No se ejecutaron workflows de negocio durante esta certificación.
- **Respuesta A6:** sí existe consumidor real PostgreSQL directo que justifica el contexto sin JWT. La lista MCP protege secretos; no se leyó la contraseña ni se hizo conexión de prueba bajo esa credencial, así que el usuario SQL actual de ese secreto no se revalidó en este turno. La evidencia de productor activo + credencial type `postgres` + bitácora de rol/uso se considera evidencia LIVE de inventario, no una ejecución de RPC.

### Matriz de certificación A1–A6

| Caso | Resultado | Evidencia / límite |
|---|---|---|
| **A1 anon real vía PostgREST** | **LIVE PASS** | POST `/rest/v1/rpc/fn_es_service_role`, API key pública anon, sin header `Authorization`, perfil `rsuelvo`: HTTP 200, cuerpo `false`. La metadata de DB confirma `anon` tiene EXECUTE en helper service role; no tiene EXECUTE en `fn_tiene_aal2()` ni en RPC crítica `fn_solicitar_habilitacion_v1`. No se abrió ningún grant. |
| **A2 JWT authenticated AAL1** | **PENDIENTE EXTERNO** (código inspeccionado) | No había sesión/JWT QA autenticada AAL1 disponible sin credenciales interactivas del titular. La lógica JWT branch espera service_role false, AAL2 false y acción crítica `mfa_requerido`; no se atribuye resultado LIVE. |
| **A3 JWT authenticated AAL2** | **PENDIENTE EXTERNO** (código inspeccionado) | Requiere sesión real MFA AAL2. No se tenía token/sesión interactiva ni se solicitaron contraseñas. Lógica espera service_role false y AAL2 true; no se atribuye resultado LIVE. |
| **A4 JWT service_role por HTTP** | **PENDIENTE EXTERNO** (código inspeccionado) | No se dispuso de la service_role key para request HTTP y no se buscó/exhibió un secreto local. Lógica JWT branch concede `fn_es_service_role=true` y comportamiento técnico de AAL2. Certificar con credencial de servicio en contexto controlado. |
| **A5 SQL Editor / PG directo sin JWT** | **LIVE PASS · DIRECT_PG_TRUSTED_CONTEXT** | Query de solo lectura: `auth.jwt()` NULL, `fn_es_service_role()` TRUE, `fn_verificar_guards_sanos()` `{"ok":true}`. Resultado esperado para contexto PostgreSQL privilegiado; no representa PostgREST. |
| **A6 consumidor PostgreSQL directo** | **LIVE inventario + CÓDIGO/bitácora** | 16 workflows activos; 8 workflows/25 nodos Postgres directos. Bitácora registra la credencial como rol bypassrls y fallo histórico al perder la identidad PG sin JWT. No se ejecutaron workflows productivos. **Existe consumidor real; JWT-only cambiaría el contrato actual de n8n.** |

**Resultado de frontera:** en la petición anon real observada el helper devolvió `false` por HTTP; ese resultado es consistente con el camino JWT/rol no privilegiado. No se expuso el GUC JWT de esa petición. No se observó bypass anon ni se confirma P0. A2/A3/A4 permanecen sin certificación LIVE, por falta de tokens/clave legítimos disponibles. Por evidencia actual la conclusión es **SAFE AS DESIGNED para la frontera A1 y el contexto A5, con certificación JWT de usuario/service_role aún parcial**, no certificación total de la matriz.

### `fn_verificar_guards_sanos()` — evaluación, sin cambios

Su comprobación estática actual es insuficiente como análisis estructural: busca `current_user` y la subcadena `auth.jwt() is null`, y la presencia de texto JWT/service_role; no demuestra que el fallback esté ligado exclusivamente a la rama NULL ni que no exista un OR independiente cuando el JWT está presente. Para AAL2 tampoco prueba que la rama de usuario compare únicamente `aal='aal2'`. Además su check conductual ejecutado desde SQL Editor solo certifica A5, contexto privilegiado.

Mejora propuesta **no implementada**: el guard estático debería contrastar una forma canónica normalizada/parseable (o inspección estructural robusta del cuerpo) de ambas funciones, rechazar cualquier rama JWT que pueda OR-conceder por `current_user`, validar que el rol service_role se compare con `auth.jwt()->>'role'`, y que usuarios ordinarios solo pasen por claim AAL2 exacto. Mantener una prueba SQL directa etiquetada A5; complementar con harness HTTP externo A1–A4 que reporte contexto/status/helper y no abra grants temporales. Esta revisión no debe hacer que SQL Editor TRUE se marque como vulnerabilidad.

**Clasificación actual:** `IAM10-H1 / IAM5-CERT — fallback direct-PG en helpers críticos requiere certificación de frontera PostgREST/direct-DB`. No es P0 confirmado. No modificar guards hasta completar A2/A3/A4 y revisión del contrato de la credencial PG n8n.

## 2. Inventario de fuentes y productores

| Fuente actual | Qué hace hoy | Qué no demuestra/captura |
|---|---|---|
| Flutter `AuthController` | `signInWithPassword`, `signOut`, listener `onAuthStateChange`; MFA TOTP enroll/challenge/unenroll; cambio de password mediante `updateUser`. | No persiste evento propio; el error local de login/challenge no es prueba durable ni autoridad backend. No aparece flujo de recuperación de contraseña Flutter en este commit. |
| Web `AuthContext` / `passwords.ts` | `signInWithPassword`, signout local, `PASSWORD_RECOVERY`, recuperación por correo, verificación del enlace y `updateUser`; MFA TOTP. | No persiste eventos de seguridad; `onAuthStateChange` es estado local del cliente. |
| Supabase Auth | Tablas internas para usuarios, sesiones, tokens, factores, desafíos, AMR y audit log. Supabase documenta Auth Audit Logs para signup/login, password, confirmation, token y MFA events. | El audit log DB estaba vacío LIVE. No asumir acceso, cobertura exacta de fallos ni retención. Los hooks disponibles dependen del plan. No leer ni copiar secretos de factores/tokens. |
| PostgreSQL RPC/trigger | `fn_aceptar_invitacion`, `fn_revocar_invitacion`, `fn_gestionar_vinculo`, transferencias de ownership, `fn_auto_alta_comercio`, `fn_solicitar_habilitacion_v1`, `fn_revocar_verificacion_v1`; `fn_auditar_cambio`. | Varias denegaciones retornan JSON/códigos sin persistir un evento SecurityEvent; no todo rechazo debe generar una fila. |
| Edge Functions LIVE | 8 activas: `invitar-usuario-comercio`, `gestionar-variante-sucursal`, `notificar-reserva-sucursal`, `registrar-dispositivo`, `meta-ingress`, `solicitar-alta-comercio`, `registrar-cuenta-comercio`, `qr-entrega`. Las funciones de registro y QR tocan `tbl_registro_intentos`; QR responde según estado V1 y entrega signed URL temporal. | Los logs de invocación/HTTP no equivalen a SecurityEvent estructurado. No se encontró escritura de SecurityEvent. `verify_jwt=false` identifica endpoints públicos/webhooks: cada uno necesita su propia verificación (por ejemplo firma de Meta) y no puede confiar en un `actor` del body. |
| Web/Flutter capabilities | Renderizan UI y gates; el backend/RLS/RPC es autoridad IAM. | No aceptar `event_type`, actor, rol, comercio, severidad ni resultado afirmados por el cliente. |
| n8n | Flujos operativos y llamadas server-to-server existentes. | No rediseñar ni convertir ejecuciones de pedido/stock/WhatsApp en SecurityEvents. |

### Supabase Auth: disponibilidad por evento

Supabase documenta audit logs de Auth, pero en esta instancia la tabla está vacía. Las fuentes de proyecto disponibles en esta auditoría no permiten verificar los logs visibles en el Dashboard ni la configuración de retención de Auth audit. `auth.sessions` / `auth.mfa_*` guardan estado y evidencia operacional de Auth, no sustituyen un feed tipado de eventos fallidos ni deben sondearse para cada evento.

| Evento candidato | Observabilidad actual | Decisión propuesta |
|---|---|---|
| Login exitoso/logout/token refresh/confirmación/email/password reset | Supabase Auth Audit Logs/Dashboard; cliente recibe estados/eventos, pero no hay sink RSUELVO. | No copiar a SecurityEvent DB hasta verificar Auth audit real y diseñar ingestión confiable/deduplicada. |
| Login fallido / password verification | Auth conoce la petición; cliente solo recibe error. Hook de verificación de password requiere Team/Enterprise según docs actuales. | Fuera del storage propio V1 en plan Free. Investigar proveedor/plan si es requisito. |
| MFA enrollment/removal y challenge exitoso/fallido | Auth API/state y audit logs del proveedor. Hook de MFA verification requiere Team/Enterprise. | Estado success puede confirmarse por Auth; los fallos repetidos necesitan hook/telemetría de proveedor. No inventar productor DB actual. |
| Sesión revocada/expirada | Auth mantiene sessions/refresh tokens; el cliente puede recibir signout; no hay listener servidor propio. | No crear evento propio hasta definir señal durable y semántica de cierre global/local. |
| Account disabled/banned | Campo nativo `auth.users.banned_until`; 0 baneados LIVE, no hay productor de RSUELVO observado. | No incluir en V1 como mecanismo existente. |
| Logs operativos Auth/Edge/Postgres | Dashboard; exportación Log Drain documentada para Pro/Team/Enterprise. | Proyecto Free: no hay Log Drain disponible según docs actuales. No desplegar proveedor SIEM en esta fase. |

Referencias primarias consultadas: [Supabase Auth Audit Logs](https://supabase.com/docs/guides/auth/audit-logs), [Supabase Auth Hooks](https://supabase.com/docs/guides/auth/auth-hooks), [Supabase Log Drains](https://supabase.com/docs/guides/observability/log-drains). Plan/features pueden cambiar; reconfirmar antes de implementación.

## 3. AuditLog existente y separación

### `tbl_logs_auditoria` LIVE

Columnas reales: `id_log uuid PK`, `id_comercio uuid NULL`, `id_usuario uuid NULL`, `accion text`, `tabla text`, `registro_id uuid NULL`, `datos_anteriores jsonb NULL`, `datos_nuevos jsonb NULL`, `ip inet NULL`, `user_agent text NULL`, `created_at timestamptz NOT NULL DEFAULT now()`.

`fn_auditar_cambio()` es trigger genérico `SECURITY DEFINER`, `search_path=rsuelvo,public`: guarda operación de fila (`TG_OP`), tabla, registro y fila JSON completa anterior/nueva. En LIVE había triggers para: `tbl_canal_whatsapp`, `tbl_comercio_config`, `tbl_comprobantes_pago`, `tbl_contact_preferences`, `tbl_dispositivos_push`, `tbl_entrega_captura`, `tbl_envios`, `tbl_inventario`, `tbl_lista_pendiente`, `tbl_movimientos_creditos`, `tbl_pedidos`, `tbl_puntos_entrega`, `tbl_reservas`, `tbl_transportadoras`, `tbl_usuario_comercio`, `tbl_variante_sucursal`, `tbl_variantes` y `tbl_verificaciones`. Transferencias de ownership y `tbl_verificaciones_comercio` tienen writes explícitos AuditLog en RPC; no se observaron entre esas 18 tablas con trigger genérico. RPCs también insertan eventos explícitos como `vinculo_suspendido`, `vinculo_revocado`, ownership y transición IAM-9. Algunos caminos pueden registrar tanto cambio por trigger como AuditLog explícito; SecurityEvent no debe repetir cada fila de esos registros.

RLS activa, no FORCE. Políticas LIVE:

- `audit_select` (PUBLIC con predicados): SuperAdmin o `fn_es_admin_comercio(id_comercio)`; lectura de log del tenant.
- `audit_sysadmin_select` para authenticated: service role, SuperAdmin o rol `ROLE_SYSADMIN`.
- `audit_insert` (PUBLIC con check): `fn_es_superadmin()`.
- Los grants de tabla incluyen INSERT/SELECT/UPDATE/DELETE para authenticated; no se encontraron políticas UPDATE/DELETE, por lo que RLS los bloquea a ese rol en solicitudes ordinarias. `service_role` tiene privilegios amplios y bypass de RLS.

**Productores:** triggers `fn_auditar_cambio()` y RPCs SECURITY DEFINER/SQL para membresía, invitaciones, ownership, IAM-7 aceptación legal, auto-alta y verificación IAM-9. EFs llaman RPCs o usan service_role para sus tareas; las EFs revisadas no escriben una entidad SecurityEvent. No es un único contrato tipado: `accion`, `tabla` y snapshots son flexibles.

**Retención/debilidades:** no se encontró política/job de retención para AuditLog; LIVE cubre aproximadamente 27 días al consultar sus límites. El trigger copia filas JSON completas, puede capturar PII de filas fuente; tabla/columnas tienen mutabilidad de propietario/servicio aunque RLS frene mutaciones autenticadas normales. Su propósito, estructura genérica y audiencia tenant/staff son distintos de SecurityEvent.

### AuditLog vs SecurityEvent

| Dimensión | AuditLog `tbl_logs_auditoria` | SecurityEvent propuesto |
|---|---|---|
| Propósito | Operación/cambio de negocio o administración: actor, acción y recurso. | Señal de seguridad priorizada: autenticación anómala, cambio de postura, abuso o intento crítico. |
| Productor | Trigger de fila o RPC/operación que conoce cambio. | Backend confiable y allowlist por evento; nunca INSERT directo desde Flutter/Web. Auth provider separado hasta una ingestión contratada. |
| Audiencia | SuperAdmin, SysAdmin y admins de comercio según RLS actual. | Staff de seguridad mínimo privilegio; sin lectura tenant directa en V1. |
| Sensibilidad | Snapshot anterior/nuevo puede contener PII/datos de dominio. | Metadatos estrictamente permitidos; no secretos, tokens ni snapshots completos. |
| Retención | Sin política de purge encontrada. | Política pendiente de aprobación; sin promesa de retención hasta contratar purge ejecutable (§4.7). |
| Mutabilidad | RLS evita update/delete ordinarios, pero grants/owner/servicio permiten más; no hay append-only fuerte. | Append-only para productores; sin UPDATE; DELETE solo proceso de retención auditado. |
| Ejemplos | Cambió precio/pedido; membership cambió; evidencia V1 creada/revocada. | Transferencia ownership, cambio sensible de membership, V1 revocada. |

## 4. Contrato REV2 — alcance normativo (sustituye §§4–17 de REV1)

Esta sección es la única taxonomía normativa. Las listas/candidatos anteriores de REV1 quedan sustituidos. SecurityEvent no replica AuditLog. V1 solo cubre transiciones IAM persistidas por productores backend identificables. **La tabla/feed aún no existe y ningún evento se está emitiendo.** Cada productor futuro escribe el evento en la misma transacción que la transición efectiva.

### 4.1 Catálogo V1 cerrado

Todos los eventos V1 tienen `id_comercio` **obligatorio**, `actor_type=USER`, `actor_user_id` interno no nulo y `source=POSTGRES_RPC`. El productor solo emite cuando puede derivar el actor humano de forma confiable; llamada técnica direct-PG sin actor humano no se atribuye a un usuario y queda fuera de estos tipos. Outcome y severidad son fijos; el productor no los acepta del cliente ni los cambia dinámicamente. `notify=NO` para todos en V1. La metadata es allowlist cerrada; UUIDs refieren exclusivamente IDs internos RSUELVO.

| `event_type` | Transición / RPC backend a instrumentar | Severidad única | Outcome único | Metadata permitida |
|---|---|---:|---|---|
| `OWNER.TRANSFER_STARTED` | Creación efectiva de transferencia (`fn_iniciar_transferencia`). | HIGH | SUCCESS | `transfer_id`, `target_user_id` |
| `OWNER.TRANSFER_COMPLETED` | Cambio efectivo de owner (`fn_responder_transferencia`). | CRITICAL | SUCCESS | `transfer_id`, `previous_owner_user_id`, `target_user_id` |
| `OWNER.TRANSFER_CANCELLED` | Cancelación efectiva (`fn_cancelar_transferencia`). | NOTICE | CANCELLED | `transfer_id` |
| `MEMBERSHIP.SUSPENDED` | ACTIVE→SUSPENDED efectivo por operación de gestión de vínculo. | HIGH | SUCCESS | `membership_id`, `target_user_id` |
| `MEMBERSHIP.REACTIVATED` | SUSPENDED→ACTIVE efectivo por operación de gestión de vínculo. | NOTICE | SUCCESS | `membership_id`, `target_user_id` |
| `MEMBERSHIP.REVOKED` | Revocación efectiva de membership. | HIGH | SUCCESS | `membership_id`, `target_user_id` |
| `MEMBERSHIP.PRIVILEGE_CHANGED` | Cambio efectivo de rol sensible que modifica capabilities, por elevación o reducción (`fn_gestionar_vinculo`). | HIGH | SUCCESS | `membership_id`, `target_user_id`, `from_role`, `to_role`, `direction` (`ELEVATED`\|`REDUCED`) |
| `VERIFICATION.V1_REVOKED` | ACTIVO→PENDIENTE_VERIFICACION efectivo por `fn_revocar_verificacion_v1`. | HIGH | SUCCESS | `verification_id` |

**Actor/target:** `actor_user_id` identifica exclusivamente a quien ejecuta la acción (`tbl_usuarios.id_usuario`). La metadata `target_user_id` identifica al usuario RSUELVO afectado/destinatario, nunca `auth.users.id`. `membership_id` refiere `tbl_usuario_comercio.id`; `transfer_id` refiere el ID interno de la transferencia; `verification_id` refiere `tbl_verificaciones_comercio.id_verificacion`. `previous_owner_user_id` es el owner interno anterior. No se registra `id_usuario` ambiguo para actor y target. En un evento de membership, el actor puede ser SuperAdmin o admin autorizado y el target es el miembro afectado.

**Privilege change:** un solo tipo captura todo cambio efectivo de rol que cambie capabilities; `direction` es obligatorio y cerrado (`ELEVATED`/`REDUCED`). Severidad siempre HIGH. Cambios sin efecto sobre rol/capabilities no emiten evento. Una mutación de capability independiente del rol no está en V1: requiere producer y metadata propios antes de incorporarse.

**Fuera de V1:**

- `VERIFICATION.V1_GRANTED`: OUT. El V0→ACTIVO ordinario es una habilitación declarativa respaldada por `tbl_verificaciones_comercio` y AuditLog; emitir otro evento duplica evidencia sin señal adicional de amenaza. V1 conserva evidencia y AuditLog existentes.
- `PERMISSION.CRITICAL_DENIED`: OUT hasta disponer de request/idempotency ID autoritativo y un producer que registre solo denegaciones de una allowlist explícita de acciones críticas. No cada 403 ni cada fallo AAL.
- `ONBOARDING.ABUSE_THRESHOLD` e `INVITE.ABUSE_THRESHOLD`: OUT. Rate limits existentes son best-effort/no atómicos y no son contador autoritativo para threshold SecurityEvent.
- Invitación normal, acceptance legal, MFA/Auth/recovery, selección de comercio, errores genéricos, guard checks y operaciones de negocio: AuditLog, Auth provider o telemetría existente según corresponda; no V1 SecurityEvent sin producer confiable y motivo de seguridad específico.

### 4.2 Valores, severidad y outcomes

Enums cerrados de REV2: severidad `NOTICE | HIGH | CRITICAL`; outcome `SUCCESS | CANCELLED`. Cada fila de 4.1 fija exactamente uno de cada uno. Sin severity dinámica, libre ni definida por cliente. No se almacena un evento para autorización denegada o fallo técnico en V1; añadirlos exige tipo, producer, outcome y política anti-ruido nuevos aprobados. `CRITICAL` queda reservado al cambio efectivo de owner; no significa urgencia operativa automatizada. El catálogo no implica notificaciones.

### 4.3 Idempotencia y deduplicación

**Transiciones PostgreSQL:** insertar SecurityEvent dentro de la transacción del cambio y solo después de comprobar la transición efectiva bajo lock. Si el RPC reintenta tras un commit y devuelve `ya_*`/no-op, emite cero eventos. Si el cambio falla o rollbackea, no queda evento. Una nueva transición legítima posterior (incluido volver de estado) sí produce otro evento.

El enlace idempotente es la identidad de la transición de dominio, no `event_type + actor + comercio`. Para recursos con ID estable (`transfer_id`, `membership_id`, `verification_id`), el producer debe asociar cada emisión con una identidad de transición/opération estable que permita reconocer el replay sin colapsar transiciones legítimas posteriores. Para RPCs sin request key/idempotencia suficiente, ese gap debe resolverse en el contrato del RPC o posponer el producer; no se inventará unicidad global por actor/recurso. Timeout después de commit debe reintentar y recibir el resultado de la misma operación/transición, sin insertar otra fila.

Campos conceptuales opcionales reservados para fuentes futuras: `producer` y `producer_event_id`; UNIQUE parcial sobre `(source, producer_event_id)` solo si la fuente garantiza un ID estable y no nulo. Futuro Auth ingest queda fuera de V1. `correlation_id` **no es** idempotency key y no deduplica: solo traza una solicitud; puede repetirse en AuditLog y SecurityEvent de la misma operación.

### 4.4 Actor, schema conceptual y metadata

Actor canónico: `actor_type` cerrado (`USER`, `SERVICE_ROLE`, `SYSTEM`, `UNKNOWN`) y `actor_user_id` nullable FK a `tbl_usuarios.id_usuario`. Para los ocho event types V1, actor es `USER` y el ID es obligatorio. SuperAdmin es `USER` con permiso global derivado en backend, no actor type separado. Identidad `SERVICE_ROLE` debe validarse por fuente segura/JWT cuando aplica; conexión direct-PG confiable se clasifica explícitamente como contexto técnico, no se deduce identidad humana de `current_user` dentro de SECURITY DEFINER. `UNKNOWN` solo aplica a una futura fuente que no pueda mapear actor, no a V1.

Schema conceptual (sin DDL): `id_evento` UUID PK; `occurred_at` (momento de transición); `created_at` (persistencia); `event_type`, `severity`, `outcome`, `actor_type`, `actor_user_id`; `id_comercio` (NOT NULL para todos los tipos V1; nullable únicamente si una extensión futura de Auth/global se aprueba); `source` cerrado (`POSTGRES_RPC` en V1); `producer`/`producer_event_id` opcionales para dedup estable; `correlation_id` nullable; `metadata` JSONB small/allowlisted. Sin `auth_user_id`, IP, User-Agent ni `session_ref` en V1: no hacen falta para estos productores y ampliarían PII. `correlation_id` nullable porque no existe request ID transversal en varios RPC DB.

Claves metadata exactas: `transfer_id`, `target_user_id`, `previous_owner_user_id`, `membership_id`, `from_role`, `to_role`, `direction`, `verification_id`. Cada tipo usa solo la subselección en la tabla. Roles toman códigos canónicos; no guardar nombres, correo, SQL/error text, request bodies, headers, tokens, secretos MFA/OTP/QR, signed URLs, claves service_role, snapshots ni documentos. Ningún valor libre del cliente.

### 4.5 Privacidad IP/UA

V1 no guarda IP/User-Agent y no copia filas de `tbl_registro_intentos`. Su email/IP en claro, límites best-effort y falta de purga son deuda separada; no convertir ese contador en SecurityEvent. Una futura captura de IP solo desde backend/proxy confiable identificado y normalizado (nunca body ni `X-Forwarded-For` sin trusted-proxy contract), con minimización y retención aprobadas. User-Agent requeriría caso de uso y límite (máximo 512 bytes), sin fingerprint persistente.

### 4.6 Producers, acceso e inmutabilidad

Solo RPC backend allowlisted produce V1. Flutter/Web no insertan y no deciden tipo/actor/comercio/severidad/outcome. La tabla debe residir en schema no expuesto por Data API, con RLS si técnicamente aplica como defensa adicional: sin SELECT tenant; sin INSERT directo `authenticated`; sin UPDATE; sin DELETE runtime. Productores por función allowlisted con grants mínimos; evitar grant amplio de tabla a `service_role`. Lectura para tenant owner/admin/cashier: ninguna en V1. Acceso staff debe ser mínimo privilegio, con consultas de investigación auditadas y sin reutilizar automáticamente el RLS de AuditLog. SuperAdmin/SysAdmin no reciben mutación manual. Purga por proceso controlado de retención, nunca cliente/runtime.

### 4.7 Correlación y retención

`correlation_id` sirve para trazabilidad; no es clave de idempotencia, identidad ni secreto. Es nullable y puede compartirse con AuditLog para la misma operación. Si la frontera confiable lo genera, UUID aleatorio interno propagado sin autoridad; RPC sin ID transversal puede dejarlo NULL. Aún no existe formato/propagación común EF→RPC→AuditLog.

**Retención: PROPUESTA NO APROBADA.** Se retiran 30/90/365 como política operativa; ninguna duración se codifica ni promete por ahora. La aprobación corresponde a owner de seguridad/producto junto con responsable legal/privacidad, considerando backups/PITR. El purge job debe formar parte del release backend IAM-10 que habilite retención finita, solo después de acordar plazos y verificar scheduler confiable. Aunque `pg_cron` existe/está disponible en el proyecto, su disponibilidad no prueba aún ejecución, monitoreo ni restauración del job. Si no hay scheduler confiable, no desplegar un event store con promesa de retención finita ni permitir acumulación indefinida: backend GO queda condicionado a resolver mecanismo operable y verificable. Eventos Auth externos mantienen la retención del proveedor y no heredan una promesa RSUELVO.

### 4.8 Alerting, decisiones abiertas y E2E antes del backend

V1 solo almacena eventos; no envía email/push, no crea SIEM y no bloquea cuentas. Futuras alertas posibles: transferencia completada o revocación V1. No se activan aquí.

Decisiones necesarias antes de GO backend: aprobar plazos/responsable y purge operable; acordar cómo cada RPC reintenta la misma transición (en particular inicio de transferencia); aprobar lista mínima de lectores staff y auditoría de consultas; completar A2/A3/A4 de IAM10-H1 cuando existan credenciales QA legítimas. La certificación parcial IAM-5 no se altera ni bloquea el contrato documental por sí misma.

E2E futuro (no ejecutado): cada transición de catálogo crea exactamente una fila tras commit; retry/no-op no duplica; rollback no deja evento; transición legítima posterior sí registra una nueva fila; actor/target/scope corresponden a IDs internos; enum, metadata y source fuera de allowlist se rechazan; usuarios tenant no pueden leer/insertar/actualizar/borrar por PostgREST/RPC; staff accede solo por consulta aprobada; ningún secreto/PII aparece; correlación no se usa para dedup; purge es acotado, idempotente, auditable y restaura conforme a política; regresión IAM-1..9, `fn_verificar_guards_sanos()` y los 8 workflows n8n direct-PG no se degradan.

### 4.9 Definition of Done documental

REV2 queda listo para revisión contractual cuando cada tipo tenga producer, transición, scope, actor/target, severity/outcome y metadata cerrados (tabla 4.1); idempotencia no colisione con transiciones legítimas; retención/purge y lectores tengan aprobación explícita. Esta revisión no autoriza DDL, RPC, trigger, Edge Function, Flutter, Web ni cambios n8n. Backend inicia solo después de aprobación expresa del contrato y resolución de decisiones de 4.8.

## 5. Fuentes OUT / no convertidas en eventos V1

No son SecurityEvent V1: actividad de pantalla/selector; lecturas RLS; cada 403; aceptación legal; ediciones/pedidos/ventas/pagos; QR view normal; log de retry/error técnico; cada fila de `tbl_registro_intentos`; autenticación/MFA/recovery sin feed server-side fiable; ejecución de workflow n8n. AuditLog conserva operaciones de negocio; Auth mantiene sus logs bajo la cobertura/retención del proveedor.

## 6. IAM10-H1 / IAM5-CERT vigente

| Caso | Clasificación | Resultado |
|---|---|---|
| A1 anon/PostgREST | LIVE PASS | `fn_es_service_role() = false` en request anon real. |
| A2 authenticated AAL1 | PENDIENTE EXTERNO | No se ejecutó con JWT QA real. |
| A3 authenticated AAL2 | PENDIENTE EXTERNO | No se ejecutó con JWT MFA real. |
| A4 service_role HTTP | PENDIENTE EXTERNO | No se ejecutó con credencial de servicio real. |
| A5 PostgreSQL directo sin JWT | LIVE PASS · `DIRECT_PG_TRUSTED_CONTEXT` | Fallback privilegiado esperado según migración 87. |
| A6 consumidor direct-PG | LIVE INVENTARIO | 16 workflows activos; 8 usan 25 nodos PostgreSQL directos. Consumidor real de n8n confirmado por inventario/bitácora; no se ejecutaron workflows en la certificación. |

Conclusión: **SAFE AS DESIGNED para las fronteras observadas A1/A5; certificación incompleta; NO P0 confirmado.** El fallback `current_user` es intencional para direct-PG confiable y no debe describirse como bypass PostgREST observado. No modificar IAM-5; mantener `IAM10-H1 / IAM5-CERT` abierto hasta A2/A3/A4 y revalidación controlada de credencial cuando corresponda. `fn_verificar_guards_sanos()` sigue necesitando mejora estática; no cambiarlo en esta fase.

## 7. Deuda de auditoría

- `auth.audit_log_entries` estaba vacía LIVE; confirmar cobertura/configuración/retención en Dashboard con owner Supabase.
- No hay Auth ingest, event store, alerting ni monitor LIVE de guard.
- `tbl_registro_intentos` guarda email/IP en claro, es best-effort y no tiene purga encontrada; tratar por separado.
- AuditLog captura snapshots JSON y no tiene purge detectado; revisar PII/retención independientemente.
- No existe correlation ID transversal.
- Retención SecurityEvent y mecanismo purge siguen sin aprobación.
- Completar A2/A3/A4 como pendientes externos; no reabrir IAM-5 sin bypass demostrado.

---

**Veredicto de esta fase:** auditoría + contrato REV2 documentales; implementación no iniciada.
**IAM-10 = CONTRATO REV2 / NO IMPLEMENTADO.**
