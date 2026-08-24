# Backlog de Historias de Usuario — RSUELVO

> **Versión:** 1.1 · **Fecha:** 2026-08-24 · **Origen:** sesión colaborativa (ChatGPT) sobre este vault + ampliación post-auditoría
> **Estado:** Congelado como base del prompt maestro · **Total:** 148 HU en 22 épicas
> **Auditoría de consistencia:** ver [[02-Auditoria-de-Consistencia]]

## Decisiones previas congeladas

1. **Roles canónicos = 6** (`ROLE_SUPERADMIN`, `ROLE_SYSADMIN`, `ROLE_SUPPORT`, `ROLE_TENANT_ADMIN`, `ROLE_TENANT_CASHIER`, `ROLE_LOGISTICS_AGENT`) según `tbl_roles` de la BD + **Comprador** como actor externo sin cuenta (WhatsApp). El resumen de 4 roles de [[arquitectura-general]] queda subsumido (mapeo en la auditoría, I1).
2. **No todas las HU son Flutter**: se clasifican en Flutter / Backend Supabase / n8n-WhatsApp.
3. Principio rector heredado: **una reserva no es una venta**; n8n nunca es motor transaccional.

## Distribución por épica

| Épica | HU | Épica | HU |
|---|---|---|---|
| E01 Autenticación | 001–005 | E12 Confirmación compra | 076–081 |
| E02 Comercio | 006–011 | E13 Pedidos | 082–085 |
| E03 Sucursales | 012–015 | E14 Logística | 086–096 |
| E04 Usuarios/Roles | 016–021 | E15 Cajero | 097–102 |
| E05 Catálogo | 022–029 | E16 Super Admin | 103–109 |
| E06 Inventario | 030–036 | E17 SysAdmin | 110–114 |
| E07 Compra WhatsApp | 037–042 | E18 Soporte | 115–119 |
| E08 Lista de espera | 043–049 | E19 WhatsApp/n8n | 120–126, **142–145** |
| E09 Reservas | 050–055 | E20 Auditoría | 127–131 |
| E10 Pagos/Comprobantes | 056–065, **141** | E21 Seguridad multitenant | 132–136 |
| E11 Créditos IA | 066–075, **146–147** | E22 UX/Offline | 137–140, **148** |

---

# ÉPICA E01 — Autenticación e identidad

**HU-001 Iniciar sesión** *(usuario)* Acceder únicamente a funciones de su rol. ✓ Credenciales válidas→acceso; inválidas→error; usuario inactivo→rechazo; sistema resuelve comercio+rol+alcance. WF: pantalla 01/21/38.
**HU-002 Registrar comercio** *(propietario)* Registrar comercio y comenzar a usar RSUELVO. Crea tenant + usuario admin + configuración inicial. WF: pantalla 02. ⚠ Ver decisión I4 (alta self-service vs SuperAdmin).
**HU-003 Recuperar acceso** *(usuario)* Recuperar credenciales perdidas.
**HU-004 Mantener sesión segura** *(usuario)* Protección vía Supabase Auth/JWT; RLS multitenant.
**HU-005 Aplicar permisos según rol** *(sistema)* Impedir operaciones fuera de la responsabilidad del rol.

# ÉPICA E02 — Administración del comercio (ROLE_TENANT_ADMIN)

**HU-006 Consultar información del comercio.**
**HU-007 Editar información del comercio.**
**HU-008 Configurar tiempo de reserva** → `tbl_comercio_config.tiempo_reserva_minutos` (nunca hardcode en n8n).
**HU-009 Configurar tiempo de aceptación de lista de espera** → `tiempo_aceptacion_lista_espera_minutos`.
**HU-010 Configurar límite de lista de espera** → `max_lista_espera_por_producto`.
**HU-011 Activar/desactivar verificación automática** → `verificacion_automatica`. WF: pantalla 20.

# ÉPICA E03 — Sucursales

