# Auditoría — SQL del schema vs ERD conceptual

> **Fecha:** 2026-08-24 · **Objeto:** `RSUELVO_SUPABASE_schema.sql` (2.149 líneas) vs [[Rsuelvo_Documentacion_Base_de_Datos]] (ERD), [[workflows]] y matriz de permisos.
> **Resultado:** schema **fiel al ERD** en estructura y reglas críticas, con **7 gaps funcionales** y **4 desajustes RLS↔matriz** a resolver antes de codificar. Ver también [[02-Auditoria-de-Consistencia]].

## 1. Inventario real del SQL

| Componente | Cantidad | Detalle |
|---|---|---|
| Esquema/extensiones | 2 | `rsuelvo`, `pgcrypto` |
| ENUMs | **14** | comercio(4), pedido(9), reserva(6)+origen(2), lista_espera(7), comprobante(5), verificacion(5), mov_inventario(7), mov_credito(6), compra_créditos(4), pago_créditos(4), qr(4), envío(7), rol_codigo(**6**) |
| Tablas | **29** | idénticas a ERD §28 (3+3+3+2+1+4+4+6+2+1) |
| Funciones | **24** | incluye las 8 RPC núcleo del doc de funciones + helpers tenancy + `fn_procesar_reservas_vencidas` |
| Triggers | 5 grupos | asignación usuario, SKU, consistencia tenant ×5 tablas, updated_at ×18 |
| Índices parciales únicos | 5 | cliente-WA, reserva-activa, posición-lista, cliente-en-lista, operación-comprobante |
| RLS | 26 tablas + policies por tabla | helpers `security definer` con `search_path` fijado ✅ |
| Vistas | 2 | `vw_inventario_disponible` (stock_disponible calculado), `vw_lista_espera_activa` |
| Storage/Cron | comentados | bucket solo `comprobantes-pago` como comentario; sin schedule pg_cron |

## 2. Consistencias verificadas contra el ERD ✅

| Regla del ERD | Implementación en SQL | Estado |
|---|---|---|
| Todos los estados/enums §6.1-§22 | 14 enums con valores exactos | ✅ idénticos |
| `UNIQUE(id_comercio, telefono_whatsapp)` clientes | índice parcial `uq_cliente_whatsapp_comercio WHERE not null` | ✅ (mejor: permite cliente sin WA) |
| Una reserva activa por variante | `uq_reserva_activa_variante_sucursal WHERE estado IN ('ACTIVA','PAGO_VALIDANDO')` | ✅ **más estricto** que ERD (incluye validando) ✚ sucursal |
| Posición única activa en lista | `uq_lista_posicion_activa` + extra `uq_cliente_lista_activa` (cliente no duplicado) | ✅ ✚ bonus |
| Cajero ↔ exactamente 1 sucursal; sucursal obligatoria cajero/logístico | trigger `fn_validar_asignacion_usuario_comercio` + FK compuesta `(id_comercio,id_sucursal)` deferrable | ✅ |
| Reserva ≠ venta; liberar al vencer | `fn_expirar_reserva` + movimiento LIBERACION_RESERVA; `fn_confirmar_pago` descuenta reservado+actual y registra VENTA | ✅ transaccional |
| Concurrencia stock=1 (BD §25) | `SELECT … FOR UPDATE` en `fn_solicitar_reserva`; `SKIP LOCKED` en lista | ✅ correcto |
| Créditos atómicos, costo desde tabla | `fn_consumir_creditos` FOR UPDATE + `tbl_servicios_creditos.costo_creditos`; ledger saldo_anterior/posterior | ✅ |
| Snapshots pedido | `sku_snapshot/nombre_snapshot/precio_unitario` + subtotal generated | ✅ |
| Auditoría JSONB anterior/nuevo + ip/user_agent | `tbl_logs_auditoria` + `fn_auditar_cambio` genérica | ⚠️ A12 |
| 8 funciones que n8n debe consumir (doc "Funciones principales…") | `fn_solicitar_reserva`, `fn_agregar_lista_espera`, `fn_aceptar_lista_espera`, `fn_crear_pedido_desde_reserva`, `fn_consumir_creditos`, `fn_confirmar_pago`, `fn_rechazar_verificacion`, `fn_crear_envio` | ✅ **8/8 presentes** |
| RLS patrón auth.uid→comercio | helpers + policies por tabla; superadmin bypass; soporte vía membresía | ✅ con matices A10 |

## 3. Hallazgos (gaps y riesgos)

