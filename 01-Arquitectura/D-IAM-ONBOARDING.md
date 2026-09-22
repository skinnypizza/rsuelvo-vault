# D-IAM-ONBOARDING — Contrato IAM-8 (rev3 con V0 server-side, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REV3 (requiere aprobación; backend solo después).

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

## 13. V0 server-side (rev3)
Membership ACTIVE = pertenencia, NO habilitación. Helper NUEVO `fn_comercio_habilitado(p_id_comercio)` (`estado='ACTIVO'`); no se tocan helpers compartidos (46 policies intactas, ventas/n8n a salvo).

| Capability | V0 | V1 | Autoridad backend | Impacto n8n |
|---|---|---|---|---|
| business.read.self / profile.update.self | ALLOW | ALLOW | RLS propia (tiene_acceso) | ninguno |
| catálogo/productos propios | ALLOW | ALLOW | `products_manage` (admin/cajero, verificado: ignora estado, sin n8n) | ninguno |
| onboarding status/read | ALLOW | ALLOW | RLS propia | ninguno |
| IAM-7 legal | ALLOW | ALLOW | fns legales | ninguno |
| cierre owner (+AAL2) | ALLOW | ALLOW | `fn_cerrar_comercio` | ninguno |
| QR/publishing público | DENY | ALLOW | storage `qr-pagos` + EF/QR: agregar `fn_comercio_habilitado` (policies humanas, no sales) | ninguno (lectura QR pública intacta) |
| créditos (solicitar/resolve) | DENY | ALLOW | resolve superadmin-only ✓; solicitar: gate `habilitado` en EF/fn (verificar path en implementación) | ninguno |
| exports sensibles | DENY | ALLOW | best-effort documentado (sin RPC frontera) | ninguno |
| invite/membership create/mutate | DENY | ALLOW | EF invite + `fn_aceptar_invitacion`: exigir comercio ACTIVO o PENDIENTE_APROBACION (excluye VERIFICACION por omisión; EF agrega check explícito) | ninguno |
| ownership transfer | DENY | ALLOW | fns transferencia (comercio debe estar ACTIVO: agregar check) | ninguno |
| staff/global | DENY | DENY | gates existentes | ninguno |

Regla: lo no protegible sin rediseñar ventas = excluido de ALLOW + documentado (exports). Owner/staff en V0 no salta estado; cambiar membership/rol tampoco.

## 14. Email verificado: fuente exacta
`auth.users.email_confirmed_at IS NOT NULL` leído server-side en `fn_auto_alta_comercio` (definer; verificado legible 2026-09-22). Fallback si el runtime lo impide: verificación en EF autenticada + alta server-side. Jamás boolean/email de cliente ni metadata editable.

## 15. IAM-7 orden
Cuenta verificada → crear V0 → owner/admin → MFA (IAM-5) → IAM-7 obligatorios → onboarding V0. IAM-7 bloquea operación (diseño vigente); legal/onboarding accesibles. Sin validación legal duplicada en auto-alta.

## 16. E2E adicional rev3
V0 DENY c/u en vivo · V1 habilita · membership/owner no saltan · service_role/n8n intactos · staff-created ACTIVO igual · guards_sanos · ventas/n8n regresión.
