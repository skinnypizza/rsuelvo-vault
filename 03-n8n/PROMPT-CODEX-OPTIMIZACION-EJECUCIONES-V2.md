# PROMPT CODEX — Auditoría de optimización n8n, v2 (SOLO LECTURA)

## Punto de partida
Ya entregaste `03-n8n/Auditoria-Optimizacion-Ejecuciones.md` (v1) con el addendum del orquestador
al inicio. Esta v2 **actualiza ese mismo archivo** (agregá sección "Cambios v2" + corregí lo indicado;
no borres la v1, queda como historial).

## Correcciones que la v1 no absorbió (fuentes ya en el vault)
1. **m38 — P1 invalidado, se mantiene solo-ciudad.** La decisión vigente (bitácora 2026-09-09 +
   `fn_procesar_captura_destino` con `destino_zona=NULL` + OBS-005 corregida) es: destino = solo
   ciudad en 1 mensaje, zona eliminada. Reescribí P1: en vez de pedir CIUDAD+ZONA, verificá la
   claridad de la pregunta única actual y si genera correcciones evitables.
2. **m40 — catálogo por sucursal (2026-09-10).** Incorporá: `fn_resolver_variante_por_sku` con
   firma `(p_id_comercio, p_sku, p_id_sucursal)`, `fn_variante_efectiva`, `fn_listar_variantes_sucursal`,
   y que WF-10/WF-13 ya usan precios/nombres efectivos por sucursal. Revisá cualquier propuesta
   que toque precios, nombres o resolución de SKU a la luz de m40.
3. **Firmas resolubles en el vault.** Ya NO van como "pendiente": `fn_registrar_guia`
   (`02-Base-de-Datos/sql/36_guia_foto.sql`), trío Momento 1 + `fn_rechazar_lista_espera`
   (archivos 35/31), captura de destino final (archivo 34), y todo m40 (archivo 40 +
   `06_functions.sql`). Mantené como pendiente solo lo genuinamente externo: panel Usage,
   topología pg_cron→pg_net, suscripción Meta/status.
4. **Bugs ya verificados por el orquestador** (van en intervención separada, no los re-audites
   como ahorro): WF-24→WF-22, espacio en IF, texto vs OBS-003, `media_url` WF-20, precheck WF-12.

## Restricciones (igual que v1)
Solo lectura: prohibido modificar workflows o BD; único cambio permitido: el informe v2.
Español, sin capturas ni JSONs enteros, ahorros en ejecuciones relativas, IDs citados.