| ID | Severidad | Hallazgo | Acción recomendada |
|----|-----------|----------|--------------------|
| **A1** | 🟠 MEDIA | Unicidad de SKU se valida por **trigger** (`exists`), pero el UNIQUE físico es solo `(id_producto,sku)` → dos INSERT concurrentes en **productos distintos** del mismo comercio pueden duplicar SKU. | Denormalizar `id_comercio` en `tbl_variantes` (columna generada o mantenida) + `UNIQUE(id_comercio, sku)` físico; trigger queda como mensaje amigable. |
| **A2** | 🔴 ALTA | No existe **mapeo número WhatsApp → comercio** (workflows WF-04 lo exige: `rpc_identificar_comercio_por_whatsapp`). Política: 1 WhatsApp = 1 tienda. | Crear `tbl_canal_whatsapp(id, id_comercio, id_sucursal, numero, provider, instance_id, status)` + función de resolución. |
| **A3** | 🔴 ALTA | La función combinada `fn_procesar_verificacion_ia_atomica()` citada por arquitectura **no existe**. Hoy crear verificación y consumir crédito son pasos separados (n8n orquesta) → ventana de carrera. | Crear `fn_iniciar_verificacion(p_id_comprobante)` transaccional: inserta verificación PROCESANDO + consume créditos + devuelve id o SIN_CREDITOS. |
| **A4** | 🟠 MEDIA | Sin `rpc_generar_cobro`: `tbl_qr_cobros` existe pero nadie la crea por función (n8n insertaría directo, contradice el principio). | `fn_generar_cobro(p_id_pedido)` que calcule monto del pedido y referencia única. |
| **A5** | 🟡 BAJA | Sin `rpc_actualizar_estado_envio`: el seguimiento se inserta directo (RLS lo permite) **sin validar máquina de estados** ni exigir prueba en ENTREGADO. | Función con transiciones válidas PENDIENTE→PREPARANDO→ASIGNADO→EN_RUTA→ENTREGADO/NO_ENTREGADO. |
| **A6** | 🟠 MEDIA | Falta `tbl_whatsapp_eventos` para idempotencia de webhooks (WF §13, política §11). Hoy HU-143 no tiene soporte de esquema. | Crearla (+ índice único en `(provider, external_message_id)`) y función `fn_registrar_evento()` que devuelve ya_procesado. |
| **A7** | 🟡 BAJA | Bucket **qr-pagos** ausente del monolito (solo `comprobantes-pago` comentado); políticas de storage inexistentes. | Resuelto en el split: `11_storage.sql` crea ambos buckets (idempotente) y deja plantilla de política por prefijo `{id_comercio}/`. |
| **A8** | 🟡 BAJA | Cron no configurado (solo helper). `pg_cron` no estaba entre extensiones. | Resuelto en split: extensión en `01`, plantilla `cron.schedule('rsuelvo_expirar_reservas', '* * * * *', fn_procesar_reservas_vencidas(200))` en `12`. Alternativa WF-30/31 documentada. |
| **A9** | 🟠 MEDIA (decisión) | `fn_rechazar_verificacion` pone pedido en **CANCELADO** ante INVALIDO. Choca con HU-065/wireframe 25 ("permitir reenvío de comprobante"): si se cancela, ¿cómo reintenta? | Decidir: INVALIDO mantiene pedido ESPERANDO_PAGO con nueva oportunidad; CANCELADO solo tras N intentos o decisión del admin. |
| **A10** | 🟠 MEDIA (RLS↔matriz) | Desajustes: `branches_all/products_all/categories_all` usan acceso-comercio ⇒ un **cajero podría escribir** catálogo/sucursales (matriz: solo admin); `shipments_manage` es admin-only pero matriz da crear/asignar también al cajero; `verification_manage` admin-only vs cajero "valida" en matriz. | Congelar matriz canónica y ajustar policies: escrituras catálogo/sucursales → `fn_es_admin_comercio`; envíos create → incluir TENANT_CASHIER; verificación manual → ver HU-141. |
| **A11** | ⚪ INFO | `numero_pedido` identity global (no por comercio); cosmetérico para UI. | Secuencia por comercio si se requiere numeración local. |
| **A12** | ⚪ INFO | `fn_auditar_cambio` definida **sin triggers adjuntos**. | Split añade bloque recomendado comentado en `07_triggers.sql`; activar por tabla crítica tras medir volumen. |

## 4. Convención de nombres congelada (I3)

