# PROMPT CODEX — Fix atajo ya_en_lista: `id_comercio` null hacia WF-80 (cuenta `rsuelvotest`)

## Diagnóstico verificado por el orquestador (no adivinar, partir de aquí)
- Ejecución WF-80 **#508** (15:14:31, `success` de 0.4s): `Receive Send Request` recibió
  `{enviar:true, id_comercio:null, phone:59171531944, provider:meta, type:text,
  text:"📋 Ya estás en la lista..."}`. `Resolve Phone Number ID` devolvió `[]`
  (`WHERE id_comercio=NULL`) y la ejecución terminó en silencio (`lastNodeExecuted`
  = Resolve). **Esa es toda la falla: falta `id_comercio`, nada más.**
- Causa: el nodo `Build Respuesta Ya en lista` (WF-10) solo asigna `message_payload`
  (con provider/phone/text adentro) pero el ítem que sale por Merge→End→WF-04→WF-02→WF-80
  no lleva `id_comercio` (ni phone/provider) a nivel superior — al contrario de todos los
  demás nodos terminales (`Error: SKU no encontrado`, `Build Output`, etc.).
- Cadena que lo produjo: WF-10 #507 → WF-02 #504 → WF-80 #508 (atajo ya_en_lista, FERC01).
- No tocar WF-80 (el silent-drop con Resolve vacío es deuda F7, fuera de alcance) ni
  `Build Output` (tiene un typo cosmético `ála` en código muerto tras `return`, probado
  inofensivo en A1/A3 — **dejarlo quieto**) ni la Matriz (la actualiza el orquestador).

## Estado del borrador (leer antes de tocar)
El orquestador intentó este fix vía MCP y sus llamadas fallaron de formas diversas
(incluido un aborto). Es **probable que el borrador esté intacto**, pero no garantizado:
1. Leer el workflow live completo primero.
2. Verificar el nodo `Build Respuesta Ya en lista`: debe tener exactamente 1 asignación
   (`message_payload` con el texto YA_EN_LISTA). Si ves placeholders (`X`, `RESTORED_OK`,
   `PRODUCTO_SIN_STOCK_MSG`, `phantom`, `FIN`) o faltan nodos del atajo, **detener y reportar**
   (el orquestador restaura desde el historial: versión publicada buena `753e3616`).
3. Solo si el estado es el esperado, aplicar el fix.

## Fix (solo WF-10 `xFcZMG8Hip0Z6aH5`)
Agregar al nodo `Build Respuesta Ya en lista` (manteniendo `includeOtherFields:true` y el
`message_payload` existente **sin cambiar ni una letra**) 3 asignaciones top-level desde
`$("Validate Input").item.json` (mismo patrón que `Error: SKU no encontrado`):
- `id_comercio` (string) = `={{ $('Validate Input').first().json.id_comercio }}`
- `phone` (string) = `={{ $('Validate Input').first().json.phone }}`
- `provider` (string) = `={{ $('Validate Input').first().json.provider }}`
Cableado (Merge input 4, IF, resto) intacto. Nada más en el workflow.

## Procedimiento y entregable
Publicar, anotar nuevo `versionId`, y **verificar leyendo el nodo después de publicar**
(4 asignaciones, textos exactos). Sin pruebas vivas (el dueño retestea mandando FERC01:
espera la respuesta directa EN EL WHATSAPP). Responder: versión anterior → nueva +
lectura de verificación. Si algo no coincide, no improvisar: reportar.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens.
