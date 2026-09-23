# D-IAM-SECURITY-EVENTS — IAM-10 Security Events (REV3.2 contractual amendment)

**Estado vigente:** contrato REV3.2 aprobado; backend IAM-10 implementado y **CERRADO CON CERTIFICACIONES DIFERIDAS DOCUMENTADAS**. Este documento conserva el expediente histórico de auditoría y contrato.
**Auditoría:** 2026-09-23 · Vault `728d06f`; Flutter `b3ebaa95c8e4c950a98637835094bea573c0b2bf`; Web `2c4eb51bf440072dafc276488156559ddb975e1a`.
**Entorno LIVE inspeccionado en solo lectura:** Supabase `iwfaktlxebxtocmswdvv` (RSUELVO, ACTIVE_HEALTHY, PostgreSQL 17.6.1.155, plan Free). `pg_cron` 1.6.4 habilitado en DB `postgres`; 2 jobs activos completaron 1.440/1.440 ejecuciones cada uno en las últimas 24 h.

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

**IAM10-H1 / IAM5-CERT (resultado histórico de frontera abajo):** la definición LIVE de `rsuelvo.fn_es_service_role()` es `SECURITY DEFINER` y tiene fallback `auth.jwt() IS NULL AND current_user IN ('postgres','service_role')`; `fn_tiene_aal2()` tiene fallback equivalente. La migración 87 explica el propósito: JWT presente manda; el fallback aplica solo a conexión directa sin JWT para backend confiable. El incidente P0 histórico fue un `current_user` OR independiente aun con JWT, patrón distinto. SQL Editor confirma el contexto directo (JWT NULL y helper TRUE), pero no prueba una petición PostgREST. A1 anon HTTP probó que PostgREST no cae en fallback. n8n direct-PG era un consumidor real cuando se realizó el inventario, pero n8n quedó retirado del target por decisión posterior; conservar el fallback durante la transición a Python/VPS está documentado. No se modificaron guards.

## 1.1 IAM10-H1 / IAM5-CERT — frontera PostgREST vs PostgreSQL directo

**Migración 87 canónica:** inspeccionada junto con la función LIVE. Lógica desplegada:

- `fn_es_service_role()`: JWT `role=service_role` concede; si `auth.jwt()` es NULL, permite solo `current_user IN ('postgres','service_role')`.
- `fn_tiene_aal2()`: sin JWT permite solo los roles PostgreSQL anteriores; JWT service_role pasa por identidad backend; cualquier otro JWT recibe AAL2 únicamente si claim `aal='aal2'`.
- No-JWT en SQL Editor es `DIRECT_PG_TRUSTED_CONTEXT`, un contexto backend privilegiado esperado bajo el diseño actual. El helper se probó allí como TRUE; esto por sí solo no indica bypass HTTP.

### Inventario real de consumidores PostgreSQL directos

El inventario histórico n8n mostró 16 workflows activos. Se inspeccionaron las versiones activas y la metadata de credenciales (sin secretos): **8 workflows tenían 25 nodos `n8n-nodes-base.postgres`** con una credencial `postgres` compartida llamada `Postgres account`. Tras la decisión de retirar n8n, esta lista es LEGACY SOURCE para `MIG-PY-01`, no un consumidor objetivo que requiera nueva certificación:

- WF-10 (3 nodos), WF-12 (1), WF-13 (3), WF-14 (5), WF-20 (4), WF-21 (1), WF-25-C (1), WF-80 (7).
- Entre las operaciones llamadas están `fn_upsert_cliente`, `fn_solicitar_reserva`, `fn_agregar_lista_espera_v2`, `fn_crear_pedido_desde_reserva`, `fn_generar_cobro` y consultas/logs de WF-80.
- Bitácora canónica de n8n registra `Postgres account` apuntando al proyecto `iwfaktlxebxtocmswdvv` con rol `bypassrls`; entradas de 2026-09-19 describen que n8n usa usuario `postgres` por conexión PG sin JWT y que quitar esa identidad rompió RPCs PG-node. No se ejecutaron workflows de negocio durante esta certificación.
- **Respuesta A6:** sí existe consumidor real PostgreSQL directo que justifica el contexto sin JWT. La lista MCP protege secretos; no se leyó la contraseña ni se hizo conexión de prueba bajo esa credencial, así que el usuario SQL actual de ese secreto no se revalidó en este turno. La evidencia de productor activo + credencial type `postgres` + bitácora de rol/uso se considera evidencia LIVE de inventario, no una ejecución de RPC.

### Matriz de certificación A1–A6 (corte de auditoría previo al retiro de n8n)

