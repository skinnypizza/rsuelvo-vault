# PROMPT CODEX — Implementar F3 y F5 en n8n (cuenta `rsuelvotest.app.n8n.cloud`)

## Contexto (tenés acceso al vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
- Paquete base: `03-n8n/PROMPT-INTERVENCION-FIXES-FUNCIONALES.md` (F1/F2/F4 ya aplicados y
  publicados; leer F3/F5 ahí como referencia, pero **esta es la especificación vigente**).
- IDs en `03-n8n/Matriz-Consistencia-WF-BD-HU.md` §0. Reglas 2/3/9 y D9/D11: WF-80 no se toca
  por dentro; sin lógica de negocio en nodos.
- **Migración 41 YA APLICADA** en BD: `fn_agregar_lista_espera_v2(p_id_comercio, p_id_sucursal,
  p_id_variante, p_id_cliente)` → jsonb `{resultado, id_lista_espera?, posicion?, activos?, maximo?}`
  con `resultado` ∈ `AGREGADO | YA_EN_LISTA | LISTA_LLENA`. Misma atomicidad que v1 (lock
  FOR UPDATE por sucursal×variante) + red unique_violation. Validada por el orquestador
  (AGREGADO pos 1 → YA_EN_LISTA mismo id/pos → LISTA_LLENA). Definición exacta en
  `02-Base-de-Datos/sql/41_lista_espera_agregar_v2.sql`. **No elimines la v1** (lo hace el
  orquestador en una migración posterior, cuando F5 esté estable).

## F3 — WF-24: 25-A único emisor (decisión del dueño con evidencia)
Hechos verificados: `trg_pedido_pagado_notifica` dispara a nivel BD (cubre modo auto Y manual,
donde WF-24 ni corre) y WF-25-A ya envía "🎉 ¡Pago confirmado! + nombre" en producción.
Tras F1, la rama TRUE de WF-24 duplicaría ese aviso.
- Workflow `RSU | 24` (`JU4QtP0vkAC7m3n1`, versión `a03891a8`).
- ⚠️ El nodo `Send Confirm via WF-80` es **compartido**: lo usan la rama TRUE (vía
  `Build WF-80 Confirm`) Y la rama RESERVA_VENCIDA (vía `Set "Msg Reserva Vencida"`).
  **No lo borres.**
- Cambio: eliminar el nodo `Build WF-80 Confirm` (solo lo usa la rama TRUE) y conectar la
  salida TRUE del IF a un noOp `Fin (confirmado, avisa 25-A)`. La rama FALSE (Switch F2 +
  aviso de vencida) queda intacta. Resultado: en PAGO_CONFIRMADO WF-24 termina sin enviar;
  el único aviso lo genera WF-25-A (ambos modos).

## F5 — WF-12: alta atómica vía v2, sin prechecks en n8n (HU-043,044; Regla 3)
- Workflow `RSU | 12` (`n9VUH43N8i7s9Rn2`, versión `f5ff4d52`).
- Reemplazar el bloque `Check Lista Espera` + `Ya en lista?` + `Capacidad llena?` +
  `Agregar Lista Espera` (v1) + `Obtener Posicion` + `Obtener Posicion Existente` por:
  un nodo PG `SELECT (r->>'resultado') AS resultado, (r->>'id_lista_espera') AS id_lista_espera,
  (r->>'posicion') AS posicion FROM rsuelvo.fn_agregar_lista_espera_v2(comercio, sucursal,
  variante, cliente) AS r` (mismos 4 parámetros que hoy) + Switch de 3 reglas
  (`AGREGADO` / `YA_EN_LISTA` / `LISTA_LLENA`, fallback → nuevo `Msg Error técnico`:
  "No pudimos agregarte a la lista, intenta de nuevo").
- Reutilizar los textos de mensaje existentes **sin cambiar ni una palabra** (OBS-001/OBS-002):
  `Msg Agregado`, `Msg Ya en lista`, `Msg Lista llena` — como la RPC ya trae `posicion`,
  las expresiones `{{ $json.posicion }}` siguen funcionando igual. Nodos `Output` y
  `Call WF-80` intactos. Borrar los nodos del bloque viejo que queden sin uso.

## Procedimiento y entregable
1. Releer cada live antes de tocarlo; si la versión cambió, detener ese fix y reportarlo.
2. Cambio mínimo, publicar, anotar `versionId` nuevo.
3. Sin pruebas vivas riesgosas (crean lista/envían WhatsApp): proponer casos en vez de ejecutarlos.
4. Responder: por fix, versión anterior → nueva + qué cambió. La Matriz la actualiza el
   orquestador — no la edites. Si algo no aplica tal cual, no improvises: reportalo.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens.
