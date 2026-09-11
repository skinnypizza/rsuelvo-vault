# PROMPT CODEX — Implementar fixes F1–F4 en n8n (cuenta `rsuelvotest.app.n8n.cloud`)

## Contexto (tenés acceso al vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
- Especificación exacta de los 4 fixes: `03-n8n/PROMPT-INTERVENCION-FIXES-FUNCIONALES.md` (F1–F4;
  F5 queda EXCLUIDO — espera la migración 41, ya aplicada con `fn_agregar_lista_espera_v2`).
- IDs y versiones en `03-n8n/Matriz-Consistencia-WF-BD-HU.md` §0. Reglas de Oro 2/3/9 y D9/D11
  del PROMPT MAESTRO: WF-80 no se toca por dentro; sin lógica de negocio en nodos.

## Aclaración para F1 (la más delicada)
El nodo `Send Confirm via WF-80` (WF-24) debe apuntar a WF-80 (`7V6MIPuGbdx9s0lT`) y espejar el
patrón que YA funciona en WF-13 (`Send via WF-80`): `mode: each`, sin mapeo manual de entradas
(el ítem que sale de `Build WF-80 Confirm` fluye directo). No inventes otro mecanismo de pasaje.

## Procedimiento por fix
1. Releer el workflow live (versión publicada) antes de tocarlo; si la versión cambió respecto a
   la documentada, detener ese fix y reportarlo.
2. Aplicar el cambio mínimo descrito en el paquete (nada más).
3. Publicar el workflow y anotar el nuevo `versionId`.
4. Probar el camino tocado si es posible sin afectar datos reales (reserva→QR para F4;
   rama automática de confirmación para F1–F3); si una prueba viva es riesgosa, declararlo y
   proponer el caso de prueba en vez de ejecutarlo.

## Entregable
Responder con: por cada fix (F1–F4), versión anterior → nueva, cambio aplicado, prueba
realizada o propuesta. La Matriz la actualiza el orquestador — no la edites.
Si algún fix no puede aplicarse tal cual está especificado, no improvises: reportalo.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens: reportá solo lo cambiado.
