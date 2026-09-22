# D-IAM-ONBOARDING — Contrato IAM-8 (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT.

## Auditoría real (2026-09-22)
- Alta hoy = 100% staff-mediada: landing EF `solicitar-alta-comercio` (anónima, fila PENDIENTE idempotente) → SuperAdmin/SysAdmin aprueba (`fn_resolver_solicitud_alta`) → staff crea (`fn_alta_comercio`, gate super/sysadmin/service) → dueño invitado (PATH B) → acepta.
- `fn_alta_comercio` NO admite self-service (raise sin rol staff). D4 (self→ACTIVO) no está implementado como tal; rige D17 (pendiente+aprobación).
- Sin signup público de Auth directo en clientes (alta de identidad solo por invite/EF).

## Decisiones
1. **Tres pasos separados:** (a) cuenta: `inviteUserByEmail`-like self via EF pública rate-limited (crea Auth + `tbl_usuarios` sin vínculos); (b) comercio: nueva `fn_auto_alta_comercio` para el propio usuario autenticado (JWT, sin rol previo) → comercio `PENDIENTE_VERIFICACION` (nuevo estado o reuso PENDIENTE_APROBACION — decidir) + vínculo TENANT_ADMIN + `propietario_id` = él (auto-owner trigger lo cubre); (c) habilitación: operación plena tras verificación V1 (IAM-9 define), con límites V0 (ej. sin QR público / sin créditos resolve / tope productos — definir).
2. **Anti-escalación:** auto-alta crea EXACTAMENTE 1 vínculo admin-propietario en SU comercio; jamás roles staff; rate-limit (1 comercio/usuario/día + captcha/honeypot como solicitud); sin bonus duplicable (1 por usuario).
3. **Ownership inicial:** propietario = creador (vía trigger auto-owner existente).
4. **Estados:** nuevo comercio self → `PENDIENTE_VERIFICACION`; SuperAdmin puede SUSPENDER/BLOQUEAR (flujo actual intacto); V0→V1 según IAM-9.
5. **Reutilización:** usuario existente puede crear su comercio (mismo fn); segundo comercio = segunda membership (IAM-3 selector lo soporta); invitaciones/owner/transfer intactos.
6. **Fuera:** KYC profunda/documentos (IAM-9); cambios a solicitud-staff actual (convive); ventas/n8n; MFA nuevo (el owner nuevo cae en `mfaEnrollmentRequired` por IAM-5).

## E2E
Cuenta self → auto-alta (PENDIENTE_VERIFICACION + admin + owner) → segundo intento mismo usuario/comercio idempotente/bloqueado · otro usuario no usurpa · staff no pierde rutas · rate-limit · V0 limitado (QR/resolve bloqueados) · aprobación posterior habilita · regresión IAM-1..7 + suites.
