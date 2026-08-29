## Goal
- Aplicar semántica de reservas opción B (una reserva activa POR CLIENTE por sucursal+variante; clientes distintos reservan en paralelo mientras haya stock) en cloud `iwfaktlxebxtocmswdvv` y sincronizar vault canónico.

## Constraints & Preferences
- Opción B confirmada explícitamente por el usuario; mantener idempotencia mismo cliente+SKU.
- No modificar n8n todavía (lo hará `rsuelvo-n8n` tras confirmar contrato DB).
- No hacer commit (pendiente de decisión del usuario).
- Preservar nombre de índice `uq_reserva_activa_variante_sucursal` y predicate `estado in ('ACTIVA','PAGO_VALIDANDO')`.
- Misma firma y lógica de `fn_solicitar_reserva`; solo añadir filtro `id_cliente=p_id_cliente` en ambas detecciones.
- No cambiar enums ni tablas; no inventar columnas/fn_*/estados.
- Preferir UUIDs existentes para prueba; sin datos basura; rollback de prueba.
- Detener y reportar si la constraint/función real difiere de lo esperado (no ocurrió).

## Progress
### Done
- Leídos archivos obligatorios + localizado monolito `_monolito_RSUELVO_SUPABASE_schema_v2.sql`.
- Verificado cloud == vault (índice, función, sin conflictos activos).
- Aplicada migración `18_reservas_por_cliente` vía `supabase_apply_migration` (success): DROP/CREATE INDEX CONCURRENTLY (3 columnas) + CREATE OR REPLACE FUNCTION con filtro id_cliente en ambas detecciones.
- Verificado post-apply cloud: índice = `(id_sucursal,id_variante,id_cliente)`; función contiene `id_cliente=p_id_cliente` en 2 ocurrencias; 0 pares conflictivos; reservas_activas sin basura.
- Prueba DO con `raise exception` (rollback): R1=RESERVA_CREADA (cliente `36d55f66…`), R2=RESERVA_YA_EXISTENTE (mismo), R3=RESERVA_CREADA (cliente distinto `2d9fbbfa…`). Opción B confirmada. Rollback limpio (0 activas, IDs ausentes, stock 10/0).
- Creado `18_reservas_por_cliente.sql`.
- Actualizado `04_constraints.sql` (índice con `id_cliente`).
- Actualizado `06_functions.sql` (cabecera fn + ambas detecciones + comentario).
- Actualizado `_monolito_RSUELVO_SUPABASE_schema_v2.sql` (índice + cabecera fn + ambas detecciones + comentario).
- Actualizado `Matriz-Consistencia-WF-BD-HU.md` (fila WF-10, fila de inconsistencia, nueva sección 5 con H-2=B).
- Actualizado `ESTADO-EJECUCION.md` (bitácora migración 18).

### In Progress
- (none)

### Blocked
- (none)

## Key Decisions
- Opción B: una reserva activa POR CLIENTE por sucursal+variante; clientes distintos en paralelo mientras haya stock.
- Usar clientes reales existentes `36d55f66-d0e2-4f1c-a27f-0ed4bc2fba3a` y `2d9fbbfa-e3d3-479f-b3db-42c5e0c4f6c0`; sin crear cliente nuevo; prueba totalmente rollback.
- El harness de prueba requirió llamada calificada `rsuelvo.fn_solicitar_reserva` (search_path de `execute_sql` no incluye `rsuelvo`); primer intento falló con `function fn_solicitar_reserva(unknown, unknown, unknown, unknown, integer) does not exist`.
- El archivo `Matriz-Consistencia-WF-BD-HU.md` real es de 65 líneas (la referencia "H-2 (B) en línea 201" del resumen previo era de una vista desactualizada). No existía sección H-2, así que se creó la **sección 5** con la decisión H-2=B.

## Next Steps
- Handoff a `rsuelvo-n8n`: adaptar WF-10 (`TSC1otHnDCr0ADiW`) y WF-80 (`ISxev9AssaAvQa8z`) si fuera necesario tras el nuevo contrato (no se requiere cambio de firma; solo documentar que RESERVA_YA_EXISTENTE es por cliente). NO modificar n8n en este subagente.
- Commit vault pendiente de decisión del usuario (no se hizo commit).

## Critical Context
- Proyecto cloud: `iwfaktlxebxtocmswdvv` (RSUELVO).
- Nombre migración: `18_reservas_por_cliente`.
- Índice `uq_reserva_activa_variante_sucursal` ahora: `(id_sucursal,id_variante,id_cliente) WHERE estado IN ('ACTIVA','PAGO_VALIDANDO')` (verificado: `btree (id_sucursal, id_variante, id_cliente)` + predicate ANY ARRAY).
- Función `rsuelvo.fn_solicitar_reserva(uuid,uuid,uuid,uuid,integer)` SECURITY DEFINER, search_path `rsuelvo,public`; `id_cliente=p_id_cliente` en 2 ocurrencias verificadas.
- La citada `852f70bd-35ac-48ca-be49-dc5fcb26d63a` está VENCIDA; no había reserva activa pre-prueba.
- Datos de prueba: variante `ae892700-2bf6-4267-85e5-9ca1bd39a4ec`, sucursal `16662a81-8cca-4809-b817-2e89c912e58f`, comercio `3cf9a53a-cf8c-4482-b752-ab64c2136875`, sku `FERA01`, stock 10.
- IDs de prueba (rollback): `bd015fa3-7ef4-4a19-aea5-a793f4378840`, `e479cea5-1e8e-4b3d-90e6-dade2027a0af`.
- Sin reservas activas conflictivas (DROP/CREATE INDEX CONCURRENTLY seguro).
- Verificación final: índice 3 cols ✓, función 2 ocurrencias ✓, 0 conflictos ✓, reservas_activas sin basura ✓.
- IDs trazabilidad: WF-10 `TSC1otHnDCr0ADiW`, WF-80 `ISxev9AssaAvQa8z`, HU-037..041/HU-041, D3, Regla de Oro 2.

## Relevant Files
- `/home/nico/obsidian/Rsuelvo-CLEAN/02-Base-de-Datos/sql/18_reservas_por_cliente.sql`: creado, SQL exacto aplicado.
- `/home/nico/obsidian/Rsuelvo-CLEAN/02-Base-de-Datos/sql/04_constraints.sql`: actualizado índice con `id_cliente`.
- `/home/nico/obsidian/Rsuelvo-CLEAN/02-Base-de-Datos/sql/06_functions.sql`: actualizado fn + comentarios.
- `/home/nico/obsidian/Rsuelvo-CLEAN/02-Base-de-Datos/sql/_monolito_RSUELVO_SUPABASE_schema_v2.sql`: actualizado índice + fn + comentario.
- `/home/nico/obsidian/Rsuelvo-CLEAN/03-n8n/Matriz-Consistencia-WF-BD-HU.md`: actualizada fila WF-10, inconsistencia, sección 5 H-2=B.
- `/home/nico/obsidian/Rsuelvo-CLEAN/00-Index/ESTADO-EJECUCION.md`: bitácora migración 18 añadida.
- `/home/nico/obsidian/Rsuelvo-CLEAN/02-Base-de-Datos/sql/15_fix_reserva_ya_existente.sql`: solo referencia, no modificar.
