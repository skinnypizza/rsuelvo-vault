# IAM-4/OWNER — Operaciones críticas (implementación, SOLO tras aprobación del contrato)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-OWNER.md`: owner explícito + controles en operaciones críticas, sin MFA/engine (fases propias).

## ALCANCE EXACTO
Backend (mig + fns) → Flutter/Web (gates + confirmaciones) → QA. Nada de IAM-5/6/9/10.

## REPOSITORIO
Vault SQL + `rsuelvo-flutter` + `rsuelvo-web`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-OWNER.md` (manda la versión revisada)
- `02-Base-de-Datos/sql/58_alta_superadmin.sql` (`fn_cambiar_estado_comercio`), `68`/`69`/`81`/`82` (vínculos), EF invite v9 (PATH A/B)
- `app/src/features/CommercesPage.tsx`, `UsersPage.tsx`, `ReportsPage.tsx` (gates + CSV)
- Flutter: usuarios/autorizaciones/reportes/comercios + shell por rol

## DEPENDENCIAS
Contrato aprobado. IAM-1/2/3 desplegados (no romper).

## CONTRATOS QUE NO SE PUEDEN ROMPER
- RLS/aislamiento/auditoría; invitaciones y lifecycle intactos + regresión; `selected.first` cero; suites verdes; jamás secretos; superadmin conserva suspensión/bloqueo.

## CAMBIOS PERMITIDOS
Mig aditiva (`propietario_id` + backfill + transferencia explícita) · guardas owner/no-último-owner en fns · reauth (re-login) para críticas tenant · confirmaciones + notificaciones + AuditLog · gates UI por capability/rol.

## CAMBIOS PROHIBIDOS
MFA/SecurityEvent completos · permission engine dinámico · KYC · selector tenant en web · tocar N-1/N-3/N-5/N-6 fuera de coordinación · secretos en logs.

## PRUEBAS REQUERIDAS
E2E fósiles: quitar admin, rol privilegiado, desactivar owner (bloqueado), transferencia doble-confirmada, email comercio, cierre con notificación, export auditado, atacante/no-owner rechazados, último-owner protegido, regresión IAM-1/2/3 + suites.

## ENTREGABLES
Mig + fns + UI + `Reporte-IAM4.md` + vault actualizado.

## DEFINITION OF DONE
Matriz toda en verde; ningún no-owner ejecuta crítica; auditoría por operación; suites verdes.
