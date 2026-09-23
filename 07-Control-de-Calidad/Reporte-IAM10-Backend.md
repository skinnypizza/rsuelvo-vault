# IAM-10 Security Events — QA backend V1

Fecha de despliegue y revisión: 2026-09-23

Contrato base: `ad38f80e7026490edbea8a04fd7218d2d3787aa8` (REV3.1); corrección IAM10-B1 documentada como REV3.2

Migraciones: `101_security_events.sql` y `102_iam10_privilege_direction_contract.sql`

Estado: **IMPLEMENTADO / NO APROBADO — pendiente revisión independiente**

## Alcance

Implementación aditiva del event store privado IAM-10 V1 y sus ocho transiciones aprobadas. No se modificaron Flutter, Web, Edge Functions, IAM-5 helpers, workflows n8n ni contratos operativos comerciales. IAM-1..9 permanecen fuera del alcance, salvo instrumentar sus transiciones aprobadas.

## Implementación

- `rsuelvo_private.tbl_security_events`: tabla append-only, RLS ENABLE/FORCE, grants directos revocados para `PUBLIC`, `anon`, `authenticated` y `service_role`; FKs restrictivas; catálogo, combinaciones event/severity/outcome/producer y metadata validados; retención generada 180/365 días.
- Metadata exacta allowlisted por event type, JSON object de hasta 2048 bytes, claves y UUIDs validados, roles canónicos y dirección de cambio de privilegio limitada a `ELEVATED` / `REDUCED` / `MIXED`.
- IAM10-B1: 101 quedó aplicada LIVE con desviación (`RECLASSIFIED`, `target_membership_id`); 102 es correctiva, agrega solo `MIXED` además de `ELEVATED`/`REDUCED`, falla cerrado para equivalencias entre roles distintos y cambia la metadata de privilege change a `previous_membership_id` + `new_membership_id`. La migración 101 no se editó.
- Writer privado `fn_emit_security_event`; no recibe severity/outcome/source/retención, ni consulta salud o backlog de purge. Los eventos se escriben en la misma transacción que la transición IAM.
- Producers: inicio, aceptación y cancelación de transferencia; suspend/reactivate/revoke/cambio efectivo de privilegio membership; revocación efectiva V1.
- Inicio de transferencia serializa por comercio y reusa la transferencia pendiente de igual pareja owner/destino. Cambio `CAMBIAR` de membership evita doble emisión de privilegio por los estados intermedios.
- RPC `fn_security_events_buscar`: filtro cerrado y keyset pagination, máximo 100, rango máximo 31 días y 365 días de antigüedad; SuperAdmin/SysAdmin; cada consulta escribe AuditLog. Support y tenants no reciben acceso.
- Purge batch con lock advisory, `SKIP LOCKED`, cutoff interno, máximo 5000 por llamada y AuditLog transaccional. Watchdog registra una falla por incidente, escalamiento operacional y recuperación una vez drenado el backlog. El estado del scheduler nunca bloquea producers IAM.
- Cron programado: `rsuelvo-security-events-purge` cada 5 minutos y `rsuelvo-security-events-purge-watchdog` cada 15 minutos.

## Matriz QA

