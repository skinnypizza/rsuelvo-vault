# Informe IAM-0/C — Auditoría Web IAM

## Resultado ejecutivo

- No se modificó ningún archivo.
- Árbol limpio: `main`, sin cambios locales.
- `tsc -p app/tsconfig.app.json --noEmit`: correcto.
- Tests no pudieron iniciar porque Vitest/Vite intentó escribir `.vite-temp` y el filesystem es solo lectura (`EROFS`). No es un fallo funcional de tests.
- No existe en este repositorio el código backend, migraciones ni políticas RLS; por tanto, las garantías reales de RLS/RPC solo pueden verificarse contra el código cliente y la documentación existente.
- Se detectan brechas importantes en `packages.manage`, invitaciones de usuarios y solicitudes.

Archivos principales revisados:

- [`permissions.ts`](/home/nico/StudioProjects/rsuelvo-web/app/src/auth/permissions.ts)
- [`access.ts`](/home/nico/StudioProjects/rsuelvo-web/app/src/auth/access.ts)
- [`AuthContext.tsx`](/home/nico/StudioProjects/rsuelvo-web/app/src/auth/AuthContext.tsx)
- [`passwords.ts`](/home/nico/StudioProjects/rsuelvo-web/app/src/auth/passwords.ts)
- [`api.ts`](/home/nico/StudioProjects/rsuelvo-web/app/src/data/api.ts)
- [`README.md`](/home/nico/StudioProjects/rsuelvo-web/README.md)
- [`solicitudes-backend.md`](/home/nico/StudioProjects/rsuelvo-web/docs/solicitudes-backend.md)

## 1. Catálogo capability → backend → autoridad real

| Capability | Acción web | Operación backend | Autoridad observada | Estado |
|---|---|---|---|---|
| `commerce.read` | Listar y consultar comercios, sucursales y configuración | `SELECT` directo sobre `tbl_comercios`, `tbl_sucursales`, `tbl_comercio_config` | RLS documentado; política no disponible en el repositorio | Server/RLS contractual |
| `commerce.create` | Crear comercio | `fn_alta_comercio` | RPC server-side | Server-side |
| `commerce.state` | Cambiar estado de comercio | `fn_cambiar_estado_comercio` | RPC server-side | Server-side |
| `authorization.resolve` | Aprobar/rechazar comercio pendiente e invitar dueño | `fn_cambiar_estado_comercio` + Edge Function `invitar-usuario-comercio` | RPC + Edge Function JWT | Server-side |
| `credits.read` | Listar compras y abrir comprobantes | `SELECT tbl_compras_creditos` + Storage signed URL | RLS/Storage policy documentados, no verificables aquí | Server/RLS contractual |
| `credits.resolve` | Aprobar o rechazar compra de créditos | `fn_resolver_compra_creditos` | RPC server-side | Server-side |
| `packages.manage` | Leer paquetes, subir/quitar QR | `SELECT tbl_paquetes_creditos`; `Storage.upload/remove`; `UPDATE tbl_paquetes_creditos` | Gate frontend; escrituras directas sobre tabla y Storage | **Riesgo: control backend no evidenciado** |
| `reports.operational` | Reportes de créditos y estados | `SELECT` directo sobre tablas de créditos/comercios | RLS documentado, políticas ausentes | Server/RLS contractual |
| `reports.sensitive` | Reportes de depósitos y autorizaciones | `SELECT` directo sobre compras y logs | La visibilidad de tipos de reporte se limita en frontend; RLS no verificable | **Riesgo: dependencia parcial del frontend** |
| `users.read` | Listar usuarios, vínculos y roles | `SELECT` directo sobre `tbl_usuarios`, `tbl_usuario_comercio`, `tbl_roles` | RLS documentado | Server/RLS contractual |
| `users.invite` | Invitar usuario | Edge Function `invitar-usuario-comercio` | JWT y validación server-side esperada | Server-side, con divergencia contractual |
| `users.mutate` | Editar usuario y activar/desactivar vínculo | `fn_editar_usuario`, `fn_gestionar_vinculo` | RPC server-side en el código web | Server-side observado; README contradictorio |
| `solicitudes.read` | Bandeja de solicitudes | `SELECT tbl_solicitudes_alta` | Documentación exige RLS y solo SuperAdmin | **Divergencia: catálogo permite también SysAdmin** |
| `solicitudes.resolve` | Aprobar/rechazar solicitud | `fn_resolver_solicitud_alta` | RPC server-side | Server-side, pero rol contractual divergente |

### Observación central

Los nombres de capabilities solo existen en el frontend. No se envían como autorización al backend. La seguridad efectiva depende de:

