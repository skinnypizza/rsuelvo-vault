# PROMPT — Codex: CRUDs de Productos, Variantes y Usuarios + Dashboards por rol

> **Directorio:** `/home/nico/StudioProjects/rsuelvo/` (Flutter · Supabase schema `rsuelvo`)
> **Base:** F4/F5/F6 + rediseño de marca ya implementados y funcionando. `flutter analyze` 0 issues · 18 tests verdes.
> **Objetivo:** (1) completar los CRUDs de **Productos**, **Variantes** y **Usuarios** respetando RLS/roles; (2) crear los **dashboards de los roles faltantes** (CAJERO y REPARTIDOR) integrados al diseño existente.
> **Eficiencia:** NO capturas de pantalla, NO APK, NO dispositivo/emulador, NO carpeta `evidence/`. Verificación = `flutter analyze` + `flutter test`.

---

## 0. Lectura previa (mínima y dirigida)

1. Leé ESTOS archivos como patrón (no más):
   - `lib/features/sucursales/` (CRUD completo con dialog + repository + controller) ← **patrón canónico para los CRUDs**
   - `lib/features/productos/` (list read-only existente, a completar)
   - `lib/features/usuarios/` (list + `usuario_edit_dialog.dart` + `usuario_vinculo_model.dart` ya existen)
   - `lib/features/dashboard/dashboard_screen.dart` + `lib/features/shell/app_shell.dart` (estructura y navegación)
   - `lib/shared/widgets/brand_widgets.dart` + `lib/core/brand.dart` + `lib/core/theme.dart` (diseño de marca: `BrandMark/BrandPanel/BrandEmpty/BrandLoading`, tokens)
   - `lib/core/router.dart` (rutas)
2. Usá el **MCP de Supabase (solo lectura)** para confirmar columnas y políticas antes de codificar. Contratos ya verificados (no los contradigas):

## 1. Matriz de permisos REAL (por RLS — respetala en la UI)

| Tabla | SELECT | INSERT/UPDATE/DELETE | Quién puede escribir |
|---|---|---|---|
| `tbl_productos` | `fn_tiene_acceso_comercio` (todo el personal del comercio) | `products_manage` → `fn_es_admin_comercio` | **Solo ADMIN** |
| `tbl_variantes` | `fn_tiene_acceso_comercio` | `variants_manage` → `fn_es_admin_comercio` | **Solo ADMIN** |
| `tbl_categorias` | `fn_tiene_acceso_comercio` | `categories_manage` → `fn_es_admin_comercio` | Solo ADMIN (no se pidió su CRUD: usar selector) |
| `tbl_inventario` | por sucursal | `inventory_all` → acceso a sucursal | ADMIN (en UI) |
| `tbl_usuario_comercio` | acceso comercio | `user_commerce_manage` → `fn_es_admin_comercio` | **Solo ADMIN** |
| `tbl_usuarios` | self o usuarios de mi comercio | `users_update_self` (solo la fila propia) | **Nadie puede crear/editar otros usuarios** |
| `tbl_comercios` | acceso comercio | UPDATE admin | — |

**Regla de UI:** las acciones de escritura se muestran SOLO al rol que la RLS permite (ADMIN). CAJERO y REPARTIDOR ven modo lectura. Nunca ofrezcas un botón que vaya a fallar por RLS.

## 2. CRUD de Productos (completar lo existente — `lib/features/productos/`)

- **ADMIN:** crear / editar / activar-desactivar / eliminar. Campos: `nombre` (obligatorio), `descripcion`, `id_categoria` (selector opcional desde `tbl_categorias` — solo lectura), `imagen_url` (texto opcional; sin subida de archivos en esta fase), `activo`.
- **CAJERO/REPARTIDOR:** solo la lista en modo lectura (sin acciones).
- **Baja:** preferí **desactivar** (`activo=false`) como acción principal; el botón ELIMINAR solo si no hay dependencias — si la BD rechaza por FK/variantes, convertir el error en mensaje claro ("No se puede eliminar: tiene variantes asociadas. Desactivalo.").
- La lista debe mostrar si tiene variantes (contador o botón "Ver variantes").
- Reutilizá el patrón de `sucursales/` (dialog, controller, invalidación de providers, SnackBars de marca).

