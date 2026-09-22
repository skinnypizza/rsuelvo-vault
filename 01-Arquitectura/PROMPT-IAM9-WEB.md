# IAM-9/WEB — Alcance real + staff read-only (implementación Codex)

## OBJETIVO
Implementar D-IAM-VERIFICACION.md rev2 en web respetando D-IAM-WEB-SCOPE (`/app` backoffice global; NO dashboard tenant).

## ALCANCE EXACTO
PRIMERO determinar alcance real: si tenant es solo-Flutter, Web = N/A para onboarding (documentarlo y no implementar flujo tenant). Si backoffice SuperAdmin necesita observar (V0/V1, checks, evidencia), implementarlo read-only. Prohibido: backend, permissions.ts (solo leer), selector tenant, revocación SuperAdmin en UI (sin contrato aprobado), MFA/capabilities existentes.

## REPOSITORIO
`skinnypizza/rsuelvo-web`, rama `main`.

## CONTRATOS REALES (si el alcance incluye lectura)
`fn_estado_verificacion_comercio` → checks + faltantes (misma forma que Flutter). Lenguaje honesto idéntico (permitido/prohibido del prompt Flutter). Sin URLs públicas construidas.

## ARCHIVOS A REVISAR
`app/src/auth/` (AuthContext, permissions.ts INTOCABLE), `app/src/App.tsx` (StaffGate), `01-Arquitectura/D-IAM-WEB-SCOPE.md`, `01-Arquitectura/D-IAM-VERIFICACION.md`.

## CAMBIOS PERMITIDOS
Solo lo que el alcance justifique + tests. No crear agentes persistentes.

## CAMBIOS PROHIBIDOS
Backend · service_role · flujo tenant en `/app` · revocar en UI · selector · autoactivar · autoridad UI · ventas/n8n · modificar contrato.

## PRUEBAS
`tsc`+build; tests (`/app` intacto, registro intacto, sin rol tenant, sin bypass IAM-6, lenguaje honesto); cero secretos.

## ENTREGABLES
Commit main + deploy Pages 200 + SHAs + resumen con decisión de alcance y diferencias vs Flutter.