**HU-012 Crear sucursal** · **HU-013 Editar sucursal** · **HU-014 Activar/desactivar sucursal** · **HU-015 Consultar sucursales.** WF: pantalla 32.

# ÉPICA E04 — Usuarios y roles

**HU-016 Crear usuario de comercio.**
**HU-017 Asignar rol.**
**HU-018 Asignar cajero a sucursal** — *Regla crítica:* `ROLE_TENANT_CASHIER` ↔ **exactamente una** sucursal activa.
**HU-019 Asignar repartidor a sucursal** (`id_sucursal` obligatorio para logístico).
**HU-020 Desactivar usuario.**
**HU-021 Consultar usuarios.** WF: pantalla 33.

# ÉPICA E05 — Catálogo

**HU-022 Crear categoría.**
**HU-023 Crear producto.**
**HU-024 Crear variante** (SKU pertenece a la variante).
**HU-025 Generar SKU automáticamente** — formato `[3L][1N][1L][3A]`, ej. `FER1H001`; trigger `trg_generar_validar_sku`.
**HU-026 Validar SKU único** — `UNIQUE(id_comercio, sku)`. WF: pantalla 10 (error duplicado).
**HU-027 Editar producto.** WF: pantalla 27.
**HU-028 Desactivar producto** (sin borrar historial).
**HU-029 Consultar catálogo.** WF: pantallas 09/26.

# ÉPICA E06 — Inventario

**HU-030 Consultar inventario** (admin). WF: pantalla 11.
**HU-031 Consultar inventario como cajero** — solo su sucursal, lectura. WF: pantalla 39.
**HU-032 Registrar entrada de inventario.**
**HU-033 Ajustar inventario.**
**HU-034 Registrar movimiento de inventario** — tipos: ENTRADA/SALIDA/RESERVA/LIBERACION_RESERVA/VENTA/AJUSTE/DEVOLUCION.
**HU-035 Consultar historial de movimientos.**
**HU-036 Reservar stock atómicamente** — transacción PostgreSQL, jamás decisión en n8n. Concurrencia: stock=1, A reserva / B lista.

# ÉPICA E07 — Compra por WhatsApp (Comprador)

**HU-037 Enviar SKU.**
**HU-038 Recibir información del producto** (nombre, precio, disponibilidad).
**HU-039 Recibir rechazo de SKU inválido** (`SKU_NO_ENCONTRADO`).
**HU-040 Recibir respuesta por falta de stock** (`SIN_STOCK`).
**HU-041 Recibir oportunidad de reserva** (`RESERVA_CREADA`).
**HU-042 Recibir información del QR** — QR **estático** del comercio/sucursal; RSUELVO no emite QR dinámicos con monto. WF: pantallas 05/23.

# ÉPICA E08 — Lista de espera

