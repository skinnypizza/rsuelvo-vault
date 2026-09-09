# 📱 PROMPT — App Flutter RSUELVO v1 (Operativo + Dashboard mínimo)

> **Destinatario:** agente Antigravity (ejecutar en `/home/nico/StudioProjects/rsuelvo/`, Flutter SDK en `/home/nico/flutter`)
> **Orquestador:** preparado por opencode (orquestador RSUELVO) · 2026-09-09 · Versión 1.0
> **Regla de oro de este prompt:** este documento es un CONTRATO. Si algo no está aquí, no lo inventes: preguntá.

---

## 1. Contexto de negocio

RSUELVO es un SaaS multitenant de gestión comercial, cobranza por WhatsApp y verificación de pagos con IA para vendedores de TikTok Live / Facebook Marketplace en Bolivia. Los compradores NO usan la app: compran por WhatsApp (los flujos de WhatsApp los maneja un backend n8n — la app NUNCA envía mensajes automatizados por WhatsApp). La app Flutter es la herramienta interna del personal del comercio:

- **Dueño (ROLE_TENANT_ADMIN)** — dashboard mínimo + todo el comercio
- **Cajero (ROLE_TENANT_CASHIER)** — confirma/rechaza verificaciones de pago (exactamente 1 sucursal)
- **Repartidor (ROLE_LOGISTICS_AGENT)** — gestiona envíos de su sucursal, registra guía/código de retiro y su **foto** (OBS-004)

**Regla inquebrantable D11:** la app jamás envía WhatsApp por su cuenta. Al llamar las `fn_*` de la BD, los triggers internos (pg_net → n8n) notifican al comprador automáticamente. **Excepción legítima:** el botón WhatsApp de la ficha de pedido (§6) solo **abre un chat humano** del vendedor con su comprador vía `wa.me` — no envía nada el sistema.

## 2. Contratos de base de datos (NO inventar nada fuera de esto)

**Todo vive en el schema `rsuelvo` (NO en `public`).** Con supabase_flutter, cada query REST debe incluir el header `Accept-Profile: rsuelvo` (o configurar headers globales del cliente). PostgREST expone ese schema.

### 2.1 Flujo de identidad (login)
1. `supabase.auth.signInWithPassword(email, password)` → JWT
2. Perfil: `SELECT * FROM rsuelvo.tbl_usuarios WHERE auth_user_id = auth.uid()` (hay exactamente 1)
3. Vínculos: `SELECT * FROM rsuelvo.tbl_usuario_comercio uc WHERE uc.id_usuario = <id_usuario> AND uc.activo = true` (campos: `id_comercio`, `id_rol`, `id_sucursal`)
4. Rol por número: 4=ADMIN, 5=CAJERO, 6=LOGISTICS_AGENT (tabla `rsuelvo.tbl_roles`: `id_rol`, `codigo`, `nombre`)
5. Ruteo inicial: CAJERO → Verificaciones · LOGISTICS_AGENT → Envíos · ADMIN → Dashboard

### 2.2 Tablas y columnas usadas (nombres EXACTOS)
- `tbl_usuarios`: `id_usuario, auth_user_id, nombre, apellido, email, activo`
- `tbl_usuario_comercio`: `id_usuario, id_comercio, id_rol, id_sucursal, activo`
- `tbl_pedidos`: `id_pedido, id_comercio, id_sucursal, id_cliente, numero_pedido (int), estado (texto: CREADO/ESPERANDO_PAGO/PAGO_RECIBIDO/PAGO_VALIDANDO/PAGADO/PREPARANDO/DESPACHADO/ENTREGADO/CANCELADO), subtotal, total, created_at`
- `tbl_envios`: `id_envio, id_comercio, id_pedido, id_sucursal, direccion, referencia, telefono_contacto, id_repartidor, estado (PENDIENTE/PREPARANDO/ASIGNADO/EN_RUTA/ENTREGADO/NO_ENTREGADO/CANCELADO), numero_guia (text nullable), guia_foto_url (text nullable), destino_ciudad, destino_zona, id_punto_entrega, created_at, updated_at`
- `tbl_clientes`: `id_cliente, nombre, apellido_paterno, apellido_materno, telefono_whatsapp`
- `tbl_verificaciones`: `id_verificacion, id_comercio, id_comprobante, id_pedido, tipo_verificacion, estado (PENDIENTE/PROCESANDO/COMPLETADA/BLOQUEADA/ERROR), resultado (jsonb), creditos_consumidos, created_at`
- `tbl_comprobantes_pago`: `id_comprobante, id_pedido, id_cliente, tipo_archivo, archivo_url, monto_detectado, fecha_detectada, numero_operacion, nombre_pagador, estado (RECIBIDO/PROCESANDO/VALIDO/INVALIDO/RECHAZADO)`
- `tbl_puntos_entrega`: `id_punto_entrega, id_sucursal, tipo (RETIRO_EN_TIENDA/PUNTO_LOCAL/ENVIO_TRANSPORTE), nombre, ciudad, direccion, referencia, dias_atencion, horario_inicio, horario_fin, activo, orden`
- `tbl_inventario`: `id_variante, id_sucursal, stock_actual, stock_reservado`
- `tbl_variantes`: `id_variante, sku (6 chars), nombre, precio (numeric), activo`
- `tbl_lista_espera`: `id_lista_espera, estado (ESPERANDO/NOTIFICADO/...), posicion`
- `tbl_comercio_config`: `id_comercio, tiempo_reserva_minutos, tiempo_aceptacion_lista_espera_minutos, verificacion_automatica (bool), rate_limit_whatsapp_por_minuto`