| Caso | Resultado | Evidencia / límite |
|---|---|---|
| **A1 anon real vía PostgREST** | **LIVE PASS** | POST `/rest/v1/rpc/fn_es_service_role`, API key pública anon, sin header `Authorization`, perfil `rsuelvo`: HTTP 200, cuerpo `false`. La metadata de DB confirma `anon` tiene EXECUTE en helper service role; no tiene EXECUTE en `fn_tiene_aal2()` ni en RPC crítica `fn_solicitar_habilitacion_v1`. No se abrió ningún grant. |
| **A2 JWT authenticated AAL1** | **PENDIENTE EXTERNO** (código inspeccionado) | No había sesión/JWT QA autenticada AAL1 disponible sin credenciales interactivas del titular. La lógica JWT branch espera service_role false, AAL2 false y acción crítica `mfa_requerido`; no se atribuye resultado LIVE. |
| **A3 JWT authenticated AAL2** | **PENDIENTE EXTERNO** (código inspeccionado) | Requiere sesión real MFA AAL2. No se tenía token/sesión interactiva ni se solicitaron contraseñas. Lógica espera service_role false y AAL2 true; no se atribuye resultado LIVE. |
| **A4 JWT service_role por HTTP** | **PENDIENTE EXTERNO** (código inspeccionado) | No se dispuso de la service_role key para request HTTP y no se buscó/exhibió un secreto local. Lógica JWT branch concede `fn_es_service_role=true` y comportamiento técnico de AAL2. Certificar con credencial de servicio en contexto controlado. |
| **A5 SQL Editor / PG directo sin JWT** | **LIVE PASS · DIRECT_PG_TRUSTED_CONTEXT** | Query de solo lectura: `auth.jwt()` NULL, `fn_es_service_role()` TRUE, `fn_verificar_guards_sanos()` `{"ok":true}`. Resultado esperado para contexto PostgreSQL privilegiado; no representa PostgREST. |
| **A6-n8n consumidor PostgreSQL directo (estado en la auditoría original)** | **LIVE inventario + CÓDIGO/bitácora; luego SUPERSEDED** | En el inventario había 16 workflows activos; 8/25 nodos Postgres directos. La bitácora registraba el rol bypassrls y fallo histórico al perder la identidad PG sin JWT. La decisión arquitectónica posterior retira n8n del target. |

**Resultado de frontera:** en la petición anon real observada el helper devolvió `false` por HTTP; ese resultado es consistente con el camino JWT/rol no privilegiado. No se expuso el GUC JWT de esa petición. No se observó bypass anon ni se confirma P0. A2/A3/A4 permanecen sin certificación LIVE, por falta de tokens/clave legítimos disponibles. Por evidencia actual la conclusión es **SAFE AS DESIGNED para la frontera A1 y el contexto A5, con certificación JWT de usuario/service_role aún parcial**, no certificación total de la matriz.

### `fn_verificar_guards_sanos()` — evaluación, sin cambios

Su comprobación estática actual es insuficiente como análisis estructural: busca `current_user` y la subcadena `auth.jwt() is null`, y la presencia de texto JWT/service_role; no demuestra que el fallback esté ligado exclusivamente a la rama NULL ni que no exista un OR independiente cuando el JWT está presente. Para AAL2 tampoco prueba que la rama de usuario compare únicamente `aal='aal2'`. Además su check conductual ejecutado desde SQL Editor solo certifica A5, contexto privilegiado.

Mejora propuesta **no implementada**: el guard estático debería contrastar una forma canónica normalizada/parseable (o inspección estructural robusta del cuerpo) de ambas funciones, rechazar cualquier rama JWT que pueda OR-conceder por `current_user`, validar que el rol service_role se compare con `auth.jwt()->>'role'`, y que usuarios ordinarios solo pasen por claim AAL2 exacto. Mantener una prueba SQL directa etiquetada A5; complementar con harness HTTP externo A1–A4 que reporte contexto/status/helper y no abra grants temporales. Esta revisión no debe hacer que SQL Editor TRUE se marque como vulnerabilidad.

**Clasificación vigente de IAM10-H1:** A1 LIVE PASS; A2/A3/A4 PENDIENTE EXTERNO; A5 LIVE PASS (`DIRECT_PG_TRUSTED_CONTEXT`). El fallback direct-PG permanece como compatibilidad transitoria hasta la migración Python/VPS; no es P0 confirmado y no se modifican guards en este cierre. A6-n8n quedó SUPERSEDED / NO PASS por decisión arquitectónica posterior; no se restaurará n8n Cloud para completar esa prueba. El gate sucesor es `IAM10-A6-PYTHON`, PENDIENTE antes del go-live Python/VPS. Ver `MIG-PY-01-N8N-A-PYTHON-VPS.md`.

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

## 4. Contrato REV3.1 — ajuste operativo de purge; resto de REV3 congelado

En el corte documental de REV3.1, REV3 había sustituido la normativa §§4–17 de REV1/REV2 y solo se proponía el contrato: aún no existían tabla, RPC, cron de purge ni emisión IAM-10. Esa descripción es histórica; las migraciones 101/102 implementaron después REV3.2. SecurityEvent no replica AuditLog.

### 4.1 Catálogo V1 congelado

Todos tienen scope `id_comercio NOT NULL`. Severidad y outcome son constantes por evento, fijados abajo y derivados por el writer; no son parámetros de producer ni de cliente. `source=POSTGRES_RPC` en los ocho.

