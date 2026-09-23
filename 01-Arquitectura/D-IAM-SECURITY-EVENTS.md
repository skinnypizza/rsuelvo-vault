# D-IAM-SECURITY-EVENTS — Propuesta IAM-10 (auditoría; NO implementada)

**Estado:** PROPUESTA PARA REVISIÓN · no aprobada · sin cambios funcionales
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
| Seguridad IAM | RPCs y triggers ya escriben AuditLog para invitaciones, membership, ownership y verificación. `fn_tiene_aal2()`/`fn_es_service_role()` son guards JWT. Existe `fn_verificar_guards_sanos()`. | SecurityEvent debería guardar solo un resumen tipado de eventos relevantes y referencia al recurso/operación, no duplicar snapshots. |
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
| Retención | Sin política de purge encontrada. | Retención temporal por severidad propuesta (§11), purga controlada. |
| Mutabilidad | RLS evita update/delete ordinarios, pero grants/owner/servicio permiten más; no hay append-only fuerte. | Append-only para productores; sin UPDATE; DELETE solo proceso de retención auditado. |
| Ejemplos | Cambió precio/pedido; membership cambió; evidencia V1 creada/revocada. | Elevación de rol, transferencia ownership, abuso de onboarding superó umbral, intento crítico sin AAL2, V1 revocada. |

## 4. Propuesta de alcance V1 y taxonomía determinista

Usar valores cerrados ASCII `NAMESPACE.EVENT`, validados por CHECK o catálogo canónico. No aceptar nombres arbitrarios ni `event_type` elegido por cliente. Severidad y necesidad de comercio son defaults contractuales, no campos libres.

| Event type | Definición | Producer candidato | Default | Actor | Comercio | Metadata allowlist (sin PII) | Notificar / retención larga |
|---|---|---|---|---|---|---|---|
| `OWNER.TRANSFER_STARTED` | Transferencia válida creada. | RPC DB | HIGH | USER | Sí | `transfer_id`, destino app-id pseudónimo | No / Sí |
| `OWNER.TRANSFER_COMPLETED` | Transferencia aceptada y owner cambiado efectivamente. | RPC DB, misma transacción | CRITICAL | USER | Sí | `transfer_id`, actor/destino app IDs, `audit_log_id` | Staff alert futuro / Sí |
| `OWNER.TRANSFER_CANCELLED` | Cancelación efectiva por actor autorizado. | RPC DB | NOTICE | USER | Sí | `transfer_id`, motivo enum no texto libre | No / No |
| `MEMBERSHIP.SUSPENDED` | Vínculo activo suspendido. | RPC DB | HIGH | USER/SERVICE_ROLE | Sí | membership ID, rol anterior | No / Sí |
| `MEMBERSHIP.REACTIVATED` | Vínculo reactivado. | RPC DB | NOTICE | USER/SERVICE_ROLE | Sí | membership ID, rol | No / No |
| `MEMBERSHIP.REVOKED` | Vínculo revocado terminalmente. | RPC DB | HIGH | USER/SERVICE_ROLE | Sí | membership ID, rol | No / Sí |
| `MEMBERSHIP.PRIVILEGE_CHANGED` | Cambio efectivo que eleva capacidad (no cambio inocuo). | RPC DB después de comparar permisos efectivos | HIGH | USER/SERVICE_ROLE | Sí | membership ID, from/to role code canónico | No / Sí |
| `INVITE.ABUSE_THRESHOLD` | Umbral de intentos inválidos/repetidos excedido; no cada invite normal. | RPC/EF confiable si existe contador fiable | WARNING | USER/UNKNOWN | Sí | código de regla, contador bucket, ventana | No / No |
| `PERMISSION.CRITICAL_DENIED` | Denegación de acción crítica (AAL2/owner/capability) tras umbral o en operación de alto impacto. No cada 403. | RPC DB | WARNING/HIGH por acción | USER/UNKNOWN | Sí/depende | acción allowlisted, motivo enum, recurso ID | Posible / No |
| `ONBOARDING.ABUSE_THRESHOLD` | Rate limit real disparado o abuso repetido; honeypot solo si backend decide señal válida. | EF/RPC confiable | WARNING | UNKNOWN/USER | No | rule code, bucket hash no reversible, ventana, contador | No / No |
| `VERIFICATION.V1_GRANTED` | V0→ACTIVO completado; evento resumen, no snapshot de checks. | RPC DB transaccional | NOTICE/HIGH (aprobar) | USER | Sí | `id_verificacion`, origen, `audit_log_id` | No / Sí |
| `VERIFICATION.V1_REVOKED` | ACTIVO→V0 por SuperAdmin. | RPC DB transaccional | HIGH | USER | Sí | `id_verificacion`, `audit_log_id`, código de motivo | Staff alert futuro / Sí |

