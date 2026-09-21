# IAM-0/B — Informe de auditoría Flutter IAM (solo lectura)

Repositorio confirmado: `skinnypizza/rsuelvo-flutter`, remoto `origin`, rama `main`.  
No se modificó ningún archivo: árbol limpio al cierre.

## Estado de verificaciones requeridas

- `flutter analyze`: no ejecutable; el entorno responde `flutter: command not found`.
- `flutter test`: no ejecutable; mismo bloqueo.
- Por ello, no es posible confirmar aquí el cierre de “278/278 verdes”. No se tocaron pruebas ni código.

## Hallazgos prioritarios

| ID | Severidad | Evidencia | Riesgo | Cambio propuesto para IAM-1/IAM-3 |
|---|---|---|---|---|
| H-IAM-01 | Alta | `usuario_invite_dialog.dart:213-231`; `autorizaciones_screen.dart:350-370`; `usuarios_staff_screen.dart:366-368` | La contraseña temporal llega al cliente, se muestra en texto seleccionable y en dos flujos se copia al portapapeles del SO. El portapapeles puede ser leído/persistido por otras apps. | Sustituir contraseña temporal por invitación de un solo uso/enlace de establecimiento de contraseña enviado fuera de la app; no devolver secretos al cliente. Si hay transición, eliminar Copy, ocultar el valor y limpiar el secreto de estado al cerrar. |
| H-IAM-02 | Alta | `auth_controller.dart:129-135`, `_rolePriority` en `217-227` | Ante múltiples membresías se ordena solo por prioridad de rol y se toma `selected.first`. No hay selector de comercio, preferencia explícita ni desempate estable por tenant; dos vínculos con el mismo rol pueden elegir un comercio según el orden devuelto por backend. | Modelar una colección de membresías y un `activeMembership` explícito. Al iniciar sesión, exigir selección cuando haya más de una membresía viable; no inferir tenant por prioridad. |
| H-IAM-03 | Alta | `auth_model.dart:10-16`, `65-73`; consumidores listados abajo | `AppUser` sólo contiene un `idComercio`, rol y sucursal. Todo el ámbito operativo depende de esa única decisión implícita. Un tenant elegido erróneamente determina lecturas/escrituras de pedidos, inventario, pagos, logística y créditos. | Crear `Membership` con `idUsuarioComercio`, `idComercio`, rol, sucursal y metadatos; separar identidad, membresías y contexto activo. |
| H-IAM-04 | Media | `sucursales_controller.dart:11-17`; `puntos_entrega_controller.dart:31-42` | Los providers se auto-disponen, pero no están parametrizados por tenant. `selectedSucursalFiltroProvider` conserva el filtro durante la vida del `ProviderScope`; si se añade cambio de comercio, puede reaplicarse una sucursal del tenant previo. | Hacer providers family/parametrizados por `membershipId` o `idComercio`; reiniciar el filtro y hacer `invalidate` coordinado al cambiar contexto. |
| H-IAM-05 | Media | `auth_model.dart:42-49`; `router.dart:47-137`; `app_shell.dart:42-193` | Permisos y navegación se basan en flags locales/IDs numéricos. La UI tiene controles, pero no existe un módulo de permisos equivalente centralizado en Flutter; la protección real debe permanecer en RLS/RPC/Edge Function. | Centralizar capacidades por código de rol/membership y aplicar guardas homogéneas de ruta/UI; validar siempre en backend. |
| H-IAM-06 | Media | `usuarios_staff_screen.dart:341-368` | La invitación global pide manualmente `ID del comercio` en texto libre y lo envía como `id_comercio`; es fácil asociar a un tenant equivocado. | Reemplazar el campo libre por selector autorizado de comercio y hacer que backend derive/autorización del alcance del invitador. |
| H-IAM-07 | Media | `sucursales_repository.dart:48-82`; `usuarios_repository.dart:296-324` | Actualizaciones de sucursal se filtran sólo por `id_sucursal`; las consultas de usuarios sí se filtran por tenant. La seguridad debe ser RLS, pero el cliente no expresa el tenant para las mutaciones de sucursal. | Para IAM-3, pasar membership/contexto al contrato y aplicar controles backend/RLS; no confiar en el identificador recibido del cliente. |

## Autenticación, identidad y membresías

