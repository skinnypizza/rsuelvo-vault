# PROMPT CODEX — WF-25-C: estados logísticos silenciosos + app en terminal (cuenta `rsuelvotest`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Decisión del dueño (OBS-007, E2E logística 2026-09-11): demasiados WhatsApps por cambio de
estado. Quedan así: `PREPARANDO` avisa (intacto) · `ASIGNADO`, `EN_RUTA` y `ENTREGADO`
**silenciosos** · el aviso de despacho con guía/número/foto SE QUEDA (es el tracking del
comprador). La guía además cierra sola la entrega (migración 48 ya aplicada: envío→ENTREGADO
y pedido→ENTREGADO si estaba pago/en curso). Reglas 2/3/9, D9/D11, Regla 7 (dedup) intactas.

## Cambio 1 — WF-25-C `2DzqPBe4xtHIuvHA` (releer live antes de tocar)
Cuando el evento sea cambio de estado (`motivo` de estado, no `guia_registrada`) con estado
`ASIGNADO`, `EN_RUTA` o `ENTREGADO`: NO enviar WhatsApp; responder 200 y mantener el marcado
de dedup exactamente igual (la ausencia de envío no debe romper ni duplicar nada).
No tocar: `guia_registrada`, `PREPARANDO`, token inválido, ni el resto del grafo.
Si la forma del evento no permite discriminar con certeza, detener y reportar (no improvisar).

## Cambio 2 — App: envío en terminal tras la guía
En la pantalla de envíos (admin/repartidor): si el envío tiene guía registrada o está
`ENTREGADO`, mostrar estado terminal y deshabilitar más transiciones/acciones sobre él
(la responsabilidad termina al despachar). Sin cambios BD.

## Procedimiento y entregable
Releer el live (versión cambiada = detener y reportar). Cambios mínimos, publicar WF-25-C,
anotar nuevo `versionId`. Sin pruebas vivas (el próximo despacho real lo prueba: 1 aviso de
guía + silencio posterior). Responder: versión anterior → nueva + qué cambió + lectura de
verificación. La Matriz la actualiza el orquestador.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens. Sin dependencias nuevas.
