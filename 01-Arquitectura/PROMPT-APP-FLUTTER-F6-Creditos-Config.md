# PROMPT — App Flutter RSUELVO F6: Créditos + Configuración + Usuarios + Sucursales + Puntos

> **Destinatario:** agente Antigravity CLI (`agy`) — trabajar SOLO en `/home/nico/StudioProjects/rsuelvo/`
> **Estado de partida:** F4+F5 ya implementadas y funcionando (login/roles, verificaciones, envíos+foto OBS-004, pedidos+WhatsApp, dashboard, productos lectura). `flutter analyze` limpio.
> **Regla de oro:** este documento es un CONTRATO. Si algo no está aquí, preguntá; no inventes.

## 1. Contexto

RSUELVO: SaaS multitenant (Flutter + Supabase schema `rsuelvo` + n8n). La app es para el personal del comercio (dueño/cajero/repartidor). **La app NUNCA envía WhatsApp** (los flujos de WhatsApp viven en n8n). Esta fase agrega al rol ADMIN: Créditos (lectura), Configuración, Sucursales, Usuarios, y **Puntos de entrega** (dueño/cajero) — completando OBS-003 (los días/horarios los define el comercio en la app).

## 2. Contratos BD (schema `rsuelvo`, columnas EXACTAS)

**Créditos (LECTURA):**
- `tbl_cuentas_creditos`: `id_cuenta_creditos, id_comercio, saldo_actual (bigint), updated_at`
- `tbl_movimientos_creditos`: `id_movimiento, id_comercio, id_cuenta_creditos, tipo (COMPRA|BONIFICACION|AJUSTE|CONSUMO_VERIFICACION|CONSUMO_VENTA|DEVOLUCION|EXPIRACION), cantidad (bigint, puede ser negativa), saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id, created_at, usuario_id`
- `tbl_servicios_creditos`: `id_servicio, codigo, nombre, descripcion, costo_creditos, activo`
- `tbl_paquetes_creditos`: `id_paquete, nombre, creditos, precio, moneda, activo`
- `tbl_compras_creditos`: `id_compra, id_comercio, id_paquete, creditos_comprados, monto, moneda, estado, fecha_creacion, fecha_pago`
- `tbl_pagos_creditos`: `id_pago, id_compra, metodo_pago, referencia_externa, monto, estado, fecha_pago`

**Configuración (LECTURA+UPDATE):**
- `tbl_comercio_config`: `id_comercio, tiempo_reserva_minutos, tiempo_aceptacion_lista_espera_minutos, max_lista_espera_por_producto, verificacion_automatica (bool), rate_limit_whatsapp_por_minuto, created_at, updated_at`

**Sucursales (CRUD):**
- `tbl_sucursales`: `id_sucursal, id_comercio, nombre, direccion, referencia, latitud (numeric), longitud (numeric), telefono, activo, created_at, updated_at`

**Usuarios (listar + editar vínculo):**
- `tbl_usuario_comercio`: `id, id_usuario, id_comercio, id_rol, id_sucursal, activo`
- `tbl_usuarios`: `id_usuario, auth_user_id, nombre, apellido, telefono, email, activo`
- `tbl_roles`: `id_rol, codigo, nombre, nivel` (4=ROLE_TENANT_ADMIN, 5=ROLE_TENANT_CASHIER, 6=ROLE_LOGISTICS_AGENT)

**Puntos de entrega (CRUD) — completa OBS-003:**
- `tbl_puntos_entrega`: `id_punto_entrega, id_sucursal, tipo (RETIRO_EN_TIENDA|PUNTO_LOCAL|ENVIO_TRANSPORTE), nombre, ciudad, direccion, referencia, id_transportadora, activo, orden, dias_atencion (texto libre ej. "LUN-SAB"), horario_inicio (time), horario_fin (time), created_at, updated_at`
- `tbl_transportadoras`: `id_transportadora, nombre, ciudades, activo` (solo lectura — lista para asignar)
- **CHECK obligatorio:** `ENVIO_TRANSPORTE` EXIGE `id_transportadora`; los otros tipos exigen `id_transportadora` NULL. Si la BD rechaza, mostrar el mensaje.

Todas estas tablas tienen RLS activo: consultas/escrituras se hacen con el JWT del usuario (semántica por fila). Si una operación devuelve error de permisos → mostrar mensaje claro, no reintentar.

## 3. Alcance F6 (pantallas + criterios)

