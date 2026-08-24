# ⭐ PROMPT MAESTRO RSUELVO — Fuente Única de Verdad

> **Versión:** 1.1-FINAL · **Fecha:** 2026-08-24 · **Estado:** ✅ Consistencia 100% certificada entre módulos
> **Changelog v1.1:** guía Meta integrada (04) + SQL v2.1 (eventos/pnid/plantillas) + auditorías históricas movidas a `07-Control-de-Calidad/` + HU-147 descartada (D7)
> **Propósito:** documento raíz para cualquier IA o humano que construya RSUELVO. Todo lo demás en el vault es detalle; esto es la ley.
> Si encuentras un conflicto entre este documento y cualquier otro archivo: **gana este documento** y abre incidencia para corregir el archivo.

---

## 1. Qué es RSUELVO

SaaS **multitenant** de gestión comercial, cobranza por **WhatsApp** y verificación de pagos con **IA (OCR)** para vendedores de TikTok Live / Facebook Marketplace en Bolivia.

**Stack:** Flutter (dueño/cajero/repartidor) · Supabase PostgreSQL+RLS · n8n Cloud (orquestación) · OpenWA/Meta Cloud API (WhatsApp intercambiables) · GPT-4o Vision (extracción OCR) · pg_cron (expiraciones).

## 2. Actores

```text
RSUELVO (con cuenta: Supabase Auth + JWT)
├── ROLE_SUPERADMIN        Global cross-tenant: tenants, paquetes, costos API, auditoría global
├── ROLE_SYSADMIN          Infra/logs/parámetros — SIN datos financieros de tenants
├── ROLE_SUPPORT           Solo lectura operativa — SIN financiero sensible
└── TENANT (id_comercio)
    ├── ROLE_TENANT_ADMIN      Dueño: todo el comercio
    ├── ROLE_TENANT_CASHIER    Cajero: EXACTAMENTE 1 sucursal
    └── ROLE_LOGISTICS_AGENT   Repartidor: sus rutas (id_sucursal obligatoria)

EXTERNO
└── COMPRADOR              Sin cuenta. Solo WhatsApp. Identidad = teléfono dentro del comercio [D10]
```

Fuente: [[arquitectura-general]] §RBAC (corregido I1) · `tbl_roles`/`rol_codigo`.

## 3. Las 10 Reglas de Oro (invariantes absolutas)

1. **Una reserva NO es una venta.** Bloqueo temporal → pago verificado → venta.
2. **Atomicidad en PostgreSQL**: reservas, stock, lista de espera, pedidos, créditos y confirmaciones viven en funciones `fn_*`; jamás en lógica n8n/frontend.
3. **n8n orquesta, no decide**: ningún `SELECT→IF→UPDATE` de negocio en workflows.
4. **GPT-4o extrae, el backend decide**: la IA devuelve JSON estructurado con confianza; nunca aprueba dinero.
5. **QR estático** del comercio/sucursal (`qr-pagos`); RSUELVO no emite QR dinámicos con monto.
6. **RLS siempre activo**; patrón `auth.uid() → tbl_usuarios.auth_user_id → tbl_usuario_comercio.id_comercio`. `service_role` solo desde backend/n8n (bypass controlado vía `fn_es_service_role()`).
7. **Idempotencia obligatoria**: todo webhook pasa por `tbl_whatsapp_eventos` antes de procesarse.
8. **Opt-out sagrado** (STOP): `tbl_contact_preferences` se consulta antes de cada envío (WF-80).
9. **Trazabilidad total**: toda operación crítica queda en `tbl_logs_auditoria` (triggers activos).
10. **Nada hardcodeado en n8n**: tiempos, costos y límites viven en `tbl_comercio_config` y `tbl_servicios_creditos`.

## 4. Especificaciones congeladas

### 4.1 SKU (v2)
- **6 caracteres** = `[3 código tienda][3 código producto]`, base36 `A-Z0-9` (ej. tienda `FER` → `FERA01`).
- `codigo_tienda char(3)` único por comercio; asignación al crear comercio.
- Generación automática serializada (`fn_resolver_variante_tenant_sku`); capacidad 46.656 SKUs/tienda.
- Garantía física `UNIQUE(id_comercio, sku)`; `sku_anterior` preserva SKUs legacy de 8 chars durante migración.

