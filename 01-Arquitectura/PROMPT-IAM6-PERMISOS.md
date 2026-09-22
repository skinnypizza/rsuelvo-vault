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
Matriz reescrita · `can()` Flutter central + migración hunters · capabilities web extendidas + gates internos · RLS `compras_select` o excepción documentada · SUPPORT recortado (o documentado) · `*.export` + AuditLog descargas.

## CAMBIOS PROHIBIDOS
Tablas de permisos dinámicos/ABAC sin caso producto · MFA · KYC · SecurityEvent · tocar lógica ventas/n8n · secretos en logs.

## PRUEBAS REQUERIDAS
Matriz por rol con evidencia backend (no solo UI) · N-5/N-6 · SUPPORT · export auditado · grep hunters · regresión IAM-1..5 + suites.

## ENTREGABLES
Mig + UI + `Reporte-IAM6.md` + vault actualizado.

## DEFINITION OF DONE
Toda capability con autoridad server-side demostrable; cero solo-frontend salvo excepciones firmadas; suites verdes.
