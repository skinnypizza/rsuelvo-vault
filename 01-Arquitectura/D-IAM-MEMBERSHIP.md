# D-IAM-MEMBERSHIP — Contrato lifecycle (revisión 2, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REVISIÓN 2 con ajustes ChatGPT (requiere aprobación antes de codificar mig 81).

## Auditoría del estado actual (cloud 2026-09-22)

- 10/10 vínculos `estado='ACTIVE'`; SUSPENDED/REVOKED sin uso.
- `fn_gestionar_vinculo` DESACTIVAR pone `activo=false` pero deja `estado='ACTIVE'` → **divergencia confirmada**.
- `fn_editar_usuario` desactiva en cascada (`activo`) sin tocar `estado` → misma divergencia.
- `fn_aceptar_invitacion` es la única que escribe ambos coherentes.
- Flutter `actualizarVinculo` hace UPDATE directo (bypasea `estado` y reglas) → debe rutearse por fn (sublote Flutter posterior, no en este backend).
- N-4 (`68:127-135`): `cajero_multiplo` cuenta por `id_usuario` en TODOS los comercios.
- Reactivación existe solo en `gestionar_vinculo` CREAR (misma tupla usuario/comercio/rol/sucursal).

## Decisiones (revisión 2)

1. **N-4 EN TODOS LOS PATHS:** mig 81 incluye `CREATE OR REPLACE` mínimo de `fn_aceptar_invitacion` que cambia EXCLUSIVAMENTE la regla `cajero_multiplo`: cuenta cajero dentro de `v_inv.id_comercio` y solo membresías vigentes (`estado IN ('ACTIVE','SUSPENDED')`). Permite cajero A + cajero B; impide duplicado en el mismo comercio. Resto de invariantes IAM-1 intactas (JWT, email, expiración, locks, sucursal, auditoría, cero secretos). Sin esto IAM-D-007 no pasa. Mismo ajuste en `fn_gestionar_vinculo`.
2. **Lifecycle:** `ACTIVE ↔ SUSPENDED` (reversible), `ACTIVE/SUSPENDED → REVOKED` (terminal). REVOKED nunca se reactiva: reingreso = fila nueva.
3. **Compatibilidad Flutter (2 fases, preferida):** NO desplegar trigger canónico con el cliente actual sin resolver (un `activo := (estado='ACTIVE')` convertiría legacy `UPDATE activo=false` en no-op). Fase A: sublote IAM-2/Flutter reemplaza UPDATE directo por `fn_gestionar_vinculo` + verificación. Fase B: endurecer DB. Si quedaran clientes antiguos: compatibilidad transitoria (cambio explícito de `estado` manda; legacy `activo=false` sin cambio de estado = SUSPENDED; legacy `activo=true` solo reactiva desde SUSPENDED; jamás REVOKED→ACTIVE), a retirar tras migración.
4. **Acciones:** extender `fn_gestionar_vinculo` con `SUSPENDER` (=SUSPENDED) y `REVOCAR` (=REVOKED); `DESACTIVAR` se mapea a SUSPENDER (compatibilidad). **`CAMBIAR` atómico (revisión 3):** cambio rol/sucursal en UNA transacción — params (usuario, comercio, rol/sucursal anterior, rol/sucursal nuevo); valida permisos, lock del vínculo vigente `FOR UPDATE`, valida destino (comercio/rol/sucursal/N-4), suspende anterior, reactiva/crea nuevo (misma semántica CREAR), captura `unique_violation`, auditoría, rollback total si falla. Flutter usará `CAMBIAR` en una sola llamada (reemplaza DESACTIVAR+CREAR del sublote 2A).
5. **`fn_editar_usuario` NO revoca:** `activo=false` → memberships ACTIVE pasan a SUSPENDED (REVOKED es terminal; revocación solo por REVOCAR explícito). Al reactivar usuario: cuenta sí, memberships NO (salvo regla explícita de causa) — no restaurar accesos suspendidos por otro admin.
6. **Anti-duplicados:** `UNIQUE(id_usuario,id_comercio,id_rol,coalesce(id_sucursal,uuid-cero)) WHERE estado IN ('ACTIVE','SUSPENDED')` (REVOKED fuera, historia intacta). Semántica CREAR: ACTIVE→idempotente; SUSPENDED→reactivar MISMA fila; solo-REVOKED→FILA NUEVA. Preflight de duplicados antes de crear el índice. El índice es la garantía final anti-phantom; la función captura `unique_violation` determinista/idempotente.
7. **Aislamiento/auditoría/IAM-1:** intactos (salvo ajuste puntual N-4 en accept).
8. **Fuera:** selector UI y `selected.first` (IAM-3); MFA/SecurityEvent.

## E2E backend requerido (fósiles, revertido)

N-4 por comercio · ACTIVE→SUSPENDED→ACTIVE · →REVOKED terminal (reactivar crea fila nueva) · cascada editar · A no afecta B (User A Admin C1 + Cashier C2, revocar C1) · duplicado concurrente (índice parcial) · IAM-D-007 · regresión IAM-1 (invite/accept/revoke) + aislamiento 11.
