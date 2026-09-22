# Reporte QA IAM-6

**Fecha:** 2026-09-22 · **Estado:** IMPLEMENTACIÓN COMPLETA / pendiente revisión final.

## DB (mig 89/90/91, en vivo)
- N-6 tabla+Storage (owner/superadmin), cajero vacío verificado; SYSADMIN/SUPPORT live pendientes (sin logins).
- `credits.resolve` solo SUPERADMIN (+service_role); humano no-superadmin DENY x3 con fila intacta.
- Helpers compartidos intactos (46 policies auditadas); ventas/n8n sin cambios.
- `fn_verificar_guards_sanos()` verde.

## Flutter (`f442a7d`, analyze 0, 322/322)
- `core/capabilities.dart`: catálogo + `can(subject,cap,context)` + mapper central id↔código.
- Decisiones migradas a códigos (invite staff, transferencia destino admin, MFA policy).
- Hunters `idRol==N` restantes: solo mapper compat (`auth_model` getters) — cero decisiones fuera.
- Tests `capabilities_test` (7/7): owner/no-owner, SUPPORT read-only, SYSADMIN sin depósito/resolve, superadmin todo, sin escalada, DENY default, mapper.

## Web (`bd373bc`, build OK, 74 tests, deploy `dea41b3d` 200)
- Migración `users/commerce→members/business` completa, sin aliases (grep cero).
- SUPPORT read-only (`business.read`, `credits.read`, `reports.operational`).
- `credits.resolve` oculto fuera de SuperAdmin; N-5 gates `members.invite/mutate` internos.
- Cero `service_role`/`auth.admin` en cliente (re-verificado).

## Export
Best-effort client-side documentado (sin RPC frontera existente); no se vende como seguridad.

## Pendiente externo
SYSADMIN/SUPPORT/SuperAdmin live + concurrencia (heredado) + caso `credits.deposit.read` SYSADMIN si negocio lo pide.

## Patch final (2026-09-22)
- `members.read` DENY SYSADMIN/SUPPORT en matriz + Flutter (Web ya estaba); test dedicado.
- Nota obsoleta `conserva credits.resolve` eliminada (grep cero).
- N-5: `EditDialog`/`InviteDialog` reciben `allowed` + guard en `submit` (defense-in-depth; backend autoridad).
- Flutter `f96a150` (323/323, analyze 0) · Web `e9f4bd4` (74 tests, `ad7a8522`).
