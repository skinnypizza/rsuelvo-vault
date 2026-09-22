# IAM-7/FLUTTER — Aceptación legal (implementación Codex)

## OBJETIVO
Implementar D-IAM-CONSENTIMIENTO.md rev3 en Flutter contra el backend IAM-7 desplegado (mig 92+93, APROBADO). Sin esto no cierra IAM-7.

## ALCANCE EXACTO
Solo consentimiento legal. Prohibido: backend/schema, KYC, SecurityEvent, tocar IAM-3/IAM-5/capabilities, service_role.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## CONTRATOS REALES (NO inventar campos)
`fn_documentos_pendientes()` → `{ok:true, documentos:[{id_documento, tipo, version, titulo, url_texto, content_sha256, obligatorio, vigente_desde}]}` ordenado por tipo; error `{ok:false,codigo:'sin_acceso'}`. La lista YA viene filtrada (activo, vigente, no aceptado); el cliente NO re-decide vigencia ni compara semver.
`fn_aceptar_documento(p_id_documento, p_canal='APP')` → éxito `{ok:true,codigo:'aceptado'|'ya_aceptado'}` (ambos éxito UX); errores `canal_invalido|sin_acceso|documento_no_existe|documento_no_vigente|version_obsoleta`. Ante obsoleta/no-vigente: refrescar pendientes, NO reintentar el id.

## ARCHIVOS A REVISAR
`lib/features/auth/` (auth_controller, AuthState, MFA gates: integrar DESPUÉS de auth/MFA sin romper selector IAM-3), `lib/core/router.dart` (gates), `lib/features/shell/app_shell.dart` (banner), `07-Control-de-Calidad/Informe-IAM0-B-Flutter.md` (patrones repo/gateway/mocks), `01-Arquitectura/D-IAM-CONSENTIMIENTO.md`.

## DEPENDENCIAS
Backend desplegado. Nada más.

## REGLAS CLIENTE OBLIGATORIAS
- Gate `legalAcceptanceRequired` si hay pendientes con `obligatorio==true`; bloquea operación; excepciones: recovery, MFA setup/challenge, flujo legal, ayuda, logout. No romper selector IAM-3 ni MFA IAM-5.
- Aceptación explícita por documento (tipo/título/versión + enlace url_texto); sin autoaceptar/background; botón anti-doble-submit; refrescar pendientes tras cada éxito; liberar solo sin obligatorios pendientes; `ya_aceptado` = éxito.
- Nueva versión en sesión → `legalAcceptanceRequired` + banner; sin gracia v1; sin semver local.
- Futuro `obligatorio=false`: nunca bloquea; no mezclar con STOP/marketing; no inventar RPC.
- Seeds BORRADOR: mostrar `Contenido legal pendiente de validación final`.
- Fail-closed: error técnico en pendientes (autenticado) → `legalStatusUnavailable` (NO asumir cero); bloquea operación; recovery/MFA/legal-retry/ayuda/logout accesibles + Retry + logout. Nunca bloquear recovery.

## CAMBIOS PERMITIDOS
Repository por gateway + modelos exactos + estados + pantalla legal + retry/logout + tests con mocks.

## CAMBIOS PROHIBIDOS
Backend/schema · service_role · KYC · SecurityEvent · cambiar IAM-3/IAM-5/capabilities · autoaceptar · guardar accepted_at/version/hash local como autoridad · modificar contrato.

## PRUEBAS REQUERIDAS
Mocks: pendientes visibles, aceptar OK, `ya_aceptado`, obsoleta/no-vigente refresca, nueva versión en sesión, opcional no bloquea, error→unavailable+retry, no privilegiado/exento según contrato, `flutter analyze` 0, suite completa verde.

## ENTREGABLES
Commit en `main` + SHA + resumen (archivos, analyze, nº tests, desvíos si los hubo — justificados o reportados, jamás silenciosos).

## DEFINITION OF DONE
Contrato respetado campo por campo; suite verde; cero cambios fuera del alcance.
