# PROMPT CODEX — QR con título de tienda (cuenta `rsuelvotest`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Decisión del dueño: el mensaje que adjunta el QR debe llevar el **nombre de la tienda
como título** (el comprador compra en varios comercios por el mismo número universal).
Solo cambia el texto del QR; nada de lógica, BD ni Matriz (orquestador).

## Cambio (solo WF-20 `1FYWXdVw2swlFYcg`, reeler live antes de tocar)
En `Preparar WF-80 Input`: anteponer al `text` la línea `🏪 {nombre_comercial}`.
El nombre sale de `tbl_comercios.nombre_comercial` por `id_comercio` del trigger
(agregar lookup PostgREST de lectura si no está disponible en el contexto; fallback:
omitir la línea si no resuelve, nunca romper el mensaje). Resto del texto idéntico
(SKU, producto, monto, vigencia).

## Procedimiento y entregable
Releer el live (versión cambiada = detener). Cambio mínimo, publicar, anotar `versionId`,
verificar leyendo el nodo. Sin pruebas vivas (el dueño lo prueba con próximo SKU:
espera el título + QR solo). Responder versión + cambio + lectura.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens.