## 3. CRUD de Variantes (NUEVO — `lib/features/variantes/` o dentro de productos)

- Contexto: se entra desde un producto ("Ver variantes" / "Agregar variante").
- Campos editables: `nombre`, `precio` (numeric > 0), `activo`. `id_producto` viene del contexto.
- **SKU: SOLO LECTURA.** La BD lo genera por trigger (`fn_resolver_variante_tenant_sku`) al INSERTAR. Reglas:
  - Al crear, **NO envíes `sku`** (dejalo ausente/null) y **leé el SKU generado** con `.select()` tras el insert para mostrarlo.
  - Si el trigger lanza error (capacidad/lógica), mostrá el mensaje tal cual; no reintentes a ciegas.
  - En edición el SKU no se modifica.
- **Inventario:** al crear una variante, creá también su fila en `tbl_inventario` (una por sucursal del comercio, `stock_actual=0`, `stock_reservado=0`) para que quede consistente. Si ya existe, no dupliques.
- **Baja:** desactivar (`activo=false`) como principal. Eliminar solo si no hay referencias (reservas/pedidos); si falla, mensaje claro.
- Lista de variantes por producto: SKU, nombre, precio (Bs), stock (join `tbl_inventario` de la sucursal del usuario o suma), estado.

## 4. Usuarios (completar `lib/features/usuarios/` — ALCANCE REAL)

Lo que ya existe: lista de vínculos + `usuario_edit_dialog` (rol/sucursal/activo). Completar:
- **ADMIN puede:** listar los vínculos del comercio (usuario + rol en español + sucursal + activo), **editar `id_rol`, `id_sucursal`, `activo`** de `tbl_usuario_comercio` (ya hay política), y desactivar vínculos.
- **Todos:** editar **su propio perfil** (`tbl_usuarios` fila propia: `nombre`, `apellido`, `telefono`) — política `users_update_self`.
- **PROHIBIDO INTENTAR (sería incoherente con RLS):** crear usuarios nuevos, asignar/editar filas de OTROS en `tbl_usuarios`, buscar usuarios por email que aún no pertenecen al comercio. **No lo implementes ni inventes workarounds.**
- **Limitación a documentar (en el informe final, con propuesta):** crear/invitar usuarios requiere backend (Edge Function con `service_role`: crear auth user + fila `tbl_usuarios` + vínculo). En la UI, NO agregues botones muertos; si querés, una nota informativa integrada al diseño que diga "La invitación de nuevos usuarios se habilitará desde el panel administrativo".

## 5. Dashboards de roles faltantes (CAJERO y REPARTIDOR)

Hoy solo el ADMIN tiene dashboard; cajero entra a Verificaciones y repartidor a Envíos. Crear dashboards **con el mismo lenguaje visual** (usar `BrandPanel`, `BrandMark`, `BrandEmpty`, `BrandLoading` y tokens; **copiá la estructura del dashboard admin**).

**Estrategia de ruteo (consistente):** una sola ruta `/dashboard` que renderiza el dashboard **según el rol** del usuario (widget por rol). Tras login, TODOS los roles van a `/dashboard`. En `app_shell`, agregar el tab **"Inicio"** a CAJERO y REPARTIDOR (admin ya lo tiene) apuntando a `/dashboard`.

