# PROMPT ANTIGRAVITY — Móvil: CRUD categorías por comercio

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
`tbl_categorias` (id_categoria, id_comercio, nombre, descripcion, activo) está
VACÍA: ningún flujo la usa y no hay UI. Backend LISTO: `categories_manage` (ALL,
dueño) + `categories_select` (acceso comercio). Referencia cercana:
`sucursales_list_screen` + form dialog (CRUD tenant simple). Marca `brand.dart`.
Reglas: jamás `service_role`, español, gate dueño, economía, sin capturas,
`flutter analyze` limpio + tests con mocks (sin datos reales).

## Cambio (sin cambios BD)
CRUD de categorías del comercio (lista + alta/editar/desactivar) donde viva el
catálogo (productos). Sin tocar flujos de venta.

## Verificación y entregable
Tests + commit. Si un contrato no existe, reportar.
