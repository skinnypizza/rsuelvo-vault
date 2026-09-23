# IAM-10 Security Events — QA backend V1

Fecha de despliegue y revisión: 2026-09-23

Contrato: `ad38f80e7026490edbea8a04fd7218d2d3787aa8` (REV3.1)

Migración: `02-Base-de-Datos/sql/101_security_events.sql`
Estado: **IMPLEMENTADO / PENDIENTE REVISIÓN INDEPENDIENTE**

## Alcance

Implementación aditiva del event store privado IAM-10 V1 y sus ocho transiciones aprobadas. No se modificaron Flutter, Web, Edge Functions, IAM-5 helpers, workflows n8n ni contratos operativos comerciales. IAM-1..9 permanecen fuera del alcance, salvo instrumentar sus transiciones aprobadas.

## Implementación

- `rsuelvo_private.tbl_security_events`: tabla append-only, RLS ENABLE/FORCE, grants directos revocados para `PUBLIC`, `anon`, `authenticated` y `service_role`; FKs restrictivas; catálogo, combinaciones event/severity/outcome/producer y metadata validados; retención generada 180/365 días.
- Metadata exacta allowlisted por event type, JSON object de hasta 2048 bytes, claves y UUIDs validados, roles canónicos y dirección de cambio de privilegio cerrada.
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
| Esquema privado no expuesto por PostgREST | LIVE | PASS; request con perfil `rsuelvo_private` recibió HTTP 406 `PGRST106`, schemas permitidos solo `rsuelvo` |
| ACL schema/tabla/writer/purge | LIVE | PASS; `anon`, `authenticated`, `service_role` sin acceso directo a schema/tabla; writer no ejecutable por esos roles; purge no ejecutable por `service_role` |
| Tabla append-only y RLS | LIVE | PASS en catálogos; RLS enabled + forced; sin policies; grants cerrados. Prueba mutacional transaccional se hizo en QA local |
| Índices aprobados | LIVE | PASS; los cinco índices más PK presentes. Advisors los marcan todavía sin uso por ser instalación nueva |
| Catálogo, validator y ocho transiciones | CÓDIGO | PASS en PostgreSQL QA local, transacciones revertidas: claves válidas, faltantes/extra/UUID/role/direction/tamaño inválidos; transición emite una fila; no-op/retry no duplica; writer inválido revierte |
| Ownership start / complete / cancel | CÓDIGO | PASS: pareja repetida devuelve mismo ID; destino diferente denegado con pendiente; completion/cancel emiten solo en transición; retries sin duplicado |
| Membership suspend/reactivate/revoke/privilege | CÓDIGO | PASS: elevación/reducción semántica, replay `CAMBIAR`, no-op y revocación |
| Verification V1 revoke / ya V0 | CÓDIGO | PASS: evento solo ACTIVO→V0; `ya_v0` no emite |
| Lector staff / Support / tenant | CÓDIGO | PASS con impersonación SQL local: SuperAdmin/SysAdmin permitidos, Support denegado; paginación/filtros/límite; AuditLog. Sesiones staff LIVE no disponibles para prueba autenticada |
| Purge / AuditLog / append-only delete controlado | CÓDIGO | PASS local: NOTICE vencido y CRITICAL vencido eliminados; HIGH vigente conservado; batch y AuditLog; UPDATE/DELETE ordinario rechazado |
| Watchdog duplicados y recovery | CÓDIGO | PASS local: dos fallas producen una alerta; recuperación con backlog drenado produce un recovery; ticks repetidos no hacen spam |
| Scheduler cron real | LIVE | PASS; ambos jobs activos en DB `postgres`, usuario `postgres`; purge y watchdog ejecutaron `succeeded` a las 2026-09-23 15:30 UTC. Sin filas de prueba en event store; el watchdog dejó solo el AuditLog contractual de configuración y el purge vacío no creó AuditLog |
| Fallo de scheduler con IAM operativo, backlog y recuperación | CÓDIGO | Writer no consulta scheduler/backlog por inspección y prueba local. No se simuló una indisponibilidad cron en LIVE para evitar mutación operativa en producción |
| Guard IAM-5 | LIVE | PASS: `fn_verificar_guards_sanos()` devolvió `ok:true`; helpers `fn_es_service_role` y `fn_tiene_aal2` no fueron modificados |
| A1 anon PostgREST | LIVE | PASS: RPC HTTP real sin Authorization devolvió `fn_es_service_role=false` |
| IAM10-H1 A2 AAL1 / A3 AAL2 / A4 service_role HTTP | PENDIENTE EXTERNO | No se dispuso de sesiones/token controlados para estos contextos |
| A5 direct-PG sin JWT | LIVE | PASS; `DIRECT_PG_TRUSTED_CONTEXT`, fallback histórico esperado |
| A6 consumers direct-PG n8n | LIVE INVENTARIO | 16 workflows activos, 8 con 25 nodos PostgreSQL; sin ejecutar/cambiar workflows |
| Regresión funcional IAM-1..9 completa | PENDIENTE EXTERNO | No se ejecutó suite completa contra identidades y fixtures LIVE; la regresión local de transición se limita a rutas instrumentadas |
| Restore de backup / recuperación completa | PENDIENTE EXTERNO | No se ejecutó restore LIVE; QA local se hizo en DB desechable |
| Flutter / Web sin cambios | CÓDIGO | PASS; no hay cambios ni checkout Flutter accesible en este entorno |

## Advisors Supabase

Advisors LIVE consultados después del DDL. El linter reporta RLS sin policy en `rsuelvo_private.tbl_security_events` (INFO); es deliberado y se combina con schema no expuesto, RLS FORCE y ACL cerradas. Reporta la RPC de lectura SECURITY DEFINER ejecutable por `authenticated` (WARN); el acceso es intencional y la función exige explícitamente SuperAdmin/SysAdmin y registra la consulta en AuditLog. Los cinco índices nuevos aparecen sin uso aún, esperable inmediatamente después del despliegue. Otros findings —views SECURITY DEFINER, grants SECURITY DEFINER históricos, `fn_set_updated_at`, `pg_net` en `public`, leaks-password protection y avisos de políticas/índices existentes— no fueron introducidos ni modificados por esta migración; quedan fuera del alcance IAM-10.

## Datos y restore

No se insertaron fixtures ni eventos de prueba en LIVE. Las pruebas de transición, rollback, deduplicación, purge y watchdog corrieron en base QA local y se revirtieron. No se borraron datos reales ni se alteró cron para simular falla en LIVE. Los dos jobs LIVE deben permanecer activos con sus schedules contractuales.

## Deudas y revisión pendiente

1. Obtener JWT de pruebas controladas para A2/A3 y service_role HTTP A4; repetir lectura con staff/Support de prueba en LIVE si se habilitan credenciales seguras.
2. Ejecutar regresión IAM-1..9 completa y restore conforme al runbook con entorno de staging/backup.
3. Revisión independiente del SQL, actores/roles y pruebas antes de marcar backend aprobado.

La certificación IAM10-H1 se mantiene: A1 LIVE PASS; A2/A3/A4 PENDIENTE EXTERNO; A5 LIVE PASS `DIRECT_PG_TRUSTED_CONTEXT`; A6 LIVE INVENTARIO. No P0 confirmado; no cambiar helpers IAM-5.