### Dashboard CAJERO (su `id_sucursal` del vínculo)
- **Verificaciones pendientes**: `tbl_verificaciones` con `estado IN ('PENDIENTE','PROCESANDO')` + `id_comercio` del usuario → contador + acceso directo
- **Pedidos de hoy por estado**: `tbl_pedidos` de su sucursal, `created_at` del día (America/La_Paz) → contadores por estado + acceso
- **Lista de espera activa**: `tbl_lista_espera` `estado IN ('ESPERANDO','NOTIFICADO')` del comercio → contador
- **Envíos por preparar**: `tbl_envios` de su sucursal `estado IN ('PENDIENTE','PREPARANDO')` → contador
- **Saldo de créditos** (lectura) + accesos rápidos a Puntos de Entrega

### Dashboard REPARTIDOR (su `id_sucursal`)
- **Por repartir**: `tbl_envios` de su sucursal `estado IN ('PENDIENTE','PREPARANDO')`
- **En calle**: `estado IN ('ASIGNADO','EN_RUTA')`
- **Entregados hoy** y **No entregados** (con observación) del día
- **"Requieren guía/código"**: `tbl_envios` con punto tipo `ENVIO_TRANSPORTE` o `PUNTO_LOCAL`, `estado IN ('PREPARANDO','ASIGNADO','EN_RUTA')`, `numero_guia IS NULL` y `guia_foto_url IS NULL` → contador + acceso al detalle (donde ya existe la sección OBS-004)
- Acceso rápido a Envíos

**No dupliques consultas**: si existe un controller/repository con esa data, reutilizalo o ampliá el provider existente; si no, creá consultas simples de conteo (head/count) en un `dashboard_repository` por rol. Todo con el JWT del usuario (RLS filtra; igual filtrá por sucursal explícitamente).

## 6. Directrices del MCP de Supabase (para Codex)

1. **Lectura libre**: usalo para inspeccionar esquema, columnas, políticas y verificar tus consultas.
2. **Escrituras permitidas SOLO para datos de prueba**: crear **usuarios de prueba de Auth** (gestión de auth) y vincularlos/seed mínimo en el tenant FER si necesitás verificar el CRUD de usuarios. Usá emails de **dominio válido** (ej. `cajero.demo@rsuelvo.dev`) — los `.test` son rechazados por la validación de GoTrue.
   - ⚠️ **Aviso conocido:** el esquema `auth.identities` tiene una constraint legacy `UNIQUE(provider_id, provider)` que permite **una sola** identidad `('email','email')` (la tiene `cajero@rsuelvo.test`). Si crear usuarios falla por eso, **NO toques el schema `auth`**: usá los usuarios de prueba existentes (`cajero@ / repartidor@ / dueno@rsuelvo.test`, pass `Test1234!`) y reportá la limitación.
3. **PROHIBIDO vía MCP:** DDL, migraciones, cambios a `fn_*`/triggers/policies, borrados o updates masivos, tocar `auth` más allá de crear test users. Si algo lo requiere → **DETENTE, documentá y reportá** (el orquestador hace las migraciones).
4. La app JAMÁS usa `service_role`; solo el JWT del usuario.

## 7. Prohibiciones

1. NO modificar la BD (DDL/policies/fns/triggers) ni ejecutar migraciones.
2. NO agregar dependencias ni paquetes.
3. NO capturas/APK/dispositivo/`evidence/`.
4. NO romper F4/F5/F6 ni el rediseño de marca (reutilizá sus componentes y tokens; no cambies la paleta).
5. NO cambiar flujos existentes (verificaciones, envíos, pedidos, puntos de entrega) salvo lo mínimo para el ruteo `/dashboard`.
6. NO botones que fallen por RLS ni workarounds de auth en el cliente.
7. Español en UI, `Bs`, fechas `America/La_Paz`.

## 8. Verificación y entregable

1. `flutter analyze` → **0 issues**
2. `flutter test` → suite existente en verde (podés agregar widget tests cortos y headless solo para los CRUDs nuevos si es barato; nada de golden tests ni imágenes)
3. Entregable = informe en texto (≤ 25 líneas): qué se creó/completó por pantalla y archivo, limitaciones encontradas (destacar la de creación de usuarios + propuesta backend), y salida resumida de analyze/test. **Sin imágenes.**
