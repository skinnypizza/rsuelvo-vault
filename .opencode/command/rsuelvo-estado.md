---
description: Muestra el estado de ejecución de RSUELVO (fases, HU, bloqueos) y propone el próximo hito. No modifica nada.
agent: rsuelvo
---

Genera el reporte de estado de RSUELVO (solo lectura, sin modificar archivos):

1. Lee `00-Index/ESTADO-EJECUCION.md` y contrasta con `git log --oneline -10` del vault.
2. Muestra: fases F0-F8 con estado, última entrada de bitácora, bloqueos del usuario (U1-U4) y HU en curso si las hay.
3. Propón el próximo hito concreto según el orden del PROMPT MAESTRO §8, indicando qué lo desbloquea y a qué agente correspondería.
