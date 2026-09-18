# PROMPT ANTIGRAVITY — Móvil: usuarios globales + filtro de reportes por rol

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Dos pendientes. Backend LISTO (migs 68/73 + EF v8, verificado): `fn_editar_usuario`,
`fn_gestionar_vinculo` (CREAR/DESACTIVAR), EF invite roles 2/3/4, `protegido` para
SUPERADMIN. Referencia web: `rsuelvo-web/app/src/features/UsersPage.tsx` (lista
cross-tenant, editar/desactivar deshabilitados donde no hay contrato — aquí SÍ hay).
Marca `brand.dart`. Reglas: jamás `service_role`, español, gates por rol
(`isSuperAdmin/isSysAdmin/isSupport/isAdmin/isCajero/isRepartidor` en `auth_model.dart`),
economía, sin capturas, `flutter analyze` limpio + tests con mocks (sin datos reales).

## 1. Usuarios globales (solo SUPERADMIN)
Lista cross-tenant (nombre, rol, comercio, estado) + editar (nombre/apellido/
teléfono/activo) + activar/desactivar vínculos + invitar SYSADMIN/SUPPORT
(EF con `id_rol` 2/3). `protegido` como aviso legible. Reutilizar
`usuarios_list_screen.dart` donde aplique.

## 2. Filtrar tipos de reporte por rol (hoy todos ven todo y rompe al generar)
En `reportes_screen.dart` (líneas ~37-49) reemplazar por mapeo exacto:
- SUPERADMIN: los 13 tipos.
- SYSADMIN/SUPPORT: solo `creditosStaff`, `estadosComercios`.
- Dueño: solo `pedidos, reservas, inventario, movimientosInventario, verificaciones, envios, creditos`.
- Cajero/Repartidor: ninguno (mensaje «tu rol no tiene reportes»).
Sin tipos visibles que fallen: lo no permitido no se muestra.

## Verificación y entregable
Tests (CRUD, gates, mapeo) + commit. Si un contrato no existe, reportar.
