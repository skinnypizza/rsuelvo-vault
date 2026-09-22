# IAM-9/FLUTTER — Habilitación V1 (implementación Codex)

## OBJETIVO
Implementar D-IAM-VERIFICACION.md rev2 en Flutter contra backend IAM-9 APROBADO (mig 96-100). V1 = PERFIL COMERCIAL DECLARATIVO COMPLETO (jamás "empresa verificada").

## ALCANCE EXACTO
Solo habilitación V1. Prohibido: backend/schema, KYC, tocar IAM-1..8, service_role, ventas/n8n.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## CONTRATOS REALES (NO inventar campos)
`fn_estado_verificacion_comercio(p_id_comercio)` → `{ok, checks:{nit,razon_social,telefono,email_owner,sucursal,qr,config} (cada uno {pass[,mode]}), faltantes:[...]}`. Usar `faltantes` del backend; UX local solo guía formularios.
`fn_solicitar_habilitacion_v1(p_id_comercio)` (solo owner + AAL2) → `habilitado|ya_activo|requisitos_faltantes|mfa_requerido|solo_owner|estado_incompatible|sin_acceso`. NO enviar user/owner/estado/nivel/checks/snapshot/reviewer.
EF `qr-entrega` `{id_comercio}` → `{ok,url}` signed temporal (NO persistir como dato; pedir de nuevo al expirar). V0/revocado → `comercio_no_habilitado`.

## LENGUAJE (obligatorio)
Permitido: "Completa los datos", "Perfil comercial completo", "Listo para habilitar", "Comercio habilitado", "NIT registrado", "Teléfono registrado", "Correo confirmado" (solo este, por Auth). PROHIBIDO: "empresa verificada", "NIT verificado", "KYC aprobado", "certificada", "tributario validado", "teléfono verificado".

## FLUJO
V0 owner: onboarding → checks → completar → QR a `qr-pagos-setup/<id_comercio>/...` (privado; JAMÁS escribir `qr-pagos`) → MFA IAM-5 → solicitar → `habilitado` → refrescar commercePhaseProvider → dashboard. V1: visualizar QR vía `qr-entrega`. No saltar IAM-3/5/7. Botón `Habilitar comercio` solo owner (backend autoridad).

## ARCHIVOS A REVISAR
`lib/features/onboarding/` (fase V0), `lib/features/comercios/` (editar datos), `lib/features/qr_comercio/` (upload/download: migrar upload V0 a staging), `lib/core/router.dart` (gates), `lib/features/auth/` (MFA), `01-Arquitectura/D-IAM-VERIFICACION.md`.

## CAMBIOS PERMITIDOS
Checklist V0 + formularios + upload staging + solicitar + visualizar vía qr-entrega + tests mocks.

## CAMBIOS PROHIBIDOS
Backend · service_role · URLs públicas/directas al bucket · "verified" recalculado · editar evidencia · elegir estado/reviewer · autoactivar · omitir AAL2 · saltar legales · IAM-1..8 · ventas/n8n · modificar contrato.

## PRUEBAS (20)
V0 incompleto · faltantes backend · NIT/teléfono no "verificados" · email confirmado OK · upload a staging (NO qr-pagos) · owner ve habilitar · no-owner no · mfa_requerido→IAM-5 · habilitado refresca phase · ya_activo · ACTIVO sale onboarding · qr-entrega visualiza · signed no persistida · V0 DENY manejado · IAM-3/7 intactos · analyze 0 · suite completa.

## ENTREGABLES
Commit main + SHA + resumen (archivos, analyze, tests, decisiones, desvíos).
