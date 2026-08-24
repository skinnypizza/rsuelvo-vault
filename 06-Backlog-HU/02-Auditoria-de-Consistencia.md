# Auditoría de Consistencia — Backlog 140 HU vs Vault RSUELVO

> **Fecha:** 2026-08-24 · **Alcance:** contraste del [[01-Backlog-Historias-de-Usuario]] contra la totalidad de las fuentes del vault, previo a usarlo como **prompt maestro** de construcción.
> **Fuentes contrastadas:** [[arquitectura-general]] · [[Rsuelvo_Documentacion_Base_de_Datos]] · [[workflows]] · [[Matriz de permisos]] · [[Política Técnica de Uso de WhatsApp y OpenWA —RSUELVO]] · [[Wireframes App Móvil]] · código Flutter (`lib/features/*`).

---

## 1. Veredicto ejecutivo

| Dimensión | Resultado |
|---|---|
| Reglas de negocio núcleo | ✅ Consistente (SKU, reserva≠venta, atomicidad, QR estático, RLS) |
| Estados/enums BD ↔ wireframes | ✅ Consistente |
| Roles | ⚠️ **Inconsistencia I1** — resuelta por decisión congelada (6 roles) |
| Estados logísticos | ⚠️ **Inconsistencia I2** — arquitectura vs BD; canónico = BD |
| Nomenclatura RPC/fn | ⚠️ **Inconsistencia I3** — dos generaciones de nombres |
| Alta de comercios | ⚠️ **Decisión I4** pendiente (self-service vs SuperAdmin) |
| Verificación manual en app | ❌ **Gap I5** — existe en wireframe 24, no en backlog |
| Cumplimiento política OpenWA | ❌ **Gap G1** — opt-out/rate-limit/circuit breaker sin HU |

El backlog es fiel al vault en lo sustantivo. Las brechas detectadas son de **cobertura** y de **nomenclatura**, no de concepto: corregibles documentalmente antes de programar.

---

## 2. Consistencias verificadas (evidencia cruzada)

| # | Afirmación del backlog | Fuente del vault que la respalda | Estado |
|---|---|---|---|
| C1 | SKU `[3L][1N][1L][3A]`, único por comercio, autogenerado | arquitectura (`trg_generar_validar_sku`) + BD `UNIQUE(id_comercio,sku)` + WF pantalla 10 con error duplicado | ✅ triple fuente |
| C2 | "Una reserva no es una venta"; bloqueo → pago → confirmación | BD §11/§26 + workflows §3/§69 | ✅ |
| C3 | Reserva atómica transaccional en PostgreSQL, nunca IF-stock en n8n | BD §25 concurrencia + workflows §67 "No hacer en n8n" + HU-036 | ✅ |
| C4 | Una sola reserva activa por variante / posición única de lista | BD §24 constraints parciales `WHERE estado='ACTIVA'` | ✅ |
| C5 | Créditos atómicos con `FOR UPDATE`; costo desde tabla, no hardcode | arquitectura (`fn_procesar_verificacion_ia_atomica`) + workflows §42-43 + HU-068/069 | ✅ |
| C6 | QR estático del dueño; sin QR dinámicos con monto | arquitectura §Roles + HU-042 | ✅ |
| C7 | Comprador sin cuenta; todo por WhatsApp | arquitectura + README + E07 completa | ✅ |
| C8 | GPT-4o extrae, backend decide | workflows §37/72 ("GPT = extracción, PostgreSQL = decisión") + HU-059 vs 060-062 | ✅ separación bien reflejada |
| C9 | Estados comprobante RECIBIDO→PROCESANDO→VALIDO/INVALIDO/RECHAZADO | BD §15.3 + WF pantallas 06/07/25 | ✅ chips coinciden |
| C10 | Estados pedido CREADO…CANCELADO y envío PENDIENTE…NO_ENTREGADO | BD §14/§22 + WF pantallas 16/30 timeline | ✅ |
| C11 | Lista de espera: posiciones, NOTIFICADO con ventana, promover siguiente | BD §12 + workflows WF-13/14 + pantallas 13/28 | ✅ orden idéntico al flujo oficial |
| C12 | Cajero ↔ exactamente una sucursal; alcance lectura inventario | BD §4.5 + matriz permisos + pantalla 39 | ✅ |
| C13 | Tiempos configurables desde `tbl_comercio_config`, nunca hardcode | BD §6.2 + workflows §22/28 + HU-008/009/010 + pantalla 20 steppers | ✅ |
| C14 | Normalizador OpenWA/Meta antes de lógica; sender único WF-80 | workflows §6/§56 + HU-122/124 | ✅ |
| C15 | Idempotencia por `message_id` | workflows §13 + política §11 + HU-061(parcial, ver G2) | ✅/⚠ |
| C16 | Error técnico de IA ≠ pago inválido (queda PROCESANDO/RECIBIDO) | workflows §63 + HU-126 | ✅ |
| C17 | Health check WF-70; Error Handler WF-00 | workflows §4 + HU-114/126 | ✅ |
| C18 | RLS `auth.uid()→id_comercio`; service_role jamás en frontend | arquitectura + workflows §5.1 + HU-133/136 | ✅ |
| C19 | Snapshots de pedido (sku/nombre/precio) | BD §14.1 + HU-079 | ✅ |
| C20 | Prueba de entrega foto+firma+GPS+historial de seguimiento | arquitectura (rol logístico) + BD §22.1 + pantallas 19/30 | ✅ |

