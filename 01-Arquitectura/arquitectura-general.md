# Arquitectura General — RSUELVO

> **Flujo REAL (2026-08-20):** el comprador compra **por WhatsApp** (envía un SKU, paga el QR de la tienda, reenvía su comprobante). La App Flutter es la herramienta del **dueño de tienda**.

## Diagrama de Alto Nivel



```
┌──────────────────────────────────────────────────────────────┐
│                COMPRADOR (WhatsApp únicamente)               │
│  1. Envía SKU del producto (ej. FER1H001)                    │
│  2. Recibe precio + QR de la tienda por WhatsApp             │
│  3. Paga el QR con su app bancaria → emite comprobante       │
│  4. Reenvía el comprobante por WhatsApp                      │
└──────────────┬───────────────────────────────────────────────┘
               │ WhatsApp
               ▼
┌──────────────────────────────────────────────────────────────┐
│                    OPENWA 0.21.0 (WhatsApp)                  │
│  - Recibe/envía mensajes y medios                           │
│  - Webhook → n8n (SKU entrante / comprobante entrante)      │
│  - Puerto: 8002 / contenedor 127.0.0.1:2785                 │
└──────────────┬───────────────────────────────────────────────┘
               ▼
┌──────────────────────────────────────────────────────────────┐
│                        n8n CLOUD                            │
│  WF4 [NUEVO]: Consulta SKU → responde producto+precio+QR     │
│  WF3 [pend]:  Adaptador OpenWA → WF2                         │
│  WF2: Verificación de comprobante con IA (OCR GPT-4o Vision) │
│    → valida autenticidad, monto coincidente y no-duplicado   │
│    → consume 1 crédito (fn_procesar_verificacion_ia_atomica) │
│    → transacción VERIFICADO/RECHAZADO + crea envío RS-XXXXX  │
└───┬──────────────────────────────────────────────────────────┘
    │
    ├───────────────────────────────┐
    ▼                               ▼
┌─────────────────────┐   ┌──────────────────────────────────┐
│ SUPABASE (prod)     │   │ APP FLUTTER (dueño de tienda)     │
│ PostgreSQL + RLS    │   │ - Sube su QR de pago → `qr-pagos` │
│ (auth.uid()→comercio│   │ - Carga catálogo/SKU/precios      │
│  combo)             │   │ - Ve métricas, créditos, envíos   │
│ Realtime            │   └──────────────────────────────────┘
└─────────────────────┘
```

## Roles del Sistema (RBAC)

> **Congelado (Auditoría I1, 2026-08-24):** canónicos = los **6 roles** de `tbl_roles`/`rol_codigo` en el schema SQL. Mapeo desde los antiguos `ROL_*`: SUPERADMIN→SUPERADMIN · ADMIN_COMERCIO→TENANT_ADMIN · OPERADOR→TENANT_CASHIER · LOGISTICO→LOGISTICS_AGENT. SYSADMIN y SUPPORT siempre existieron en BD/matriz; se restauran aquí.

| Rol                     | Código canónico        | Alcance             | Permisos clave                                                                                              |
| ----------------------- | ---------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------- |
| Super Admin RSUELVO     | `ROLE_SUPERADMIN`      | Global cross-tenant | Gestión de comercios, paquetes de créditos, costos de APIs (WhatsApp/IA), auditoría global                  |
| SysAdmin                | `ROLE_SYSADMIN`        | Infraestructura     | Logs, monitoreo, parámetros globales. **Sin** acceso a saldos/cuentas/datos sensibles de tenants            |
| Soporte                 | `ROLE_SUPPORT`         | Solo lectura        | Diagnóstico de operaciones del comercio; sin acceso financiero sensible                                     |
| Admin Comercio (dueño)  | `ROLE_TENANT_ADMIN`    | Su `id_comercio`    | Subir QR de pago, sucursales, usuarios, catálogo/SKU/precios, compra de créditos, métricas                  |
| Operador / Cajero       | `ROLE_TENANT_CASHIER`  | **Una** sucursal    | Cobros QR, consulta de comprobantes/cobros/historial, inventario en lectura                                 |
| Agente Logístico        | `ROLE_LOGISTICS_AGENT` | Rutas asignadas     | Hoja de ruta, cambios de estado de envío (`EN_RUTA`/`ENTREGADO`/`NO_ENTREGADO`), firma/foto/GPS de entrega   |

> El **comprador no tiene cuenta**: interactúa exclusivamente por WhatsApp.
> El QR de pago es **estático y del dueño** (`val_ruta_qr_imagen` en comercio/sucursal);
> RSUELVO no emite QR dinámicos con monto.

## Modelo Multitenant

- Cada **comercio** es un tenant aislado mediante `id_comercio`.
- Supabase aplica **RLS (Row Level Security)** con el patrón canónico `auth.uid() → tbl_usuarios.auth_user_id → tbl_usuario_comercio.id_comercio` en las 29 tablas `tbl_*` (implementado en `sql/08_rls.sql`; migraciones históricas: `20260819_rls_auth_uid.sql`, `20260820_produccion_completar.sql`).
- El backend server-side (n8n, futuro .NET 8) puede usar la variable `app.current_id_comercio` para operaciones entre tenants.

## Reglas de Negocio Server-Authoritative

- **Jerarquía de SKU obligatoria** `[3L][1N][1L][3A]` (ej. `FER1H001`) validada por el trigger `trg_validar_sku_variante_comercio` en `tbl_variantes` (unicidad por comercio; ver Auditoría SQL A1 para endurecimiento recomendado).
- **Verificación IA ACID**: el consumo de créditos es atómico con bloqueo pesimista `FOR UPDATE` sobre `tbl_cuentas_creditos` (`fn_consumir_creditos`). ⚠️ La función combinada `fn_procesar_verificacion_ia_atomica()` citada previamente **no existe aún en el schema** — ver Auditoría SQL A3.
- Backend futuro (diseñado): **.NET 8 Web API** con claims JWT: `sub` (usuario), `id_comercio` (tenant), `id_rol`, `cant_creditos`.
- **Fuente canónica del schema:** `/home/nico/rsuelvo/sql/01…12` (+ copia en [[Rsuelvo_Documentacion_Base_de_Datos]] → `sql/`). Convención congelada (I3): funciones internas ACID = `fn_*`; los `rpc_*` del doc de workflows son alias conceptuales de las mismas.

## Decisiones de Arquitectura

| Decisión | Motivo |
|---|---|
| Supabase en lugar de MongoDB | RLS nativo, Realtime CDC, JSONB para auditoría |
| n8n como orquestador | Velocidad de implementación, integración visual, nodo Postgres nativo |
| OpenWA en lugar de WhatsApp Business API | Costo cero, mensajes libres sin aprobación de Meta, setup en minutos |
| Flutter solo para dueños/repartidores | El comprador no usa app: todo sucede por WhatsApp |
| Demo Mode en Flutter | Permite desarrollar sin conexión al backend usando `--dart-define=DEMO_MODE=true` |