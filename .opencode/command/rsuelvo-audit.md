---
description: Auditoría de consistencia global de RSUELVO (WF↔BD↔HU↔wireframes↔matrices); opcional acotar alcance como argumento.
agent: rsuelvo
---

Ordena una auditoría de consistencia a `rsuelvo-qa`.

- Alcance: $ARGUMENTS (si está vacío → auditoría global del vault; si se indica un dominio, fase, HU o WF → limitar a eso).
- `rsuelvo-qa` aplica su checklist (IDs, nada inventado, matrices al día, Reglas de Oro por dominio, DoD §9.5) y devuelve su informe sin corregir nada.
- Integra el informe: agrupa hallazgos por agente de dominio responsable y propón un plan de remediación priorizado por severidad.
- Actualiza `00-Index/ESTADO-EJECUCION.md` (bitácora) con el veredicto de la auditoría. No apliques correcciones sin aprobación del usuario.
