# Edge Function — `invitar-usuario-comercio`

> **Proyecto:** `iwfaktlxebxtocmswdvv` · **Slug:** `invitar-usuario-comercio` · **Versión 8 (2026-09-17)**
> **Estado:** ✅ DESPLEGADA (`verify_jwt=true`) y **validada E2E** (invite support→login→lectura global OK; fuente en `Edge-Function-invitar-usuario-comercio-v8.ts`)
> **Autor:** orquestador de BD (deploy vía CLI) · consumidor: app Flutter (ADMIN + SUPERADMIN)
> **Path SUPERADMIN (v6→v8):** `id_rol` ∈ {2 SYSADMIN, 3 SUPPORT, 4 dueño} con `id_comercio` explícito; `id_rol:1` (SUPERADMIN) siempre rechazado; idempotente (200 si mismo vínculo).

## Contrato para la app (Flutter)

```dart
final res = await supabase.functions.invoke(
  'invitar-usuario-comercio',
  body: {
    'email': email.trim().toLowerCase(),
    'nombre': nombre.trim(),
    'apellido': apellido.trim(),
    'telefono': telefono.trim(),
    'id_rol': idRol,          // solo 5 (CAJERO) o 6 (REPARTIDOR)
    'id_sucursal': idSucursal // obligatoria
  },
);
```

### Respuestas (v9 — IAM-1, sin secretos)
| HTTP | Cuerpo | Significado |
|---|---|---|
| **200** | `{ok:true, email, ya_existente:true}` | Vínculo equivalente ya activo |
| **200** | `{ok:true, email, pendiente:true}` | Invitación PENDIENTE reutilizada (idempotencia) |
| **201** | `{ok:true, email, pendiente:true}` | Invitación creada. **JAMÁS contiene secreto.** Usuario nuevo recibe correo Supabase; existente acepta desde su cuenta |
| **400** | `{ok:false, error}` | Email inválido · rol fuera de 2-6 · falta sucursal/comercio · sucursal/comercio ajeno |
| **401** | `{ok:false, error}` | Sin sesión / token inválido |
| **403** | `{ok:false, error}` | El invocador no tiene permiso para este rol |
| **500** | `{ok:false, error}` | Error interno (con compensación: invitación huérfana se elimina o se reutiliza) |

### Path SUPERADMIN (v6, aprueba comercios)
Solo `ROLE_SUPERADMIN`, con `{email, nombre, apellido, telefono, id_rol:4,
id_comercio, id_sucursal:null}`. Secuencia app: `fn_cambiar_estado_comercio→ACTIVO`
y luego este invite (reintentable; 200 si ya existe). Fuente: `db:{schema:rsuelvo}`
(obligatorio: `from()` sin schema cae en `public`).

> En supabase_flutter, un status ≠ 2xx lanza `FunctionException`. Parsear `e.details` (el JSON del cuerpo) para mostrar `error`. Nunca mostrar códigos crudos.

### UX recomendada (solo ADMIN, en `UsuariosListScreen`)
- Botón "Invitar usuario" visible SOLO para ADMIN (`id_rol == 4`).
- Formulario: email, nombre, apellido, teléfono, rol (CAJERO/REPARTIDOR) y sucursal (dropdown de las sucursales del comercio).
- Al 200/201: mensaje "Invitación enviada/pendiente. La persona deberá aceptar el acceso desde su cuenta." + estado Pendiente. **PROHIBIDO mostrar/copiar credenciales (ya no existen).**
- Refrescar la lista de usuarios al cerrar.
- **NO** usar `supabase.auth.signUp()` ni inserts directos a `tbl_usuarios`.

## Qué hace la función (v9 — IAM-1, D-IAM-INVITACIONES)
1. Exige JWT (`verify_jwt=true`) y resuelve `auth.uid()`.
2. Resuelve invocador y sus vínculos (PATH SUPER rol 2/3/4 con comercio explícito; PATH ADMIN rol 5/6 con sucursal del propio comercio).
3. Valida email, rol ∈ {2..6}, sucursal del comercio.
4. Idempotencia: vínculo equivalente → 200; PENDIENTE vigente → 200.
5. Crea fila `tbl_invitaciones` PENDIENTE primero (reintento seguro).
6. Usuario nuevo: `auth.admin.inviteUserByEmail` (Supabase único secreto) + fila espejo mínima; usuario existente: solo invitación (acepta vía `fn_mis_invitaciones_pendientes`/`fn_aceptar_invitacion`).
7. **Compensación**: si el envío falla, elimina la invitación huérfana.
8. Ningún secreto se loguea, persiste ni devuelve.

## Secretos y configuración
- **No requiere secretos nuevos**: `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` se inyectan automáticamente en las Edge Functions.
- `service_role` vive **solo** dentro de la función (jamás en Flutter).
- v9 no envía credenciales: usuario nuevo por correo Supabase, existente por aceptación autenticada (D-IAM-INVITACIONES).

## Operación
- **Actualizar**: redeploy con `deploy_edge_function` (mismo slug).
- **Probar manualmente**: login ADMIN → `POST /functions/v1/invitar-usuario-comercio` con `Authorization: Bearer <token>`.
- **No crea** tablas, políticas, triggers ni funciones SQL.
