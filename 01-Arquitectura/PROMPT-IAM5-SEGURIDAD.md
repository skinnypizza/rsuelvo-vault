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
Helper `fn_tiene_aal2` + guards en fns listadas · enroll/verify TOTP guiado + `mfaEnrollmentRequired` (sin gracia) · sesiones (cerrar-otras cliente si SDK lo permite + EF ownership-estricto) · matriz recovery A-D (B/C sin automatización) · mensajes `mfa_requerido`.

## CAMBIOS PROHIBIDOS
"Recent-auth" sin mecanismo · phone/WebAuthn · passkeys · bypass/TOTP-removal manual o automatizado · `auth.admin`/service_role en clientes · user_id arbitrario en EF sesiones · booleanos cliente como autorización · permission engine · secretos (incl. QR TOTP) en logs/tablas.

## PRUEBAS REQUERIDAS
E2E fósiles: sin-factor→enrollmentRequired · aal1 salta UI en crítica→`mfa_requerido` · aal2 PASS · normal aal1 conserva no-críticas · service_role intacto · QR/secret ausente en logs/tablas · enroll incompleto/reintento · recovery no elimina factor · recovery-privilegiado aal1 sin crítica · login post-enroll exige challenge · cerrar-otras no toca otro usuario · grep service_role/admin en clientes cero · regresión IAM-1..4 + suites.

## ENTREGABLES
Mig + UI + `Reporte-IAM5.md` + vault actualizado.

## DEFINITION OF DONE
Matriz toda verde; ningún privilegiado opera crítica sin aal2; recovery no es camino débil; suites verdes.
