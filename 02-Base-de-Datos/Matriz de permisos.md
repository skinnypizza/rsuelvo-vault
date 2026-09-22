# Matriz de Permisos RSUELVO — normativa (IAM-6 rev2)

> **Estado:** 2026-09-22 · Fuente normativa de capabilities. Autoridad efectiva = RLS + fn_* + EF (UI jamás autoriza).
> Taxonomía canónica: `members.*`, `business.*`, `credits.*`, `orders.*`, `inventory.*`, `payments.*`, `reports.*`, `customers.*`, `logistics.*`.
> Scope: GLOBAL (staff, sin tenant) vs TENANT (membership seleccionada).
> `can(subject, capability, context)` con `context.owner` (jamás `TENANT_ADMIN==owner`).

| Capability | Scope | SUPERADMIN | SYSADMIN | SUPPORT | TENANT_ADMIN | OWNER (+admin) | CASHIER | LOGISTICS | Autoridad backend | AAL2 | Flutter | Web |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `members.read` | GLOBAL/TENANT | ✅ | ✅ | ✅ staff | ✅ propio | — | ❌ | ❌ | `users_select`, `user_commerce_select` | — | `can views` | `members.read` |
| `members.invite` | GLOBAL/TENANT | ✅ | ❌ | ❌ | ✅ 5/6 (PATH A) | — | ❌ | ❌ | EF invite v9 | — | invite dialogs | `members.invite` |
| `members.mutate` | GLOBAL/TENANT | ✅ | ❌ | ❌ | ❌ | — | ❌ | ❌ | `fn_editar_usuario`, `fn_gestionar_vinculo` | desactivar | `gestionarVinculoGlobal` | `members.mutate` |
| `members.lifecycle` | TENANT | ✅ | ❌ | ❌ | ❌ | — | ❌ | ❌ | SUSPENDER/REVOCAR/CAMBIAR | ✅ | vía fn | — |
| `business.read` | GLOBAL/TENANT | ✅ | ✅ | ✅ | ✅ propio | — | ✅ propio | ✅ propio | RLS comercios | — | pantallas | `business.read` |
| `business.create` | GLOBAL | ✅ | ✅ | ❌ | ❌ | — | ❌ | ❌ | `fn_alta_comercio` | — | — | `business.create` |
| `business.state` | GLOBAL | ✅ | ❌ | ❌ | ❌ | — | ❌ | ❌ | `fn_cambiar_estado_comercio` | — | — | `business.state` |
| `business.close` | TENANT/GLOBAL | ✅ excepcional | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | `fn_cerrar_comercio` | ✅ | cerrar owner | cerrar |
| `business.transferOwnership` | TENANT | ✅ (cancela) | ❌ | ❌ | solo recibe | ✅ inicia | ❌ | ❌ | transferencia lifecycle | ✅ | transf. UI | perfil |
| `business.configure` | TENANT | ✅ | ❌ | ❌ | ✅ | — | ❌ | ❌ | `tbl_comercio_config` RLS | — | config | — |
| `credits.read` | GLOBAL/TENANT | ✅ | ✅ propio-staff | ✅ lectura | ✅ propio | — | ❌ | ❌ | `staff_read`, cuentas/movimientos | — | créditos | `credits.read` |
| `credits.resolve` | GLOBAL | ✅ | ❌ DENY (ciego sin deposit.read) | ❌ | ❌ | — | ❌ | ❌ | `fn_resolver_compra_creditos` (solo SUPERADMIN) | — | — | `credits.resolve` (visible, backend DENY no-superadmin) |
| `credits.deposit.read` | GLOBAL/TENANT | ✅ | ❌ DENY | ❌ DENY | ❌ | ✅ mismo comercio | ❌ | ❌ | `compras_select` + `depositos-creditos` Storage | — | — | solo vía matriz |
| `credits.packages.manage` | GLOBAL | ✅ | ❌ | ❌ | ❌ | — | ❌ | ❌ | `paquetes_superadmin_update` + Storage | — | — | `packages.manage` |
| `reports.operational` | GLOBAL/TENANT | ✅ | ✅ | ✅ | ✅ propio | — | ❌ | ❌ | RLS por tabla | — | `reportes_access` | `reports.operational` |
| `reports.sensitive` | GLOBAL | ✅ | ❌ | ❌ | ❌ | — | ❌ | ❌ | `audit_*`, depósitos (N-6) | — | superadmin | `reports.sensitive` |
| `customers.export` | TENANT/GLOBAL | ✅ | ❌ | ❌ | ✅ propio | — | ❌ | ❌ | RPC export + AuditLog (o best-effort doc.) | según matriz | — | export gate |
| `orders.*` | TENANT | ✅ | ❌ | ❌ | ✅ | — | ✅ sucursal | ❌ | fns pedidos/reservas | — | operativo | — |
| `inventory.*` | TENANT | ✅ | ❌ | ❌ | ✅ | — | ✅ lectura/suc. | ❌ | `fn_puede_gestionar_catalogo`, RLS | — | operativo | — |
| `payments.*` | TENANT | ✅ | ❌ | ❌ | ✅ | — | ✅ verifica | ❌ | `fn_puede_verificar`, confirmar | — | operativo | — |
| `logistics.*` | TENANT | ✅ | ❌ | ❌ | ✅ | — | ❌ | ✅ propio | `fn_puede_gestionar_envios`, RLS | — | operativo | — |
| `solicitudes.read/resolve` | GLOBAL | ✅ | ✅ | ❌ | ❌ | — | ❌ | ❌ | fns solicitudes | — | autorizaciones | `solicitudes.*` |
| `authorization.resolve` | GLOBAL | ✅ | ❌ | ❌ | ❌ | — | ❌ | ❌ | `fn_cambiar_estado_comercio` (vía) | — | autorizaciones | `authorization.resolve` |

Notas:
- SUPPORT: lectura + diagnóstico explícito; cero writes, cero exports, cero depósitos (cambio vs matriz pre-IAM que le daba aprobar/resolve).
- SYSADMIN: pierde `credits.resolve`→ conserva (operativo: aprueba compras con comprobante) — ver nota: matriz pre-IAM le daba aprobar; IAM-6 conserva `credits.resolve` SYSADMIN pero DENY depósitos. `solicitudes.resolve` SYSADMIN conserva (flujo actual), SUPPORT lo pierde.
- `business.create` SUPPORT: DENY (antes permitido en web).
- Owner ≠ rol: toda fila OWNER requiere `context.owner=true` verificado por `fn_es_owner`.
