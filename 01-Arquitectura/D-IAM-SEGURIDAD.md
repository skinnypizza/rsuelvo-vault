# D-IAM-SEGURIDAD — Contrato IAM-5 (rev2, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REV2 con ajustes ChatGPT (requiere aprobación antes de código).

## Auditoría real (2026-09-22)

- **Supabase Auth cloud:** TOTP enroll+verify ON (max 10), phone/webauthn OFF; refresh rotation ON; `update_password_require_reauthentication=false`; mail 2/h; OTP mail 3600s/8 dígitos.
- **Mecanismo server-side verificable:** JWT expone `aal` (`aal1`/`aal2`) + `amr` → las `fn_*` PUEDEN exigir `auth.jwt()->>'aal'='aal2'` (step-up real, no booleano cliente).
- **Clientes:** MFA inexistente en Flutter y web (solo recovery OTP en web). Sin UX de sesiones. Recovery = link Supabase sin controles por rol.

## Decisiones rev2

1. **Terminología:** `MFA/AAL2 guard` (assurance, NO "recent-auth" — sin claim de frescura temporal hasta diseñarlo).
2. **MFA TOTP obligatorio** (SUPERADMIN/SYSADMIN/TENANT_ADMIN/owner; SUPPORT→IAM-6) con estado `mfaEnrollmentRequired`: sin factor verificado → solo enroll/verify/logout/ayuda (SIN período de gracia). RPCs críticas exigen AAL2 igual (defensa en profundidad, no solo UI).
3. **Helper canónico** `fn_tiene_aal2()` (`auth.jwt()->>'aal'='aal2'`; service_role passthrough; jamás params cliente; fallo=`mfa_requerido`). Aplicar en: iniciar/aceptar transferencia, cerrar, SUSPENDER/REVOCAR/CAMBIAR admin-owner que corresponda, `fn_editar_usuario` desactivación privilegiada, cambio password privilegiado si hay path server-side. Export solo si RPC canónica existe (si no, IAM-6).
4. **Sesiones (arquitectura resuelta):** `signOut(scope:'others')` cliente para cerrar-otras (verificar en SDK actual); listar sesiones propias e invalidaciones administrativas → EF dedicada con JWT + ownership estricto (jamás user_id arbitrario; service_role solo server-side). Definido: cerrar-otras, cerrar-todas, invalidación tras password/transferencia/cierre crítico.
5. **Recovery matriz:** A (pierde password, conserva TOTP): link OK → sesión aal1, críticas bloqueadas, TOTP NO se desenrola. B/C (pierde TOTP): SIN bypass automatizado — procedimiento excepcional manual NO implementado en esta fase. D (compromiso): re-auth + rotación + cerrar-otras + auditoría. Prohibido "soporte quita MFA a pedido".
6. **Enrollment lifecycle** `unenrolled→pending→verified`: QR/secret solo durante enroll, jamás en tablas/logs/backend propio; cancelar limpia factor/challenge; tras verify refrescar sesión, comprobar AAL, recién salir de enrollmentRequired.
7. **Passkeys Fase 2.**

## Matriz MFA/AAL2

| Operación | Requiere |
|---|---|
| Login base | password (+challenge si inscrito) |
| Sin factor (privilegiado) | `mfaEnrollmentRequired` (enroll/verify/logout/ayuda) |
| Invitar/aceptar staff, operar | sesión válida |
| Transferir/aceptar propiedad, cerrar, revocar/suspender admin, desactivar privilegiado | AAL2 (`mfa_requerido` si no) |
| Cambio password propia | sesión (+privilegiado: AAL2 si path server-side) |
| Recovery | link OK → aal1; críticas bloqueadas; TOTP intacto |
| Cerrar otras/todas | sesión válida; ownership estricto en EF |

## Fuera
SecurityEvent completo (IAM-10); permission engine (IAM-6); biometría.