- La sesión se obtiene de Supabase en `auth_controller.dart:55-59`, y los eventos `signedIn`/`signedOut` se manejan en `75-87`.
- El perfil activo se busca en `tbl_usuarios` por `auth_user_id`, con `activo=true`, y toma la primera fila tras ordenar por creación: `auth_controller.dart:97-109`.
- Luego carga todos los vínculos activos de `tbl_usuario_comercio`: `auth_controller.dart:111-119`.
- Carga todos los roles y ordena los vínculos por `_rolePriority`; fija el contexto con `selected.first`: `auth_controller.dart:122-135`.
- Sólo consulta el comercio del vínculo ya elegido: `auth_controller.dart:139-148`.
- `AppUser` materializa exactamente un comercio, rol y sucursal: `auth_model.dart:10-16`, `65-73`. No almacena la lista de vínculos ni identidad de membresía.
- No existe UI ni ruta para seleccionar/cambiar comercio o membresía.
- Al cerrar sesión se limpia `AuthState.user`: `auth_controller.dart:205-213`. No hay limpieza central explícita de todos los providers, aunque la mayoría son `autoDispose`.

La matriz de prioridad actual es:

| Rol | Prioridad |
|---|---:|
| `ROLE_SUPERADMIN` | 6 |
| `ROLE_SYSADMIN` | 5 |
| `ROLE_SUPPORT` | 4 |
| `ROLE_TENANT_ADMIN` | 3 |
| `ROLE_CASHIER` | 2 |
| `ROLE_LOGISTICS` | 1 |

Fuente: `auth_controller.dart:217-227`.

## Contraseña temporal, diálogo y portapapeles: inventario completo

| Archivo | Comportamiento actual | Riesgo | Propuesta |
|---|---|---|---|
| `usuarios_repository.dart:148-166` | `InvitacionUsuario` deserializa `password_temporal` a `passwordTemporal`. | El secreto queda en memoria de UI/resultado de la API. | Reemplazar contrato por estado de invitación, sin secreto. |
| `usuarios_repository.dart:245-264` | Invitación de cajero/repartidor llama a `invitar-usuario-comercio`; no envía `id_comercio`, sólo rol y sucursal. | El backend debe derivar de forma segura el comercio desde la sucursal/sesión. | Mantener esa derivación exclusivamente backend y devolver enlace/estado, no contraseña. |
| `usuario_invite_dialog.dart:59-80` | El formulario dispara la invitación y abre `_PasswordDialog`. | Se propaga secreto a un widget. | Mostrar “invitación enviada” sin credencial. |
| `usuario_invite_dialog.dart:196-239` | Muestra `passwordTemporal` con `SelectableText` y botón `Copiar` mediante `Clipboard.setData`. | H-IAM-01: exposición visual y portapapeles. | Eliminar representación/copia del secreto. |
| `usuarios_repository.dart:117-136`, `222-242` | Invitación global recibe y reenvía `id_comercio`; también retorna `InvitacionUsuario`. | Asociación libre de tenant y propagación de contraseña. | Selector de comercio autorizado + invitación sin contraseña. |
| `usuarios_staff_screen.dart:341-378` | Invitación SYSADMIN/SUPPORT con ID de comercio libre; concatena la contraseña temporal en texto del diálogo. | H-IAM-01 y H-IAM-06. | Selector de tenant autorizado y mensaje sin secreto. |
| `autorizaciones_repository.dart:31-52`, `93-117` | La aprobación activa comercio y llama a la misma Edge Function para invitar dueño; parsea `password_temporal`. | El flujo de alta también expone credencial. | Usar token de activación/recuperación de contraseña. |
| `autorizaciones_screen.dart:342-372` | Muestra contraseña de dueño y permite copiarla al portapapeles. | H-IAM-01. | No retornar ni mostrar credencial. |
| `test/usuarios_global_repository_test.dart:97-103`, `186-207` | Mock y prueba validan que la respuesta contiene contraseña temporal. | Cobertura congela contrato inseguro. | Actualizar en IAM-3 hacia estado/link de invitación seguro. |
| `test/autorizaciones_repository_test.dart:11-15`, `44-71` | Mock y prueba validan contraseña temporal del dueño. | Igual. | Actualizar contrato y expectativas. |

No se detectaron logs o `print` de contraseñas en `lib/`.

