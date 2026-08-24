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

| Rol                    | Código               | Alcance             | Permisos Clave                                                                                              |
| ---------------------- | -------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------- |
| Super Admin RSUELVO    | `ROL_SUPERADMIN`     | Global cross-tenant | Gestión de comercios, paquetes de créditos, costos de APIs (WhatsApp/IA), auditoría global                  |
| Admin Comercio (dueño) | `ROL_ADMIN_COMERCIO` | Su `id_comercio`    | Subir QR de pago, sucursales, usuarios, catálogo/SKU/precios, compra de créditos, métricas                  |
| Operador / Cajero      | `ROL_OPERADOR`       | Sus sucursales      | Soporte en el catálogo, consulta de cobros e historial                                                      |
| Agente Logístico       | `ROL_LOGISTICO`      | Rutas asignadas     | Hoja de ruta de entregas, cambios de estado de envío (EN_TRANSITO/ENTREGADO/FALLIDO), firma/foto de entrega |

> El **comprador no tiene cuenta**: interactúa exclusivamente por WhatsApp.
> El QR de pago es **estático y del dueño** (`val_ruta_qr_imagen` en comercio/sucursal);
> RSUELVO no emite QR dinámicos con monto.

## Modelo Multitenant

- Cada **comercio** es un tenant aislado mediante `id_comercio`.
- Supabase aplica **RLS (Row Level Security)** con el patrón canónico `auth.uid()` → `tbl_adm_usuarios.id_comercio` en las 17 tablas `tbl_*` (ver `20260819_rls_auth_uid.sql` y `20260820_produccion_completar.sql`).
- El backend server-side (n8n, futuro .NET 8) puede usar la variable `app.current_id_comercio` para operaciones entre tenants.

## Reglas de Negocio Server-Authoritative

- **Jerarquía de SKU obligatoria** `[3L][1N][1L][3A]` (ej. `FER1H001`) generada y validada por el trigger `trg_generar_validar_sku` en `tbl_com_productos`.
- **Verificación IA ACID**: `fn_procesar_verificacion_ia_atomica()` usa bloqueo pesimista `FOR UPDATE` sobre `tbl_cre_saldos_comercio` para garantizar que el descuento de crédito y el registro de la verificación ocurran sin condiciones de carrera.
- Backend futuro (diseñado): **.NET 8 Web API** con claims JWT: `sub` (usuario), `id_comercio` (tenant), `id_rol`, `cant_creditos`.

## Decisiones de Arquitectura

| Decisión | Motivo |
|---|---|
| Supabase en lugar de MongoDB | RLS nativo, Realtime CDC, JSONB para auditoría |
| n8n como orquestador | Velocidad de implementación, integración visual, nodo Postgres nativo |
| OpenWA en lugar de WhatsApp Business API | Costo cero, mensajes libres sin aprobación de Meta, setup en minutos |
| Flutter solo para dueños/repartidores | El comprador no usa app: todo sucede por WhatsApp |
| Demo Mode en Flutter | Permite desarrollar sin conexión al backend usando `--dart-define=DEMO_MODE=true` |