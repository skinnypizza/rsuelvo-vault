# PROMPT ANTIGRAVITY — Móvil: transportadoras SÍ (no categorías, eso ya está)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Aclaración: el commit anterior hizo categorías globales; ESO NO ERA. Lo pedido
son TRANSPORTADORAS (empresas de envío). Backend LISTO (mig 78, verificado):
`tbl_transportadoras` (id, nombre, ciudades, activo, id_comercio NULL=global
«RSUELVO»); RLS (globales visibles + propias full dueño). Marca `brand.dart`.
Reglas: jamás `service_role`, español, gate dueño, economía, sin capturas,
`flutter analyze` limpio + tests con mocks (sin datos reales).

## Cambio (sin cambios BD)
En configuración del comercio, sección Transportadoras: lista (globales con
marca «RSUELVO» solo lectura + propias), alta/editar/desactivar propias y
«Copiar como propia» desde una global. Filtro Supabase: `or('id_comercio.is.null,id_comercio.eq.<id>')`.

## Verificación y entregable
Tests + commit. Si un contrato no existe, reportar.
