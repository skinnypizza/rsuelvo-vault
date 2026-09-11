# PROMPT CODEX — Auditoría de optimización de ejecuciones n8n (SOLO LECTURA)

## Objetivo
Auditar los 16 workflows canónicos de RSUELVO (cuenta n8n **`rsuelvotest.app.n8n.cloud`**)
para reducir el **gasto total de ejecuciones** en n8n Cloud, SIN modificar nada todavía.
El único entregable es un **informe en el vault** con hallazgos y propuestas priorizadas.

## ⛔ Restricción dura
- **PROHIBIDO modificar, crear, archivar, activar/desactivar workflows** (nada de
  `update_workflow`, ni cambios en nodos, conexiones, settings o credenciales).
- **PROHIBIDO tocar la base de datos** (ni DDL ni DML; si necesitás verificar la firma
  exacta de una `fn_*`, pedísela al orquestador en tu informe como "pendiente de verificar").
- Único archivo que podés crear: el informe (ruta abajo). Ningún otro cambio en el vault.

## Contexto del proyecto (tenés acceso total al vault)
Leé primero, en este orden:
1. `00-Index/00-PROMPT-MAESTRO-RSUELVO.md` — Reglas de Oro (especialmente **2, 3, 9**: la
   lógica vive en `fn_*`, n8n orquesta, trazabilidad en `tbl_logs_auditoria`) y decisiones D9/D11.
2. `03-n8n/Matriz-Consistencia-WF-BD-HU.md` — §0 con los **IDs reales** de los 16 workflows
   en `rsuelvotest` + qué hace cada uno y a qué `fn_*` llama.
3. `03-n8n/workflows.md` + `03-n8n/Checklist-Migracion-n8n.md` — diseño de cada flujo.
4. `07-Control-de-Calidad/Observaciones-Usuario.md` — OBS-001…005 (comportamientos que
   NO deben romperse).
5. JSONs exportados de referencia en `~/Escritorio/WORKFLOWS EXTRAIDOS FINAL/rsuelvo-workflows/`
   (pueden estar desactualizados; la Matriz §0 manda para IDs).

## Qué auditar
Para cada workflow y para las cadenas completas, determiná:
1. **Mapa de ejecuciones por escenario**: ¿cuántas ejecuciones de workflow dispara 1 mensaje
   de WhatsApp / 1 venta completa / 1 mensaje inválido / 1 corrida de cron? Trazá las cadenas
   (ej. WF-02 → WF-04 → WF-10 → WF-20 → WF-80) y contá ejecuciones por eslabón.
2. **Llamadas a sub-workflows evitables**: workflows diminutos que solo transforman datos
   (candidatos a inline como nodos Code/Set en el llamador) vs. los que deben seguir separados.
3. **Filtros tardíos**: webhooks/schedules que disparan ejecuciones y llaman sub-flujos ANTES de
   validar (token, opt-out, idempotencia en `tbl_whatsapp_eventos`, formato). Todo descarte debe
   ocurrir lo antes posible en la cadena.
4. **Triggers con desperdicio**: schedules demasiado frecuentes, webhooks sin filtro temprano,
   loops que llaman sub-workflows por ítem (¿se puede procesar en lote?).
5. **Settings de guardado**: `saveExecutionProgress`, `saveDataSuccessExecution`,
   `saveDataErrorExecution` por workflow — qué se puede recortar SIN violar la Regla 9
   (la auditoría canónica vive en `tbl_logs_auditoria`, no en n8n).
6. **Duplicación entre flujos**: lógica repetida (lookups de cliente/sucursal, construcción de
   payloads para WF-80) candidata a centralizar.
7. **Ramas de error**: ¿los caminos de error generan ejecuciones en cascada innecesarias?

## Entregable: informe en el vault
Creá **`03-n8n/Auditoria-Optimizacion-Ejecuciones.md`** con:
- Resumen ejecutivo (top 5 ahorros, con estimación de ejecuciones ahorradas por escenario).
- Tabla por workflow: ejecuciones actuales por escenario → propuesta → ahorro estimado → riesgo.
- Lista explícita de **"no tocar"** (WF-80 y todo lo atado a D9/D11, opt-out, idempotencia,
  Regla 9) con justificación.
- Propuestas ordenadas por ratio ahorro/riesgo, cada una con IDs citados
  (`WF-xx` + `HU-xxx` + tabla/fn afectada) y pasos de implementación futura.
- Sección "pendiente de verificar" (firmas `fn_*`, JSONs live) para el orquestador.

## Reglas operativas
- Español. Sin capturas ni volcados gigantes (economía de tokens: resumí, no pegués JSONs
  enteros salvo el fragmento mínimo que pruebe un hallazgo).
- No inventes datos de facturación de n8n: si un costo no es verificable desde el diseño,
  exprésalo en ejecuciones relativas, no en dinero.