### 4.2 Estados canónicos (enums SQL v2 — no inventar otros)
| Entidad | Valores |
|---|---|
| comercio | ACTIVO · SUSPENDIDO · BLOQUEADO · CANCELADO |
| pedido | CREADO · ESPERANDO_PAGO · PAGO_RECIBIDO · PAGO_VALIDANDO · PAGADO · PREPARANDO · DESPACHADO · ENTREGADO · CANCELADO |
| reserva | ACTIVA · PAGO_VALIDANDO · CONFIRMADA · VENCIDA · CANCELADA · LIBERADA (+origen DIRECTA/LISTA_ESPERA) |
| lista_espera | ESPERANDO · NOTIFICADO · ACEPTADO · CONVERTIDO_RESERVA · RECHAZADO · VENCIDO · CANCELADO |
| comprobante | RECIBIDO · PROCESANDO · VALIDO · INVALIDO · RECHAZADO |
| verificación | PENDIENTE · PROCESANDO · COMPLETADA · BLOQUEADA · ERROR |
| envío | PENDIENTE · PREPARANDO · ASIGNADO · EN_RUTA · ENTREGADO · NO_ENTREGADO · CANCELADO |
| mov. inventario | ENTRADA · SALIDA · RESERVA · LIBERACION_RESERVA · VENTA · AJUSTE · DEVOLUCION |
| mov. créditos | COMPRA · BONIFICACION · AJUSTE · CONSUMO_VERIFICACION · DEVOLUCION · EXPIRACION(reservado, ver D7) |

⚠️ No existen `EN_TRANSITO` ni `FALLIDO` (D2).

### 4.3 Cadena comercial (flujo canónico, ERD §13 + workflows §69)

```text
SKU por WhatsApp → reserva atómica (10 min config) ─┬─ SIN stock → lista de espera (#posición)
                                                    └─ QR estático → comprobante → OCR GPT-4o
                                                         ├─ VÁLIDO  → pedido PAGADO → datos envío → envío → entrega (foto+firma+GPS)
                                                         └─ INVÁLIDO→ comprobante INVALIDO, pedido ESPERANDO_PAGO (reenvío) [D5]
```

## 5. Registro de Decisiones (cerradas — nada queda pendiente)

| ID | Decisión | Cierra |
|----|----------|--------|
| **D1** | Roles canónicos = 6 de BD. Antiguos `ROL_*` son alias históricos | I1 |
| **D2** | Enums logísticos = BD (`EN_RUTA`, `NO_ENTREGADO`). `EN_TRANSITO/FALLIDO` eliminados del vocabulario | I2 |
| **D3** | Funciones reales = `fn_*`; los `rpc_*` de workflows.md son alias documentados | I3 |
| **D4** | **Alta self-service**: registro público crea comercio **ACTIVO** + admin + bonificación 100 créditos (wireframe 02). SuperAdmin conserva SUSPENDER/BLOQUEAR (HU-105/106). Sin estado PENDIENTE en MVP | I4 |
| **D5** | Comprobante inválido ⇒ pedido regresa a `ESPERANDO_PAGO` con `puede_reenviar=true`; CANCELADO solo manual del admin | A9 |
| **D6** | `numero_pedido` identity global (interno); numeración por comercio pospuesta a P2 | A11 |
| **D7** | **Los créditos NO expiran** (coherente con wireframes 15/29). HU-147 = DESCARTADA; valor EXPIRACION reservado en enum | G5 |
| **D8** | Verificación manual: admin o cajero relanza comprobantes RECIBIDO/BLOQUEADO mediante `fn_iniciar_verificacion(forzar)` | I5/HU-141 |
| **D9** | Cola + rate-limiter + circuit breaker son **capa n8n (WF-80)**; la BD aporta opt-out e idempotencia. Implementación fase F7 | G3 |
| **D10** | El comprador jamás tendrá cuenta/app; su identidad es `(id_comercio, telefono_whatsapp)` único | refuerzo |

## 6. Mapa de módulos (fuente canónica de cada dominio)