## 3. Inconsistencias detectadas

### I1 — Dos modelos de roles (resuelta por decisión)
- `arquitectura-general` §RBAC lista **4 roles** con códigos `ROL_*`.
- BD §4 y matriz de permisos definen **6** (`ROLE_SUPERADMIN/SYSADMIN/SUPPORT/TENANT_ADMIN/TENANT_CASHIER/LOGISTICS_AGENT`).
- **Resolución congelada:** canónicos = los 6 de BD. Mapeo oficial:

| arquitectura (viejo) | Canónico BD | Matriz de permisos |
|---|---|---|
| `ROL_SUPERADMIN` | `ROLE_SUPERADMIN` | Superadmin |
| — | `ROLE_SYSADMIN` | Admin Sistema |
| — | `ROLE_SUPPORT` | Agente Soporte |
| `ROL_ADMIN_COMERCIO` | `ROLE_TENANT_ADMIN` | Admin Comercio |
| `ROL_OPERADOR` | `ROLE_TENANT_CASHIER` | Operador/Cajero |
| `ROL_LOGISTICO` | `ROLE_LOGISTICS_AGENT` | Agente Logístico |

- **Acción requerida:** actualizar §RBAC de `arquitectura-general` para reflejar los 6 (pendiente; este documento es la referencia hasta entonces).

### I2 — Enums logísticos divergentes
- arquitectura línea 54 dice estados `EN_TRANSITO/ENTREGADO/FALLIDO`.
- BD §22 define `PENDIENTE/PREPARANDO/ASIGNADO/EN_RUTA/ENTREGADO/NO_ENTREGADO/CANCELADO`; workflows §50 igual; wireframes 18/30/31 usan EN_RUTA/NO_ENTREGADO.
- **Resolución:** canónico = enum BD. Corregir mención en arquitectura-general. `FALLIDO` y `EN_TRANSITO` **no existen** como valores válidos.

### I3 — Dos generaciones de nombres de funciones
- arquitectura cita `fn_procesar_verificacion_ia_atomica()` sobre `tbl_cre_saldos_comercio` (tablas `tbl_cre_*`, `tbl_com_productos`, `tbl_adm_usuarios`).
- workflows §68 propone RPCs `rpc_iniciar_verificacion/rpc_consumir_creditos/rpc_registrar_resultado_verificacion` y tablas `tbl_cuentas_creditos` etc.
- **Riesgo:** el prompt maestro heredaría dos vocabularios.
- **Resolución:** elegir UNA convención en el `schema.sql` definitivo (recomendado: prefijo `fn_` para funciones internas ACID y `rpc_` para expuestas; documento de nombres único). Marcar en SQL final cuál cubre `procesar_verificacion_ia_atomica`.

### I4 — Alta de comercios: self-service vs SuperAdmin (decisión abierta)
- Wireframe 02 + HU-002 permiten **auto-registro público** de comercios.
- HU-104 asigna crear tenants al **SuperAdmin** (coincide con arquitectura "gestión de comercios" del SuperAdmin).
- **Decisión pendiente para MVP:** ¿registro self-service con verificación, o alta asistida por SuperAdmin/staff? Impacto en onboarding, fraude y créditos bonificados (pantalla 22 regala 100 créditos). *Recomendación:* MVP = self-service con revisión; dejar flag `comercios.estado=PENDIENTE_ACTIVACION`.

### I5 — Verificación manual disparada desde la app (gap real)
- Wireframe 24 incluye botón **"Verificar ahora"** (y pantalla 20 toggle `verificacion_automatica`).
- El backlog cubre verificación automática (HU-058→063) pero **ninguna HU permite al admin/cajero lanzar manualmente una verificación** cuando `verificacion_automatica=false` o tras un bloqueo SIN_CRÉDITOS ya resuelto (pantalla 08 promete "continuará automáticamente al recargar").
- **Propuesta:** añadir **HU-141** *(Como admin/cajero, quiero reintentar/lanzar la verificación de un comprobante RECIBIDO/BLOQUEADO, para desbloquear pagos pendientes)* → consume crédito, misma cadena atómica.

## 4. Gaps de cobertura (vault exige, backlog no modela)

