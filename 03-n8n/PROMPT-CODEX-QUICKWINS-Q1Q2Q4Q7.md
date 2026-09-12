# PROMPT CODEX — Quick-wins Q1/Q2/Q4/Q7 (cuenta `rsuelvotest`)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Auditoría en `03-n8n/Auditoria-Robustez-Conversacional.md` (§5). Implementar SOLO estos 4,
quirúrgicos, sin migraciones BD. Reglas 2/3/9, D9/D11, STOP intacto (no tocar opt-out),
Matriz la actualiza el orquestador. IDs y versiones base en Matriz §0 (releer live de cada
workflow antes de tocarlo; versión inesperada = detener ese fix y reportar).

## Q1 — Acuses no se guardan como nombre/ciudad (WF-25-B)
Solo en contextos nombre/ciudad/captura (NO en WF-14, eso es Q2): antes de consumir texto
como dato, reconocer chitchat conservador (`gracias`, `muchas gracias`, `hola`, `buenas`,
`buenos dias/tardes/noches`, `rebaja*`, `descuento*`, `ok`/`dale` sueltos como acuse) →
devolver la pregunta pendiente (ciudad, nombre o menú según el paso) SIN escribir en BD
(ni captura, ni cliente). Orden: primero validación de menú Q4 (números), luego este filtro,
luego consumo como dato. Vocabularios SI/NO de lista no se tocan aquí.

## Q2 — Vocabulario SI/NO unificado, solo NO rechaza (WF-04 + WF-14)
- WF-14 `Parse Decision` (+`Parse Decision 2` si aplica): aceptar `SI/SÍ/OK/DALE/YO`
  (YO se suma; el router ya lo marca afirmativo); `NO` canónico → RECHAZAR (fns intactas);
  **cualquier otra cosa → CONSERVAR** (no toca pendiente/turno) + re-pregunta con el texto
  de la pregunta vigente (reusar mensajes existentes, no inventar copy nuevo salvo mínimo).
  Pasar de 2 a 3 salidas donde corresponda.
- WF-04 `Enrich & Classify`: mantener YO afirmativo; documentar en el informe los sets
  finales aceptado/rechazado/no-reconocido.

## Q4 — Menú numérico estricto (WF-25-B)
`¿Selección?`: aceptar enteros completos (multi-dígito), validar pertenencia al catálogo
vigente (soportar >9 opciones); lo inválido reenvía el menú. **Nunca derivar a `Parse
Nombre`** una entrada de menú inválida (hoy "10"/"2 por favor" se guardan como nombre).
Verificar el cableado actual antes de moverlo.

## Q7 — Contrato top-level en errores (lección #508)
`Error: SKU no encontrado`, `Error: Input inválido` (+`Error: Cliente upsert`, verificar):
agregar `id_comercio/phone/provider` (+`sku` donde aplique) a nivel superior desde
`Validate Input`, patrón del atajo ya_en_lista. Barrer otros nodos terminales con
`message_payload` hacia WF-02 en WF-10/14/20/21 y corregir los que falten; reportar cada uno.

## Procedimiento y entregable
Por fix: releer live, cambio mínimo, publicar, anotar `versionId`, verificar leyendo nodos.
Sin pruebas vivas (el dueño testea con casos dirigidos). Responder: por fix versión
anterior → nueva + qué cambió + lectura. Si algo no aplica tal cual, reportar, no improvisar.

## Reglas operativas
Español. Sin capturas ni JSONs enteros. Economía de tokens. Sin dependencias ni migraciones.