| Dominio | Documento(s) | Código |
|---|---|---|
| **Este prompt** | `00-Index/00-PROMPT-MAESTRO-RSUELVO.md` | — |
| Arquitectura | `01-Arquitectura/arquitectura-general.md` | Flutter `/mnt/windows/Desktop/Proyectos/Rsuelvo/rsuelvo/` |
| Base de datos | `02-Base-de-Datos/Rsuelvo_Documentacion_Base_de_Datos.md` (ERD) · `07-Control-de-Calidad/Auditoria-SQL-vs-ERD.md` (histórico, resuelto en v2) | **`02-Base-de-Datos/sql/01…12` (v2)** · monolito `_monolito_…_v2.sql` |
| Workflows | `03-n8n/workflows.md` · `Matriz-Consistencia-WF-BD-HU.md` | n8n Cloud |
| Canal WhatsApp | `04-OpenWA/Política Técnica…md` (normativa) · **Guia Meta WhatsApp Business.md** (integración oficial) · `07-Control-de-Calidad/Auditoria-Guia-Meta-Business.md` (histórico) | OpenWA 0.21 / Meta Cloud API |
| UX/UI | `05-Diseño-UX/Wireframes App Móvil.md` · PDF 40 págs · PNGs | Stitch project `1852486780525167950` |
| Control de calidad | `07-Control-de-Calidad/` (auditorías históricas con banner) | — |
| Requisitos | `06-Backlog-HU/01-Backlog…md` (148 HU) · `07-Control-de-Calidad/02-Auditoria-de-Consistencia.md` (histórico) · `03-Correlacion-Wireframes-HU.md` | — |

## 7. Trazabilidad global (cifras certificadas)

```text
32 tablas ── 14 enums ── 36 funciones fn_* ── 47 políticas RLS ── 2 vistas
     ↕                        ↕                                ↕
26 workflows n8n  ↔  148 HU (22 épicas; 147 activas + D7 descartada)  ↔  39 wireframes
     ↕                        ↕                                ↕
 Matriz WF-BD-HU         Correlación WF↔HU                Auditoría SQL-vs-ERD (v2)
```

- Cada pantalla ↔ ≥1 HU y viceversa donde aplica (`03-Correlacion…`).
- Cada WF crítico ↔ exactamente una RPC transaccional (`Matriz-Consistencia…`).
- Cada regla ERD ↔ implementación verificada (`Auditoria-SQL…§2`) y hallazgos A1-A12 resueltos (§6).

## 8. Orden de construcción (fases)

| Fase | Contenido | Módulos/HU |
|------|-----------|------------|
| **F0** | Ejecutar `sql/01…12`; seed; asignar `codigo_tienda`; buckets+cron | E21 completa |
| **F1** | WF-00/01/02/03/04/80 + idempotencia + opt-out | E19, 142-145, D9 |
| **F2** | Compra WhatsApp: WF-10/11/12/13/14 + cron 30/31 | E07, E08, E09 |
| **F3** | Pagos + IA: WF-20/21/22/23/24 + créditos 50/51/52 | E10, E11, 141, 146 |
| **F4** | App dueño núcleo: login/dashboard/productos/inventario/reservas/cobros (wireframes A-F) | E01-E06, E13, E22 |
| **F5** | Logística: WF-40/41/42 + app repartidor (H) + envíos admin (G) | E14 |
| **F6** | Créditos UI + compra paquetes + configuración/usuarios/sucursales (F, I) | E02-E04, E15(cajero) |
| **F7** | Hardening WhatsApp: cola/rate-limit/breaker en WF-80; pruebas de duplicados y caídas | D9, política §30 |
| **F8** (P2) | Panel web SuperAdmin/SysAdmin/Soporte + numeración por comercio | E16-E18 |

## 9. Reglas para IAs que consuman este prompt

1. **Cita IDs** en cada entregable: `HU-xxx` + `WF-xx` + pantalla `WF#` + tabla/fn afectada.
2. El schema canónico es `02-Base-de-Datos/sql/` (v2). **Prohibido inventar** tablas/columnas/funciones fuera de él; si falta algo, proponer migración `03_tables`→`12_cron` correspondiente.
3. Los nombres válidos son los de §4.2 y las `fn_*`; sugerir nuevos requiere entrada en este documento.
4. Cambiar cualquier artefacto exige actualizar su matriz (WF-BD-HU o Correlación) en el mismo commit.
5. Definition of Done de una HU = criterios + prueba de concurrencia/idempotencia cuando aplique + auditoría generándose + wireframe respetado.
6. Español en UI; moneda Bs; tiempos desde config; mensajes WhatsApp agrupados y mínimos (política §7-8).
