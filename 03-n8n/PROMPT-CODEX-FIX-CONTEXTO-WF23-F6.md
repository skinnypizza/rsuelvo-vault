# PROMPT CODEX — F6: restaurar contexto WF-21→WF-23 + mensajes Reject/Manual (cuenta `rsuelvotest`)

## Diagnóstico verificado por el orquestador (partir de aquí, no re-investigar)
- WF-21 #574 → WF-23 #576 (2026-09-11): OCR OK (`is_payment_receipt:true`, conf 0.99,
  monto 33, pedido `d897376d`), comprobante registrado, verificación iniciada, ACK enviado.
- WF-23 #576 muere en `Rechazar (fn_rechazar_verificacion)` con PostgREST **404 PGRST202**:
  llamó con body `{"p_resultado":{}}` **sin `p_id_verificacion`**. La fn EXISTE en BD con firma
  `(p_id_verificacion uuid, p_resultado jsonb)` — el 404 es solo por el argumento faltante.
- Causa raíz: el nodo `Call WF-23 (Verify)` de WF-21 le pasa únicamente los 5 campos del ACK
  (`id_comercio, phone, provider, type, text`). Se pierden `id_verificacion, confidence,
  amount, is_payment_receipt, operation_number`. Blast radius probado: (1) `Decide Verification`
  decide RECHAZAR por ausencia de datos (conf undefined→0); (2) la RPC Rechazar va sin id;
  (3) la rama CONFIRMAR también llegaría a WF-24 sin `id_verificacion` (mismo bug latente).
- Los datos completos EXISTEN en WF-21 en `Parse Verification Result`
  (`resultado, id_verificacion, id_comercio, phone, provider, is_payment_receipt, confidence,
  amount, operation_number`).
- Hallazgo 2: `Build WF-80 Reject` y `Build WF-80 Manual` (WF-23) son Sets **vacíos**
  (sin asignaciones) → aunque la decisión fuera correcta, el aviso saldría vacío.
- Alcance: SOLO restaurar contexto y mensajes. **No rediseñar los umbrales de decisión**
  (deuda Regla 3/4 ya registrada en P5, fuera de aquí).

## Cambios
### WF-21 `nJCQI6MfFSjUhywB` (releer live antes de tocar)
- La entrada de `Call WF-23 (Verify)` debe llevar el contexto completo. Insertar Build
  `WF-23 Input` (o remapear equivalente) que tome de `$('Parse Verification Result')`:
  `id_verificacion, id_comercio, phone, provider, is_payment_receipt, confidence, amount,
  operation_number` (+ `id_pedido` si está disponible en el flujo para los mensajes).
  El envío del ACK por WF-80 queda intacto (funciona).
### WF-23 `okF8Ayhp5CicRpVU` (releer live antes de tocar)
- Con el contexto restaurado, verificar que `Decide Verification` recibe los campos
  (sin cambiar sus umbrales).
- `Build WF-80 Reject`: construir payload real con `id_comercio/phone/provider` del input
  + `type:text` + texto de rechazo con reenvío (D5: pedido vuelve a ESPERANDO_PAGO,
  `puede_reenviar=true`; decirlo en el mensaje).
- `Build WF-80 Manual`: construir payload real (aviso "revisión humana en curso").
- Ambos Sends a WF-80 ya existen; solo faltaba el contenido.
- Verificar que `Call WF-24 (Confirm)` arrastra `id_verificacion` por passthrough
  (con el contexto restaurado debe llegar solo).

## Procedimiento y entregable
Releer ambos lives (si alguna versión cambió respecto a lo citado, detener ese fix y reportar).
Cambios mínimos, publicar ambos, anotar nuevos `versionId`, y verificar leyendo los nodos
(contexto completo en la entrada de WF-23; Builds con contenido). Sin pruebas vivas
(el dueño retestea con el mismo comprobante: espera rechazo CORRECTO y avisado, ya que el
monto 33 no corresponde al pedido). Responder: versiones + qué cambió + lectura de
verificación. La Matriz la actualiza el orquestador. Si algo no aplica, reportar.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens.