**Criterio para denegaciones:** registrar solo acción crítica, actor mapeado cuando exista y razón cerrada; agrupar/reducir por umbral para evitar tormenta de eventos. No persistir SQLSTATE, texto de error, request body ni valor proporcionado por cliente como etiqueta.

### Candidatos no integrables aún (no productores V1 hoy)

Estos nombres son candidatos para contrato futuro condicionado a una fuente. No son parte de la allowlist de V1 ni se deben emitir hasta aprobar un productor confiable.

| Candidato (no activo) | Productor requerido | Severity | Actor / comercio | Metadata permitida | Alert / retención larga | Gating |
|---|---|---|---|---|---|---|
| `AUTH.LOGIN_SUCCEEDED` | Auth Audit Log ingestado | NOTICE | USER si mapeado / no tenant requerido | método Auth enum | No / No | Feed Auth verificado; no cliente. |
| `AUTH.LOGIN_FAILED` | Auth Audit Log o Password Verification Hook | WARNING tras umbral | UNKNOWN/USER / no tenant | bucket de intentos, método enum | Futuro si umbral alto / No | Hook password requiere Team/Enterprise; confirmar Auth log. |
| `MFA.ENROLLMENT_COMPLETED` | Auth provider/estado de factor confirmado | NOTICE | USER / no | tipo factor enum, sin ID/secreto por defecto | No / No | Confirmación server side. |
| `MFA.FACTOR_REMOVED` | Auth provider | HIGH | USER / no | tipo factor enum | Futuro / Sí | Feed provider; nunca factor payload. |
| `MFA.CHALLENGE_SUCCEEDED` | Auth Audit Log/hook | INFO/NOTICE | USER / no | método MFA enum | No / No | Hook MFA requiere Team/Enterprise; feed verificado. |
| `MFA.CHALLENGE_FAILURE_THRESHOLD` | Auth verification hook/log provider | HIGH | UNKNOWN/USER / no | bucket/contador/ventana | Futuro / No | Hoy sin hook elegible en Free. |
| `RECOVERY.REQUESTED` | Auth Audit Log | NOTICE | UNKNOWN/USER / no | canal enum; correlation id | No / No | No email/token. Confirmar feed y dedup. |
| `RECOVERY.COMPLETED` | Auth Audit Log | NOTICE | USER / no | correlation id | No / No | Confirmar fuente de éxito server-side. |
| `SESSION.REVOKED` | Auth provider/session feed | NOTICE | USER si mapeado / no | scope enum local/others | No / No | Definir evento vs expiración natural. |
| `SECURITY.GUARD_HEALTH_FAILURE` | Monitor/job backend | CRITICAL | SYSTEM / no | guard code, resultado enum | Staff alert futuro / Sí | No cron/monitor LIVE. |
| `SECURITY.SERVICE_ROLE_DENIED` | Backend invocación autentica | HIGH | SERVICE_ROLE / scope según función | producer code, failure enum | Staff alert solo repetido / Sí | Fuente técnica autenticada; no `current_user`. |
| `SECURITY.ACCOUNT_LOCKED` | RPC/operador de lock aprobado | HIGH | USER/SYSTEM / no | lock reason enum, expiry | Futuro / Sí | No existe lock global RSUELVO observado. |
| `SECURITY.SUPERADMIN_OVERRIDE` | RPC específico de override | CRITICAL | USER con rol global confirmado / depende recurso | acción/recurso/case id | Staff alert futuro / Sí | No hay mecanismo general de override actual. |

## 5. Eventos OUT / sin señal propia

