# PROMPT CODEX — WF-10: respuesta directa con lista llena (cuenta `rsuelvotest`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
- OBS-006 (`07-Control-de-Calidad/Observaciones-Usuario.md`): con lista llena, respuesta directa
  sin pregunta SI/NO.
- **Migración 43 YA APLICADA**: `fn_solicitar_reserva` devuelve en ambos SIN_STOCK (cuando no
  está en lista) `lista_llena` (boolean), `activos`, `maximo`. Definición exacta en
  `02-Base-de-Datos/sql/43_solicitar_reserva_lista_llena.sql`. Validada: buyer1→llena true (1/1).
- Reglas 2/3/9 y D9/D11. IDs en Matriz §0. WF-10 actual: ver. `6cedb686` (atajo ya_en_lista).

## Cambio (solo WF-10 `xFcZMG8Hip0Z6aH5`)
1. Nodo `PG fn_solicitar_reserva`: agregar `(r->>'lista_llena')::boolean AS lista_llena`.
2. En la salida FALSE del IF `¿Ya en lista?` (hoy va a `PG fn_pendiente_lista`), insertar IF
   `¿Lista llena?` con condición `resultado == SIN_STOCK AND (ya_en_lista ?? false) == false
   AND lista_llena == true` (null-safe: null → false).
   - TRUE → nuevo Build `Respuesta Lista llena` → `Merge Outputs` (subir `numberInputs`
     de 5 a 6, usar el índice 5).
   - FALSE → `PG fn_pendiente_lista` existente (mover el cable actual).
3. El Build lleva texto EXACTO (ni una palabra distinta):
   `Lo sentimos, el producto que busca no tiene stock y la lista de espera está llena.`
4. ⚠️ OBLIGATORIO (lección del incidente #508): el Build DEBE incluir a nivel superior
   `id_comercio`, `phone` y `provider` desde `$("Validate Input").item.json`
   (mismo patrón del atajo ya_en_lista), con `includeOtherFields:true`.
   Sin estos campos el gateway descarta en silencio.
5. Nada más: ni pregunta, ni atajo ya_en_lista, ni Build Output, ni credenciales.

## Procedimiento y entregable
Releer el live antes de tocarlo (si la versión cambió respecto a `6cedb686`, detener y reportar).
Cambio mínimo, publicar, anotar nuevo `versionId`, y **verificar leyendo el nodo después**
(4 asignaciones: message_payload + 3, textos exactos). Sin pruebas vivas (el dueño testea).
Responder: versión anterior → nueva + lectura de verificación. Si algo no coincide, reportar.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens.