## Comercios, sucursales y supuesto de “comercio actual”

| Área | Evidencia | Comportamiento/riesgo |
|---|---|---|
| Lista de sucursales | `sucursales_controller.dart:11-17` | Consulta sucursales usando `user.idComercio`: un único tenant implícito. |
| Alta de sucursal | `sucursal_form_dialog.dart:62-87` | Inserta `id_comercio` desde el usuario actual. |
| Repository de sucursales | `sucursales_repository.dart:5-45` | Lectura e inserción usan `idComercio`; edición/toggle sólo usan `id_sucursal` en `48-82`. |
| Gestión de usuarios del comercio | `usuarios_controller.dart:20-27`; `usuarios_repository.dart:296-329` | La lista de personal se limita al `idComercio` del contexto implícito. |
| Invitación de personal | `usuario_invite_dialog.dart:92-170` | La sucursal ofrecida procede del provider del comercio implícito; el payload usa la sucursal seleccionada. |
| Comercio staff | `comercios_controller.dart:6-9`; `comercios_repository.dart:33-67` | Es vista global de comercios para staff; la ficha se consulta por el comercio tocado, no por el comercio de `AppUser`. Es el patrón correcto de recurso explícitamente seleccionado, pero requiere autorización backend. |
| Configuración | `configuracion_controller.dart:15-19`; `configuracion_screen.dart:118` | Lee y actualiza configuración del único `user.idComercio`. |
| Perfil | `perfil_edit_dialog.dart:24-50`; `usuarios_repository.dart:267-280` | El perfil se actualiza por `idUsuario`; después no se recarga `authProvider`, por lo que el nombre visible puede seguir desactualizado hasta nueva carga de perfil. |
| Cambio de contraseña | `cambiar_password_dialog.dart:28-43` | `supabase.auth.updateUser` cambia la contraseña de sesión actual; validación local mínima de 8 caracteres en `54-70`. No se fuerza cambio de contraseña temporal. |
| Cache local de tenant | `auth_controller.dart:160-165`; providers `FutureProvider.autoDispose`, por ejemplo `sucursales_controller.dart:11-17` | No se halló cache persistente de tenant (`SharedPreferences`, Hive, Isar, SQLite o secure storage) en Flutter. El contexto en memoria es `AuthState.user`; Riverpod autoDispose reduce persistencia, pero no sustituye el aislamiento explícito por membership. |

## Dónde `id_comercio` del cliente alimenta consultas operativas

Todos estos puntos heredan el tenant elegido por H-IAM-02:

| Dominio | Cadena de origen y consulta |
|---|---|
| Pedidos | `pedidos_controller.dart:21-27` pasa `user?.idComercio`; `pedidos_repository.dart:35-36` aplica `.eq('id_comercio', idComercio)`. |
| Dashboard | `dashboard_controller.dart:54-88` consulta verificaciones, pedidos y espera con `u.idComercio`; `dashboard_controller.dart:161-230` consulta pedidos, reservas, verificaciones y envíos con el mismo valor. |
| Productos/inventario | Providers consumen `user.idComercio` en `productos_repository.dart:487-516`; consultas por comercio en `329-336`, `430-444`; alta/gestión pasa el mismo contexto desde `producto_form_dialog.dart:46-53` y `categorias_manage_dialog.dart:36-40`, `208-222`. |
| Sucursales | `sucursales_controller.dart:11-17` → `sucursales_repository.dart:5-10`. |
| Usuarios y roles | `usuarios_controller.dart:20-27` → `usuarios_repository.dart:296-324`. |
| Créditos | `creditos_controller.dart:13-25` alimenta cuenta y movimientos con `user.idComercio`; la consulta aplica el filtro en `creditos_repository.dart:153-169`. |
| Reservas | `reservas_controller.dart:36-46` usa `user.idComercio`; filtro en `reservas_repository.dart:19-35`. |
| Configuración | `configuracion_controller.dart:15-19` y `configuracion_screen.dart:118`; filtros en `configuracion_repository.dart:7-9`, `26-28`. |
| Puntos de entrega/transportadoras | `puntos_entrega_controller.dart:14-28`, `45-65`; altas/ediciones pasan el valor desde `transportadoras_manage_dialog.dart:54-60`, `229-244`. |
| QR del comercio | `qr_comercio_screen.dart:37-40`, `99-104`, `127-170` usa `idComercio` para download/upload/path. |
| Setup del dueño | `owner_setup_warnings.dart:10-13` consulta QR con `user.idComercio`. |
| Solicitud de créditos | `solicitar_creditos_screen.dart:87-101` construye la solicitud con `user.idComercio`. |

