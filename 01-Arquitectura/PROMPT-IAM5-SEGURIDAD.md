# IAM-5/SEGURIDAD — MFA + step-up + sesiones + recovery (implementación, SOLO tras aprobación)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-SEGURIDAD.md`: TOTP obligatorio privilegiados, AAL2 en fns críticas, UX sesiones, recovery contenido por step-up.

## ALCANCE EXACTO
Backend (guards AAL en fns + EF sesiones si aplica) → Flutter/Web (enroll/verify TOTP, UX sesiones, flujos recovery) → QA. Nada de IAM-6/9/10.

## REPOSITORIO
Vault SQL + EFs + `rsuelvo-flutter` + `rsuelvo-web`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-SEGURIDAD.md` (manda la versión revisada)
- Auth config real (resumen en el contrato; re-verificar antes de codificar)
- Fns críticas: transferencia, cerrar, gestionar-vínculo, export; `fn_es_owner`, gates actuales
- Flutter `auth_controller` (+`recargarPerfil`), login; web `AuthContext`, `passwords.ts`, `RecoveryPage`, `ProfilePage`

## DEPENDENCIAS
Contrato aprobado. IAM-1..4 desplegados (no romper; `mfa_requerido` nuevo código canónico).

## CONTRATOS QUE NO SE PUEDEN ROMPER
- RLS/aislamiento/auditoría; invitaciones/lifecycle/owner intactos + regresión; suites verdes; `selected.first` cero; jamás secretos; login sin MFA sigue funcionando (con privilegios reducidos).

## CAMBIOS PERMITIDOS
Guards `aal2` en fns críticas (helper canónico) · enroll/verify TOTP guiado · UX sesiones (ver/cerrar-otras, invalidación tras críticos) · matriz recovery · mensajes `mfa_requerido`.

## CAMBIOS PROHIBIDOS
Phone/WebAuthn (apagados en cloud) · passkeys · bypass manual de MFA · booleanos cliente como autorización · permission engine · secretos en logs.

## PRUEBAS REQUERIDAS
E2E fósiles: enroll/verify, login sin MFA con críticas bloqueadas, login con MFA OK, sesiones ver/cerrar, recovery privilegiado contenido (aal1), atacante aal1 en crítica, regresión IAM-1..4 + suites.

## ENTREGABLES
Mig + UI + `Reporte-IAM5.md` + vault actualizado.

## DEFINITION OF DONE
Matriz toda verde; ningún privilegiado opera crítica sin aal2; recovery no es camino débil; suites verdes.