| Área / escenario | Clasificación | Resultado |
|---|---|---|
| Aplicación migración IAM-10 a Supabase LIVE `iwfaktlxebxtocmswdvv` | LIVE | PASS; registrada como `iam10_security_events_v1` |
| Aplicación correctiva IAM10-B1 | LIVE | PASS; `iam10_b1_direction_and_membership_metadata` registrada después de 101; tabla tenía cero SecurityEvents y constraints revalidados |
| Esquema privado no expuesto por PostgREST | LIVE | PASS; request con perfil `rsuelvo_private` recibió HTTP 406 `PGRST106`, schemas permitidos solo `rsuelvo` |
| ACL schema/tabla/writer/purge | LIVE | PASS; `anon`, `authenticated`, `service_role` sin acceso directo a schema/tabla; writer no ejecutable por esos roles; purge no ejecutable por `service_role` |
| Tabla append-only y RLS | LIVE | PASS en catálogos; RLS enabled + forced; sin policies; grants cerrados. Prueba mutacional transaccional se hizo en QA local |
| Índices aprobados | LIVE | PASS; los cinco índices más PK presentes. Advisors los marcan todavía sin uso por ser instalación nueva |
| Catálogo, validator y ocho transiciones | CÓDIGO | PASS en PostgreSQL QA local desechable: claves válidas, faltantes/extra/UUID/role/direction/tamaño inválidos; transición emite una fila; no-op/retry no duplica; writer inválido revierte. La DB clon de pruebas fue eliminada |
| Ownership start / complete / cancel | CÓDIGO | PASS: pareja repetida devuelve mismo ID; destino diferente denegado con pendiente; completion/cancel emiten solo en transición; retries sin duplicado |
| Matriz de direcciones IAM-6 | CÓDIGO | PASS local: los 25 pares distintos permitidos (fuente 6 roles, destino excepto SUPERADMIN) clasifican ELEVATED/REDUCED/MIXED; no existe par equivalente distinto; mismo role es no-op |
| `CAMBIAR` ACTIVE role A→B | CÓDIGO | PASS local con `ROLE_TENANT_ADMIN`→`ROLE_LOGISTICS_AGENT`: exactamente 1 `MEMBERSHIP.PRIVILEGE_CHANGED` MIXED con IDs previous/new; cero SUSPENDED/REACTIVATED |
| `CAMBIAR` retry tras commit | CÓDIGO | PASS local: devuelve `ya_cambiado`; total permanece en 1 SecurityEvent |
| `CAMBIAR` concurrencia | CÓDIGO | PASS local con dos sesiones solapadas y lock del origen: una transición efectiva, segunda llamada `ya_cambiado`, total 1 SecurityEvent y cero eventos lifecycle |
| Metadata privilege change REV3.2 | CÓDIGO | PASS local: allowlist nueva acepta; `membership_id`/`target_membership_id` antiguos y `RECLASSIFIED` se rechazan |
| Membership suspend/reactivate/revoke | CÓDIGO | PASS: transiciones efectivas/no-op; un evento por edge |
| Verification V1 revoke / ya V0 | CÓDIGO | PASS: evento solo ACTIVO→V0; `ya_v0` no emite |
| Lector staff / Support / tenant | CÓDIGO | PASS con impersonación SQL local: SuperAdmin/SysAdmin permitidos, Support denegado; paginación/filtros/límite; AuditLog. Sesiones staff LIVE no disponibles para prueba autenticada |
| Purge / AuditLog / append-only delete controlado | CÓDIGO | PASS local: NOTICE vencido y CRITICAL vencido eliminados; HIGH vigente conservado; batch y AuditLog; UPDATE/DELETE ordinario rechazado |
| Watchdog duplicados y recovery | CÓDIGO | PASS local: dos fallas producen una alerta; recuperación con backlog drenado produce un recovery; ticks repetidos no hacen spam |
| Scheduler cron real | LIVE | PASS; ambos jobs activos en DB `postgres`, usuario `postgres`; purge `succeeded` a 15:50 UTC y watchdog a 15:45 UTC, posteriores a migración 102. Sin filas de prueba en event store; el watchdog dejó solo el AuditLog contractual de configuración y el purge vacío no creó AuditLog |
| Fallo de scheduler con IAM operativo, backlog y recuperación | CÓDIGO | Writer no consulta scheduler/backlog por inspección y prueba local. No se simuló una indisponibilidad cron en LIVE para evitar mutación operativa en producción |
| Guard IAM-5 | LIVE | PASS: `fn_verificar_guards_sanos()` devolvió `ok:true`; helpers `fn_es_service_role` y `fn_tiene_aal2` no fueron modificados |
| A1 anon PostgREST | LIVE | PASS: RPC HTTP real sin Authorization devolvió `fn_es_service_role=false` |
| Recheck IAM-5 tras migración 102 | LIVE | PASS; `fn_verificar_guards_sanos()` devuelve `ok:true`; `fn_es_service_role()` y `fn_tiene_aal2()` sin cambios. El PASS HTTP A1 anterior sigue aplicando porque no se modificó el helper ni su ACL |
| Event store luego de migración 102 | LIVE | PASS; `tbl_security_events` sigue en cero filas; no se insertaron eventos/fixtures de QA |
| Cron y acceso direct-PG luego de migración 102 | LIVE | PASS; purge `succeeded` a 15:50 UTC y watchdog a 15:45 UTC; misma firma `fn_gestionar_vinculo`, EXECUTE preservado para `service_role` y owner `postgres` |
| IAM10-H1 A2 AAL1 / A3 AAL2 / A4 service_role HTTP | PENDIENTE EXTERNO | No se dispuso de sesiones/token controlados para estos contextos |
| A5 direct-PG sin JWT | LIVE | PASS; `DIRECT_PG_TRUSTED_CONTEXT`, fallback histórico esperado |
| A6 consumers direct-PG n8n | LIVE INVENTARIO | 16 workflows activos, 8 con 25 nodos PostgreSQL; sin ejecutar/cambiar workflows |
| Regresión funcional IAM-1..9 completa | PENDIENTE EXTERNO | No se ejecutó suite completa contra identidades y fixtures LIVE; la regresión local de transición se limita a rutas instrumentadas |
| Restore de backup / recuperación completa | PENDIENTE EXTERNO | No se ejecutó restore LIVE; QA local se hizo en DB desechable |
| Flutter / Web sin cambios | CÓDIGO | PASS; no hay cambios ni checkout Flutter accesible en este entorno |