- Aceptación legal y evidencia IAM-7: AuditLog/evidencia legal, no señal de seguridad salvo incidente específico demostrado.
- Invite creada/aceptada/revocada/expirada de forma normal: AuditLog; abuso repetido supera umbral y sí puede producir `INVITE.ABUSE_THRESHOLD`.
- Selección normal de comercio, navegación, lectura, consulta RLS y cada 403 trivial: ruido, no SecurityEvent.
- Edición de producto, pedido, venta, pago, QR normal: AuditLog/dominio; no SecurityEvent.
- Errores técnicos genéricos, HTTP 4xx/5xx sin contexto de abuso, retry y log de ejecución n8n: telemetría operacional, no SecurityEvent.
- Cada evento individual de `tbl_registro_intentos`: no copiar a SecurityEvent; solo evento agregado en umbral si productor fiable lo decide.
- Score de riesgo/ML, IP reputation, geovelocity, device fingerprinting, SIEM y lock automático: fuera de esta propuesta V1.

## 6. Severidad y outcome

### Severidad cerrada

`INFO`, `NOTICE`, `WARNING`, `HIGH`, `CRITICAL`.

- INFO: señal de contexto sin riesgo inmediato (no se propone usar para cada operación).
- NOTICE: acción sensible válida y esperable, por ejemplo cancelar transferencia o habilitar V1 automática.
- WARNING: repetición anómala/umbral superado, por ejemplo abuso de registro.
- HIGH: cambio de privilegio, suspensión/revocación de membership, denegación crítica repetida.
- CRITICAL: transferencia de ownership completada, revocación V1 por staff o incidente guard comprometido.

Severity predeterminada en el catálogo; SECURITY DEFINER/RPC decide el tipo/resultado desde el estado final. No se acepta del cliente.

### Outcome cerrado

Propuesta: `SUCCESS`, `DENIED`, `FAILED`, `BLOCKED`, `CANCELLED`, `EXPIRED`.

- `SUCCESS`: transición/acción acabó con éxito.
- `DENIED`: autorización/guard rechazó la acción.
- `FAILED`: el productor confiable intentó y falló por error técnico relevante.
- `BLOCKED`: política de abuso/rate-limit impidió continuar.
- `CANCELLED`: actor autorizado canceló.
- `EXPIRED`: intento significativo expiró al ejercerse.

No usar `REVOKED` como outcome: revocar es la acción/event type, cuyo outcome suele `SUCCESS`. Resultado fuera de estos valores se rechaza. Para eventos de anomalía detectada sin operación fallida, el catálogo define outcome (`BLOCKED` o `SUCCESS`) explícitamente.

## 7. Modelo de actor

- `USER`: el servidor deriva `id_usuario` desde `auth.uid() → tbl_usuarios`; no recibe `actor_user_id`, rol, owner ni tenant desde JSON del cliente.
- `SERVICE_ROLE`: solo productor backend confiable que valida JWT claims o identidad de servicio autenticada. No guardar key/token. No inferir actor humano desde `current_user`; solo el helper de identidad backend puede usar el fallback no-JWT aprobado para la conexión PostgreSQL directa.
- `SYSTEM`: job/trigger identificado explícitamente por nombre de productor confiable y ejecución real; no usarlo como fallback genérico.
- `UNKNOWN`: intento no autenticado o sujeto no mapeable; actor_user_id NULL. Si el proveedor aporta Auth user UUID, no guardar automáticamente; requerir justificación, limitación de acceso y mapa seguro.
- SuperAdmin no es actor_type: es un usuario RSUELVO cuyo rol/capability se deriva en backend. Guardar `actor_scope=GLOBAL_STAFF` o rol canónico calculado solo si hace falta investigar, no `owner=true` ni declaración del cliente.

**No se propone columna `auth_user_id` separada en V1.** `id_usuario` es identidad canónica interna cuando existe; duplicar Supabase UUID no mapeado amplía sensibilidad y debe aprobarse caso por caso.

## 8. Schema conceptual mínimo (no DDL)

