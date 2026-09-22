# D-IAM-ONBOARDING — Contrato IAM-8 (rev2 determinista, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REV2 (requiere aprobación; backend solo después).

## 1. Estado congelado
`PENDIENTE_VERIFICACION` (nuevo; NO reusar `PENDIENTE_APROBACION` = flujo staff). Transiciones: self→PENDIENTE_VERIFICACION; V1→ACTIVO (IAM-9); SuperAdmin→SUSPENDIDO/BLOQUEADO; cierre/transfer IAM-4 intactos. Sin otras transiciones.

## 2. Capabilities V0 (sin tope numérico de productos)
ALLOW: completar perfil/configurar básicos, catálogo/productos, ver onboarding, aceptar legales IAM-7, cerrar (owner+AAL2 si aplica). DENY: QR público, créditos, exports sensibles, confianza externa, crear memberships, transferir ownership, capabilities staff/global, invitar. V0→V1 lo eleva IAM-9.

## 3. Alta atómica
`fn_auto_alta_comercio` en UNA transacción: comercio + membership ACTIVE TENANT_ADMIN del JWT + `propietario_id`=él. Fallo = rollback total (sin huérfanos). Trigger ayuda pero postcondición verificada.

## 4-5. Identidad self + email verificado
EF `registrar-cuenta-comercio` (email/nombre/apellido/teléfono-opcional + antiabuso; jamás rol/comercio/owner/membership): normaliza, rate-limit, anti-enumeración (respuesta neutra si Auth existe), crea identidad por flujo seguro Supabase, exige email verificado antes de auto-alta, upsert `tbl_usuarios` idempotente, sin passwords, sin filtrar pertenencia ajena. Compensación: retry repara perfil sin duplicar Auth. `fn_auto_alta_comercio` exige JWT + vínculo `tbl_usuarios` + activo + email verificado (claim Supabase) + IAM-7 antes de operar; email de cliente jamás. Sin verificación → DENY explícito.

## 6-7. Idempotencia + rate-limit
`p_request_id UUID` por intención, persistido: mismo usuario+mismo id → mismo comercio; distinto id → otro comercio si pasa rate-limit (multi-comercio OK, sin duplicados por retry; NO dedup por nombre). Rate-limit: EF por IP/email/device; auto-alta máx 1 comercio nuevo/usuario/24h (antiabuso temporal, NO límite vitalicio).

## 8-9. Anti-escalación + ownership
Fn jamás acepta `id_rol`: siempre TENANT_ADMIN para el JWT actual en comercio nuevo; nada staff/cashier/logistics/terceros; resto vía IAM-1/2. Postcondición: exactamente 1 owner == creador con membership ACTIVE. Negativo: B jamás se auto-asigna owner de A.

## 10. Sin bonus
Eliminada toda mención a bonus/duplicación (no existe beneficio; no inventar reglas).

## 11. Compatibilidad
Staff flow, `fn_alta_comercio`, IAM-1..7, ventas/n8n intactos. Self = nuevo entrypoint.

## 12. E2E backend
Cuenta nueva · no-verificado DENY · verificado→PENDIENTE_VERIFICACION · 1 admin ACTIVE · owner=creador · retry mismo id→mismo · distinto id en ventana→DENY · no usurpación · staff imposible · rollback · 2º comercio tras ventana · V0 exacto · MFA/legal vigentes · staff intacto · guards_sanos · regresión IAM-1..7.
