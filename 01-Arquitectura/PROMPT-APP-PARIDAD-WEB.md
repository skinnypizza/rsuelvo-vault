# PROMPT APP — Paridad staff con web (comercios + reportes + usuarios)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
El dashboard web (`rsuelvo-web/app/src/features`) tiene piezas staff que el móvil
no tiene. Backend LISTO (migs 58-65 + EF `invitar-usuario-comercio` v7):
`fn_alta_comercio` (p_estado; staff coaccionado a PENDIENTE), `fn_cambiar_estado_comercio`,
`tbl_compras_creditos` + `tbl_movimientos_creditos` (lectura RLS), policies QR/depósitos.
Marca `brand.dart` + `Identidad-de-Marca.md`. Reglas: jamás `service_role`, español,
gate por rol, economía de tokens, sin capturas/APK, `flutter analyze` limpio + tests
con mocks (prohibido tocar datos/buckets reales).

## Brechas a cerrar (referencia web entre paréntesis)
0. **Roles múltiples (bug real 406):** un usuario puede tener varios vínculos
   (ej. Cajero + Superadmin) y la app reventaba con `.single()` (PostgREST 406:
   "multiple rows returned"). PROHIBIDO `.single()` en resolución de rol/usuario:
   traer lista y elegir el de mayor privilegio
   (SUPERADMIN > SYSADMIN > SUPPORT > TENANT_ADMIN > CASHIER > LOGISTICS).
   Verificado en web; igualar en móvil.
1. **Comercios** (`CommercesPage.tsx`): lista global con estado+saldo, ficha
   (config, sucursales, canales), alta wizard (staff → PENDIENTE_APROBACION con
   dueño; el invite va al aprobar, flujo existente en Autorizaciones),
   suspender/reactivar (`fn_cambiar_estado_comercio`). Solo SUPERADMIN crea
   ACTIVO directo; SYSADMIN/SOPORTE siempre pendiente.
2. **Reportes staff** (`ReportsPage.tsx`): Depósitos de comercios (compras con
   comprobante firmado al ver), Créditos+consumo por comercio, Estado de
   comercios, Estado de usuarios, Estado de autorizaciones. Reutilizar
   `reportes_exporter` (PDF) donde aplique.
3. **Usuarios global** (`UsersPage.tsx`, solo SUPERADMIN): lista cross-tenant
   con rol/comercio/estado; editar/desactivar DESHABILITADOS con aviso (sin
   contrato backend aún — igual que la web, no inventar).
4. **Overview** (`OverviewPage.tsx` vs `staff_dashboard_screen.dart`): igualar
   métricas (comercios por estado, créditos, pendientes) o reportar qué falta.

## Verificación y entregable
Pantallas + repos + gates + tests + commit. Si un contrato no existe, reportar.
