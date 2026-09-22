# D-IAM-CONSENTIMIENTO — Contrato IAM-7 (rev2, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REV3 determinista (requiere aprobación; backend solo después).

## 1. Tipos explícitos (no un "consentimiento" único)
- `TERMINOS` → aceptación contractual obligatoria.
- `PRIVACIDAD` → constancia del aviso/política.
- `TRATAMIENTO_DATOS` → autorización/consentimiento informado cuando corresponda.
- Marketing/novedades → preferencia opcional revocable, jamás bloqueante; sin fusionar con legales ni con STOP (`tbl_contact_preferences` intacto).

## 2. Documento = versión inmutable
`tbl_documentos_legales(id_documento PK, tipo, version text, titulo, url_texto, content_sha256, obligatorio boolean NOT NULL, vigente_desde, activo, created_at)`:
- `UNIQUE(tipo, version)` + partial UNIQUE `(tipo) WHERE activo=true` (nunca dos activas; activación controlada).
- `content_sha256` = hex lowercase 64 chars (CHECK).
- Obligatoriedad v1 congelada: TERMINOS/PRIVACIDAD/TRATAMIENTO_DATOS = true para todo autenticado (DB fuente de verdad, no derivación cliente; sin motor applicability/ABAC). Marketing fuera de esta tabla.
- Inmutabilidad verificable por trigger: con ≥1 aceptación asociada, DENY cambios a tipo/version/titulo/url/hash/obligatorio/vigente_desde; solo `activo` mutable (retirar/superseder). Nueva redacción = nueva fila.
- `p_canal` enum `APP|WEB` (CHECK; sin valores libres).

## 3-4. Aceptación + evidencia
`tbl_aceptaciones(id_aceptacion, id_usuario, id_documento, accepted_at, canal)` · `UNIQUE(id_usuario, id_documento)` (sin versión duplicada; versión y hash vía documento). Evidencia: usuario X + documento Y + versión Z + hash H + timestamp T + canal C. Sin contenido completo en aceptación. Sin IP (sin requerimiento, sin fuente fiable, sin retención definida; jamás IP de cliente).

## 5. Política de versión (congelada, sin gracia v1)
Nuevo con obligatorios pendientes → no opera. Existente con nueva versión → `legalAcceptanceRequired` hasta aceptar vigente. Siempre accesibles: recovery, MFA setup/challenge, pantalla legal, ayuda, logout. Opcionales nunca bloquean.

## 6. Autoridad y límites honestos
`fn_documentos_pendientes()` fuente server-side (usuario solo de `auth.uid()`; sin `p_id_usuario`). v1 NO añade guards a RPCs de ventas: control = session/router gate en clientes respaldado por la fn. Documentado como limitación (no frontera absoluta de API).

## 7. Contratos RPC
- `fn_documentos_pendientes()` → lista determinista: id_documento, tipo, version, titulo, url_texto, content_sha256, obligatorio, vigente_desde. Solo vigentes+activos+requeridos+no-aceptados del propio usuario.
- `fn_aceptar_documento(p_id_documento, p_canal)`: deriva usuario JWT; valida activo/vigente/no-obsoleto; idempotente (retry/doble tap, una fila); `{ok,codigo}` sin secretos. Cliente no controla user/timestamp/hash/versión.

## 8. RLS
Documentos: lectura de publicados; escritura backend/migraciones. Aceptaciones: sin INSERT/UPDATE/DELETE directo; solo RPC; lectura propia solo si hay caso UX (si no, RPC dedicada). Sin service_role en clientes.

## 9. Seeds
v1 = `BORRADOR — PENDIENTE VALIDACIÓN LEGAL BOLIVIA` explícito. Producción exige validación profesional (Términos, Privacidad, tratamiento).

## 10. E2E Backend
Nuevo→pendientes · aceptar parcial→resto pendiente · todos→cero · doble→idempotente 1 fila · otro usuario no acepta por el primero · inactivo DENY · vieja no satisface vigente · nueva→pendiente · opcional no bloquea · accepted_at/hash/versión server-side · INSERT directo DENY · buyer exento · recovery independiente · `obligatorio` proviene de DB (3 seeds true) · documento opcional futuro jamás en gate · evidencia inmutable (modificar hash/título/url/version→DENY; desactivar→OK) · dos activas mismo tipo→DENY · canal inválido→DENY · regresión IAM-1..6 + `fn_verificar_guards_sanos()` verde.

## Fuera
KYC/biometría (IAM-9); SecurityEvent (IAM-10); ventas/n8n. Agentes hijos NO modifican el contrato.
