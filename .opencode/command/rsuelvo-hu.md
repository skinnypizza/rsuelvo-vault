---
description: Implementa una Historia de Usuario RSUELVO de extremo a extremo (ej. /rsuelvo-hu HU-023).
agent: rsuelvo
---

Implementa la Historia de Usuario **$1** de RSUELVO.

1. Protocolo de inicio (PROMPT MAESTRO + `00-Index/ESTADO-EJECUCION.md`).
2. Localiza $1 en `06-Backlog-HU/01-Backlog-Historias-de-Usuario.md`: épica, criterios de aceptación, y su destino de implementación (sección "Clasificación por destino").
3. Reúne trazabilidad: WF asociado (`03-n8n/Matriz-Consistencia-WF-BD-HU.md`), pantalla (`06-Backlog-HU/03-Correlacion-Wireframes-HU.md` + wireframe PNG en `05-Diseño-UX/attachments/wireframes/`), tablas/fn_ afectadas (`02-Base-de-Datos/`).
4. Verifica precondiciones (fase correspondiente iniciada, dependencias de otras HU, bloqueos U1-U4).
5. Descompón y delega según el mapa de delegación; integra los entregables.
6. Valida Definition of Done con `rsuelvo-qa` (PROMPT MAESTRO §9.5): criterios + concurrencia/idempotencia cuando aplique + auditoría + wireframe.
7. Actualiza matrices y `00-Index/ESTADO-EJECUCION.md`; solicita confirmación antes de commitear.
