# IAM-8/FLUTTER — Self onboarding (implementación Codex)

## OBJETIVO
Implementar D-IAM-ONBOARDING.md rev3 en Flutter contra backend IAM-8 APROBADO (mig 94/95 + EFs). Flujo: registro → email verificado → login → auto-alta → PENDIENTE_VERIFICACION → IAM-3 → IAM-5 → IAM-7 → onboarding V0.

## ALCANCE EXACTO
Solo onboarding self. Prohibido: backend/schema, KYC, tocar IAM-3/5/6/7, service_role, ventas/n8n.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## CONTRATOS REALES (NO inventar campos)
EF `registrar-cuenta-comercio` (pública, verify_jwt=false): `{email, nombre, apellido?, telefono?, empresa(honeypot)}` → siempre neutral `{ok:true,mensaje:"Si el correo es válido, recibirás instrucciones."}`. Jamás mostrar "ya existe"/estado/membership/Auth ID. Sin auto-login.
`fn_auto_alta_comercio(p_request_id, p_nombre_comercio, p_codigo_tienda, p_sucursal, p_telefono_comercio)` → éxito `{ok, id_comercio, codigo_tienda, estado:'PENDIENTE_VERIFICACION', id_sucursal, repetido}`; errores `sin_acceso|email_no_verificado|rate_limit|codigo_invalido|codigo_en_uso|nombre_invalido`. NO enviar email/user/rol/owner/estado/membership. `p_request_id`: un UUID por intención, conservar en retry, nuevo solo para intención nueva.

## ARCHIVOS A REVISAR
`lib/features/auth/` (login, recargarPerfil, MFA gates), `lib/features/comercios/` (alta staff existente: NO duplicar, reutilizar patrones), `lib/core/router.dart` (integrar tras IAM-3/5/7), `lib/features/shell/` (banner V0), `01-Arquitectura/D-IAM-ONBOARDING.md`.

## REGLAS
- V0 visible como pendiente (NO error, NO activo): ALLOW perfil/config/catálogo/onboarding/legales/cierre; DENY QR/créditos/invitar/memberships/transfer/exports (UI oculta/deshabilita; backend es autoridad — comentarlo en código).
- Tras alta: refrescar memberships por reconciliación IAM-3 (1→auto, N→selector); jamás `selected.first` ni AppUser manual.
- Orden: membership → MFA → legal → onboarding. Legales por gate IAM-7 (no aceptar durante auto-alta).
- `p_request_id` en storage seguro temporal por intención.

## CAMBIOS PERMITIDOS
Pantallas registro/crear-comercio/V0 + repo/gateway + router + banner + tests mocks.

## CAMBIOS PROHIBIDOS
Backend · service_role · roles/ids/owner/estado desde cliente · UI como enforcement · saltar MFA/legal · capabilities · ventas/n8n · modificar contrato.

## PRUEBAS
Mocks: idempotencia request_id, multi-comercio, gates MFA/legal, V0 DENY visibles, errores (no-verificado/rate/en-uso); analyze 0; suite completa.

## ENTREGABLES
Commit main + SHA + resumen (archivos, analyze, tests, decisiones UX, desvíos).