**HU-043 Entrar a lista de espera** (`LISTA_ESPERA_CREADA`; llena → `LISTA_ESPERA_LLENA`).
**HU-044 Recibir posición** (#N).
**HU-045 Recibir notificación de oportunidad** (estado NOTIFICADO + ventana `tiempo_aceptacion_lista_espera_minutos`).
**HU-046 Aceptar oportunidad** ("SI" → `rpc_aceptar_oportunidad`: valida estado/expiración/inventario y crea reserva atómico).
**HU-047 Rechazar oportunidad** ("NO" → pasa al siguiente).
**HU-048 Expirar oportunidad** automáticamente.
**HU-049 Promover siguiente comprador** — flujo oficial: liberar reserva → buscar posición #1 → notificar → acepta/rechaza → crear reserva. Nunca SELECT MAX(posicion) desde n8n.

# ÉPICA E09 — Reservas

**HU-050 Crear reserva** — origen DIRECTA/LISTA_ESPERA; bloquea `stock_reservado`. *Una reserva activa por variante* (`UNIQUE(id_variante) WHERE estado='ACTIVA'`). Estados: ACTIVA/PAGO_VALIDANDO/CONFIRMADA/VENCIDA/CANCELADA/LIBERADA. WF: pantallas 12/13.
**HU-051 Mostrar tiempo restante** (countdown). WF: pantallas 05/12/13.
**HU-052 Expirar reserva** — Schedule → `rpc_procesar_reservas_expiradas()` transaccional (WF-30).
**HU-053 Liberar stock** al vencer (+ movimiento LIBERACION_RESERVA). WF: pantalla 34.
**HU-054 Cancelar reserva** (admin/sistema). WF: pantallas 13/34.
**HU-055 Registrar historial de reserva** (auditoría).

# ÉPICA E10 — Pagos y comprobantes

**HU-056 Registrar intención de pago** — cadena QR→Cobro→Comprobante→Verificación; crea `tbl_qr_cobros` vía RPC y envía `qr_url` (WF-20).
**HU-057 Enviar comprobante** por WhatsApp.
**HU-058 Recibir comprobante** — descarga media → Storage → `tbl_comprobantes_pago(RECIBIDO)` (WF-21).
**HU-059 Procesar OCR** — GPT-4o Vision **extrae datos, no decide** (WF-22); salida JSON estructurada con confianza.
**HU-060 Validar monto** — backend compara monto esperado vs detectado (WF-23 `rpc_validar_comprobante`). WF: pantalla 25.
**HU-061 Detectar comprobante duplicado.**
**HU-062 Validar autenticidad** — operación, fecha, cliente vs pedido; estados VALIDO/INVALIDO/RECHAZADO.
**HU-063 Mostrar resultado válido** al operador. WF: pantalla 07.
**HU-064 Mostrar rechazo** con motivo. WF: pantalla 25.
**HU-065 Reintentar comprobante** — feedback al comprador; opción "permitir reenvío" en app.

# ÉPICA E11 — Créditos IA

**HU-066 Consultar saldo** — píldora persistente en app. WF: pantalla 14.
**HU-067 Bloquear verificación sin créditos** — estado `SIN_CREDITOS`; comprobante queda RECIBIDO; aviso al cliente. WF: pantalla 08.
**HU-068 Consumir crédito** según `tbl_servicios_creditos.costo_creditos` (no hardcode).
**HU-069 Consumir crédito atómicamente** — `fn_procesar_verificacion_ia_atomica()` con `FOR UPDATE` sobre `tbl_cre_saldos_comercio`.
**HU-070 Registrar movimiento de créditos** — ledger: COMPRA/BONIFICACION/AJUSTE/CONSUMO_VERIFICACION/DEVOLUCION/EXPIRACION.
**HU-071 Consultar movimientos.** WF: pantalla 14.
**HU-072 Consultar paquetes** (Básico 100/Pro 500/Empresa 1000). WF: pantalla 15.
**HU-073 Comprar créditos** — compra PENDIENTE_DE_PAGO con QR. WF: pantalla 15.
**HU-074 Registrar pago de créditos** (PAGADA).
**HU-075 Acreditar créditos** automáticamente tras pago válido. WF: pantalla 29.

# ÉPICA E12 — Confirmación de compra

**HU-076 Solicitar datos de envío** — estado conversacional ESPERANDO_DIRECCION (nombre/dirección/referencia/teléfono).
**HU-077 Guardar datos del cliente** — `tbl_clientes` con `UNIQUE(id_comercio, telefono_whatsapp)`.
**HU-078 Confirmar compra** solo tras pago válido (`rpc_confirmar_pago`: valida reserva+comprobante+estado).
**HU-079 Crear pedido** con snapshots (sku_snapshot/nombre_snapshot/precio_unitario).
**HU-080 Asociar reserva al pedido** (`id_reserva FK`).
**HU-081 Finalizar reserva** → CONFIRMADA/venta; unidad reservada→vendida + movimiento VENTA.

# ÉPICA E13 — Gestión de pedidos

Estados: CREADO/ESPERANDO_PAGO/PAGO_RECIBIDO/PAGO_VALIDANDO/PAGADO/PREPARANDO/DESPACHADO/ENTREGADO/CANCELADO.
**HU-082 Consultar pedidos** · **HU-083 Consultar detalle** · **HU-084 Consultar estado** · **HU-085 Actualizar estado operativo.**

# ÉPICA E14 — Logística

Estados envío: PENDIENTE/PREPARANDO/ASIGNADO/EN_RUTA/ENTREGADO/NO_ENTREGADO/CANCELADO. Cada cambio inserta en `tbl_env_seguimiento_estados` (historial, nunca sobrescribir).
**HU-086 Crear envío** (WF-41 `rpc_crear_envio`). WF: pantalla 17.
**HU-087 Asignar repartidor.** WF: pantalla 17.
**HU-088 Consultar envíos.** WF: pantalla 16.
**HU-089 Consultar detalle de envío + timeline.** WF: pantalla 30.
**HU-090 Consultar hoja de ruta** (repartidor, entregas del día). WF: pantalla 18.
**HU-091 Consultar detalle de entrega.** WF: pantalla 31.
**HU-092 Actualizar a EN_RUTA.**
**HU-093 Registrar entrega exitosa** (+prueba). 
**HU-094 Registrar entrega fallida** (NO_ENTREGADO + observación).
**HU-095 Registrar prueba de entrega** — foto+firma+GPS+hora. WF: pantalla 19.
**HU-096 Consultar timeline logístico.**

# ÉPICA E15 — Operador / Cajero

**HU-097 Consultar cobros** de su sucursal. WF: pantalla 39.
**HU-098 Emitir cobro QR** (matriz: emitir/validar). WF: pantallas 04/05.
**HU-099 Consultar comprobantes.**
**HU-100 Consultar stock** de su sucursal.
**HU-101 Registrar cliente.**
**HU-102 Operar únicamente en su sucursal** — restricción estructural (una sola asignación activa).

# ÉPICA E16 — Super Admin

Estados comercio: ACTIVO/SUSPENDIDO/BLOQUEADO/CANCELADO.
**HU-103 Consultar comercios** · **HU-104 Crear comercio (tenant)** · **HU-105 Suspender** · **HU-106 Bloquear** · **HU-107 Gestionar paquetes de créditos** · **HU-108 Configurar costos de APIs** (WhatsApp/IA) · **HU-109 Consultar auditoría global.**

# ÉPICA E17 — SysAdmin

**HU-110 Consultar estado de infraestructura** · **HU-111 Consultar logs técnicos** · **HU-112 Gestionar parámetros globales** · **HU-113 Monitorear servicios** (Supabase/n8n/OpenWA/Meta/OpenAI) · **HU-114 Ejecutar health check** (WF-70).

Restricción estricta: SysAdmin NO consulta saldos, cuentas bancarias ni datos sensibles de tenants (RLS).

# ÉPICA E18 — Soporte

**HU-115 Consultar información operativa** (solo lectura) · **HU-116 Consultar estado de operaciones** · **HU-117 Diagnosticar problema** · **HU-118 Consultar auditoría relacionada** · **HU-119 Respetar acceso limitado** (sin datos financieros sensibles).

# ÉPICA E19 — WhatsApp / n8n

**HU-120 Recibir mensaje OpenWA** (WF-01 webhook `/webhooks/whatsapp/openwa`).
**HU-121 Recibir mensaje Meta** (WF-02; GET verificación verify-token; POST responde 200 inmediato).
**HU-122 Normalizar proveedores** (WF-03): contrato interno único {provider, channel, message_id, chat_id, phone, type, text, media, timestamp}.
**HU-123 Enrutar conversación** (WF-04 router por imagen/texto/reserva activa/SKU; estados IDLE…PEDIDO_CONFIRMADO; identificar comercio por número — nunca id_comercio enviado por el cliente).
**HU-124 Responder WhatsApp** (WF-80 sender único; plantillas cuando corresponda).
**HU-125 Procesar imágenes** (descarga Meta media_id / OpenWA binario → Storage).
**HU-126 Manejar errores** (WF-00 global; backoff 1/2/4/8 s; error técnico ≠ pago inválido).

# ÉPICA E20 — Auditoría

`tbl_logs_auditoria` con JSONB datos_anteriores/nuevos.
**HU-127 Registrar operación crítica** (RESERVA_CREADA…ENVIO_CREADO) · **HU-128 Auditar inventario** · **HU-129 Auditar verificaciones IA** · **HU-130 Auditar créditos** · **HU-131 Auditar cambios logísticos.**

# ÉPICA E21 — Seguridad multitenant

**HU-132 Aislar por `id_comercio`** · **HU-133 Aplicar RLS** patrón `auth.uid() → tbl_adm_usuarios.id_comercio` · **HU-134 Validar alcance de sucursal** · **HU-135 Impedir escalamiento de privilegios** · **HU-136 Proteger credenciales** (service_role jamás en frontend/navegador/respuestas).

# ÉPICA E22 — Estados offline / UX

**HU-137 Detectar pérdida de conexión** · **HU-138 Mostrar estado offline** · **HU-139 Reintentar sincronización** — WF: pantalla 35 · **HU-140 Mostrar estados vacíos** — WF: pantallas 22/26.

---

---

# AMPLIACIÓN POST-AUDITORÍA — HU-141 a HU-148

> Nacidas de [[02-Auditoria-de-Consistencia]] (I5 + G1-G6). Se integran a sus épicas de destino.

**HU-141 Reintentar verificación manual** *(admin/cajero → E10)* Lanzar o relanzar la verificación de un comprobante en RECIBIDO/BLOQUEADO cuando `verificacion_automatica=false` o tras recargar créditos. Consume crédito por la misma cadena atómica. WF: pantallas 24 ("Verificar ahora") y 08.
**HU-142 Registrar opt-out del comprador** *(sistema → E19)* Detectar STOP / NO QUIERO / NO ME CONTACTEN; persistir `contact_preferences.opted_out`; suprimir comunicaciones no esenciales. Política §16.
**HU-143 Idempotencia global de eventos** *(sistema → E19)* Tabla `tbl_whatsapp_eventos`: si `message_id` ya fue procesado → ignorar. Obligatorio antes de procesar cualquier webhook (workflows §13).
**HU-144 Cola y rate limiting de envíos** *(sistema → E19)* Toda salida pasa por cola `pending→queued→processing→sent` con límites configurables por instancia/tienda/número. Política §9-10.
**HU-145 Circuit breaker de envíos** *(sistema → E19)* CLOSED→OPEN→HALF_OPEN ante anomalías; pausa los envíos automáticos sin cortar la recepción. Política §14.
**HU-146 Devolver créditos por fallo técnico** *(sistema → E11)* Si la verificación falla por error técnico (IA indisponible, timeout), registrar movimiento DEVOLUCION del costo (WF-52) sin marcar el pago como inválido.
**HU-147 Expirar créditos** *(sistema → E11)* Si se define vigencia comercial de créditos, registrar movimiento EXPIRACION en el ledger (P2).
**HU-148 Actualización en tiempo real en la app** *(usuario móvil → E22)* Suscripción Supabase Realtime para pedidos/reservas/comprobantes: lo que ocurre por WhatsApp se refleja solo en dashboard, cobros y reservas.

## Clasificación por destino de implementación

```text
FLUTTER (UI):   001-003, 006-007, 011-021(parcial), 022-035(UI), 063-064, 066, 071-073,
                082-084, 086-091, 093-095(UI), 097-101, 137-140
BACKEND (Supabase RPC/RLS): 004-005, 008-010, 018(regla), 025-026, 034, 036, 050-055,
                058(Storage), 060-062, 067-070, 074-075, 077-081, 085, 102, 107, 127-136
n8n/WhatsApp:   037-042(respuesta), 043-049(notificación), 056-059, 065, 076, 120-126
HÍBRIDO:        011, 048-049(Schedule+n8n), 052(WF-30), 074, 086(WF-40/41), 092-094
```
