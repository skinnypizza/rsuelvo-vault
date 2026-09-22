# Reporte QA IAM-5

**Fecha:** 2026-09-22 · **Estado:** IMPLEMENTACIÓN COMPLETA / EVIDENCIA aal2 REAL INCLUIDA.

## Backend (mig 86/87/88, en vivo)

| Caso | Resultado | Evidencia |
|---|---|---|
| aal1 salta UI en crítica | PASS | `mfa_requerido` en iniciar/cerrar (dueno aal1) |
| aal2 PASS crítica | PASS | helper true + `fn_cerrar_comercio` OK con sesión aal2 (comercio fósil, limpio) |
| service_role intacto | PASS | backend-identity true sin JWT; EF v9 operativa |
| Incidente P0 cerrado | PASS | Reporte-Incidente + mig 87/88, RLS re-verificado |

## SDK verificado (fuentes instaladas, no memoria)
- Flutter gotrue-2.27.2: `mfa.{enroll,challenge,verify,challengeAndVerify,unenroll,listFactors,getAuthenticatorAssuranceLevel}`, `AuthenticatorAssuranceLevels.aal2`, `SignOutScope.others`.
- Web auth-js 2.116.0: `auth.mfa.*` homólogos + `signOut({scope:'others'})`.
- Hallazgo: challenge es `POST /factors/{id}/challenge` (el 404 previo era shape incorrecto por REST manual).

## Flutter (`b8a8de3`, analyze 0, 313/313)
Enroll/verify, challenge, `mfaEnrollmentRequired` sin gracia, router gates, cerrar-otras, logout limpia, recovery compatible (links intactos, aal1 contenido por backend). Tests `mfa_policy_test` (6/6).

## Web (`2acd5e6`, build OK, 72 tests, deploy `ac96e3fd` 200)
`mfa.ts` + AuthContext status + rutas `/mfa-setup`/`/mfa-challenge` + StaffGate + cerrar-otras en Perfil. Tests `mfa.test.ts` (4/4). Cero `service_role`/`auth.admin` en cliente.

## Pendiente externo
sesión SuperAdmin real con MFA (cuando exista) + login posterior con challenge en dispositivo real. Recovery-TOTP: sin bypass (declarado no implementado).