## Advisors Supabase

Advisors LIVE consultados después del DDL. El linter reporta RLS sin policy en `rsuelvo_private.tbl_security_events` (INFO); es deliberado y se combina con schema no expuesto, RLS FORCE y ACL cerradas. Reporta la RPC de lectura SECURITY DEFINER ejecutable por `authenticated` (WARN); el acceso es intencional y la función exige explícitamente SuperAdmin/SysAdmin y registra la consulta en AuditLog. Los cinco índices nuevos aparecen sin uso aún, esperable inmediatamente después del despliegue. Otros findings —views SECURITY DEFINER, grants SECURITY DEFINER históricos, `fn_set_updated_at`, `pg_net` en `public`, leaks-password protection y avisos de políticas/índices existentes— no fueron introducidos ni modificados por esta migración; quedan fuera del alcance IAM-10.

## Datos y restore

No se insertaron fixtures ni eventos de prueba en LIVE. Las pruebas previas de transición, rollback, deduplicación, purge y watchdog corrieron en QA local con rollback; el E2E IAM10-B1 corrió en una base clon desechable que fue eliminada tras las pruebas. La base QA de referencia quedó con cero SecurityEvents. No se borraron datos reales ni se alteró cron para simular falla en LIVE. Los dos jobs LIVE deben permanecer activos con sus schedules contractuales.

## Deudas y revisión pendiente

1. Obtener JWT de pruebas controladas para A2/A3 y service_role HTTP A4; repetir lectura con staff/Support de prueba en LIVE si se habilitan credenciales seguras.
2. Ejecutar regresión IAM-1..9 completa y restore conforme al runbook con entorno de staging/backup.
3. Revisión independiente del SQL, actores/roles y pruebas antes de marcar backend aprobado.

## IAM10-B1: decisión y matriz

El `CAMBIAR` real bloquea asignar `ROLE_SUPERADMIN` como destino, pero no fija otro filtro de rol destino; valida el código, protege al owner y conserva N-4/sucursal. Los roles distintos que llegan a la rama efectiva son, por tanto, cualquier rol fuente canónico a uno de los cinco destinos restantes, condicionados a esas reglas. IAM6 define capabilities distintas para esos códigos.

| from \\ to | SYSADMIN | SUPPORT | TENANT_ADMIN | TENANT_CASHIER | LOGISTICS_AGENT |
|---|---|---|---|---|---|
| SUPERADMIN | REDUCED | REDUCED | REDUCED | REDUCED | REDUCED |
| SYSADMIN | — | REDUCED | MIXED | MIXED | MIXED |
| SUPPORT | ELEVATED | — | ELEVATED | MIXED | MIXED |
| TENANT_ADMIN | MIXED | REDUCED | — | REDUCED | MIXED |
| TENANT_CASHIER | MIXED | MIXED | ELEVATED | — | MIXED |
| LOGISTICS_AGENT | MIXED | MIXED | MIXED | MIXED | — |

Los 25 pares efectivos producen 14 `MIXED`, 3 `ELEVATED`, 8 `REDUCED` y cero pares distintos equivalentes. Por tanto `MIXED` es necesario; `RECLASSIFIED` no tiene par real y se eliminó. IAM-2 `CAMBIAR` suspende el vínculo previo y reactiva/crea otro para cambio de role code, así que se guardan ambos UUID internos como `previous_membership_id` y `new_membership_id`.

Nota de procedencia: el expediente REV3.1 rastreado contenía un texto ampliado de cuatro direcciones y los IDs `membership_id`/`target_membership_id`; esto no coincide con el freeze de dos valores comunicado al revisar IAM10-B1. REV3.2 registra la insuficiencia y la resolución con evidencia de matriz/código; la autoridad de esta corrección es la enmienda documental y la migración 102.

La certificación IAM10-H1 se mantiene: A1 LIVE PASS; A2/A3/A4 PENDIENTE EXTERNO; A5 LIVE PASS `DIRECT_PG_TRUSTED_CONTEXT`; A6 LIVE INVENTARIO. No P0 confirmado; no cambiar helpers IAM-5. IAM10-B1 queda corregido en LIVE y código, pendiente revisión/aprobación independiente.
