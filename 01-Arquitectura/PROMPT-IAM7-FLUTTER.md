# IAM-7/FLUTTER — Aceptación de términos + banner de versión (implementación, SOLO tras backend + contrato aprobado)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-CONSENTIMIENTO.md` en Flutter: aceptar Términos/Privacidad al registrarse o al primer acceso pendiente + banner ante versión nueva + preferencias opcionales sin bloqueo.

## ALCANCE EXACTO
Solo consentimiento. Prohibido: KYC, biometría, SecurityEvent, tocar auth/selección/IAM-3, backend/schema.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-CONSENTIMIENTO.md` (flujos obligatorio/opcional, gracia)
- Contrato real desplegado: `fn_documentos_pendientes`, `fn_aceptar_documento` (NO inventar campos; leer respuestas exactas del vault/EF si aplica)
- `lib/features/auth/` (dónde enganchar pendientes post-login sin romper IAM-3/5), `lib/features/shell/app_shell.dart` (banner global si aplica)
- `07-Control-de-Calidad/Informe-IAM0-B-Flutter.md` (patrones repo/gateway/mocks)

## DEPENDENCIAS
Backend IAM-7 desplegado (tablas + fns + seed v1). Sin eso, solo preparar sin integrar.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- IAM-1..6 intactos (invite, lifecycle, selector, owner, MFA, capabilities); suite verde completa (actualizar, no reducir); `flutter analyze` 0; jamás `service_role`; comprador exento (sin cuenta, sin cambios WhatsApp).

## CAMBIOS PERMITIDOS
Repository por gateway + modelos + pantalla/aceptación + banner versión + preferencias opcionales + tests con mocks + textos ES claros (sin redactar obligación legal definitiva: marcar textos como borrador pendiente de validación boliviana).

## CAMBIOS PROHIBIDOS
KYC/documentos/selfie · bloquear comprador · reauth/MFA nuevo · permission engine · secretos en logs · UPDATE/INSERT directos (solo fns).

## PRUEBAS REQUERIDAS
Tests con mocks: pendientes visibles, aceptar registra, versión nueva exige re-aceptar, opcional no bloquea, error backend mapeado, `flutter analyze` 0.

## ENTREGABLES
Commit en `main` + resumen (archivos, analyze, nº tests, contratos faltantes).

## DEFINITION OF DONE
Flujos del contrato verdes; suite verde; sin cambios fuera del alcance.