| `event_type` | RPC producer | Transición exacta | Severidad | Outcome |
|---|---|---|---|---|
| `OWNER.TRANSFER_STARTED` | `fn_iniciar_transferencia(p_id_comercio,p_destino)` | Se inserta una nueva fila `PENDIENTE` después de lock/lookup y sin transferencia vigente equivalente. | HIGH | SUCCESS |
| `OWNER.TRANSFER_COMPLETED` | `fn_responder_transferencia(p_id,p_acepta=true)` | Owner del comercio cambia del origen esperado al destino y la transferencia pasa PENDIENTE→ACEPTADA en la misma transacción. | CRITICAL | SUCCESS |
| `OWNER.TRANSFER_CANCELLED` | `fn_cancelar_transferencia(p_id)` | Transferencia PENDIENTE→CANCELADA efectiva. El rechazo del destino no es CANCELLED y queda fuera del catálogo. | NOTICE | CANCELLED |
| `MEMBERSHIP.SUSPENDED` | `fn_gestionar_vinculo(...,p_accion='SUSPENDER'|'DESACTIVAR')` | La membership objetivo cambia ACTIVE→SUSPENDED. | HIGH | SUCCESS |
| `MEMBERSHIP.REACTIVATED` | `fn_gestionar_vinculo(...,p_accion='CREAR')` o `CAMBIAR` mismo rol | La membership persistida cambia SUSPENDED→ACTIVE; solo si el estado previo leído bajo lock era SUSPENDED. | NOTICE | SUCCESS |
| `MEMBERSHIP.REVOKED` | `fn_gestionar_vinculo(...,p_accion='REVOCAR')` | La membership cambia ACTIVE/SUSPENDED→REVOKED. | HIGH | SUCCESS |
| `MEMBERSHIP.PRIVILEGE_CHANGED` | `fn_gestionar_vinculo(...,p_accion='CAMBIAR')` | Cambia realmente el rol activo o su conjunto de capabilities; una sola emisión por cambio semántico, no por suspender/crear filas intermedias. | HIGH | SUCCESS |
| `VERIFICATION.V1_REVOKED` | `fn_revocar_verificacion_v1(p_id_comercio,p_motivo)` | ACTIVO→PENDIENTE_VERIFICACION y evidencia REVOCADA insertada en la misma transacción. | HIGH | SUCCESS |

`VERIFICATION.V1_GRANTED`, Auth, MFA, recovery, denied, abuse thresholds y todo evento fuera de esta tabla permanecen OUT. No ampliar el catálogo sin nueva aprobación.

### 4.2 Idempotencia por productor y concurrencia

Regla común: writer se llama solo después de la transición efectiva y dentro de su misma transacción. Rollback elimina transición, AuditLog y SecurityEvent juntos. Solo un thread obtiene el lock y cruza el estado de origen; retries posteriores ven estado final/no-op y emiten cero. No se usa `event_type + actor + comercio` como clave global ni `correlation_id` como deduplicador. V1 omite `producer_event_id`: RPC transaccional más estado/locks e identidad de recurso cubren los retries; no hay fuente externa con ID estable.

| Evento | Identidad de transición | Retry tras commit | Concurrencia / control anti-duplicado |
|---|---|---|---|
| `OWNER.TRANSFER_STARTED` | `tbl_transferencias_propiedad.id` nuevo; clave activa por comercio. | Misma solicitud lógica (mismo owner+destino) devuelve ID PENDIENTE existente; cero insert y cero evento. | `fn_iniciar_transferencia` debe tomar `FOR UPDATE` de la fila comercio y revalidar owner, expirar vencidas, buscar pendiente vigente. Si owner+destino coincide, devuelve esa transferencia; otro destino devuelve `transferencia_pendiente`. El índice LIVE `transf_pendiente_unica` (UNIQUE por `id_comercio WHERE estado='PENDIENTE'`) queda como última defensa; convertir su carrera actual que retorna error en lookup del ganador. No insertar SecurityEvent si no se obtiene/crea una transición idempotente.
| `OWNER.TRANSFER_COMPLETED` | `transfer_id`; transición PENDIENTE→ACEPTADA y cambio efectivo de `propietario_id`. | Estado no pendiente/owner ya cambiado → resultado no-op/ya procesado; cero evento. | `SELECT ... FOR UPDATE` de transferencia serializa; comprobar owner origen antes de actualizar; evento una sola vez tras verificar `UPDATE` efectivo.
| `OWNER.TRANSFER_CANCELLED` | `transfer_id`; PENDIENTE→CANCELADA. | CANCELADA/no pendiente → cero evento. | Lock de transferencia serializa contra aceptar/rechazar/cancelar; solo ganador de PENDIENTE inserta el evento que corresponda.
| `MEMBERSHIP.SUSPENDED` | `membership_id`; edge ACTIVE→SUSPENDED. | Estado distinto de ACTIVE → no-op/error de negocio, cero evento. | Lock de membership objetivo; emitir solo si `UPDATE ... WHERE estado='ACTIVE' RETURNING` devuelve fila.
| `MEMBERSHIP.REACTIVATED` | `membership_id`; edge SUSPENDED→ACTIVE. | ACTIVE → `reactivado=false`/no-op, cero evento. | Lock de fila existente; emitir solo si transición condicional SUSPENDED→ACTIVE devuelve fila.
| `MEMBERSHIP.REVOKED` | `membership_id`; edge ACTIVE/SUSPENDED→REVOKED terminal. | REVOKED/no encontrado → no-op, cero evento. | Lock de fila; emitir solo si transición condicional devuelve fila. Nunca reactivar REVOKED.
| `MEMBERSHIP.PRIVILEGE_CHANGED` | Membership anterior + membership resultante; comparar tupla y capabilities. | Si destino ya está ACTIVE y origen ya refleja el resultado previo, devolver `ya_cambiado`, cero evento. | Lock de membership origen y destino; comparar el estado antes/después final. Un cambio CAMBIAR es un evento semántico único, no contar sus updates auxiliares como SUSPENDED/REACTIVATED. La implementación debe detectar replay antes de mutar para no repetir la transición.
| `VERIFICATION.V1_REVOKED` | `verification_id` recién insertado, asociado al comercio bloqueado. | `ya_v0` → cero evidencia adicional/evento. | `SELECT tbl_comercios ... FOR UPDATE`; insertar evidencia y actualizar estado en la misma transacción; emitir solo después de comprobar ACTIVO→V0. Dos revocaciones concurrentes se serializan; la segunda ve V0.

