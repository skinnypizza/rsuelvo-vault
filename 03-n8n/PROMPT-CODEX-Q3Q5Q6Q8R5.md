# PROMPT CODEX — Q3/Q5/Q6/Q8-WF25B/R5-wiring (cuenta `rsuelvotest`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Decisiones del dueño aprobadas (bitácora 2026-09-12): Q3 con política explícita, Q5 con copy
exacto, Q6 con P5, Q8 con migración 50 aplicada, R5 con RPC nueva (migración 51). R3 NO va.
Q1/Q2/Q4/Q7 ya publicados. Reglas 2/3/9, D9/D11, STOP y Matriz (orquestador) como siempre.
IDs y versiones en Matriz §0: releer cada live antes de tocarlo (versión inesperada =
detener ese fix y reportar).

## Q3 — Política STOP explícita (WF-04, rama opt-out)
Cuentan como STOP (normalizar: mayúsculas, espacios colapsados, sin `!.?` final):
`STOP`, `NO QUIERO`, `NO ME CONTACTEN`, `NO ME CONTACTE`, `NO ME ESCRIBAN`,
`NO ME ESCRIBAS`, `NO MOLESTAR`. Si no se puede resolver/persistir el comercio:
rama igualmente terminal (no avanza a captura) + el fallo queda en auditoría por el
canal operativo existente. Regla dura: `NO` jamás es STOP.

## Q5 — Ayuda genérica (WF-04 fallback + camino sin payload de WF-02)
Texto exacto: `👋 Para comprar, enviame el código del producto (6 caracteres, ej: FERJ01). Si ya pagaste, enviame la foto del comprobante.` Contratos top-level completos hacia
WF-80. Sin throttle propio (el rate-limit de WF-80 ya acota).

## Q6 — Error técnico OCR distinguido (WF-22 + WF-21, con P5, sin cambiar umbrales)
`Parse OCR`: validar esquema (booleano, confianza 0–1, monto ≥ 0, fecha válida,
operación texto); si falla → `parse_error` explícito. WF-21 `¿Error técnico del OCR?`:
reconocer `parse_error` como técnico (rama de error técnico existente, no "ilegible").

## Q8-WF25B — Nombre confirmado (backend listo, migración 50)
`Guardar Nombre` (WF-25-B): agregar `p_origen_nombre: 'CONFIRMADO'` a la llamada
`fn_upsert_cliente` (los nombres parseados del mensaje son confirmados; el perfil solo
rellena vacíos desde la migración). Verificar que WF-10 sigue sin el parámetro
(default PERFIL = protegido).

## R5-wiring — Respuestas post-QR con estado real (backend listo, migración 51)
`fn_estado_pago_cliente(p_id_comercio, p_id_cliente)` devuelve snapshot
(reserva activa+expiración, pedido ESPERANDO_PAGO, verificación en curso, último
comprobante). En WF-04 (textos post-QR/"ya pagué"): consultar y responder según estado
SIN mutar nada (reserva activa: recordar QR+comprobante con minutos; verificación en
curso: "lo estamos verificando"; comprobante inválido: reenvío; pagado: estado
nombre/entrega). Mensajes cortos, tono existente; reportar los textos usados.

## Procedimiento y entregable
Por fix: releer live, cambio mínimo, publicar, anotar `versionId`, verificar leyendo nodos.
Sin pruebas vivas (el dueño testea dirigido). Responder: por fix versión + cambios +
lectura. Si algo no aplica, reportar, no improvisar.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens. Sin migraciones ni Matriz.
