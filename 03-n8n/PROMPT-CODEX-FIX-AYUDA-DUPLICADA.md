# PROMPT CODEX — Fix ayuda duplicada en WF-02 (cuenta `rsuelvotest`)

## Diagnóstico verificado por el orquestador (partir de aquí)
SKU FERJ01 (WF-02 #744) produjo DOS envíos: QR legítimo (WF-80 #749, padre WF-20 #748) +
ayuda espuria (WF-80 #750, padre WF-02 #744). Causa: el cambio Q5 ("sin payload → ayuda")
dispara también cuando el retorno es legítimamente silencioso porque otro subflujo ya
envió (RESERVA_CREADA/YA_EXISTENTE → QR vía WF-20). Evidencia en ejecuciones #744/#749/#750.

## Fix (solo WF-02 `kXuiHOMTxgR1Lo1O`, reeler live, base ver. `f62e9638`)
Condicionar el envío de ayuda: solo si NO hay `message_payload` en el retorno Y el
`resultado` NO está en el conjunto manejado-por-subflujo. Conjunto inicial:
`RESERVA_CREADA`, `RESERVA_YA_EXISTENTE` (QR vía WF-20). Antes de cerrar, relevar TODOS
los `resultado` posibles que llegan a ese nodo y justificar cada uno (envía ayuda vs
suprime) en el informe; ante duda, suprimir solo los dos documentados.
Nada más en el workflow. STOP/opt-out/WF-80 intactos.

## Procedimiento y entregable
Releer el live (versión cambiada = detener). Cambio mínimo, publicar, anotar `versionId`,
verificar leyendo el nodo. Sin pruebas vivas (el dueño retestea con próximo SKU: espera
SOLO el QR). Responder versión + cambio + lectura. Matriz: orquestador.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens.