Verificación LIVE: `transf_pendiente_unica` ya existe; las RPC owner/membership/verificación usan locks de fila en la lógica inspeccionada. La función actual de inicio owner no hace lock/lookup idempotente para mismo owner+destino; su contrato actual de carrera devuelve `transferencia_pendiente` sin reutilizar el ID. REV3 requiere modificar ese RPC antes de insertar el evento. `fn_gestionar_vinculo` permite `CAMBIAR` también sobre una membership SUSPENDED; la implementación debe añadir la detección de replay definida arriba. Ninguno de estos cambios se implementa con REV3.

Histórico REV3.1: el texto previo de este expediente amplió la dirección a cuatro valores; IAM10-B1 confirmó que esa expansión no estaba aprobada. La norma vigente es REV3.2 §5, que permite solo `ELEVATED`, `REDUCED` y `MIXED`, y falla cerrado si dos códigos distintos llegan a tener capacidades iguales.

### 4.3 Metadata cerrada y enforcement

El producer no acepta `metadata` del cliente. Cada RPC construye internamente los campos tipados a partir de filas bloqueadas y valores ya validados; el helper valida allowlist antes de insertar y el constraint vuelve a validarla.

| Event type | Claves exactas requeridas |
|---|---|
| `OWNER.TRANSFER_STARTED` | `transfer_id`, `target_user_id` |
| `OWNER.TRANSFER_COMPLETED` | `transfer_id`, `previous_owner_user_id`, `target_user_id` |
| `OWNER.TRANSFER_CANCELLED` | `transfer_id` |
| `MEMBERSHIP.SUSPENDED` / `MEMBERSHIP.REACTIVATED` / `MEMBERSHIP.REVOKED` | `membership_id`, `target_user_id` |
| `MEMBERSHIP.PRIVILEGE_CHANGED` | Según enmienda REV3.2 §5.2: `previous_membership_id`, `new_membership_id`, `target_user_id`, `from_role`, `to_role`, `direction` |
| `VERIFICATION.V1_REVOKED` | `verification_id` |

UUIDs son IDs internos RSUELVO (`tbl_usuarios.id_usuario`, `tbl_usuario_comercio.id`, `tbl_transferencias_propiedad.id`, `tbl_verificaciones_comercio.id_verificacion`), nunca `auth.users.id`. Metadata no incluye correo, motivo libre, SQL/error, snapshots, tokens, headers, signed URLs, QR ni documentos.

Enforcement contractual: `rsuelvo_private.fn_security_event_metadata_valid(text,jsonb) IMMUTABLE` pura y allowlisted por event type; rechaza claves extra/faltantes, tipo incorrecto, UUID/string inválidos, direction/role codes no válidos y objeto no JSON. CHECK llama al validator. Límite `octet_length(metadata::text) <= 2048` y `jsonb_typeof(metadata)='object'`. El helper de escritura también valida antes del INSERT. Sin SQL JSON arbitrario en endpoints de lectura.

### 4.4 Schema físico mínimo propuesto (sin DDL en REV3.1)

Tabla: `rsuelvo_private.tbl_security_events`, schema privado no expuesto a PostgREST/Data API. La configuración de schemas expuestos se verifica en backend; nunca añadir `rsuelvo_private`. Revocar `USAGE` del schema y todos los grants de tabla a `PUBLIC`, `anon`, `authenticated` y `service_role`.

