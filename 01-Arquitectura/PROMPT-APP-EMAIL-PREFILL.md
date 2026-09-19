# PROMPT ANTIGRAVITY — Móvil: prefill email desde solicitud

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
La solicitud trae `email` (mig 75) pero el alta no lo pre-rellena. Reglas: jamás
`service_role`, español, economía, sin capturas, `flutter analyze` limpio + tests
con mocks (sin datos reales).

## Cambio (sin cambios BD)
`SolicitudAlta` + select + ficha muestran `email`; «Crear comercio» lo pasa al
`_AltaDialog` (campo Email del dueño pre-rellenado, editable). Sin tocar diseño.

## Verificación y entregable
Tests + commit. Si un contrato no existe, reportar.