El SQL usa **`fn_*`** para todo. Se congela: `fn_` = implementación real; los `rpc_*` listados en workflows son alias conceptuales (documentar equivalencias en el schema.sql final): `rpc_solicitar_sku/rpc_crear_reserva → fn_solicitar_reserva` · `rpc_agregar_lista_espera → fn_agregar_lista_espera` · `rpc_aceptar_oportunidad → fn_aceptar_lista_espera` · `rpc_confirmar_pago → fn_confirmar_pago` · `rpc_crear_envio → fn_crear_envio` · `rpc_procesar_reservas_expiradas → fn_procesar_reservas_vencidas`.

## 5. Separación del monolito

Ejecutado según el doc [[Funciones principales que n8n debería consumir]] (ruta real del monolito: `/home/nico/rsuelvo/RSUELVO_SUPABASE_schema.sql`; el doc citaba `/home/nico/RSUELVO` — corregir referencia):

```text
sql/
├── 01_extensions.sql   pgcrypto + pg_cron + schema rsuelvo
├── 02_enums.sql        14 enums
├── 03_tables.sql       29 tablas (DDL puro)
├── 04_constraints.sql  5 índices únicos parciales + FK diferida reserva↔pedido
├── 05_indexes.sql      17 índices de rendimiento
├── 06_functions.sql    24 funciones (orden de dependencias)
├── 07_triggers.sql     triggers + bloque recomendado de auditoría
├── 08_rls.sql          enable + policies + grants
├── 09_views.sql        2 vistas operativas
├── 10_seed.sql         roles + servicios de créditos (+ paquetes sugeridos)
├── 11_storage.sql      buckets qr-pagos y comprobantes-pago + plantilla políticas
└── 12_cron.sql         schedule de expiración (alternativa WF-30/31 documentada)
```

Verificación automática post-split: 29 tablas · 14 enums · 24 funciones · sin `begin;/commit;` global · cada archivo idempotente con `search_path` fijado.

## 6. RESOLUCIÓN — Schema v2 (2026-08-24, mismo día)

El schema **v2** (`RSUELVO_SUPABASE_schema_v2.sql`, 2.614 líneas; split en `sql/01…12`) cierra los hallazgos:

| ID | Resolución v2 |
|----|---------------|
| A1 | `tbl_variantes.id_comercio` denormalizado + `UNIQUE(id_comercio,sku)` físico + trigger genera/valida SKU |
| **SKU v2** | **6 caracteres = [3 código tienda][3 producto] base36** (`^[A-Z0-9]{6}$`). `codigo_tienda char(3)` único por comercio (ej. FER → FERA01…). Generación automática serializada con FOR UPDATE; `sku_anterior` conserva el formato viejo durante migración |
| A2 | `tbl_canal_whatsapp` (1 WhatsApp=1 tienda, provider OPENWA/META) + `fn_identificar_comercio_por_whatsapp` (solo service_role) |
| A3 | `fn_iniciar_verificacion`: verificación + consumo atómicos; SIN_CREDITOS→BLOQUEADA sin excepción (HU-141) |
| A4 | `fn_generar_cobro` con referencia `RS-{numero_pedido}` |
| A5 | `fn_actualizar_estado_envio` valida transiciones y exige observación en NO_ENTREGADO |
| A6 | `tbl_whatsapp_eventos` + `fn_registrar_evento_whatsapp` (HU-143) |
| A7/A8 | buckets creados en `11_storage.sql`; pg_cron programado en `12_cron.sql` |
| A9 | rechazo deja pedido en ESPERANDO_PAGO con `puede_reenviar=true` |
| A10 | RLS reescrito: escritura catálogo/sucursales/métodos=admin; envíos admin|cajero; verificar admin|cajero (`fn_puede_verificar/gestionar_envios`) |
| A11 | pendiente de decisión (cosmético) |
| A12 | triggers de auditoría ACTIVOS en 10 tablas críticas |

**Nuevo hallazgo resuelto en v2:** las funciones security-definer fallaban cuando n8n llama con service_role (`auth.uid()` null ⇒ "Sin acceso"). Añadido `fn_es_service_role()` como bypass controlado en los helpers de tenancy — sin esto, E07/E09/E10 no funcionaban desde workflows.

Estado final: **0 inconsistencias conocidas** entre SQL v2 ↔ ERD ↔ HU (148) ↔ workflows ↔ wireframes. Decisiones de cierre D1-D10 registradas en [[00-PROMPT-MAESTRO-RSUELVO]] §5 (incluye D4 que cierra I4 y D7 que descarta la HU-147).