| Columna | Tipo/constraint canónico | Nota |
|---|---|---|
| `id_evento` | `uuid PRIMARY KEY DEFAULT gen_random_uuid()` | Identidad del evento. |
| `occurred_at` | `timestamptz NOT NULL` | Lo fija writer con `clock_timestamp()` tras transition efectiva; nunca input cliente. |
| `created_at` | `timestamptz NOT NULL DEFAULT transaction_timestamp()` | Timestamp de persistencia/transacción. |
| `event_type` | `text NOT NULL CHECK` allowlist exacta de los 8 tipos 4.1 | Sin catálogo dinámico en V1. |
| `severity` | `text NOT NULL CHECK IN ('NOTICE','HIGH','CRITICAL')` + CHECK cross-field | Constante por event_type; no input producer. |
| `retention_days` | `smallint GENERATED ALWAYS AS (CASE severity WHEN 'NOTICE' THEN 180 WHEN 'HIGH' THEN 365 WHEN 'CRITICAL' THEN 365 END) STORED` | No parámetro ni editable; purger aplica por `occurred_at`. |
| `outcome` | `text NOT NULL CHECK IN ('SUCCESS','CANCELLED')` + CHECK cross-field | Exacto por event_type 4.1. |
| `actor_type` | `text NOT NULL CHECK IN ('USER','SERVICE_ROLE')` | Tipo técnico/humano explícito. |
| `actor_user_id` | `uuid NULL REFERENCES rsuelvo.tbl_usuarios(id_usuario) ON DELETE RESTRICT` + CHECK | USER exige ID; SERVICE_ROLE exige NULL. |
| `id_comercio` | `uuid NOT NULL REFERENCES rsuelvo.tbl_comercios(id_comercio) ON DELETE RESTRICT` | Scope requerido en todos los eventos V1. |
| `source` | `text NOT NULL DEFAULT 'POSTGRES_RPC' CHECK (source='POSTGRES_RPC')` | Fuente cerrada en V1. |
| `producer` | `text NOT NULL CHECK` en cinco RPCs canónicas | `fn_iniciar_transferencia`, `fn_responder_transferencia`, `fn_cancelar_transferencia`, `fn_gestionar_vinculo`, `fn_revocar_verificacion_v1`; CHECK cruzado limita cada tipo a su RPC. |
| `correlation_id` | `uuid NULL` | Trazabilidad opcional; no identidad, secreto ni dedup. |
| `metadata` | `jsonb NOT NULL CHECK` objeto + validator + máximo 2.048 bytes | JSON único allowlist por tipo (4.3). |

Constraints cruzados `event_type→severity,outcome,producer`, actor_id/actor_type y metadata son obligatorios. `ON DELETE RESTRICT` conserva integridad histórica; las identidades/comercios se desactivan/anonimizan según su lifecycle, no hard-delete. `producer_event_id` se **omite** en V1: solo hay producers PostgreSQL síncronos con transición/locks idempotentes; una ingestión Auth futura necesitaría contrato e ID externo estable antes de añadirlo. Sin `ip`, `user_agent`, `session_ref`, `auth_user_id`, `audit_log_id` ni columna libre extra.

### 4.5 Patrón único de escritura

Usar helper central `rsuelvo_private.fn_emit_security_event(...)`, `SECURITY DEFINER`, `SET search_path = pg_catalog, rsuelvo_private, rsuelvo`, propiedad de `postgres` (igual a los RPC producers LIVE). Sin grants a `PUBLIC`, `anon`, `authenticated` ni `service_role`; sus propietarios `postgres` lo invocan internamente. Los RPC producers siguen siendo únicos puntos de entrada autorizados.

Firma conceptual: `(event_type text, actor_type text, actor_user_id uuid, id_comercio uuid, producer text, correlation_id uuid, metadata jsonb) RETURNS uuid`. No recibe severity, outcome, retention_days ni source; los deriva del catálogo cerrado. Valida pairing event/producer, actor/scope y metadata, asigna timestamps, inserta una fila y devuelve `id_evento`. Actor y comercio vienen ya autorizados desde producer bajo JWT/membership/AAL/estado aplicables. El writer no consulta salud del scheduler ni existencia de eventos expirados. Si la tabla está disponible, constraints válidos y el INSERT tiene éxito, transición IAM + SecurityEvent se confirman atómicamente. Si el INSERT contractual falla, la transición asociada revierte. Una caída de `pg_cron`, backlog o demora de purge nunca causa por sí misma un error del writer ni bloquea la operación IAM.

Actor: transfer/verification RPCs actuales derivan el usuario por `auth.uid()/sub → tbl_usuarios`; son `USER` no nulo. `fn_gestionar_vinculo` LIVE actual no separa/deriva actor humano de forma canónica (sus params identifican target); backend debe derivar actor USER desde JWT y no reutilizar `p_id_usuario` como actor. Para invocación direct-PG/service_role validada por el helper IAM5 existente, actor=`SERVICE_ROLE`, actor_user_id=NULL; no inferir humano desde `current_user`. Esto conserva IAM10-H1 sin cambiar guards. Si actor/scope no son válidos, producer no llama al writer.

### 4.6 Grants, RLS y append-only

`rsuelvo_private.tbl_security_events`: `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY`; sin grants de tabla a API roles. Runtime no tiene SELECT/INSERT/UPDATE/DELETE directos, incluido `service_role`. Solo helper y RPCs SECURITY DEFINER con owner `postgres` acceden con permisos de owner; no exponer la tabla por Data API. RLS es defensa adicional, no autorización única. Las funciones usan `search_path` fijo/seguro y referencias calificadas.

- **INSERT:** solo `fn_emit_security_event` internamente; REVOKE a PUBLIC/anon/authenticated/service_role. Producers construyen metadata internamente.
- **UPDATE:** sin grant a ningún runtime/produtor; no existe RPC UPDATE. Eventos no se corrigen in-place.
- **DELETE:** sin grant runtime/producer/lectura; solo `fn_security_events_purge` (4.8). Database owner break-glass es control de infraestructura fuera del runtime; toda intervención excepcional debe auditarse.
- **SELECT:** solo `fn_security_events_buscar` tras autorización staff (4.7); sin grant de tabla a authenticated/service_role.

RLS sin policy para usuarios API (default deny). Revocar explícitamente `USAGE` del schema y `ALL` sobre todas las tablas/secuencias a PUBLIC/anon/authenticated/service_role, y configurar default privileges de `postgres` en el schema privado para no conceder acceso a tablas futuras. Funciones privilegiadas se limitan por ACL, validaciones y uso interno; los grants no se sustituyen por RLS.