| Campo conceptual | Recomendación | Justificación |
|---|---|---|
| `id_evento` | UUID generado por DB, PK | Identidad opaca del evento. |
| `occurred_at` | `timestamptz NOT NULL`, timestamp del productor confiable | Momento real de la señal. En RPC coincide con transacción; separar de ingestion si hay feed externo futuro. |
| `created_at` | `timestamptz NOT NULL DEFAULT now()` | Momento de persistencia; detecta demora de ingestión. No sustituye `occurred_at`. |
| `event_type` | Código cerrado, allowlist versionada/check | Taxonomía determinista. |
| `severity` | Enum/check cerrado, asignado backend por catálogo | Priorización consistente. |
| `outcome` | Enum/check cerrado | Éxito/denegación/bloqueo/etc. |
| `actor_type` | Enum/check cerrado | USER/SERVICE_ROLE/SYSTEM/UNKNOWN. |
| `id_usuario` | UUID nullable FK a `tbl_usuarios`; permitir NULL | Actor autenticado app conocido; el target puede no tener perfil. |
| `id_comercio` | UUID nullable FK | Scope tenant cuando evento sea tenant-scoped; NULL en auth global/registro. |
| `source` | Enum/check cerrado `POSTGRES_RPC`, `POSTGRES_TRIGGER`, `EDGE_FUNCTION`, `AUTH_PROVIDER`, `SYSTEM_JOB` | Productor técnico declarado por backend; nunca frontend. |
| `correlation_id` | UUID nullable | Agrupa una solicitud distribuida. No es credencial/secreto. |
| `metadata` | JSONB pequeño y allowlisted por event_type | Datos específicos mínimos; no payload arbitrario. |
| `ip`, `user_agent`, `session_ref`, `auth_user_id` | **Excluir del mínimo V1** | Alto costo de privacidad y no necesarios para los eventos IAM DB iniciales. Reevaluar solo con caso de uso/retención explícitos. |

`metadata` solo acepta claves declaradas por tipo, tipos y tamaños acotados. Permitidos: UUIDs de recurso relacionados, códigos enum, from/to role canónico, ventana/contador bucketizado. Prohibidos: correo/teléfono/nombre, SQL/error text, body/request headers, access/refresh/recovery/invite tokens, claves service_role, MFA secrets/OTP/QR, signed URL, documentos personales y dumps de fila. No guardar `checks_snapshot` de IAM-9; usar `id_verificacion`.

## 9. IP, User-Agent y `tbl_registro_intentos`

`tbl_registro_intentos` actual es un contador compartido, no evidencia de evento: las EFs registran email en claro (`email` o `qr:<id_comercio>`), IP texto opcional y timestamp; registro limita 5/24 h por email y QR 30/h por comercio+IP, con consultas/escrituras best-effort. El código toma el primer valor de `x-forwarded-for`, trunca a 64 caracteres y no prueba en repo qué proxy es confiable. Registro consulta y después inserta, sin atomicidad mostrada para concurrencia. La tabla no tiene retención/purga encontrada; LIVE contiene 17 filas recientes.

Propuesta:

- No copiar IP/UA a SecurityEvent v1. Usar Auth provider logs existentes donde proceda; definir política de almacenamiento separada antes de cualquier persistencia nueva.
- Si operación futura requiere IP, solo tomarla en backend desde cabecera escrita/normalizada por proxy confiable y documentado; ignorar o no confiar en `X-Forwarded-For` directo no verificado. Parsear IPv4/IPv6, eliminar espacios/puertos correctamente y nunca usar valor del body.
- User-Agent no se necesita para V1; si se aprueba luego: máximo 512 bytes/caracteres con truncado, sin fingerprint ni perfil persistente.
- Email crudo ya existente en intentos es deuda de privacidad/retención, no extender su esquema como “solución” a IAM-10. Decidir retención/purga de esa tabla por separado y mantener el rate limiter compatible hasta un diseño probado.

## 10. Producers y correlación

**Permitidos:** RPC SECURITY DEFINER con `search_path` seguro y checks canónicos; trigger solo para transición concreta si no duplica el AuditLog; Edge Function server-side después de validar contexto; sistema/job con identidad operacional fija. La escritura del SecurityEvent de transición IAM crítica debe ocurrir en la misma transacción PostgreSQL de la mutación cuando sea técnicamente viable.

**Prohibidos:** insert desde Flutter/Web; que el cliente suministre tipo, actor, rol, comercio autorizado, severity u outcome; copiar `auth.uid()` como actor técnico sin revisar source; tratar `service_role` como actor humano; inferir actor humano desde `current_user` dentro de SECURITY DEFINER (el fallback técnico no-JWT queda acotado al helper aprobado y a conexiones directas confiables).

