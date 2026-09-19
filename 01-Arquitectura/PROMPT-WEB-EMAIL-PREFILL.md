# PROMPT CODEX (Astra) — Web: prefill email desde solicitud + alta

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
La solicitud trae `email` (`tbl_solicitudes_alta.email`, mig 75) pero el wizard
de alta no lo pre-rellena. Reglas: español, economía, UN commit, builds+tests verdes.

## Cambio (solo `/app`)
1. `SolicitudAlta` + `listSolicitudes`: incluir `email`.
2. Ficha: mostrar email; botón «Crear comercio» pasa `email` en el state.
3. `CommerceWizard`: pre-rellenar «Correo del dueño» desde la solicitud
   (editable). Sin tocar diseño ni flujos.
