# D-IAM-MULTICOMERCIO-FLUTTER — Contrato IAM-3 (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT. Cubre brief IAM-3.

## Auditoría (código real)

- Selección: `auth_controller.dart:130-135` sort `_rolePriority` + `selected.first` — único punto de elección (bien localizado).
- `AppUser`: un solo `idComercio/idRol/idSucursal` + flags `isAdmin/isCajero/isRepartidor/isSuperAdmin` derivados del rol único → toda la app (20+ archivos con `idComercio`: pedidos, inventario, reservas, créditos, config, QR, puntos-entrega...) opera sobre ese contexto.
- Sin persistencia de selección: no hay SharedPreferences/secure-storage de comercio (nada que migrar; diseñar desde cero con `flutter_secure_storage` solo para id de membresía, jamás tokens).
- Bootstrap 0 membresías: ya existe (throw → estado error). Bootstrap 1: directo. Bootstrap N: NUEVO selector.
- `recargarPerfil()` (IAM-1) recarga todo — reutilizar tras aceptar/cambiar; NO duplica lógica.
- Revocación del seleccionado en sesión: hoy deja datos viejos en providers — IAM-3 debe expulsar del contexto.

## Decisiones (revisión 2 con ajustes ChatGPT)

1. **Modelo:** `AuthenticatedUser` (perfil) + `Membership(id, idComercio, comercio, idRol, rolCodigo, idSucursal, sucursal)` + `SelectedMembership` en `AuthState`. `AppUser` se mantiene como vista derivada del seleccionado (compatibilidad: 20+ archivos NO se tocan).
2. **Persistencia scoped por identidad:** solo `membershipId` bajo clave `selected_membership:<auth_user_id>` (jamás tokens). Bootstrap: cargar ACTIVE → validar persisted (pertenece + sigue ACTIVE) → restaurar o purgar → N>1 sin válida = selector → jamás `selected.first` como fallback. Logout limpia selección (sin herencia entre identidades).
3. **Cambio de tenant atómico:** estado `switchingMembership`: bloquear UI → invalidar/generación tenant-scoped → cambiar selección → derivar AppUser → persistir → reconstruir contexto → UI operativa. Providers `family` por `membershipId` o `contextGeneration` para descartar futures tardíos de A en B.
4. **Reconciliación en sesión** (sin realtime): bootstrap, `recargarPerfil()`, resume, tras aceptar, tras señal de pérdida de acceso. Si la seleccionada no está ACTIVE: invalidar caches, purgar persisted, 1→auto, N→selector, 0→`noMemberships` (estado legítimo: ver/aceptar invitaciones + logout + reintentar, sin crash).
5. **Roles/sucursal por membresía; segunda invitación NO cambia contexto.**

## E2E Flutter (mocks + integración)
Dos comercios mismo rol/distinto rol · cambio repetido sin mezcla · revocación del seleccionado expulsa · restart restaura · revocación+2→selector · revocación+1→auto · revocación+0→`noMemberships` con invitaciones accesibles · persisted ajeno jamás restaura · persisted no-vigente se descarta · request tardío de A no aparece en B · logout/login distinto sin contaminación · analyze 0.
