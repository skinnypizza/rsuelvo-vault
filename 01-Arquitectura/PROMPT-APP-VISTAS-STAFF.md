# PROMPT APP — Vistas staff: Autorizaciones + Créditos + Solicitud dueño

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Roles expandidos + backend LISTO (migs 58-65, verificado): `fn_cambiar_estado_comercio`,
`fn_solicitar_creditos`, `fn_resolver_compra_creditos`, EF `invitar-usuario-comercio`
(ver `06-Integraciones/Edge-Function-invitar-usuario-comercio.md`), buckets
`depositos-creditos` (dueño sube `<id_comercio>/...`, staff lee) y `qr-pagos`.
Marca obligatoria: `05-Diseño-UX/Identidad-de-Marca.md`.
Reglas: jamás `service_role` (anon + RLS), español, gate por rol en `role_dashboard`,
economía de tokens, sin capturas/APK, `flutter analyze` limpio + tests con mocks
(prohibido tocar buckets reales).

## Vistas (sin cambios BD)
1. **Autorizaciones** (solo `ROLE_SUPERADMIN`): lista comercios
   `PENDIENTE_APROBACION` → ficha (datos+sucursal+fecha) → aprobar (RPC a `ACTIVO`
   + invocar EF invite al dueño) / rechazar (`CANCELADO`).
2. **Créditos por revisar** (SYSADMIN/SUPPORT/SUPERADMIN): lista compras PENDIENTE
   → ficha (paquete, monto, comprobante firmado al ver desde `depositos-creditos`)
   → aprobar / rechazar (`fn_resolver_compra_creditos`).
3. **Solicitar créditos** (dueño): selector de paquete (`tbl_paquetes_creditos`
   activos) + subida de comprobante de depósito a `depositos-creditos/<id>/...` +
   `fn_solicitar_creditos`; lista de sus solicitudes con estado.

## Entregable
3 vistas + repos + tests + commit. Si algún contrato no existe, reportar.