| ID | Gap | Fuente que lo exige | HU propuestas |
|---|---|---|---|
| G1 | **Opt-out del comprador** (STOP/NO QUIERO → `contact_preferences.opted_out`) | Política §16 obligatoria | HU-142 sistema registra y respeta opt-out |
| G2 | **Idempotencia general de webhooks** (`tbl_whatsapp_eventos`: procesado→ignorar duplicados) | workflows §13 + política §11-12 | HU-143 deduplicación global de eventos (amplía HU-061) |
| G3 | **Rate limiting + cola + circuit breaker** de envíos salientes | Política §9/§10/§14 (condición de producción) | HU-144 cola+rate-limiter; HU-145 circuit breaker CLOSED/OPEN/HALF_OPEN |
| G4 | **Devolución de créditos** (tipo DEVOLUCION; WF-52 existe) | BD §17.2 + workflows WF-52 | HU-146 devolución ante fallo técnico de IA |
| G5 | **Expiración de créditos** (tipo EXPIRACION en ledger) | BD §17.2 | HU-147 (P2, si se define vigencia) |
| G6 | **Actualización en tiempo real** en app (Supabase Realtime aparece en diagrama; countdowns/chips vivos) | arquitectura (diagrama Supabase "Realtime") | HU-148 suscripción realtime pedidos/reservas (P1) |
| G7 | Nota: mensajes agrupados y minimización (política §7-8) son reglas editoriales de plantillas → incorporar como criterio dentro de HU-124 más que HU nueva | Política §7-8 | criterio adicional |

Con G1-G6 el backlog pasaría de **140 → ~148 HU** sin alterar épicas existentes.

## 5. Trazabilidad Épica → Fuente primaria → Pantallas

| Épica | Fuente normativa principal | Wireframes |
|---|---|---|
| E01 | arquitectura (Auth/JWT) + workflows §5 | 01, 21, 38, 02, 37 |
| E02-E04 | BD §4-§7 + matriz permisos | 20, 32, 33 |
| E05-E06 | BD §8-§9 + arquitectura SKU | 09, 26, 10, 27, 11, 39 |
| E07 | arquitectura flujo real + workflows WF-10/11 | (WhatsApp, sin pantalla) |
| E08-E09 | BD §11-§13 + workflows WF-12/13/14/30/31 | 12, 13, 28, 34, 35 |
| E10 | workflows WF-20/21/22/23 + BD §15-16 | 24, 06, 07, 25, 08 |
| E11 | BD §17-§20 + arquitectura fn atómica | 14, 15, 29, 08 |
| E12-E13 | workflows WF-24/40 + BD §14 | 07(CTA), 16 |
| E14 | BD §22 + workflows WF-41/42 | 16, 17, 30, 18, 31, 19 |
| E15 | BD §4.5 + matriz + pantalla propia | 39, 04, 05 |
| E16 | arquitectura RBAC + BD §6.1 | (panel web, fuera de móvil) |
| E17-E18 | matriz permisos + workflows WF-70/00 | (fuera de móvil MVP) |
| E19 | workflows íntegro + política | — |
| E20-E21 | BD §23 + RLS + política §21 | — |
| E22 | wireframes + Flutter offline | 35, 36 |

## 6. Mapa completo wireframe ↔ HU (39 pantallas)

01 Login→001 · 02 Registro→002(I4) · 03 Dashboard→agregación(082/066/050) · 04 Lista cobros→097/082 · 05 Emitir cobro→098/042/051 · 06 Verificando→058-059 · 07 Válido→063/078 · 08 Sin créditos→067/I5 · 09 Productos→029 · 10 Nuevo producto→023/024/025/026 · 11 Inventario→030/032/033/035 · 12 Reservas→050/051/054 · 13 Detalle+lista→044/045/049/054 · 14 Créditos→066/070/071 · 15 Paquetes→072/073 · 16 Envíos→088/092/093/094 · 17 Nuevo envío→086/087 · 18 Hoja ruta→090 · 19 Prueba entrega→095/093/094 · 20 Config tienda→006-011 · 21 Login carga→001 · 22 Dashboard vacío→140 · 23 QR ampliado→042/098 · 24 Modal comprobante→058/**I5** · 25 Inválido→060/064/065 · 26 Catálogo vacío→140 · 27 Editar producto→027/028 · 28 Vencida→048/052/053 · 29 Compra exitosa→074/075 · 30 Detalle envío→089/096 · 31 Detalle entrega→091 · 32 Sucursales→012-015 · 33 Usuarios→016-021 · 34 Diálogo liberar→053/054 · 35 Offline→137-139 · 36 Menú Más→navegación · 37 Onboarding permisos→UX onboarding · 38 Login error→001 · 39 Cajero→031/097-102.

*Cobertura: 39/39 pantallas mapeadas a ≥1 HU. Sin pantallas huérfanas; sin épicas móviles sin pantallas (E07/E19 son conversacionales por diseño).*

## 7. Conclusión para el prompt maestro

1. El backlog **respeta el modelo**: ninguna HU contradice las reglas duras del vault (C1-C20).
2. Antes de generar código, incorporar al backlog: **I5 + G1-G6** (~8 HU nuevas).
3. Congelar en el schema.sql la **convención de nombres** (I3) y corregir las dos menciones de arquitectura-general (**I1**, **I2**) para que el vault quede monolingüe.
4. Decidir **I4** (alta de comercios) porque condiciona onboarding, créditos de bienvenida y HU-002/104.
