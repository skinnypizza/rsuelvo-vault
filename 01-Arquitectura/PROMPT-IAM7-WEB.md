# IAM-7/WEB — Aceptación de términos + banner de versión (implementación, SOLO tras backend + contrato aprobado)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-CONSENTIMIENTO.md` en web: aceptar Términos/Privacidad (staff/backoffice y dueños que operen web) + banner ante versión nueva + preferencias opcionales sin bloqueo.

## ALCANCE EXACTO
Solo consentimiento (`app/`; landing solo si el contrato exige enlace a textos). Prohibido: KYC, SecurityEvent, tocar capabilities/permisos, selector tenant, backend/schema.

## REPOSITORIO
`skinnypizza/rsuelvo-web`, rama `main` (`app/`).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-CONSENTIMIENTO.md` (flujos y gracia)
- Contrato real desplegado: `fn_documentos_pendientes`, `fn_aceptar_documento` (NO inventar campos)
- `app/src/auth/AuthContext.tsx` (dónde enganchar pendientes sin romper MFA gates), `app/src/App.tsx` (rutas/gates), `app/src/data/api.ts` (llamadas RPC)
- `app/src/auth/permissions.ts` (NO renombrar ni duplicar; solo usar gates existentes)

## DEPENDENCIAS
Backend IAM-7 desplegado. No crear agentes persistentes.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- IAM-1..6 intactos; `permissions.ts` referencia única; build + deploy Pages verdes; tests verdes; jamás secretos; D-IAM-WEB-SCOPE (sin selector tenant).

## CAMBIOS PERMITIDOS
Llamadas RPC + pantalla/banner + preferencias opcionales + tests + textos ES (borrador pendiente de validación boliviana).

## CAMBIOS PROHIBIDOS
KYC · bloquear recuperación de cuenta por falta de aceptación (recovery es crítico) · MFA nuevo · permiso paralelo · tocar backend/Supabase · exponer secretos.

## PRUEBAS REQUERIDAS
`tsc`+build verdes; tests de aceptación/pendientes/banner; verificación: ninguna respuesta/UI/log contiene secreto.

## ENTREGABLES
Commit en `main` + deploy Pages verificado 200 + resumen.

## DEFINITION OF DONE
Flujos del contrato verdes; build/tests verdes; alcance respetado.
