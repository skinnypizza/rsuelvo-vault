---
description: Ejecuta una fase de construcción RSUELVO (F0..F8) de extremo a extremo siguiendo el orden del PROMPT MAESTRO §8.
agent: rsuelvo
---

Ejecuta la fase **$ARGUMENTS** de RSUELVO.

1. Protocolo de inicio (PROMPT MAESTRO + `00-Index/ESTADO-EJECUCION.md` + git status del vault).
2. Localiza la fase en PROMPT MAESTRO §8: contenido, módulos y HU asociadas.
3. Verifica precondiciones: fases previas completas y bloqueos que dependen del usuario (U1-U4 en ESTADO-EJECUCION.md). Si un bloqueo impide avanzar, repórtalo y detente.
4. Descompón la fase en tareas delegables con IDs citables (HU/WF/pantalla/tabla-fn_) y reparte según el mapa de delegación (`rsuelvo-db`, `rsuelvo-n8n`, `rsuelvo-whatsapp`, `rsuelvo-flutter`).
5. Presenta el plan al usuario para aprobación antes de tocar servicios cloud.
6. Tras cada entregable: validación con `rsuelvo-qa`, actualización de matrices si aplica, y actualización de `00-Index/ESTADO-EJECUCION.md`.
7. Cierre: resumen de la fase con IDs entregados y solicitud explícita antes de cualquier commit.
