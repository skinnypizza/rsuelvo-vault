# PROMPT CODEX — Auditoría blindaje conversacional (SOLO LECTURA)

## Objetivo
Auditar cómo el sistema trata textos del comprador FUERA de flujo ("rebajame", "gracias",
chitchat en post-QR, verificación, captura de ciudad, momentos SI/NO) en los 16 workflows
(`rsuelvotest`), SIN modificar nada. Entregable: informe + propuestas priorizadas.

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
OBS-010. PROMPT MAESTRO (Reglas 2/3/9, D9/D11), Matriz §0 (IDs), workflows.md, OBS-001…009.
Casos reales conocidos: "gracias" como ciudad capturada; regateo post-QR; texto durante
verificación.

## Qué auditar
1. Inventario de puntos donde texto libre se consume como DATO (captura ciudad, SI/NO,
   SKU, nombre) y qué validación existe en cada uno.
2. Fallbacks actuales ante texto inesperado por estado (ayuda genérica, re-pregunta,
   silencio, corrupción de estado) + qué pasa con mensajes cruzados/órdenes alteradas.
3. Opt-out y STOP en medio de flujos (no romperlos con ningún cambio futuro).

## Entregable
Crear `03-n8n/Auditoria-Robustez-Conversacional.md`: tabla punto→riesgo→propuesta
(saludo/acuse sin romper estado, re-pregunta con contexto, validaciones estrictas donde
corresponda), ordenadas por riesgo/beneficio, con IDs (`WF-xx`, `HU-xxx`, fn/tabla).
Proponer sin implementar; እንደ sea posible distinguir quick-wins de rediseño. Único archivo creable.

## Reglas operativas
Solo lectura (cero cambios n8n/BD). Español, sin capturas ni JSONs enteros, IDs citados.