### 2.3 RPC `fn_*` que la app consume (firmas exactas)
| Función | Parámetros | Retorna | Uso |
|---|---|---|---|
| `fn_confirmar_pago` | `p_id_verificacion uuid, p_resultado jsonb` | `{resultado:'PAGO_CONFIRMADO'/'YA_PROCESADO'/'RESERVA_VENCIDA', id_pedido, id_reserva}` | Cajero: botón CONFIRMAR. `p_resultado` = `{"modo":"manual","validado_por":"<nombre usuario app>"}` |
| `fn_rechazar_verificacion` | `p_id_verificacion uuid, p_resultado jsonb` | igual estructura | Cajero: botón RECHAZAR |
| `fn_actualizar_estado_envio` | `p_id_envio uuid, p_nuevo_estado rsuelvo.estado_envio, p_observacion text DEFAULT NULL, p_latitud numeric DEFAULT NULL, p_longitud numeric DEFAULT NULL` | `{resultado:'ESTADO_ACTUALIZADO', id_envio, estado}` | Repartidor. Máquina de estados: saltos hacia adelante permitidos (PENDIENTE<PREPARANDO<ASIGNADO<EN_RUTA<ENTREGADO); `NO_ENTREGADO` solo desde ASIGNADO/EN_RUTA y **exige `p_observacion`**; `CANCELADO` desde no-terminales. Lanza EXCEPTION con mensaje en español — mostrarla al usuario |
| `fn_registrar_guia` | `p_id_envio uuid, p_numero_guia text DEFAULT NULL, p_guia_foto_url text DEFAULT NULL` | `{resultado:'GUIA_REGISTRADA', numero_guia, guia_foto_url, tipo_punto}` | Repartidor (OBS-004). Acepta ENVIO_TRANSPORTE (guía) y PUNTO_LOCAL (código de retiro). Requiere estado PREPARANDO/ASIGNADO/EN_RUTA. Lanza EXCEPTION si el envío ya notificado con mismo contenido |
| `fn_listar_puntos_entrega` | `p_id_sucursal uuid` | `{puntos:[{opcion,id_punto_entrega,tipo,nombre,ciudad,direccion,referencia,transportadora,dias_atencion,horario}]}` | Consulta |
| `fn_pedido_entrega_pendiente` | `p_telefono text` | `{pendiente, id_pedido, numero_pedido, id_sucursal}` | Consulta |

**Errores:** las fn lanzan EXCEPTION con mensajes en español (ej. "El pedido X no está PAGADO (estado: Y)", "Transición inválida: ASIGNADO -> ENTREGADO"). PostgREST los envuelve en `{"message": ..., "details": ...}` — mostrar `message` en un SnackBar.

**RLS:** la app usa el JWT del usuario (políticas via `fn_tiene_acceso_sucursal`). **Prohibido service_role/anon con privilegios.** Si una query devuelve 0 filas sin error, es RLS — no forzar.

## 3. Alcance v1 (pantallas + criterios de aceptación)

