# D-IAM-SEGURIDAD — Contrato IAM-5 (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT.

## Auditoría real (2026-09-22)

- **Supabase Auth cloud:** TOTP enroll+verify ON (max 10), phone/webauthn OFF; refresh rotation ON; `update_password_require_reauthentication=false`; mail 2/h; OTP mail 3600s/8 dígitos.
- **Mecanismo server-side verificable:** JWT expone `aal` (`aal1`/`aal2`) + `amr` → las `fn_*` PUEDEN exigir `auth.jwt()->>'aal'='aal2'` (step-up real, no booleano cliente).
- **Clientes:** MFA inexistente en Flutter y web (solo recovery OTP en web). Sin UX de sesiones. Recovery = link Supabase sin controles por rol.

## Decisiones

1. **MFA TOTP obligatorio** (enroll guiado + grace login): owner/tenant-admin/superadmin/sysadmin. SUPPORT según IAM-6. Sin MFA → sesión válida aal1 pero SIN operaciones críticas/step-up.
2. **Step-up por AAL:** fns críticas (transferir/aceptar-propiedad, cerrar, revocar admin, export sensible) exigen `aal2` cuando el invocador es privilegiado. Error canónico `mfa_requerido`. Compatible: usuarios no-privilegiados sin cambio.
3. **Sesiones:** UX ver sesiones activas + cerrar otras (Supabase admin API vía EF dedicada o cliente con `auth.admin`? definir en implementación; mínimo: cerrar-otras + invalidar tras cambio crítico/password).
4. **Recovery:** conserva links; matriz pérdida (contraseña/email/teléfono/compromiso); cuenta privilegiada recuperada queda aal1 → step-up la contiene (sin segundo camino débil). Sin soporte manual que bypassee MFA (solo superadmin con doble auditoría — definir).
5. **Passkeys:** Fase 2 (post MFA estable).

## Matriz recent-auth/MFA (resumen)

| Operación | Requiere |
|---|---|
| Login base | password (+MFA si inscrito) |
| Invitar/aceptar staff | sesión válida |
| Transferir/aceptar propiedad, cerrar, revocar admin, export sensible | aal2 (privilegiados) |
| Cambio password propia | sesión + (privilegiado: aal2) |
| Recovery privilegiado | link OK pero sesión aal1 hasta MFA |
| Cerrar otras sesiones | sesión válida |

## Fuera
SecurityEvent completo (IAM-10); permission engine (IAM-6); biometría.
