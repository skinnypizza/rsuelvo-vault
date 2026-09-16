# PROMPT CODEX — WF-21 + WF-22: persistir `archivo_path` (CORRIGE prompt WF-20)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`, n8n `rsuelvotest.app.n8n.cloud`)
El prompt anterior apuntaba a WF-20 (`1FYWXdVw2swlFYcg`) pero ese WF no toca
comprobantes: la subida vive en **WF-22** (`53xUuvoriN3fqvHD`, nodos `Subir a
Storage` → `URL Firmada` con `expiresIn 604800` → `Output Final` devuelve
`foto_url`) y el registro en **WF-21** (`nJCQI6MfFSjUhywB`, nodos `Registrar
Comprobante (RPC)`, `Registrar Comprobante Rechazado (RPC)`,
`Registrar Comprobante Sin OCR` → `fn_registrar_comprobante` con
`p_archivo_url`). Backend LISTO (mig 65: `p_archivo_path` opcional; la app ya
firma al ver). Reglas n8n: orquesta, no decide; economía de tokens.

## Cambios
1. **WF-22 `Output Final`**: devolver además `foto_path` =
   `<id_comercio>/<mid>.jpg` (mismos insumos que `Subir a Storage`: `id_comercio`
   del trigger + `mid` del regex sobre `media_url`). Sin tocar OCR ni firma.
2. **WF-21 `Registrar Comprobante (RPC)`**: pasar `p_archivo_path` = `foto_path`
   de WF-22. Ramas Rechazado/Sin-OCR: dejar NULL (URL Meta transitoria, sin copia
   en storage — documentado, fuera de alcance).
3. No cambiar estados, ramas ni mensajes.

## Verificación y entregable
Diff de ambos + prueba viva (un comprobante deja `archivo_path` poblado; limpiar
rastro de prueba). Reportar versiones. El prompt WF-20 previo queda SUPERSEDED.
