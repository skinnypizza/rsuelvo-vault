# Edge Function — `invitar-usuario-comercio`

> **Proyecto:** `iwfaktlxebxtocmswdvv` · **Slug:** `invitar-usuario-comercio` · **Versión 6 (2026-09-16)**
> **Estado:** ✅ DESPLEGADA (`verify_jwt=true`) y **validada E2E** (loop aprobar: alta→ACTIVO→invite→login dueño OK)
> **Autor:** orquestador de BD (fuente en `Edge-Function-invitar-usuario-comercio-v6.ts`, deploy vía CLI) · consumidor: app Flutter (ADMIN + SUPERADMIN)

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

### Respuestas
| HTTP | Cuerpo | Significado |
|---|---|---|
| **200** | `{ok:true, email, id_usuario, ya_existente:true}` | Reintento idempotente (mismo email+vinculo) |
| **201** | `{ok:true, email, id_usuario, password_temporal, mensaje}` | Invitado creado. **Mostrar `password_temporal` con botón COPIAR** — no se envía por correo en v1 |
| **400** | `{ok:false, error}` | Email inválido · rol fuera de 4/5/6 · falta sucursal/comercio · sucursal/comercio ajeno |
| **401** | `{ok:false, error}` | Sin sesión / token inválido |
| **403** | `{ok:false, error}` | El invocador no tiene permiso para este rol |
| **409** | `{ok:false, error}` | Ese email ya tiene cuenta (otro vínculo) |
| **500** | `{ok:false, error}` | Error interno (con compensación: no quedan usuarios/vínculos a medias) |

### Path SUPERADMIN (v6, aprueba comercios)
Solo `ROLE_SUPERADMIN`, con `{email, nombre, apellido, telefono, id_rol:4,
id_comercio, id_sucursal:null}`. Secuencia app: `fn_cambiar_estado_comercio→ACTIVO`
y luego este invite (reintentable; 200 si ya existe). Fuente: `db:{schema:rsuelvo}`
(obligatorio: `from()` sin schema cae en `public`).

> En supabase_flutter, un status ≠ 2xx lanza `FunctionException`. Parsear `e.details` (el JSON del cuerpo) para mostrar `error`. Nunca mostrar códigos crudos.

### UX recomendada (solo ADMIN, en `UsuariosListScreen`)
- Botón "Invitar usuario" visible SOLO para ADMIN (`id_rol == 4`).
- Formulario: email, nombre, apellido, teléfono, rol (CAJERO/REPARTIDOR) y sucursal (dropdown de las sucursales del comercio).
- Al 201: diálogo destacado con la **contraseña temporal** + botón **Copiar** + advertencia "compartila por un canal seguro; se cambia en el primer ingreso".
- Refrescar la lista de usuarios al cerrar.
- **NO** usar `supabase.auth.signUp()` ni inserts directos a `tbl_usuarios`.

## Qué hace la función (seguridad)
1. Exige JWT (`verify_jwt=true`) y resuelve `auth.uid()`.
2. Valida `tbl_usuarios.auth_user_id = uid` y un vínculo **activo con `id_rol=4`** → deriva `id_comercio` (MVP: un comercio por admin).
3. Valida email (normalizado), rol ∈ {5,6}, `id_sucursal` existente/activa **del mismo comercio**.
4. Crea el Auth user con `auth.admin.createUser({ email_confirm: true, password: <temporal fuerte> })`.
5. Inserta `tbl_usuarios` (nombre vacío → "Usuario invitado") y `tbl_usuario_comercio`.
6. **Compensación**: ante cualquier fallo posterior, borra el vínculo/fila y el Auth user → no deja estados incompletos.
7. La contraseña temporal **nunca** se loguea ni persiste.

## Secretos y configuración
- **No requiere secretos nuevos**: `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` se inyectan automáticamente en las Edge Functions.
- `service_role` vive **solo** dentro de la función (jamás en Flutter).
- **v1 no envía correo** (decisión acordada): el ADMIN comparte la contraseña temporal.
- **Futuro (v2)**: si se configura `RESEND_API_KEY` (+ dominio verificado) o SMTP, la función puede enviar el correo "Tu acceso a RSUELVO" con el código, manteniendo la contraseña en la respuesta como respaldo. No se requiere cambio de contrato: se agrega el envío dentro de la EF.

## Operación
- **Actualizar**: redeploy con `deploy_edge_function` (mismo slug).
- **Probar manualmente**: login ADMIN → `POST /functions/v1/invitar-usuario-comercio` con `Authorization: Bearer <token>`.
- **No crea** tablas, políticas, triggers ni funciones SQL.
