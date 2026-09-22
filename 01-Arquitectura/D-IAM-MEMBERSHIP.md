# D-IAM-MEMBERSHIP — Contrato lifecycle (propuesta para revisión, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA (requiere revisión ChatGPT antes de codificar) · Cubre puntos 1-8 del brief IAM-2.

## Auditoría del estado actual (cloud 2026-09-22)

- 10/10 vínculos `estado='ACTIVE'`; SUSPENDED/REVOKED sin uso.
- `fn_gestionar_vinculo` DESACTIVAR pone `activo=false` pero deja `estado='ACTIVE'` → **divergencia confirmada**.
- `fn_editar_usuario` desactiva en cascada (`activo`) sin tocar `estado` → misma divergencia.
- `fn_aceptar_invitacion` es la única que escribe ambos coherentes.
- Flutter `actualizarVinculo` hace UPDATE directo (bypasea `estado` y reglas) → debe rutearse por fn (sublote Flutter posterior, no en este backend).
- N-4 (`68:127-135`): `cajero_multiplo` cuenta por `id_usuario` en TODOS los comercios.
- Reactivación existe solo en `gestionar_vinculo` CREAR (misma tupla usuario/comercio/rol/sucursal).

## Decisiones propuestas

1. **N-4:** scope por comercio. Un usuario PUEDE ser cajero en comercios distintos; sigue prohibido doble cajero en el MISMO comercio (regla de negocio vigente).
2. **Lifecycle:** `ACTIVE ↔ SUSPENDED` (reversible), `ACTIVE/SUSPENDED → REVOKED` (terminal). REVOKED nunca se reactiva: reingreso = fila nueva (trazabilidad intacta).
3. **Regla canónica única:** `activo = (estado = 'ACTIVE')`, impuesta por trigger `BEFORE INSERT/UPDATE` (fuente = `estado`; `activo` derivado). Cero divergencia futura.
4. **Acciones:** extender `fn_gestionar_vinculo` con `SUSPENDER` (=SUSPENDED) y `REVOCAR` (=REVOKED); `DESACTIVAR` se mapea a SUSPENDER (compatibilidad); `fn_editar_usuario` en cascada pone REVOKED; `fn_aceptar_invitacion` crea ACTIVE (intacto).
5. **Anti-duplicados:** índice único parcial `UNIQUE(id_usuario,id_comercio,id_rol,coalesce(id_sucursal,'000...')) WHERE estado='ACTIVE'` + `FOR UPDATE` en funciones (aceptar ya lo tiene; agregar en gestionar).
6. **Aislamiento:** ninguna acción toca filas de otro comercio (todas filtran `id_comercio`); RLS/auditoría/protección SUPERADMIN intactos; contratos IAM-1 e invitaciones intactos.
7. **IAM-D-007:** E2E dedicado (existente + otro comercio + accept → ACTIVE en B, intacto en A).
8. **Fuera:** selector UI y `selected.first` (IAM-3); Flutter `actualizarVinculo` por fn (sublote IAM-2/Flutter tras revisión); MFA/SecurityEvent.

## E2E backend requerido (fósiles, revertido)

N-4 por comercio · ACTIVE→SUSPENDED→ACTIVE · →REVOKED terminal (reactivar crea fila nueva) · cascada editar · A no afecta B (User A Admin C1 + Cashier C2, revocar C1) · duplicado concurrente (índice parcial) · IAM-D-007 · regresión IAM-1 (invite/accept/revoke) + aislamiento 11.
