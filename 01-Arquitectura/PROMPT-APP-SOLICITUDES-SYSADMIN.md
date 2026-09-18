# PROMPT ANTIGRAVITY — Móvil: solicitudes sysadmin

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Backend LISTO (mig 73, verificado): `tbl_solicitudes_alta` legible por
SUPERADMIN y SYSADMIN; `fn_resolver_solicitud_alta` acepta ambos roles.
Marca `brand.dart`. Reglas: jamás `service_role`, español, gates por rol,
economía, sin capturas, `flutter analyze` limpio + tests con mocks (sin datos reales).

## Cambio (sin cambios BD)
Abrir `Solicitudes` (lista+ficha+aprobar/rechazar+crear-comercio) a SYSADMIN
con idéntica funcionalidad que SUPERADMIN. Nada más.

## Verificación y entregable
Tests (gates por rol) + commit. Si un contrato no existe, reportar.