1. RLS para lecturas y escrituras directas.
2. Validación interna de cada RPC.
3. Validación JWT/rol de la Edge Function.
4. Policies de Storage.

Sin el backend no puede confirmarse que esas comprobaciones existan realmente.

## 2. Capabilities con brecha solo-frontend o control insuficiente

### `packages.manage`

Es la brecha más clara.

`uploadPackageQr` y `removePackageQr`:

- Suben o eliminan archivos directamente en Storage.
- Actualizan directamente `tbl_paquetes_creditos`.
- No pasan por RPC ni Edge Function.
- Solo se muestran mediante `can(roles, "packages.manage")`.

El frontend limita el botón a `ROLE_SUPERADMIN`, pero cualquier cliente que invoque esas funciones puede intentar la operación. La protección real depende totalmente de RLS y Storage policies, que no están presentes para auditar.

Además, esto contradice el README, que afirma que el cliente no actualiza tablas directamente.

### `reports.sensitive`

La separación entre reportes normales y sensibles se implementa en [`features/reports.ts`](/home/nico/StudioProjects/rsuelvo-web/app/src/features/reports.ts):

- SuperAdmin ve los cuatro reportes.
- SysAdmin y Support ven solo `creditos` y `estados`.

Sin embargo, `loadReport(kind)` acepta cualquier `ReportKind` y hace consultas directas. El bloqueo de tipos sensibles ocurre principalmente en la interfaz. Si RLS no bloquea las tablas sensibles, existe una brecha.

### `users.invite`

El catálogo reserva esta capability a SuperAdmin, pero `UsersPage` no comprueba explícitamente `users.invite`; la página completa queda protegida indirectamente por `users.read`.

El formulario permite seleccionar:

- `ROLE_SYSADMIN`
- `ROLE_SUPPORT`
- `ROLE_TENANT_ADMIN`

El README indica que la Edge Function solo debe invitar `ROLE_TENANT_ADMIN`. La UI, por tanto, expone opciones incompatibles con el contrato documentado. El backend debe rechazarlas obligatoriamente.

### `users.mutate`

La UI expone edición y gestión de vínculos sin comprobar explícitamente `users.mutate`. Actualmente solo SuperAdmin tiene `users.read`, por lo que el gate de ruta actúa de forma indirecta. Si se amplía `users.read` a otro rol, también recibiría los controles de mutación salvo que se agregue un gate específico.

### `solicitudes.read` y `solicitudes.resolve`

La documentación [`docs/solicitudes-backend.md`](/home/nico/StudioProjects/rsuelvo-web/docs/solicitudes-backend.md) exige:

- Bandeja solo para `ROLE_SUPERADMIN`.
- Resolución solo para `ROLE_SUPERADMIN`.

Pero [`permissions.ts`](/home/nico/StudioProjects/rsuelvo-web/app/src/auth/permissions.ts) concede ambas capabilities a `ROLE_SYSADMIN`, y `SolicitudesPage` no aplica un gate adicional.

Esto constituye una divergencia contractual directa.

## 3. Roles y supuesto de comercio único

El acceso se carga así:

1. Se localiza el usuario por `auth_user_id`.
2. Se leen todas sus membresías activas.
3. Se leen todos sus roles.
4. Se devuelve una lista global de `roles`.
5. Se devuelve una lista global de `commerceIds`.

No existe:

- Comercio activo seleccionado.
- Contexto de comercio en las llamadas API.
- Capability evaluada contra `(usuario, comercio, rol)`.
- Filtro explícito por comercio en `listCommerces`, reportes, usuarios o solicitudes.
- Selector de comercio en la interfaz.

Por tanto, la web asume implícitamente un contexto global o usuario asociado a un único comercio operativo.

### Trampa de `highestRole`

```ts
return staffRoles.find((role) => roles.includes(role)) ?? null;
```

Como `staffRoles` está ordenado:

```ts
ROLE_SUPERADMIN
ROLE_SYSADMIN
ROLE_SUPPORT
```

`highestRole` selecciona el rol más alto globalmente, no el rol del comercio actual.

Ejemplo:

```ts
roles = ["ROLE_SUPPORT", "ROLE_SUPERADMIN"]
```

produce `ROLE_SUPERADMIN`, aunque ambos roles podrían corresponder a comercios distintos.

También `can()` usa:

```ts
roles.some(...)
```

Esto concede la unión de capabilities de todos los roles globales. No existe aislamiento por comercio.

## 4. Recovery y `/auth/confirm`

### Verificaciones realizadas

El flujo acepta:

