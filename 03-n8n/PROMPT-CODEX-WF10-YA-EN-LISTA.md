# PROMPT CODEX — WF-10: atajo "ya en lista" (cuenta `rsuelvotest.app.n8n.cloud`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
- Decisión del dueño: quien ya está en lista y reenvía el SKU recibe directo
  "Ya estás en la lista #N", sin la pregunta SI/NO de Momento 1.
- **Migración 42 YA APLICADA**: `fn_solicitar_reserva` devuelve en ambos `SIN_STOCK`
  `ya_en_lista` (boolean), `posicion` (integer|null), `id_lista_espera` (uuid|null).
  Definición en `02-Base-de-Datos/sql/42_solicitar_reserva_ya_en_lista.sql`.
- Reglas 2/3/9 y D9/D11. IDs en Matriz §0. WF-10 actual: ver. `aac5e27e` (título "sin stock").

## Cambio (solo WF-10, `xFcZMG8Hip0Z6aH5`)
1. Nodo `PG fn_solicitar_reserva`: agregar al SELECT `(r->>'ya_en_lista')::boolean AS ya_en_lista,
   `(r->>'posicion')::integer AS posicion_lista`.
2. Entre la salida TRUE de `¿Sin stock?` y `PG fn_pendiente_lista`, insertar IF `¿Ya en lista?`
   (condición: `resultado == SIN_STOCK AND ya_en_lista == true`; null-safe: null → false).
   - TRUE → nuevo Build `Respuesta Ya en lista` con `message_payload` tipo texto:
     `📋 Ya estás en la lista de espera, en la posición #{{ posicion_lista }}. Te avisaremos cuando haya stock.`
     (mismo texto del YA_EN_LISTA que ya recibe el comprador; reusar `posicion_lista`
     de la RPC) → conectar a `Merge Outputs` (subir `numberInputs` de 4 a 5, usar el índice 4).
   - FALSE → `PG fn_pendiente_lista` existente (flujo Momento 1 intacto).
3. No tocar nada más: ni textos de la pregunta, ni Build Output, ni credenciales.

## Procedimiento y entregable
Releer el live antes de tocarlo (si la versión cambió respecto a `aac5e27e`, detener y reportar).
Cambio mínimo, publicar, anotar nuevo `versionId`. Sin pruebas vivas (el dueño lo prueba
mandando el SKU de nuevo). Responder: versión anterior → nueva + qué cambió.
La Matriz la actualiza el orquestador — no la edites.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens.
