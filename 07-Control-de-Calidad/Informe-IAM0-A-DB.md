# IAM-0/A — Informe DB/IAM backend (solo lectura, ejecutado por orquestador)

**Fecha:** 2026-09-21 · **Cloud:** `iwfaktlxebxtocmswdvv` schema `rsuelvo` (solo SELECT/information_schema) · **Cambios:** ninguno.

## 1. Estado exacto por tabla (cloud real)

**`tbl_usuario_comercio`** (id, id_usuario, id_comercio, id_rol smallint, id_sucursal NULL, activo bool default true, created_at, updated_at):
- Único lifecycle = `activo bool`. NO existen `invited_by/invited_at/accepted_at/disabled_at/disabled_by/revocation_reason` ni columna de estado. IAM-2 requiere migración aditiva.
- Sin constraint que impida multi-membresía: una persona PUEDE tener N vínculos activos (base lista para multi-comercio; el bloqueo está en Flutter, no en BD).

**`tbl_usuarios`** (id_usuario, auth_user_id NULL, nombre, apellido, telefono, email, activo, timestamps): sin lifecycle de invitación. `auth_user_id` nullable (cuidado IAM-1: filas huérfanas posibles).

**`tbl_roles`**: `codigo` enum canónico (`02_enums.sql:90-91`): ROLE_SUPERADMIN, ROLE_SYSADMIN, ROLE_SUPPORT, ROLE_TENANT_ADMIN, ROLE_TENANT_CASHIER, ROLE_LOGISTICS_AGENT + `nivel int`. Roles son globales, no por comercio (convergencia IAM-6: rol→permiso se documenta, no se reestructura).

**`tbl_comercios`**: `estado` default ACTIVO + `id_solicitud` (linaje D17). **`tbl_sucursales`**: `activo bool`. `tbl_logs_auditoria`: existe (trazabilidad OK).

## 2. Funciones de vínculos (`68_usuarios_staff.sql:6-158`)

- `fn_editar_usuario`: gate `fn_es_service_role() or fn_es_superadmin()` ("solo superadmin"); protege SUPERADMIN; desactivar usuario desactiva sus vínculos (cascada correcta, multi-comercio safe).
- `fn_gestionar_vinculo` (CREAR/DESACTIVAR + reactivación idempotente): gate superadmin-only; valida comercio ACTIVO/PENDIENTE_APROBACION, sucursal del tenant, sucursal obligatoria para LOGISTICS, protege SUPERADMIN.
- ⚠️ **Hallazgo A-1 (`cajero_multiplo`, líneas 127-135):** cuenta cajerías por `id_usuario` en TODOS los comercios. Una persona no puede ser cajera en 2 comercios. Restricción cross-tenant implícita — IAM-2 debe decidir: scoping por comercio o mantener regla global documentada.
- RLS vigente: `users_select`, `users_update_self`, `user_commerce_select`, `user_commerce_manage` (4 policies). Invitaciones de tenant-admin van por EF con `service_role`, NO por estas fn (verificar en IAM-1 que el nuevo invite no abra `user_commerce_manage` de más).

## 3. Qué falta para IAM-1/IAM-2 (migración mínima PROPUESTA, no aplicada)

1. Columnas aditivas en `tbl_usuario_comercio`: `estado text default 'ACTIVE'` (INVITED/ACTIVE/SUSPENDED/REVOKED), `invited_by uuid`, `invited_at`, `accepted_at`, `disabled_at`, `disabled_by`, `revocation_reason text` — compatible con `activo` actual (mantener sincronizado por trigger o vista).
2. Invitación un-solo-uso: según `01-Arquitectura/D-IAM-INVITACIONES.md` (decisión posterior que reemplaza este borrador): Supabase único secreto + `tbl_invitaciones` solo contexto/estado, índice único parcial PENDIENTE(email, id_comercio), `fn_aceptar_invitacion` con identidad exclusiva del JWT, expiración inline sin depender del cron.
3. Decisión A-1: scope de `cajero_multiplo` por comercio.
4. No loggear tokens (Regla 9); RLS deny-by-default en `tbl_invitaciones` (solo service_role + lectura propia del invitado por token_hash).

## 4. Matriz actual→objetivo→objeto

| Aspecto | Actual | Objetivo | Objeto |
|---|---|---|---|
| Estado membresía | `activo bool` | + estado INVITED/ACTIVE/SUSPENDED/REVOKED | mig aditiva uc |
| Invitación | password_temporal vía EF | token un-solo-uso + aceptación | `tbl_invitaciones` + EF |
| Trazabilidad invite | ninguna | invited_by/at, accepted_at | columnas aditivas |
| Cajero multi-comercio | bloqueado global (`cajero_multiplo`) | decisión documentada | `fn_gestionar_vinculo` |
| Baja | `activo=false` (sin motivo/actor) | + disabled_by/at + reason | columnas aditivas |
| Historial | conserva `id_usuario` (sin hard-delete) | mantener | regla IAM-2 |

## DoD IAM-0/A
Cero cambios (cumplido); inventario contra cloud real (cumplido); breaking changes: ninguno si la migración es aditiva + gates intactos; dependencia: su migración es prerrequisito de IAM-1 backend.
