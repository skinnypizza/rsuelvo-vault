# D-IAM-CONSENTIMIENTO — Contrato IAM-7 (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT.

## Auditoría real (2026-09-22)
- BD: 0 tablas de consentimientos/términos. Solo `tbl_contact_preferences` (opt-out STOP por canal, distinto dominio).
- Flutter/Web/landing: 0 pantallas, 0 textos, 0 versiones. Alta de comercio, invite y registro operan sin aceptación registrada.

## Decisiones
1. **Versionado explícito:** `tbl_documentos_legales` (id, tipo: TERMINOS/PRIVACIDAD, versión semver-texto, título, url_texto, vigente_desde, activo) + `tbl_aceptaciones` (id_usuario, id_documento, versión, accepted_at, canal: APP/WEB, ip?) con UNIQUE(id_usuario, id_documento, versión). RLS deny-by-default + fns (`fn_aceptar_documento`, `fn_documentos_pendientes`).
2. **Obligatorio vs opcional:** obligatorios = Términos + Privacidad (bloquean operar hasta aceptar); opcionales = marketing/novedades (nunca bloquean; viven junto a `tbl_contact_preferences` sin fusionarse).
3. **Cambio de versión:** nueva versión activa → usuarios con versión vieja ven banner y deben aceptar; gracia operativa definida (ej. 30 días con aviso; Dorso: o bloqueo inmediato para cambios materiales — elegir en revisión).
4. **Comprador sin cuenta:** no acepta términos (solo WhatsApp); su STOP sigue en `tbl_contact_preferences`.
5. **Evidencia:** timestamp + versión + usuario + canal; auditoría; jamás contenido legal dentro de tablas de aceptación (solo referencia versión).
6. **Fuera:** KYC/biometría/documentos (IAM-9); SecurityEvent (IAM-10); ventas/n8n salvo que un flujo exija aceptación previa (no es el caso hoy).

## E2E
Documentos seed v1 · pendientes al registrar/invitar · aceptar registra evidencia · versión nueva → banner + re-aceptación · opcional no bloquea · comprador exento · regresión IAM-1..6 + suites.