### 4.7 Lectores staff y RPC de búsqueda

Únicos lectores V1: `ROLE_SUPERADMIN` y `ROLE_SYSADMIN`, ambos **global SELECT**; autorización backend con `fn_es_superadmin() OR fn_tiene_rol('ROLE_SYSADMIN')`. `ROLE_SUPPORT`: sin acceso directo. Roles tenant, `authenticated` genérico, anon y service_role: sin acceso. No existe flujo caso/ticket para esta fase.

RPC expuesta en schema `rsuelvo`: `fn_security_events_buscar(p_from timestamptz,p_to timestamptz,p_event_type text DEFAULT NULL,p_id_comercio uuid DEFAULT NULL,p_actor_user_id uuid DEFAULT NULL,p_before_at timestamptz DEFAULT NULL,p_before_id uuid DEFAULT NULL,p_limit integer DEFAULT 100) RETURNS TABLE(...)`, `SECURITY DEFINER`, search_path fijo. Revocar EXECUTE de PUBLIC/anon/service_role; conceder solo `authenticated`; cada llamada valida rol global en DB.

- `p_from/p_to` requeridos, `p_from < p_to`, `p_to <= now()`, rango máximo 31 días y `p_from >= now()-365 days`.
- `event_type`, comercio y actor son filtros exactos opcionales; event_type debe pertenecer a allowlist. No hay filtros JSON ni SQL/query libre.
- `p_limit` 1..100; cursor keyset con `p_before_at` y `p_before_id` ambos NULL o ambos requeridos. Orden estable `occurred_at DESC, id_evento DESC`; siguiente página usa la última pareja retornada.
- Campos retornados: `id_evento`, `occurred_at`, `created_at`, `event_type`, `severity`, `retention_days`, `outcome`, `actor_type`, `actor_user_id`, `id_comercio`, `source`, `producer`, `correlation_id`, `metadata` ya validada. No retorna headers, IP, UA, secretos ni payload libre.
- Cada búsqueda autorizada escribe un AuditLog `security_events_consultados` con actor staff, sin contenido de eventos ni metadata; registra ventana, filtros usados y límite para trazabilidad de acceso.

### 4.8 Retención y purge operable

Política V1 cerrada, basada en `occurred_at` (UTC): `NOTICE=180 días`; `HIGH=365`; `CRITICAL=365`. `retention_days` es generated stored (4.4), no configurable en insert. No conservar SecurityEvents indefinidamente.

**Scheduler LIVE verificado:** extensión `pg_cron` 1.6.4 instalada, `cron.job` y `cron.job_run_details` presentes, database target `postgres`. Hay dos jobs activos con `username=postgres`, schedule cada minuto; en las 24 h consultadas cada uno tiene 1.440 ejecuciones `succeeded`, 0 no-succeeded y última ejecución `2026-09-23 14:16 UTC`. Esto prueba scheduler operativo observado, no el nuevo job aún inexistente. REV3 usará el mismo `pg_cron` tras smoke de alta/ejecución del nuevo job en backend; no requiere infraestructura externa.

Contrato de jobs: `cron.schedule('rsuelvo-security-events-purge','*/5 * * * *','select rsuelvo_private.fn_security_events_purge(500)')` y `cron.schedule('rsuelvo-security-events-purge-watchdog','*/15 * * * *','select rsuelvo_private.fn_security_events_purge_watchdog()')`; el scheduler corre como `postgres`. Purge: cada llamada es una transacción atómica que procesa chunks de 500 con `FOR UPDATE SKIP LOCKED`, hasta 10 chunks/5.000 filas por corrida y termina. Re-ejecución procesa backlog restante. Solo corta filas vencidas por severity; nunca recibe fecha/cutoff del llamador. Usa lock advisory transaccional para evitar solape con otra purga. Devuelve `deleted_count`; batch vacío no crea AuditLog.

`fn_security_events_purge(p_batch_size integer)` SECURITY DEFINER propiedad `postgres`, valida 1..500, calcula corte internamente, borra solo expirados, es idempotente y escribe **un AuditLog por ejecución con deleted_count>0** (`accion='security_events_purge'`, tabla `tbl_security_events`, scope/actor NULL, metadata administrativa numérica y versión de política; sin contenido personal). DELETE + AuditLog son atómicos: error → rollback total y run `failed` en `cron.job_run_details`; el siguiente tick de 5 min reintenta.

Job watchdog cada 15 min (`fn_security_events_purge_watchdog`, también solo `postgres`) inspecciona `cron.job_run_details`: si hay 2 fallas consecutivas o no hay ejecución exitosa de purge en 20 min, escribe **una sola fila AuditLog `security_events_purge_failure` por incidente** con `incident_started_at`; no repite filas cada tick. Al recuperarse registra una sola fila `security_events_purge_recovered`, cuando el backlog realmente vencido quedó drenado. El nivel operativo se deriva de la duración del incidente no resuelto: `DEGRADED` tras >20 min, `HIGH` tras >24 h y `CRITICAL` tras >72 h. Esos niveles describen monitoreo/prioridad operativa, no severity de SecurityEvent ni autorización para bloquear IAM. El owner de seguridad/DB revisa AuditLog y `cron.job_run_details`.

