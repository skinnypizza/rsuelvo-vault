# PROMPT CODEX — WF-04: ruteo universal con fallback (cuenta `rsuelvotest`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Migración 56 YA APLICADA (ver `02-Base-de-Datos/sql/56_resolucion_universal.sql`):
`fn_resolver_sku_universal(p_sku)` → `{RESUELTO (comercio+sucursal+variante+precio) |
NO_ENCONTRADO (motivo)}` y `fn_contexto_por_telefono(p_telefono)` → `{origen:
CAPTURA|PENDIENTE|OPORTUNIDAD|RESERVA|PEDIDO|ULTIMO_COMERCIO|DESCONOCIDO + ids}`.
Reglas 2/3/9, D9/D11, STOP/opt-out y Matriz (orquestador) como siempre.

## Cambio (solo WF-04 `0fw2ymvAY1hHoV9M`, reeler live antes de tocar)
1. **SKU-candidato**: resolver con M1 en vez de (o antes que) el canal. Si `RESUELTO` →
   continuar el flujo con `id_comercio` + `id_sucursal` de M1 (WF-10 ya acepta sucursal
   como parámetro, sin cambios ahí). Si `NO_ENCONTRADO` → camino actual intacto
   (canal → error SKU).
2. **Texto no-SKU**: consultar M2 y adjuntar su contexto (origen + ids) al mensaje que
   baja por el router, SIN cambiar ninguna decisión existente hoy (SI/NO, lista, entrega,
   ayuda, R5). Es cableado de contexto para el futuro multi-comercio, no nuevas ramas.
3. **Fallback obligatorio**: si M1/M2 fallan o devuelven vacío/DESCONOCIDO, el flujo sigue
   EXACTAMENTE por el camino actual por canal (cero regresión single-tenant).
Nada más: ni textos, ni umbrales, ni WF-80, ni credenciales.

## Procedimiento y entregable
Releer el live (versión cambiada = detener). Cambios mínimos, publicar, anotar `versionId`,
verificar leyendo nodos. Sin pruebas vivas (el dueño retestea: SKU igual que siempre +
`hola` igual que siempre). Responder versión + cambios + lectura. Si algo no aplica,
reportar, no improvisar.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens. Sin migraciones ni Matriz.
