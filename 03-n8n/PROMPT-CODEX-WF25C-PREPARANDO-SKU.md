# PROMPT CODEX — WF-25-C: silenciar PREPARANDO + SKU en caption (cuenta `rsuelvotest`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
OBS-008/009 tras prueba real del dueño (flujo perfecto, sobran avisos). Migración 49 YA
APLICADA: el webhook `guia_registrada` trae `sku` (validado live: ejecución #741 con
`sku:FERC01`). Reglas 2/3/9, D9/D11, Regla 7 intactas. WF-25-C actual: ver. `c71a9a72`.

## Cambio (solo WF-25-C `2DzqPBe4xtHIuvHA`, reeler live antes de tocar)
1. **OBS-008:** la salida `PREPARANDO` del switch Por Estado → `Respond 200 OK` (igual que
   ASIGNADO/EN_RUTA/ENTREGADO ya silenciados). Dedup y resto intactos.
2. **OBS-009:** `Build Guia`: primera línea del caption con `SKU {sku}` tomado de
   `$json.body.sku`, con fallback al caption actual si viene vacío/ausente. Resto del
   caption (transportadora/ciudad/número/foto) intacto.
Si algo no discrimina con certeza, detener y reportar (no improvisar).

## Procedimiento y entregable
Releer el live (versión cambiada = detener). Cambios mínimos, publicar, anotar nuevo
`versionId`, verificar leyendo nodos. Sin pruebas vivas (próximo despacho real lo prueba:
guía con SKU + solo ese aviso). Responder versión + cambios + lectura. Matriz: orquestador.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens. Sin dependencias nuevas.