**Correlation ID:** UUID aleatorio creado por primera frontera confiable (EF o gateway) y propagado a RPC/AuditLog/Event por parámetro/contexto interno. No usar ID elegido por usuario como prueba de identidad; nunca incluir tokens ni datos personales. RPC sin frontera HTTP puede generar UUID local para evento, pero eso solo correlaciona ese registro. Formato/propagación en PostgREST y n8n queda pendiente de decisión; hoy no se encontró contrato transversal de request ID.

## 11. Inmutabilidad y retención propuesta

- Eventos append-only: productor puede insertar vía procedimientos allowlisted; ningún rol de usuario tenant/cliente puede INSERT/UPDATE/DELETE.
- Sin UPDATE incluso para corregir clasificación; para error material se emite evento de corrección relacionado, conservando evidencia original.
- Purga por job controlado dedicado, no cliente ni service_role de runtime; lote acotado, ventana aprobada, métricas y AuditLog administrativo del purge. No `TRUNCATE` ni hard-delete manual.
- Retención de propuesta (requiere validación legal/operativa): NOTICE/WARNING 90 días; HIGH/CRITICAL 365 días; INFO solo 30 días si finalmente se habilita. Purga también metadatos; exportar antes solo si se acuerda destino/controles.
- Auth provider audit logs conservan su propia retención/configuración de Supabase; no prometer la retención anterior a ese feed. No guardar IP/UA custom en V1, así no hay retención parcial inconsistente.
- Retención no está aprobada. Validar necesidad legal, plan de backups/PITR y efecto de backups tras purga antes de codificar.

## 12. RLS y acceso propuesto

Tabla en schema privado/no expuesto por Data API (preferible), RLS activa como defensa adicional, grants mínimos. Usuarios de comercio no consultan SecurityEvents directamente en V1.

| Actor | INSERT | SELECT | UPDATE | DELETE |
|---|---|---|---|---|
| Tenant Owner | No | No (V1) | No | No |
| Tenant Admin | No | No (V1) | No | No |
| Cashier / Logistics | No | No | No | No |
| Support | No | Sin acceso directo; eventual vista de incidente/ticket redacted con permiso temporal | No | No |
| SysAdmin | No | Consulta de seguridad operacional con auditoría de lectura, alcance asignado | No | No |
| SuperAdmin | No manual; acciones siguen RPCs | Investigación global con motivo/caso y trazabilidad | No | No |
| `authenticated` genérico | No | No | No | No |
| `service_role` runtime | Solo vía RPC/function allowlisted; no permiso tabla amplio por defecto | No por defecto | No | No |
| Job de retención | No para evento normal | Solo lo necesario | No | Delete limitado por política/fecha/catálogo aprobado |

Lectura de eventos de seguridad puede revelar login/riesgo en identidad con memberships múltiples; no debe seguir el RLS tenant de AuditLog automáticamente. Evaluar una vista resumida para owner/admin más adelante con selección de eventos tenant-scope y sin señales internas.

## 13. Notification/alerting (fuera de V1)

V1 registra. No envía email/push ni bloquea cuentas. En fase posterior se pueden evaluar: `OWNER.TRANSFER_COMPLETED` y `VERIFICATION.V1_REVOKED` → staff alert; repetición de `MFA.CHALLENGE_FAILURE_THRESHOLD` → alerta de seguridad; abuso onboarding → monitoreo/limitación. `PERMISSION.CRITICAL_DENIED` y errores de guard no producen notificación por cada ocurrencia. Cualquier lock automático exige contrato aparte, falsos positivos, desbloqueo y mecanismo de recovery.

## 14. Gaps y deuda de auditoría

1. `auth.audit_log_entries` estaba vacía LIVE pese a existencia de users/sessions/MFA; confirmar configuración, eventos cubiertos y retención en Dashboard con owner de Supabase.
2. Proyecto Free: no dispone de hooks password/MFA attempt ni Log Drain según docs consultados; si esos eventos son requisitos v1, decidir si actualizar plan u otra fuente. No crear provider ahora.
3. No existe tabla/app SecurityEvent ni RPC/EF/trigger que la escriba; no hay alerting.
4. `tbl_registro_intentos` almacena email/IP en claro, es best-effort, compartida por QR y registro y no tiene purga detectada; acordar retención/minimización por separado.
5. `tbl_logs_auditoria` registra snapshots JSON completos, 2.132 filas en ~27 días sin purge detectada, con lecturas tenant/staff; confirmar campos con PII y retención.
6. No se encontró request/correlation ID transversal EF→RPC→AuditLog.
7. No existe monitor/job LIVE para `fn_verificar_guards_sanos()`.
8. No se observó lock global de cuenta en capa RSUELVO.
9. IAM10-H1 / IAM5-CERT está clasificado como fallback intencional direct-PG; A1/A5 LIVE PASS, A2/A3/A4 PENDIENTE EXTERNO, A6 confirma consumidor directo. Sin P0 confirmado; no cambiar guards hasta certificar JWTs y credencial n8n.
10. Estado Auth Hook/log retention configurado desde Dashboard no pudo inspeccionarse con los repos/catálogos consultados; no concluir que “no está habilitado” solo por falta de source.

