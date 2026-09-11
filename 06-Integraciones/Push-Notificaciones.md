# Push notifications — RSUELVO (app staff, FCM)

> Decisión del dueño 2026-09-11: v1 con 6 eventos; teléfono del comprador SOLO para
> `ROLE_TENANT_ADMIN`; sin horario silencioso. Sin n8n (D11 intacto: esto es push de app).

## Catálogo v1

| # | Evento (`motivo`) | Disparador BD | Destinatarios | Título / Cuerpo |
|---|---|---|---|---|
| 1 | `reserva_nueva` | `trg_reserva_push` (INSERT reserva ACTIVA) | ADMIN+CAJERO sucursal | Nueva reserva / `SKU {sku} en {sucursal}` |
| 2 | `comprobante_recibido` | `trg_push_comprobante` (INSERT comprobante) | ADMIN+CAJERO sucursal del pedido | Comprobante para revisar / `Pedido {id8} · {sku}` |
| 3 | `reserva_por_vencer` | cron `rsuelvo_push_por_vencer` (banda 60–120s) | ADMIN+CAJERO sucursal | Reserva por vencer / `SKU {sku} vence en ~2 min` |
| 4 | `envio_asignado` | `trg_push_envio` (→ASIGNADO) | repartidor asignado + ADMIN comercio | Envío asignado / `Pedido {id8} → {ciudad}` |
| 5 | `stock_bajo` | `trg_push_stock` (cruce a disponible≤5) | ADMIN comercio + CAJERO sucursal | Stock bajo/agotado / `SKU {sku} en {suc}: quedan {N}` |
| 6a | `pago_confirmado` | `trg_push_pedido` (→PAGADO) | ADMIN comercio | Pago confirmado / `Pedido {id8} · {sku}` |
| 6b | `entrega_completada` | `trg_push_envio` (→ENTREGADO) | ADMIN comercio | Entrega completada / `Pedido {id8} en {ciudad}` |

**Teléfono del comprador**: se anexa (` · {phone}`) SOLO en textos a ADMIN.
**Payload `data`** (tap-to-screen): `{motivo, id_comercio, ...ids del caso}`.
**Reenvío de comprobante** (UPDATE) no dispara evento 2 en v1 — seguimiento futuro.
**Banda por-vencer** ≈1 tick normal de cron; doble aviso ocasional aceptado en v1.

## Arquitectura

```text
triggers AFTER no-mutantes (m46/m47) ──pg_net──▶ EF `notificar-reserva-sucursal` v2
   (despachadora por motivo; secreto x-webhook-secret; FCM v1; baja de inválidos)
```

- Secreto en `supabase_vault` (`rsuelvo_push_webhook_secret`) + secreto de entorno EF.
- El push jamás bloquea (EXCEPTION-swallow en triggers; EF fail-closed 401/503).
- **No interferencia n8n**: ninguna `fn_*` existente modificada; triggers coexisten con
  audit/tenant/updated_at y con `trg_pedido_pagado_notifica`/`trg_envio_estado_notifica`;
  cron job nuevo; misma slug de EF (n8n no la llama).
- Tablas: `tbl_dispositivos_push` (m45, RLS solo-propios, registro vía EF con JWT).
