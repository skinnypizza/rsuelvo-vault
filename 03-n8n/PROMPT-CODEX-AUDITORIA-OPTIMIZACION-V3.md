# PROMPT CODEX — Auditoría de optimización n8n v3 (SOLO LECTURA)

## Por qué v3
La v2 (2026-09-11) quedó obsoleta: desde entonces cambiaron WF-02 (ayuda + fix
duplicada), WF-04 (STOP 7 frases, R5, M1/M2), WF-10 (atajo ya_en_lista/lista_llena,
título), WF-12 (F5), WF-13/14 (efectivos, Q2 3 ramas), WF-20/21/23/24 (F1–F6, QR),
WF-25-B (Q1/Q4) y WF-25-C (ramas silenciosas + SKU). Más migraciones 41–56 y crons
nuevos (`rsuelvo_push_por_vencer`). Esta v3 re-baselinea todo.

## Alcance y reglas
- Solo lectura: cero cambios n8n/BD; único archivo creable:
  `03-n8n/Auditoria-Optimizacion-Ejecuciones-V3.md` (v1/v2 quedan como historial).
- Base: Matriz §0 (IDs), Maestro v1.7 (D1–D16), bitácora 2026-09-11/12/14/15,
  `Auditoria-Optimizacion-Ejecuciones.md` (v1+v2) y `Auditoria-Robustez-Conversacional.md`.
- Disciplina T/Q vigente (docs n8n: solo raíces cuentan a cuota; sub-ejecuciones no).
  Nodos/RPCs extra dentro de una ejecución NO cambian Q (latencia/DB sí): no los
  presentes como ahorro de cuota.

## Qué auditar
1. Releer los 16 live (versiones + diff contra la tabla v2 §2).
2. Recalcular cadenas por escenario con las ramas nuevas: atajo ya_en_lista/lista_llena
   (¿cuántas raíces ahorra vs ronda SI?), estados silenciosos (¿cambian raíces? ¿menos
   respuestas del comprador?), STOP variantes, R5 (solo lee), M1/M2 (nodos extra, misma
   ejecución), Q-filtros, avispas push (pg_net/cron NO tocan n8n: excluir de T/Q).
3. Medir ventana Usage fresca: raíces por webhook (02/13/25-A/25-C), vacíos de WF-13
   (incluye el cron por-vencer), duplicados pg_net, errores y reintentos.
4. Estado de cada propuesta P1–P8 v1/v2: implementada / superada / vigente / descartada,
   con evidencia de versión.
5. Nuevas oportunidades priorizadas por ahorro/riesgo contra el diseño actual
   (P3 status, P4 vacíos, menos mensajes→menos raíces, dedup, settings de guardado).

## Entregable
`03-n8n/Auditoria-Optimizacion-Ejecuciones-V3.md`: resumen (top 5 vigente), tabla por
workflow actual→propuesta→ahorro→riesgo, lista no-tocar actualizada, pendientes de
medición. Español, sin capturas ni JSONs enteros, ahorros relativos, IDs citados.

## Reglas operativas
Solo lectura. Economía de tokens. Si falta un dato live, anotarlo como pendiente,
no inventarlo.
