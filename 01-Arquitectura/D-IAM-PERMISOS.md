# D-IAM-PERMISOS — Contrato IAM-6 (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT.

## Auditoría real (2026-09-22)

- **DB:** roles enum (6) + ~15 helpers (`fn_tiene_*`, `fn_puede_*`, `fn_es_*`) + gates por fn. Autoridad real, pero sin matriz única documentada (Matriz de permisos.md desactualizada: pre-IAM).
- **Flutter:** flags en `AppUser` (`isAdmin/isCajero/...`, 12 archivos) + `reportes_access.dart` centralizado (bien) + 20 hunters `idRol == N` hardcodeados. Sin catálogo de capabilities.
- **Web:** `permissions.ts` centralizado (Capability + `can()`), pero N-5 (acciones internas sin gates propios) y N-6 (`compras_select` permite SYSADMIN/SUPPORT ver depósitos; restricción solo en `visibleReportKinds`) siguen abiertos.
- **SUPPORT:** en helpers `fn_es_admin_comercio`/`fn_tiene_acceso_*` ve datos tenant como admin (decisión pendiente: ¿soporte operativo o solo lectura?).
- **Exportes sensibles:** CSV web (depósitos, auditoría, créditos) + reportes Flutter; sin capability `export` ni auditoría de descarga.

## Decisiones

1. **Matriz canónica primero:** actualizar `02-Base-de-Datos/Matriz de permisos.md` como Role→Permission (CRUD/Approve/Export por rol) — documento mandante; código converge a él, no al revés.
2. **Catálogo funcional único** (nombres web-compatibles): `orders/inventory/payments/members/reports/customers/business` + `.action` (ej. `members.invite`, `customers.export`). Flutter expone `can(user, 'members.invite')` central (reemplaza hunters `idRol==N` gradualmente); web reutiliza `permissions.ts` extendido; DB documenta qué fn/RLS respalda cada permiso (sin tablas dinámicas salvo caso producto real — no ABAC).
3. **N-5:** gates `users.invite`/`users.mutate` en acciones internas UsersPage + equivalentes Flutter.
4. **N-6:** restringir `compras_select` (depósitos solo superadmin/owner mismo comercio) O documentar excepción con justificación; jamás solo-frontend.
5. **SUPPORT:** propuesta = lectura operativa + invitar nada + export nada; cualquier escritura tenant (incl. solicitudes-resolve) pasa a SYSADMIN/SUPERADMIN. Revisar `fn_es_admin_comercio` (saca SUPPORT o documenta).
6. **Export:** capability `*.export` + AuditLog por descarga sensible (quién/qué/cuándo, no el contenido).
7. **Fuera:** ventas/n8n intactos (capabilities los envuelven sin cambiar lógica); MFA (IAM-5); KYC (IAM-9).

## E2E
Matriz verde por rol (permitido/denegado real, no solo UI) · N-5/N-6 cerrados · SUPPORT sin escritura · export auditado · greps `idRol ==` en cero (o lista de excepciones) · suites verdes.