Si purge falla: eventos nuevos siguen ingresando normalmente; IAM sigue funcionando; backlog expirado permanece hasta recuperación; no se usa otra ruta de borrado ni se acortan retenciones. Cada tick de 5 min reintenta. Al volver, los batches procesan todas las filas expiradas según su cutoff real; los no expirados permanecen. La demora se registra como `retention SLA breach / operational debt`. Una falla del watchdog también queda en el historial `cron.job_run_details` y requiere revisión operativa. **Purge/backlog nunca participa en el control transaccional del writer.**

### 4.9 Índices mínimos

Además de PK en `id_evento`, crear solo:

1. `(occurred_at DESC, id_evento DESC)` — consulta/cursor global y purge oldest-first.
2. `(event_type, occurred_at DESC, id_evento DESC)` — filtro tipo.
3. `(id_comercio, occurred_at DESC, id_evento DESC)` — filtro comercio.
4. `(actor_user_id, occurred_at DESC, id_evento DESC)` — filtro actor.
5. `(severity, occurred_at)` — corte de purge por 180/365 días.

No índice separado en `producer_event_id` porque la columna no existe en V1; no indexar JSONB ni `correlation_id` sin caso medido.

### 4.10 Estado IAM10-H1 y regresión backend

| Caso | Clasificación vigente |
|---|---|
| A1 anon/PostgREST | LIVE PASS |
| A2 authenticated AAL1 | PENDIENTE EXTERNO |
| A3 authenticated AAL2 | PENDIENTE EXTERNO |
| A4 service_role HTTP | PENDIENTE EXTERNO |
| A5 PostgreSQL directo sin JWT | LIVE PASS · `DIRECT_PG_TRUSTED_CONTEXT` |
| A6-n8n direct-PG | SUPERSEDED / NO PASS / NO APLICA AL TARGET; smoke preparado pero no ejecutado |
| IAM10-A6-PYTHON | PENDIENTE / GATE PRE-GO-LIVE tras la migración Python/VPS |

Conclusión vigente: **SAFE AS DESIGNED para A1/A5 observados; A2/A3/A4 permanecen PENDIENTE EXTERNO; NO P0 confirmado.** La certificación histórica A6-n8n no se transforma en PASS y deja de ser gate de IAM-10. El gate futuro es IAM10-A6-PYTHON; nunca abrir grants temporales para facilitarlo.

### 4.11 E2E/DoD backend para este contrato

El backend IAM-10 quedó aprobado a nivel de implementación conforme al reporte QA. Las certificaciones diferidas A2/A3/A4, E2E integral IAM-1..9 y restore permanecen registradas como pendientes externos. La prueba n8n direct-PG fue superseded por el cambio de arquitectura; la frontera de runtime futura se valida mediante `IAM10-A6-PYTHON` antes del go-live Python/VPS.

**Resultado contractual de REV3.1 (corte histórico previo a implementación):** REV3 fijó catálogo, schema, retención/purge, lectores, escritura, grants/RLS, índices e idempotencia; REV3.1 aclaró que purge es operacional y no bloquea IAM. Los cambios identificados a `fn_iniciar_transferencia` y `fn_gestionar_vinculo` pasaron al alcance de implementación backend. El estado vigente de implementación y sus certificaciones diferidas se registra arriba y en `CIERRE-IAM-ONBOARDING.md`.

---

**Veredicto contractual histórico (antes de implementar backend):** REV3.1 aprobada; GO backend. Esta instantánea quedó superseded por la implementación 101/102, el cierre IAM10-B1 y el estado vigente documentado al inicio de este archivo y en `CIERRE-IAM-ONBOARDING.md`.

## 5. REV3.2 — enmienda contractual IAM10-B1

Esta enmienda corrige el contrato de dirección de privilegio y la identidad de las filas involucradas en `CAMBIAR`. El catálogo de ocho eventos, severidades, resultados, retención, acceso, escritura, purge y demás cláusulas REV3.1 se conservan. No añade eventos ni roles.

### 5.1 Matriz de cambios de rol permitidos

`fn_gestionar_vinculo(..., p_accion='CAMBIAR')` bloquea como destino `ROLE_SUPERADMIN`, pero no restringe el rol de origen. Para los demás destinos exige rol existente, protege al owner de cambio de rol, valida sucursal y conserva N-4 para cajero. Por tanto, para sujetos no-owner que satisfacen esas condiciones, los pares distintos de rol admitidos son las 25 celdas siguientes. La dirección compara los conjuntos efectivos IAM-6 del origen y destino: el destino contiene estrictamente al origen = `ELEVATED`; el origen contiene estrictamente al destino = `REDUCED`; ninguno contiene al otro = `MIXED`.

Conjuntos cerrados usados por la comparación (role scopes y capabilities IAM-6; abreviaciones no aplican):

