# IAM-8/WEB — Self onboarding alcance real (implementación Codex)

## OBJETIVO
Implementar D-IAM-ONBOARDING.md rev3 en web respetando D-IAM-WEB-SCOPE (`/app` = backoffice global staff, NO tenant dashboard).

## ALCANCE EXACTO
Primero DETERMINAR alcance: si onboarding público vive en landing/web pública → registro allí; auto-alta autenticada solo si encaja flujo tenant en Web; si tenant es solo-Flutter → Web SOLO registro público, sin inventar administración tenant en `/app`. Prohibido: backend, permissions.ts (solo leer), selector tenant, MFA/capabilities existentes.

## REPOSITORIO
`skinnypizza/rsuelvo-web`, rama `main` (landing + app según alcance).

## CONTRATOS REALES (NO inventar campos)
EF `registrar-cuenta-comercio`: `{email, nombre, apellido?, telefono?, empresa(honeypot)}` → neutral siempre. Sin auto-login, sin "ya existe".
`fn_auto_alta_comercio(p_request_id, p_nombre_comercio, p_codigo_tienda, p_sucursal, p_telefono_comercio)` (solo si el alcance lo incluye) → éxito `{ok, id_comercio, codigo_tienda, estado:'PENDIENTE_VERIFICACION', id_sucursal, repetido}`; errores `sin_acceso|email_no_verificado|rate_limit|codigo_invalido|codigo_en_uso|nombre_invalido`. Nada de email/rol/owner/estado desde cliente. Un UUID por intención.

## ARCHIVOS A REVISAR
`landing/src/pages/` (registro público), `app/src/auth/` (AuthContext, MFA gates, permissions.ts intocable), `app/src/App.tsx` (StaffGate), `01-Arquitectura/D-IAM-WEB-SCOPE.md`, `01-Arquitectura/D-IAM-ONBOARDING.md`.

## REGLAS
- V0 como pendiente (no error/activo); DENY visibles sin autoridad UI; backend manda.
- Orden MFA→legal→onboarding con gates existentes; recovery fuera de gates.
- No crear agentes persistentes.

## CAMBIOS PERMITIDOS
Registro público + (según alcance) auto-alta/V0 + tests.

## CAMBIOS PROHIBIDOS
Backend · service_role · selector tenant · permissions.ts · auto-login · autoridad UI · ventas/n8n · modificar contrato.

## PRUEBAS
`tsc`+build verdes; tests (neutralidad, idempotencia, errores, gates intactos); cero secretos.

## ENTREGABLES
Commit main + deploy Pages 200 + SHAs + resumen (incl. diferencia de alcance vs Flutter).
