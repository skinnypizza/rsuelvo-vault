# D-IAM-PERMISOS — Contrato IAM-6 (rev2, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REV2 con 12 ajustes ChatGPT (requiere aprobación antes de código).

## 1. Matriz normativa vs autoridad
`Matriz de permisos.md` = contrato normativo. Autoridad efectiva = RLS + fn_* + EF (UI jamás autoriza). Por capability: nombre, scope (GLOBAL/TENANT), roles, condición contextual, autoridad backend concreta, gate Flutter, gate Web, MFA/AAL2.

## 2. Taxonomía canónica (migración completa, sin aliases)
Dominios: `members.*`, `business.*`, `credits.*` (dominio propio), `orders/inventory/payments/reports/customers.*` según matriz. Migración: `users.read→members.read`, `users.invite→members.invite`, `users.mutate→members.mutate`, `commerce.*→business.*`. Web `permissions.ts` + tests; Flutter `can()` nuevo con mismos nombres.

## 3. Owner es contexto, no rol
Firma `can(subject, capability, context)` con `context.owner: bool` (derivado de `fn_es_owner`/membership, jamás `TENANT_ADMIN==owner`). `business.close/transferOwnership/cancelOwnershipTransfer` = `TENANT_ADMIN + owner=true` (+SuperAdmin donde aplique).

## 4. Scopes
GLOBAL (SUPERADMIN/SYSADMIN/SUPPORT, backoffice web, sin selector) vs TENANT (ADMIN/CASHIER/LOGISTICS vía membership seleccionada IAM-3). Prohibido highest-role global para operación tenant.

## 5. SUPPORT read-only exacto (propuesta)
PERMITIDO: `business.read` + diagnóstico enumerado en matriz. DENY: `members.invite/mutate`, `business.create`, `business.state`, `credits.resolve`, `solicitudes.resolve`, todo tenant-write, todo `*.export`, depósitos (DB+Storage) salvo `credits.deposit.read` explícita si negocio la aprueba (SYSADMIN a decisión; SUPPORT DENY). Web: quitar `commerce.create`+`credits.resolve` a SUPPORT.

## 6. Helpers compartidos (dependency audit obligatorio)
Inventariar dependientes de `fn_es_admin_comercio`, `fn_tiene_acceso_comercio/sucursal` y demás ANTES de tocarlos (lección P0). Si hace falta: separar `staff_read` vs `tenant_admin` explícitos; migrar solo policies/RPC necesarias + regresión ventas/n8n. No cambiar semántica global a ciegas.

## 7. N-6 DB + Storage
Misma regla en `tbl_compras_creditos` y `storage.objects/depositos-creditos` (`depositos_staff_select` verificada: SYSADMIN+SUPPORT leen). Decidir `credits.deposit.read` (SYSADMIN?) con SUPPORT DENY. Sin excepciones solo-frontend.

## 8. Export: boundary vs UX
Export sensible controlado = RPC/EF canónica (JWT→capability→scope→AAL2 si aplica→AuditLog quién/qué/scope/cuándo/cantidad, nunca contenido). CSV client-side sobre datos legibles = `UX capability / best-effort`, NO frontera (documentarlo así; DoD honesto).

## 9. N-5 con nombres canónicos (§2) + autoridad EF/RPC documentada por acción. UI gate = UX.

## 10. Hardcodes Flutter
Cero `idRol == N` como REGLA fuera del mapper central de compatibilidad (`rolCodigo` + catálogo). IDs en parsing/fixtures/mapper permitidos.

## 11. Ventas/n8n intactos
Dependency inventory de policies de pedidos/inventario/pagos/logística + regresión tenant + n8n server-to-server antes de tocar helpers compartidos.

## 12. E2E
Owner vs no-owner capabilities distintas · SUPPORT read OK + writes/export/depósitos DENY (DB y Storage) · SYSADMIN depósito según decisión · CASHIER/LOGISTICS sin escalada · multi-membership por seleccionada · web global sin contaminar tenant · export sin capability DENY + autorizado con 1 AuditLog · `fn_verificar_guards_sanos` verde · regresión ventas/n8n.