| role code | Capabilities |
|---|---|
| `ROLE_SUPERADMIN` | `authorization.resolve`, `business.close`, `business.configure`, `business.create`, `business.read`, `business.state`, `business.transferOwnership`, `credits.deposit.read`, `credits.packages.manage`, `credits.read`, `credits.resolve`, `customers.export`, `inventory.manage`, `inventory.read`, `logistics.manage`, `logistics.own`, `members.invite`, `members.lifecycle`, `members.mutate`, `members.read`, `orders.manage`, `payments.verify`, `reports.operational`, `reports.sensitive`, `solicitudes.read`, `solicitudes.resolve` |
| `ROLE_SYSADMIN` | `business.create`, `business.read`, `credits.read`, `reports.operational`, `solicitudes.read`, `solicitudes.resolve` |
| `ROLE_SUPPORT` | `business.read`, `credits.read`, `reports.operational` |
| `ROLE_TENANT_ADMIN` | `business.configure`, `business.read`, `credits.read`, `customers.export`, `inventory.manage`, `inventory.read`, `logistics.manage`, `members.invite`, `members.read`, `orders.manage`, `payments.verify`, `reports.operational` |
| `ROLE_TENANT_CASHIER` | `business.read`, `inventory.read`, `orders.manage`, `payments.verify` |
| `ROLE_LOGISTICS_AGENT` | `business.read`, `logistics.own` |

| from \ to | SYSADMIN | SUPPORT | TENANT_ADMIN | TENANT_CASHIER | LOGISTICS_AGENT |
|---|---|---|---|---|---|
| SUPERADMIN | REDUCED | REDUCED | REDUCED | REDUCED | REDUCED |
| SYSADMIN | — | REDUCED | MIXED | MIXED | MIXED |
| SUPPORT | ELEVATED | — | ELEVATED | MIXED | MIXED |
| TENANT_ADMIN | MIXED | REDUCED | — | REDUCED | MIXED |
| TENANT_CASHIER | MIXED | MIXED | ELEVATED | — | MIXED |
| LOGISTICS_AGENT | MIXED | MIXED | MIXED | MIXED | — |

La matriz usa la clasificación backend cerrada de capabilities por role code, alineada a `02-Base-de-Datos/Matriz de permisos.md`; no usa `tbl_roles.nivel`. Hay pares permitidos incomparables, entre ellos SYSADMIN→TENANT_ADMIN y TENANT_ADMIN→LOGISTICS_AGENT. Clasificarlos como `ELEVATED` o `REDUCED` falsearía la diferencia, por lo que `MIXED` sí es necesario. No existe actualmente ningún par permitido entre códigos de rol distintos con conjuntos iguales; `RECLASSIFIED` se elimina, no tiene productor/caso real. Si una futura matriz IAM-6 introduce roles distintos equivalentes, primero requiere nueva revisión contractual; el helper falla cerrado mientras tanto. El mismo rol no genera `PRIVILEGE_CHANGED`.

### 5.2 Semántica de membership y metadata

Un cambio efectivo de role code suspende la fila source y reactiva una fila destino SUSPENDED o crea una nueva fila ACTIVE, todo dentro de una transacción. Es el patrón de IAM-2 `CAMBIAR`, no una mutación del role code sobre una única fila. Se conserva un identificador para cada extremo con nombres no ambiguos:

| Clave | Valor |
|---|---|
| `previous_membership_id` | `tbl_usuario_comercio.id` de la fila cuyo rol previo queda SUSPENDED |
| `new_membership_id` | `tbl_usuario_comercio.id` de la fila de rol destino que queda ACTIVE, reactivada o recién creada |
| `target_user_id` | `tbl_usuarios.id_usuario` afectado |
| `from_role` / `to_role` | role codes canónicos antes/después |
| `direction` | exactamente `ELEVATED`, `REDUCED` o `MIXED` según §5.1 |

Metadata allowlist exacta de `MEMBERSHIP.PRIVILEGE_CHANGED`: `previous_membership_id`, `new_membership_id`, `target_user_id`, `from_role`, `to_role`, `direction`. No acepta `membership_id` ni `target_membership_id` en este evento. Los restantes event types conservan sus allowlists REV3.1.

### 5.3 Prueba contractual `CAMBIAR`

Para ACTIVE role A→role B, la operación efectiva emite exactamente un `MEMBERSHIP.PRIVILEGE_CHANGED` con IDs anterior/nuevo. No emite `MEMBERSHIP.SUSPENDED` ni `MEMBERSHIP.REACTIVATED` por sus pasos internos. Retry luego del commit devuelve resultado idempotente y agrega cero eventos. Llamadas concurrentes sobre el mismo origen se serializan con el lock de membership; una sola gana la transición y emite una fila. Migración 102 verificada en QA PostgreSQL desechable: transition 1, retry 0 adicional, dos sesiones concurrentes 1 transición/1 evento; ver matriz y resultados en el reporte QA.

**Estado de contrato:** REV3.2 resuelve la insuficiencia de REV3.1 para pares de roles incomparables. **Estado de backend al redactar la enmienda:** migración 101 no conforme hasta que una migración posterior alinee validator, helper y metadata; no reinterpretar ni editar 101.

**Actualización de implementación:** la migración aditiva `102_iam10_privilege_direction_contract.sql` alinea LIVE con esta enmienda; `101_security_events.sql` permanece inalterada. QA de matriz, retry y concurrencia figura en `07-Control-de-Calidad/Reporte-IAM10-Backend.md`. IAM10-B1 fue aprobado y el backend queda **CERRADO CON CERTIFICACIONES DIFERIDAS DOCUMENTADAS**, conforme a la decisión de cierre global en `07-Control-de-Calidad/CIERRE-IAM-ONBOARDING.md`.
