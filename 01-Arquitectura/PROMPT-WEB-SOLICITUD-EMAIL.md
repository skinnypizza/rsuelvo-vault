# PROMPT CODEX (Astra) — Landing: campo email en solicitud

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
Backend LISTO (mig 75 + EF, verificado): `tbl_solicitudes_alta.email` (opcional)
y EF que acepta/valida `email` (formato, 422 si malo). Patrón a seguir: campo
`codigo` ya implementado (input + `contractPayload` + tests + 409). Reglas:
español, economía, UN commit, builds+tests verdes.

## Cambio (solo landing)
Agregar input `email` (type=email, opcional) al formulario + `RequestPayload` +
validación en `contractPayload` + test (válido/inválido/ausente). Sin tocar diseño.

## Verificación
Tests + build verdes; commit «solicitud email».