| # | Pantalla | Contenido | Criterios de aceptación |
|---|----------|-----------|------------------------|
| S1 | Login | Email+password, Material 3 | (a) login OK lleva a pantalla según rol; (b) credenciales malas → mensaje; (c) sesión persiste al reiniciar (supabase_flutter la persiste) |
| S2 | Shell + rol | BottomNav según rol: ADMIN→[Dashboard, Pedidos, Envíos], CAJERO→[Verificaciones, Pedidos], REPARTIDOR→[Envíos] | El cajero NO ve envíos; el repartidor NO ve verificaciones |
| S3 | Verificaciones (cajero) | Lista de `tbl_verificaciones` con `estado='PENDIENTE'` o `'PROCESANDO'` de su comercio (join a pedido+cliente+comprobante: foto, monto_detectado, numero_operacion, nombre_pagador, numero_pedido) | (a) tap → detalle con la **foto del comprobante** (imagen desde `archivo_url` del bucket); (b) botones **CONFIRMAR** → `fn_confirmar_pago` y **RECHAZAR** → `fn_rechazar_verificacion` con `{"modo":"manual","validado_por":"<nombre+apellido del usuario>"}`; (c) tras éxito → refresca lista y muestra SnackBar con el `resultado` retornado; (d) error de fn → SnackBar con el `message` |
| S4 | Pedidos (cajero/admin) | Lista de pedidos (número, cliente, estado, total) con **filtro por estado** + ficha de detalle | (a) botón **WhatsApp** (§6) visible en la ficha y en cada fila; (b) estados legibles en español |
| S5 | Envíos (repartidor/admin) | Lista de `tbl_envios` de su sucursal (join pedido+cliente+punto) + ficha de detalle | (a) ficha muestra: cliente (nombre completo), dirección denormalizada, punto (nombre/tipo), destino ciudad/zona si transporte, `numero_guia`/`guia_foto_url` si existen; (b) **botones de transición según estado actual** (PENDIENTE→PREPARANDO; PREPARANDO→ASIGNADO/ENTREGADO; ASIGNADO→EN_RUTA/ENTREGADO/NO_ENTREGADO; EN_RUTA→ENTREGADO/NO_ENTREGADO) llamando `fn_actualizar_estado_envio`; NO_ENTREGADO pide observación (dialog); (c) sección **Guía/Código (OBS-004)** visible si punto es ENVIO_TRANSPORTE o PUNTO_LOCAL y estado ∈ {PREPARANDO, ASIGNADO, EN_RUTA} |
| S6 | Registrar guía/código (OBS-004) | Dentro de la ficha de envío (S5): campo texto opcional (`numero_guia`/`código`) + botón **📷 Cámara** y **🖼️ Galería** (image_picker) → preview → botón REGISTRAR | (a) valida que haya texto y/o foto; (b) sube la foto a Storage bucket `guias-envios` en ruta `{id_comercio}/{id_envio}.jpg` (upsert, solo usuarios autenticados — RLS del bucket ya configurada); (c) obtiene la URL con `getPublicUrl` o crea Signed URL si el bucket privado la requiere — **usar Signed URL de 7 días** (bucket privado + WhatsApp necesita URL accesible); (d) llama `fn_registrar_guia(p_id_envio, texto, foto_url)`; (e) muestra el resultado; (f) el comprador recibe la imagen por WhatsApp AUTOMÁTICAMENTE (pg_net+n8n) — la app no hace nada más |
| S7 | Dashboard mínimo (admin) | Cards: pedidos de hoy (por estado), reservas activas, verificaciones pendientes, envíos en curso | Solo conteos + listas recientes; sin gráficos |
| S8 | Productos básicos (admin) | Lista de variantes (SKU, nombre, precio, stock) | Solo lectura v1 (crear/editar en v2) |

**EXCLUIDOS de v1 (NO construir):** gestión de créditos/paquetes, configuración del comercio, usuarios, reservas CRUD, pagos de paquetes, reportes, chat interno, notificaciones push.

## 4. OBS-004 — flujo foto guía/código (resumen operativo)

1. Repartidor entrega el paquete en la paquetería (código de retiro) o transportadora (guía)
2. En la app abre la ficha del envío → sección Guía/Código → toma/sube la foto → (opcional) escribe el código → REGISTRAR
3. La app sube la foto a `guias-envios/{id_comercio}/{id_envio}.jpg` y llama `fn_registrar_guia`
4. **La notificación WhatsApp con la imagen al comprador ocurre sola** (pg_net → n8n WF-25-C). La app termina su trabajo al recibir `{resultado:'GUIA_REGISTRADA'}`

## 5. Botón WhatsApp de la ficha de pedido

- Icono/branding verde de WhatsApp (usa el assets o un Icon personalizado; NO dependencias pesadas)
- Al tap: `url_launcher` → `https://wa.me/<telefono>` donde `<telefono>` = `tbl_clientes.telefono_whatsapp` del pedido (ya viene con código de país, ej. `59171531944` — **sin `+` ni espacios**)
- Si el teléfono es null → botón deshabilitado
- Opcional: prefijar `?text=` con saludo breve: `Hola, te escribo de RSUELVO sobre tu pedido #<numero_pedido>`
- Es un deep-link humano del vendedor — no pasa por n8n ni viola D11

## 6. Arquitectura técnica (fijada, no negociable)

