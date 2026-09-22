# IAM-2A/FLUTTER — Compatibility: eliminar UPDATE directo (implementación)

## OBJETIVO
Eliminar el UPDATE directo de `tbl_usuario_comercio.activo` antes de endurecer la DB. Prerrequisito de mig 81.

## ALCANCE EXACTO
Solo `usuario_edit_dialog.dart` + repository. Nada de schema/cloud. NO selector, NO `selected.first`, NO IAM-3.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `lib/features/usuarios/usuario_edit_dialog.dart` (único llamador de `actualizarVinculo`)
- `lib/features/usuarios/usuarios_repository.dart` (`actualizarVinculo` directo vs `gestionarVinculoGlobal` por fn)
- `lib/features/usuarios/usuario_vinculo_model.dart` (idUsuario/idComercio disponibles)

## DEPENDENCIAS
Ninguna. IAM-2B depende de este sublote verificado.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- `fn_gestionar_vinculo` actual (CREAR/DESACTIVAR, superadmin-gate intacto); UI sin cambios visibles salvo mensajes; suite verde

## CAMBIOS PERMITIDOS
Nuevo método repository que mapea el diálogo a fns: desactivar→DESACTIVAR(tupla vieja); activar→CREAR; cambio rol/sucursal→DESACTIVAR(vieja)+CREAR(nueva); manejar `{ok,codigo}` (`vinculo_no_existe` tolerable en re-mapeo). Marcar `actualizarVinculo` como `@deprecated` (no borrar aún).

## CAMBIOS PROHIBIDOS
UPDATE/INSERT/DELETE directos nuevos a `tbl_usuario_comercio`; cambiar gates; selector; `selected.first`; schema.

## PRUEBAS REQUERIDAS
Tests con mocks: activar, desactivar, reactivar, cambio rol/sucursal (doble llamada), error protegido; regresión usuarios/staff; analyze 0.

## ENTREGABLES
Commit en `main` + SHA para revisión (puerta de IAM-2B).

## DEFINITION OF DONE
Cero UPDATE directos a `tbl_usuario_comercio` en `lib/` (grep); analyze 0; suite verde.