Esto confirma el alcance operativo de IAM-1/IAM-3: cambiar la selección de membresía sin invalidar/parametrizar estas fuentes produciría contaminación de contexto entre comercios.

## Navegación y permisos actuales

- Los getters de rol usan combinaciones de IDs numéricos y códigos: `auth_model.dart:42-49`.
- La navegación de shell se decide enteramente por esos flags: `app_shell.dart:42-193`; accesos secundarios en `284-336`.
- El router restringe algunas rutas por rol: `router.dart:47-137`.
- Autorizaciones verifica visualmente `isSuperAdmin`: `autorizaciones_screen.dart:22-27`, `101-107`.
- Usuarios globales verifica `isSuperAdmin`: `usuarios_controller.dart:8`; `usuarios_staff_screen.dart:60-69`.
- No hay directorio o módulo `auth/permissions` equivalente; la lógica está repartida entre `AppUser`, router, shell y pantallas.

## Cobertura de pruebas IAM actual

| Prueba | Cubre | Vacíos relevantes |
|---|---|---|
| `test/multirol_test.dart:5-123` | Simula orden por prioridad y elección `.first`; comprueba precedencia admin y superadmin. | Duplica la lógica en vez de probar `AuthNotifier`; no cubre dos comercios con mismo rol, selector de tenant, estabilidad de orden ni invalidación de caches. |
| `test/usuarios_global_repository_test.dart:107-223` | Control de acceso UI lógico a usuarios globales; filtrado de roles; edición; activar/desactivar vínculo; invitación SYSADMIN; error “protegido”. | No cubre RLS, autorización de tenant, UI de diálogo, portapapeles ni contrato seguro de invitación. Actualmente asume `password_temporal`. |
| `test/autorizaciones_repository_test.dart:33-130` | Rechazo, activación antes de invitación, payload de dueño, ya-existente, fallo de activación y reintento. | No cubre UI, portapapeles, seguridad del secreto ni autorización real. Actualmente asume `password_temporal`. |
| `test/*auth*` | No existe archivo con ese patrón. | No hay prueba directa de controlador de auth, sesión, cierre de sesión o selección explícita de membresía. |

## Matriz actual → objetivo

| Aspecto | Actual | Objetivo IAM |
|---|---|---|
| Contexto de tenant | Un `AppUser.idComercio`, derivado por orden de rol. | `activeMembership` explícita, seleccionable y persistida de forma segura por usuario. |
| Multirol/multi-comercio | Prioridad global de rol + `selected.first`. | Lista de memberships, elección explícita; rol evaluado dentro del tenant activo. |
| Identidad | Perfil, rol, comercio y sucursal mezclados en `AppUser`. | Identidad separada de memberships y de contexto activo. |
| Invitaciones | API devuelve contraseña temporal al cliente. | Token/enlace de un uso, expiración y establecimiento de contraseña fuera del payload Flutter. |
| Portapapeles | Dos acciones `Clipboard.setData` con credenciales. | Nunca copiar secretos de autenticación desde UI. |
| Permisos | Flags repartidos en modelo/router/shell/pantallas. | Matriz de capacidades centralizada; backend como fuente de verdad. |
| Providers/cache | AutoDispose mayoritario, no tenant-keyed; filtro de sucursal no tenant-keyed. | Providers family por `membershipId`/tenant; invalidación atómica en cambio de contexto. |
| Mutaciones | Algunos métodos sólo incluyen ID de recurso. | Backend/RLS comprueba tenant/membership, no sólo IDs enviados por cliente. |
| Cobertura | Repositorios y lógica duplicada; sin auth controller real. | Pruebas de selección, cambio de tenant, aislamiento de providers, rutas, revocación de vínculo e invitaciones sin secreto. |

Conclusión: el riesgo dominante es que Flutter trata una cuenta multi-membresía como una sesión single-tenant elegida implícitamente. La corrección debe introducir contexto de membresía explícito antes de ampliar la gestión IAM, y debe retirar por completo `password_temporal` de los contratos cliente.
