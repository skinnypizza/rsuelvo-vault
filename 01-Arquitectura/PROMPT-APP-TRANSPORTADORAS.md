# PROMPT ANTIGRAVITY — Móvil: transportadoras por comercio (opción B)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Decisión del dueño (opción B): cada comercio crea y gestiona las SUYAS; las 2
globales quedan como plantilla visible. Backend LISTO (mig 78): `id_comercio`
NULLABLE (`NULL` = global), RLS (globales visibles todos + propias full para
dueño). Marca `brand.dart`. Reglas: jamás `service_role`, español, gate dueño,
economía, sin capturas, `flutter analyze` limpio + tests con mocks.

## Cambio (sin cambios BD)
En configuración del comercio: lista (globales marcadas «RSUELVO» + propias),
alta/editar/desactivar propias, opcional «copiar global como propia».
Sin tocar flujos de envío (aún no las referencian).

## Verificación y entregable
Tests + commit. Si un contrato no existe, reportar.