- PKCE `?code=...` mediante `exchangeCodeForSession`.
- Recovery OTP `?token_hash=...&type=recovery` mediante `verifyOtp`.
- Rechaza enlaces con errores.
- Rechaza `code` combinado con `token_hash`.
- Exige `type=recovery` para `token_hash`.
- Reemplaza la URL por `/app/recuperar` después del canje.
- Actualiza la contraseña mediante `auth.updateUser`.
- Cierra la sesión local después del cambio.

`/app/auth/confirm` y `/app/recuperar` muestran el mismo `RecoveryPage`.

### Qué no verifica el frontend

- No valida roles durante recovery; la autorización staff ocurre después, al cargar `tbl_usuarios` y membresías.
- No implementa MFA ni reautenticación adicional.
- Solo valida localmente una contraseña mínima de 8 caracteres; la política completa depende de Supabase Auth.
- No procesa tokens `access_token`/`refresh_token` en el fragmento; el flujo esperado es PKCE o `token_hash`.
- No existe evidencia local del TTL, uso único o revocación del token; eso depende de Supabase Auth.
- La ruta `/auth/confirm` por sí sola no verifica nada: la verificación ocurre en `AuthContext` durante el arranque.

## 5. Diferencias contractuales web vs Flutter

No existe código Flutter dentro de este repositorio, por lo que no es posible hacer una comparación completa contra su implementación.

Diferencias verificables de la web:

- La web usa roles staff canónicos:
  - `ROLE_SUPERADMIN`
  - `ROLE_SYSADMIN`
  - `ROLE_SUPPORT`
- Rechaza roles tenant en `isStaffRole`.
- Usa un contexto global de roles y comercios, sin comercio seleccionado.
- `highestRole` colapsa múltiples roles a un único rol global.
- El recovery usa PKCE o `token_hash` explícitamente.
- `/auth/confirm` y `/recuperar` convergen en `RecoveryPage`.
- La web permite seleccionar roles de invitación que contradicen el contrato documentado.
- La web permite mutaciones directas de QR de paquetes, mientras el README declara que las mutaciones deben pasar por RPC/Edge Function.
- Solicitudes permite SysAdmin según el catálogo, mientras el contrato documentado las reserva a SuperAdmin.

La hipótesis de que la trampa de `highestRole` es la misma que en Flutter queda confirmada estructuralmente en la web: roles y membresías se agregan globalmente sin contexto de comercio.

## 6. Matriz actual → objetivo

| Área | Estado actual | Objetivo IAM |
|---|---|---|
| Catálogo de capabilities | Existe una única referencia en `permissions.ts` | Mantenerla como contrato único y reflejarla server-side |
| Lecturas | Consultas directas, seguridad delegada a RLS | Verificar policies reales por tabla y por rol/comercio |
| Mutaciones sensibles | RPC/Edge para varias operaciones | Todas las operaciones sensibles deben usar RPC/Edge con autorización server-side |
| Paquetes/QR | Escritura directa a tabla y Storage | RPC/Edge transaccional o policies explícitas verificadas |
| Reportes sensibles | Filtrado de tipos en frontend | RLS/server-side debe impedir consultas sensibles no autorizadas |
| Usuarios | Ruta protegida por `users.read`; acciones internas sin gates propios | Gates específicos para `users.invite` y `users.mutate`, además de validación backend |
| Invitaciones | UI permite tres roles | Alinear UI y Edge Function con roles realmente permitidos |
| Solicitudes | UI/catálogo permite SysAdmin | Alinear con contrato: solo SuperAdmin, o actualizar formalmente el contrato |
| Comercio actual | `commerceIds` global, sin selección | Introducir contexto explícito de comercio o confirmar modelo global |
| `highestRole` | Rol global de mayor prioridad | Resolver rol por comercio/contexto |
| Recovery | Verificación delegada correctamente a Supabase Auth | Confirmar configuración real de expiración, uso único, MFA y policies |
| Documentación | README contradice el código actual en usuarios/paquetes | Actualizar contrato después de validar backend |
| Verificación | TypeScript correcto; tests bloqueados por filesystem read-only | Ejecutar build/tests en entorno con cache temporal escribible |

## Conclusión

La web tiene gates de frontend bien centralizados en `permissions.ts`, pero no todas las capabilities tienen autoridad server-side demostrable.

Estado global:

- Server-side claro: altas, cambios de estado, resolución de créditos, resolución de solicitudes, invitación vía Edge Function y mutaciones de usuario vía RPC.
- RLS contractual pero no verificable: lecturas de comercios, créditos, reportes, usuarios y solicitudes.
- Brecha prioritaria: `packages.manage`.
- Brechas contractuales: invitaciones de roles, permisos de solicitudes y afirmación del README sobre ausencia de mutaciones directas.
- Brecha arquitectónica: roles y capabilities se calculan sin contexto de comercio.
- Sin cambios funcionales realizados.
