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
Mig aditiva (`propietario_id` nullable + backfill regla 1-admin + preflight ambiguos + `tbl_transferencias_propiedad` + índice única PENDIENTE/comercio) · `fn_es_owner` + guardas owner/no-último-owner/anti-degradar-owner en fns · transferencia con lifecycle (iniciar/aceptar/rechazar/cancelar, FOR UPDATE, expiración) · CERRAR owner vs SUSPENDER/BLOQUEAR superadmin · confirmaciones + notificaciones + AuditLog · gates UI por capability/rol.

## CAMBIOS PROHIBIDOS
Reauth fuerte/MFA/SecurityEvent · permission engine dinámico · KYC · backfill por antigüedad · transferencia por UPDATE directo · transferencia sin expiración/límite · permitir REVOKED→propietario · CERRAR por no-owner · SUSPENDER/BLOQUEAR por owner · absorber N-6/IAM-6 · secretos en logs.

## PRUEBAS REQUERIDAS
E2E fósiles: backfill 1-admin→owner + 2-admins→NULL + preflight ambiguos · owner SUSPENDED no ejecuta · degradar/revocar owner bloqueado · transferencia a no-admin bloqueada · doble PENDIENTE imposible · concurrencia/idempotencia accept · vencida no cambia · accept atómico + ex-owner sin privilegios · CERRAR owner OK + SUSPENDER por owner rechazado · quitar admin + rol privilegiado + email comercio + export identificado · atacante/no-owner rechazados · último-owner protegido · regresión IAM-1/2/3 + suites.

## ENTREGABLES
Mig + fns + UI + `Reporte-IAM4.md` + vault actualizado.

## DEFINITION OF DONE
Matriz toda en verde; ningún no-owner ejecuta crítica; auditoría por operación; suites verdes.