- **Flutter estable** instalado en `/home/nico/flutter` (ya en PATH). Package: `rsuelvo` (esqueleto ya creado)
- Dependencias: `supabase_flutter`, `flutter_riverpod`, `go_router`, `image_picker`, `url_launcher`, `intl`
- Estructura:
  ```
  lib/
    main.dart
    core/
      supabase_client.dart   (cliente con headers 'Accept-Profile: rsuelvo')
      router.dart            (go_router, guard por sesión)
      theme.dart             (Material 3, español, Bs)
      constants.dart
    features/
      auth/                  (login, sesión, proveedor de perfil+rol)
      verificaciones/        (lista, detalle, confirmar/rechazar)
      pedidos/               (lista, detalle, botón WhatsApp)
      envios/                (lista, ficha, transiciones, foto guía)
      dashboard/
      productos/
    shared/widgets/          (badges de estado, cards, snackbars de error)
  ```
- **Config por `--dart-define`** (jamás hardcodear): `SUPABASE_URL=https://iwfaktlxebxtocmswdvv.supabase.co`, `SUPABASE_ANON_KEY=<publishable key que provee el orquestador>`
- Formatos: fechas/horas en `America/La_Paz` (`intl`), moneda `Bs 1.234,00`, textos UI en español
- Manejo de errores central: toda fn/postgrest error → SnackBar con `error.message` (los mensajes ya vienen en español)

## 7. Plan de ejecución por fases (agéntico, con checkpoints)

Ejecuta en este orden exacto. **Cada fase termina con `flutter analyze` sin errores + `flutter build apk --debug` exitoso.** Si analyze/build falla, corrige ANTES de pasar a la siguiente fase.

- **Fase A** — Scaffolding + deps + theme + cliente Supabase (con Accept-Profile) + Login (S1) + Shell por rol (S2) + router con guard de sesión
- **Fase B** — Verificaciones (S3): lista + detalle con foto + confirmar/rechazar
- **Fase C** — Envíos (S5) + transiciones + **Registrar guía/código con foto (S6, OBS-004)**
- **Fase D** — Pedidos (S4) + botón WhatsApp (§5) + Dashboard mínimo (S7) + Productos lectura (S8)

No avances de fase sin el checkpoint verde. No refactorices más allá de lo pedido.

## 8. Definition of Done (verificación en Android Studio / dispositivo)

Al terminar TODAS las fases, el operador ejecutará este checklist con los datos reales (tenant FER — ya sembrado en Supabase):

| # | Prueba | Esperado |
|---|--------|----------|
| 1 | Login `cajero@rsuelvo.test` / `Test1234!` | Entra directo a Verificaciones |
| 2 | Login `repartidor@rsuelvo.test` / `Test1234!` | Entra directo a Envíos |
| 3 | Login `dueno@rsuelvo.test` / `Test1234!` | Entra al Dashboard |
| 4 | Cajero: confirmar una verificación PENDIENTE | SnackBar `PAGO_CONFIRMADO` + pedido pasa a PAGADO en BD + comprador recibe WhatsApp de datos de entrega (pg_net) |
| 5 | Cajero: rechazar otra | SnackBar + verificación COMPLETADA/rechazada sin tocar stock |
| 6 | Repartidor: mover un envío PENDIENTE→PREPARANDO→ASIGNADO | Estados actualizados; comprador recibe notificaciones (pg_net) |
| 7 | Repartidor: tomar foto del "código" y registrar | Foto sube al bucket `guias-envios` + `fn_registrar_guia` OK + comprador recibe la **foto** por WhatsApp |
| 8 | Repartidor: transición inválida (ej. PENDIENTE→ENTREGADO) | SnackBar con el mensaje de la fn ("Transición inválida...") — no crashea |
| 9 | Pedidos: botón WhatsApp | Abre el chat del vendedor con el comprador |
| 10 | Logout + login con otro rol | Shell cambia según rol |

**Nota para el operador:** hay 1-2 pedidos PAGADOS pendientes de entrega (sembrados) para probar S5-S6 sin depender del flujo WhatsApp.

## 9. Prohibiciones explícitas

1. **NO aplicar migraciones ni DDL** — la BD está lista y es de solo-lectura-estructura para ti. Si falta algo, DETENTE y reporta
2. **NO usar service_role ni la service key** — solo anon/publishable + RLS
3. **NO enviar WhatsApp desde la app** (solo el deep-link wa.me del §5)
4. **NO inventar tablas/columnas/funciones/estados** fuera de §2 — los nombres son exactos
5. **NO hardcodear claves ni URLs** — todo por `--dart-define`
6. **NO agregar dependencias** fuera de las listadas en §6 sin justificar
7. NO uses `public` como schema — siempre `rsuelvo`

## 10. Datos de prueba disponibles (tenant FER)

- Comercio FER (`Prueba RSUELVO`), sucursal única, 3 puntos de entrega (retiro/punto local con horario LUN-SAB 09:00-18:00/transporte "Expreso Bolívar")
- Producto `FERG01` (Bs 200), stock 1, pedidos #54 (PAGADO, pendiente de entrega) y #51/#48 históricos
- Usuarios de prueba (§8) — los 3 roles vinculados a la sucursal
- Créditos del comercio: 78

---
