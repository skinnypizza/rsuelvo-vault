# D-IAM-MULTICOMERCIO-FLUTTER — Contrato IAM-3 (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT. Cubre brief IAM-3.

## Auditoría (código real)

- Selección: `auth_controller.dart:130-135` sort `_rolePriority` + `selected.first` — único punto de elección (bien localizado).
- `AppUser`: un solo `idComercio/idRol/idSucursal` + flags `isAdmin/isCajero/isRepartidor/isSuperAdmin` derivados del rol único → toda la app (20+ archivos con `idComercio`: pedidos, inventario, reservas, créditos, config, QR, puntos-entrega...) opera sobre ese contexto.
- Sin persistencia de selección: no hay SharedPreferences/secure-storage de comercio (nada que migrar; diseñar desde cero con `flutter_secure_storage` solo para id de membresía, jamás tokens).
- Bootstrap 0 membresías: ya existe (throw → estado error). Bootstrap 1: directo. Bootstrap N: NUEVO selector.
- `recargarPerfil()` (IAM-1) recarga todo — reutilizar tras aceptar/cambiar; NO duplica lógica.
- Revocación del seleccionado en sesión: hoy deja datos viejos en providers — IAM-3 debe expulsar del contexto.

## Decisiones

1. **Modelo:** `AuthenticatedUser` (perfil) + `Membership(id, idComercio, comercio, idRol, rolCodigo, idSucursal, sucursal)` + `SelectedMembership` en `AuthState`. `AppUser` se mantiene como vista derivada del seleccionado (compatibilidad: 20+ archivos NO se tocan).
2. **Reglas:** 1 membresía→directo; N→restaurar última válida o selector; selector siempre accesible (perfil/header); cambio recarga providers dependientes e invalida caches (family por membershipId donde aplique); expulsión del contexto si se pierde la seleccionada; jamás `id_comercio` del cliente como autorización (ya es así: RLS/fns mandan).
3. **Roles distintos por comercio y sucursal por membresía:** el rol/sucursal se leen de la membresía seleccionada, no globales.
4. **Segunda invitación aceptada:** aparece en lista; NO cambia el contexto actual automáticamente (deliberado IAM-1).
5. **Fuera:** cambios backend, permisos dinámicos, MFA.

## E2E Flutter (mocks + integración)
Dos comercios mismo rol/distinto rol · cambio repetido sin mezcla (assert tenant en providers) · revocación del seleccionado expulsa · restart restaura · 0 membresías muestra estado vacío (no crash) · analyze 0.