## 15. Decisiones que requieren aprobación antes de implementación

1. ¿V1 de SecurityEvent incluye solo eventos backend IAM (ownership, membership, verification, abuse threshold, critical denied) y excluye Auth provider hasta resolver el feed?
2. ¿El plan Free se mantiene, aceptando que login fallido/MFA failure no se ingieren al registro propio; o esos eventos son un requisito que implica upgrade/infra?
3. Retención propuesta 30/90/365 días: ¿aprobada tras revisión legal y backups?
4. Acceso staff-only global con lectura auditada: confirmar roles, ticket/caso requerido y si algún subconjunto se expondrá a tenant más adelante.
5. ¿`tbl_registro_intentos` es deuda y mantiene contador separado con política propia, o se planifica migración futura? No combinar tablas sin diseño de concurrencia y privacidad.
6. Completar A2/A3/A4 con sesiones/clave de QA controladas; confirmar usuario DB de la credencial Postgres n8n sin revelar su secreto. Mejorar contractualmente el regression guard antes de cambios IAM-10.
7. Confirmar si triggers y RPC duales producen AuditLogs duplicados para acciones IAM críticas; SecurityEvent emitirá máximo un evento semántico por transición efectiva.

## 16. E2E futuro requerido (no ejecutado en esta fase)

- transición real ownership emitió exactamente un evento para started/completed/cancelled según estado; denied no mutó recurso ni actor;
- membership SUSPENDED/ACTIVE/REVOKED/role elevation crea eventos solo tras mutación efectiva; retry no duplica evento semántico;
- V0→V1 y revocación crean resumen relacionado a `tbl_verificaciones_comercio`/AuditLog, sin copiar `checks_snapshot` ni motivo libre sensible;
- intento no-owner/AAL1 de acción crítica clasifica outcome correctamente, no crea evento si categoría trivial y no filtra existencia de recurso;
- abuse threshold agregado, carreras/concurrencia, rate window y fail-closed/fail-open decididos; evento no incluye email, IP ni honeypot input;
- tenant no puede leer/insertar/alterar/borrar SecurityEvent por PostgREST/RPC directo; Staff solo ve scope autorizado; service role no se convierte en actor humano;
- metadatos inválidos, event_type/outcome/severity/source no permitidos y payload con claves secretas son rechazados;
- correlation atraviesa EF→RPC→AuditLog→SecurityEvent sin ser autoridad ni secreto;
- purge por fecha no elimina eventos vigentes, es idempotente/auditable y cumple backup/retention contract;
- migrar/regresión `fn_verificar_guards_sanos` tras aprobación de resolución IAM-5;
- regresión IAM-1..9, `guards_sanos`, consumidores n8n/server y restore limpio.

## 17. Definition of Done para contrato

- Dueño aprueba taxonomía, severidad, outcome, actor model, privacidad, retención y RLS.
- Cada tipo tiene producer real, condición de emisión, actor, comercio, outcome, severidad, metadata allowlist, duplicación/idempotencia y alerting futuro definido.
- Diagrama de datos/event flow distingue AuditLog, Auth audit y SecurityEvent; indica explícitamente fuentes no disponibles en el plan actual.
- Auditoría del guard IAM-5 resuelta o riesgo aceptado explícitamente por decisión de seguridad (sin ignorar el hard rule actual).
- No se incluye SQL ejecutable ni cambios app/EF/workflow en el contrato aprobado; después se inicia fase backend con migración/RPC aprobada.

---

**Veredicto de esta fase:** auditoría y propuesta documental realizadas; contrato no aprobado; ninguna implementación iniciada.
**IAM-10 = PROPUESTA / NO IMPLEMENTADO.**
