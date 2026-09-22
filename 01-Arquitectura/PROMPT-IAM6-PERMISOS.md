# IAM-6/PERMISOS — RBAC + capabilities (implementación, SOLO tras aprobación)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-PERMISOS.md`: matriz mandante + convergencia Flutter/Web/DB + N-5/N-6 + SUPPORT + export auditado.

## ALCANCE EXACTO
Docs (matriz) → DB (RLS/fns mínimas) → Flutter/Web (gates) → QA. Nada de ventas/n8n/MFA/KYC.

## REPOSITORIO
Vault + `rsuelvo-flutter` + `rsuelvo-web`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-PERMISOS.md` (manda la versión revisada)
- `02-Base-de-Datos/Matriz de permisos.md` (a reescribir como matriz mandante)
- `07-Control-de-Calidad/Informe-IAM0-C-Web.md` (N-5/N-6) + `app/src/auth/permissions.ts`
- `lib/features/reportes/reportes_access.dart` (patrón a extender), hunters `idRol == N` (20)
- Helpers `fn_es_admin_comercio`, `fn_tiene_acceso_*`, `compras_select`, CSV web + reportes Flutter

## DEPENDENCIAS
Contrato aprobado. IAM-1..5 desplegados (no romper; `mfa_requerido` intacto).

## CONTRATOS QUE NO SE PUEDEN ROMPER
- RLS/aislamiento/auditoría; backend autoridad (UI nunca autoriza); `selected.first` cero; suites verdes; jamás secretos; ventas/n8n sin cambios de lógica.

## CAMBIOS PERMITIDOS
Matriz reescrita (normativa por capability: scope/roles/contexto/autoridad/gates/MFA) · migración taxonomía completa `users/commerce→members/business` + `credits.*` (sin aliases) · `can(subject,cap,context)` Flutter + `permissions.ts` extendido · RLS N-6 DB+Storage o excepción firmada · SUPPORT recortado exacto §5 · helpers separados con dependency audit · `*.export` server-side o best-effort documentado + AuditLog.

## CAMBIOS PROHIBIDOS
Aliases permanentes/dual-catalog · `TENANT_ADMIN==owner` en UI · highest-role para tenant · cambiar semántica global de helpers sin audit · tablas dinámicas/ABAC sin caso · MFA · KYC · SecurityEvent · lógica ventas/n8n · secretos en logs.

## PRUEBAS REQUERIDAS
E2E §12 del contrato (owner/no-owner, SUPPORT read+Deny DB+Storage, SYSADMIN depósito, sin escalada, multi-membership, web global, export DENY/auditado, guards_sanos, ventas/n8n) con evidencia backend · grep hunters fuera de mapper · regresión IAM-1..5 + suites.

## ENTREGABLES
Mig + UI + `Reporte-IAM6.md` + vault actualizado.

## DEFINITION OF DONE
Toda capability con autoridad server-side demostrable; cero solo-frontend salvo excepciones firmadas; suites verdes.
