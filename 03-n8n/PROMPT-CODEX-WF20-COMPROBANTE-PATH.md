# PROMPT CODEX — WF-20: guardar `archivo_path` del comprobante

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`, n8n `rsuelvotest.app.n8n.cloud`)
Bug real: WF-20 (`1FYWXdVw2swlFYcg`, RSU|20|Pago|Generar QR) persiste en
`tbl_comprobantes_pago.archivo_url` una URL firmada con expiración (y a veces el
link Meta lookaside) — los comprobantes viejos no se pueden mostrar. Backend
LISTO (mig 64): columna `archivo_path` + policies; la app firmará al ver.
Reglas n8n: orquesta, no decide; sin `SELECT→IF→UPDATE` de negocio; economía de tokens.

## Cambio (solo WF-20, sin tocar lógica de negocio)
1. Inspeccionar WF-20: ubicar el nodo donde se sube el archivo a
   `comprobantes-pago` y donde se inserta la fila (`archivo_url`).
2. Persistir además `archivo_path` = path relativo en el bucket
   (`<id_comercio>/<filename>`, sin host ni token). `archivo_url` se conserva
   para uso inmediato.
3. No cambiar estados, ramas ni mensajes.

## Verificación y entregable
Diff del workflow + prueba viva (un comprobante de prueba deja `archivo_path`
poblado; borrar el archivo/rastro de prueba si contamina). Reportar versión.