| # | Pantalla | Rol | Contenido | Criterios de aceptación |
|---|----------|-----|-----------|------------------------|
| S9 | **Créditos** | ADMIN | Card saldo actual (Bs grande) + lista de movimientos (últimos 50: tipo en español, ±cantidad, saldo posterior, concepto, fecha) + catálogo de paquetes (nombre, créditos, precio) + servicios con costo | (a) saldo se lee de `tbl_cuentas_creditos` del comercio del usuario; (b) movimientos ordenados desc; (c) los paquetes son solo informativos — botón "¿Cómo recargar?" que muestra un diálogo informativo (la compra se habilita en una fase futura; NO implementar pago) |
| S10 | **Configuración** | ADMIN | Formulario: tiempo_reserva_minutos, tiempo_aceptacion_lista_espera_minutos, max_lista_espera_por_producto, rate_limit_whatsapp_por_minuto (numéricos), **verificacion_automatica** (Switch "Verificación automática de comprobantes (IA)") | (a) carga valores reales; (b) guarda solo los campos editados con UPDATE; (c) SnackBar de éxito; (d) validación > 0 en numéricos |
| S11 | **Sucursales** | ADMIN | Lista + crear/editar (nombre, direccion, referencia, telefono, activo) + activar/desactivar | (a) CRUD completo; (b) refresca; (c) estados con badge |
| S12 | **Usuarios** | ADMIN | Lista de vínculos (nombre completo del usuario, rol en español, sucursal, activo) + editar rol/sucursal/activo | (a) join tbl_usuarios+tbl_roles+tbl_sucursales; (b) editar `id_rol`, `id_sucursal`, `activo` de `tbl_usuario_comercio`; (c) **alta de usuarios NUEVOS excluida** (requiere backend/Auth admin) — mostrar nota informativa |
| S13 | **Puntos de Entrega** | ADMIN + CAJERO | Lista por sucursal + crear/editar: tipo (dropdown 3 valores), nombre, ciudad, direccion, referencia, **dias_atencion** (chips multi-select LUN..DOM que guardan "LUN,SAB"), **horario_inicio/fin** (time pickers → `HH:mm:00`), transportadora (solo si ENVIO_TRANSPORTE, de la lista), activo, orden | (a) CAJERO ve/gestiona SOLO lo de su sucursal (su vínculo tiene 1 sucursal); ADMIN puede elegir sucursal; (b) al elegir ENVIO_TRANSPORTE el selector de transportadora es obligatorio; (c) el punto creado aparece luego en el menú de WhatsApp (n8n `fn_listar_puntos_entrega`) — no programar nada de WhatsApp, solo persistir bien |

**EXCLUIDO de F6:** compra/pago real de paquetes · alta de usuarios nuevos · login/auth changes · gestión de transportadoras (solo lectura) · todo lo de fases anteriores (no refactorizar).

## 4. Arquitectura (respetar la existente)

- Riverpod + go_router + supabase_flutter. Estructura `lib/features/{creditos,configuracion,sucursales,usuarios,puntos_entrega}/` con `*_model.dart`, `*_repository.dart`, `*_controller.dart`, `*_screen.dart` (mismo patrón que `envios/`).
- Agregar rutas: `/creditos`, `/configuracion`, `/sucursales`, `/usuarios`, `/puntos-entrega`. En el shell del ADMIN agregar los accesos (puede ser una sección "Administración" en el Dashboard o ítems del menú; manterse coherente con el diseño existente).
- Reutilizar `StatusBadge`, `showSuccessSnackBar`/`showErrorSnackBar`/`mensajeResultado*` de `shared/widgets/error_snackbar.dart`.
- Textos en español, moneda Bs (`AppTheme.formatCurrency`), fechas con `AppTheme.formatDateTime`.
- **NO agregar dependencias nuevas.** Para días: `FilterChip`; para hora: `showTimePicker` (formato a `HH:mm:00` para Supabase).
- Sin tildes problemáticas en Code/no aplica (no hay Code nodes; esto es Dart): tildes normales en UI.

## 5. Plan por fases (checkpoint por fase: `flutter analyze` sin errores + `flutter build apk --debug` OK)

- **F6-A** Créditos (S9)
- **F6-B** Configuración (S10)
- **F6-C** Sucursales (S11)
- **F6-D** Usuarios (S12)
- **F6-E** Puntos de Entrega (S13)

No pases de fase sin el checkpoint verde.

## 6. Definition of Done (verificación con datos reales del tenant FER)

| # | Prueba | Esperado |
|---|--------|----------|
| 1 | Login `dueno@rsuelvo.test` / `Test1234!` → Créditos | Saldo ~78 visible + movimientos (CONSUMO_VENTA recientes) |
| 2 | Configuración: cambiar `tiempo_reserva_minutos` a 15 y guardar | SnackBar éxito; al recargar persiste 15 |
| 3 | Configuración: activar `verificacion_automatica` y guardar | Persiste el toggle |
| 4 | Sucursales: crear "Sucursal Norte" | Aparece en la lista |
| 5 | Usuarios: cambiar el rol del usuario `repartidor@rsuelvo.test` a CAJERO y volver | El badge de rol refleja el cambio |
| 6 | Puntos: CAJERO crea un PUNTO_LOCAL "Punto Test F6" con LUN-VIE 09:00-17:00 | Se guarda con días y horario correctos |
| 7 | Puntos: intentar crear ENVIO_TRANSPORTE sin transportadora | Error claro (CHECK de BD), no crashea |
| 8 | `flutter analyze` final | 0 issues |

**Nota wireframes:** si el MCP de Stitch falla (su configuración está rota), NO bloquees: seguí el estilo Material 3 ya usado en la app.

## 7. Prohibiciones

1. NO tocar la BD (DDL/migraciones/queries de escritura vía MCP) — la BD ya está lista. El MCP de Supabase es **solo lectura** para verificar.
2. NO usar service_role. Solo el JWT del usuario.
3. NO enviar WhatsApp (no aplica; los flujos son n8n).
4. NO inventar tablas/columnas/funciones fuera de §2.
5. NO hardcodear URLs/keys (usar la config existente de `core/`).
6. NO agregar dependencias.
7. NO modificar pantallas/flujos ya funcionando de F4/F5 (salvo agregar los accesos de navegación).
8. Schema `rsuelvo` siempre.

## 8. Datos de prueba (tenant FER)

Comercio FER · usuarios `dueno@/cajero@/repartidor@rsuelvo.test` (`Test1234!`) · 2 transportadoras (Expreso Bolívar, CobExpress) · 5 puntos existentes · 10 SKUs · créditos 78 · config actual: tiempos 10/10, máx lista 5, verificacion_automatica=false, rate_limit 20.
