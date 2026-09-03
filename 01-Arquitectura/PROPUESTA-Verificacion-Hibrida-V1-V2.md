# D13/D14 — Verificación Híbrida (Cajero) y Créditos por Venta

> **Estado:** ✅ OFICIAL — aprobado por el dueño (2026-09-02). Registrado como **D13** y **D14** en PROMPT MAESTRO §5 (v1.5). Regla de Oro 4 reformulada.
> **Fecha:** 2026-09-02 · **Origen:** análisis con el dueño (responsabilidad del OCR) · **Autor:** orquestador opencode

---

## 1. Contexto y motivación

- **Riesgo de responsabilidad del OCR:** caso real en pruebas — Gemini extrajo `amount: 170` con confianza 0.99 para un producto de 180 Bs y lo habría confirmado. Con verificación IA, un falso positivo es responsabilidad de RSUELVO. Con cajero, el juicio es del comercio (su empleado) y el nuestro se reduce a proveer la herramienta con trazabilidad (`usuario_id` en auditoría).
- **Costo operativo:** Gemini por recibo desaparece del camino crítico en V1.
- **Posicionamiento:** V1 dirigido a **comercios de bajo tráfico** (verificación humana); V2 abre **API de pagos QR + verificación automática** para alto tráfico.

## 2. Decisiones adoptadas (pendientes de oficializar)

| ID | Decisión | Consecuencia |
|---|---|---|
| **D-A** | Verificación **híbrida**: la IA extrae datos (pre-llena), el **cajero confirma** | El OCR deja de decidir; WF-23 (decide IA) queda solo para el modo automático |
| **D-B** | Toggle **por comercio** | La columna `tbl_comercio_config.verificacion_automatica` (ya existe desde F0) gobierna el branch |
| **D-C** | Verifica el **cajero** (rol existente, 1 sucursal) | RLS por sucursal para la cola de comprobantes |
| **D-D** | **Realtime** para la cola del cajero | Supabase Realtime (ya disponible); Push FCM queda para F6 |
| **D-E** | **Créditos por VENTA**: cada `PAGO_CONFIRMADO` consume 1 crédito del comercio | Cambio de modelo de negocio (ver §4) |
| **D-F** | Consecuente de D-A | WF-22 pasa a rol de asistente (pre-llenado), no decisor |
| **D-G** | Reformula Regla de Oro 4: **"La IA (opcional) extrae; el humano o el backend decide"** | En modo manual el backend sigue decidiendo vía fn_* (Regla 2 intacta) |
| **D-H** | El comprador ya recibe ack ("Hemos recibido tu comprobante…") | Sin cambios |

## 3. Sub-decisiones que surgen (requieren confirmación del dueño)

| ID | Sub-decisión | Recomendación |
|---|---|---|
| **SD-1** | ✅ APROBADO — ¿Qué pasa con el saldo de créditos en 0 al confirmar una venta? | **La venta NUNCA se bloquea** (el dinero del comprador ya está). El crédito se consume y el saldo puede quedar negativo; el cobro/recargo es facturación, no un bloqueo del flujo. El bloqueo comercial (p.ej. no recibir nuevos SKUs con paquete vencido) sería un mecanismo separado a diseñar |
| **SD-2** | ✅ APROBADO — ¿Es renombrar CONSUMO_VERIFICACION? **No: se AGREGA** `CONSUMO_VENTA` (nuevo valor; `CONSUMO_VERIFICACION` se conserva para V2 automático). Registrado en `CONSUMO_VENTA` en `tipo_movimiento_credito` (reutilizar CONSUMO_VERIFICACION sería confuso). Requiere migración |
| **SD-3** | ✅ APROBADO — ¿V1 incluye el OCR-asistente? | **Sí (híbrido)**: Gemini pre-llena monto/operación/pagador y el cajero compara. Falla el OCR → el cajero completa a mano. Si el costo Gemini preocupara a bajo tráfico, sería un toggle más — pero a bajo volumen es mínimo |
| **SD-4** | ✅ APROBADO COMO **DECISIÓN V2** — no contemplada en el MVP; Regla de Oro 5 queda INTACTA hasta V2. Contexto: **V2 (API QR) chocará con la Regla de Oro 5** ("RSUELVO no emite QR dinámicos") | Reformular: el QR dinámico lo **emite la pasarela/banco vía su API** (no RSUELVO), la confirmación llega por **webhook de la pasarela** y matchea la referencia del cobro → confirmación automática sin IA. Regla 5 se actualiza a: *"RSUELVO no genera códigos de pago propios; si el comercio usa pasarela, el QR la emite la pasarela"* |
| **SD-5** | ✅ APROBADO — ¿Los rechazos del cajero consumen crédito? | **No** — solo ventas confirmadas |
| **SD-6** | ✅ APROBADO — ¿Las ventas por aceptación de lista de espera también consumen? | **Sí** — todo `PAGO_CONFIRMADO` consume (uniforme) |

## 4. Flujo V1 — Híbrido (cajero, comercios de bajo tráfico)

```
Comprador envía comprobante
  → WF-21: registrar comprobante (RECIBIDO) + ack al comprador
  → IF tbl_comercio_config.verificacion_automatica = false:
       → FIN n8n (queda archivado en Storage, estado RECIBIDO)
       → Supabase Realtime avisa a la app del cajero
  → [APP — Cajero de la sucursal]
       Cola: comprobantes RECIBIDO de su sucursal (Realtime/polling)
       Detalle: imagen + datos pre-llenados por OCR-asistente (SD-3)
       → [VERIFICAR]  → RPC fn_confirmar_pago(id_verificacion, {manual:true})
                          → consume 1 crédito (CONSUMO_VENTA, SD-2)
                          → pedido PAGADO + reserva CONFIRMADA + VENTA
       → [RECHAZAR]   → RPC fn_rechazar_verificacion → comprador reenvía
  → Pedido PAGADO → F5: datos de entrega → envío
```

## 5. Flujo V2 — Automático (alto tráfico + API QR)

```
Comprador escanea QR DINÁMICO de la pasarela (SD-4)
  → Pasarela confirma el pago → webhook a n8n
  → match referencia/cobro → fn_confirmar_pago automático (sin IA, sin humano)
  → Venta + consumo crédito → F5 directo

Comprador envía comprobante manual (fallback)
  → WF-21 → verificacion_automatica = true → WF-22 OCR → WF-23 decide IA
  → CONFIRMAR → fn_confirmar_pago (como hoy) · confianza baja → cola del cajero
```

## 6. Impacto por componente

| Componente | V1 híbrido | V2 automático |
|---|---|---|
| WF-02/03/04/10/12/13/14/20/80 | Sin cambios ✓ | Sin cambios ✓ |
| WF-21 | Branch por `verificacion_automatica`; sin WF-22/23 en manual | Igual que hoy (OCR → WF-23) |
| WF-22 (Gemini) | Asistente: pre-llena datos del cajero | Decide (como hoy) |
| WF-23 (decide IA) | Solo actúa en automático (archivado en manual) | Activo |
| WF-24 | Se reemplaza por botones de la app (RPC directo) | Como hoy |
| `fn_confirmar_pago` | +1 paso: consumo CONSUMO_VENTA (misma transacción, Regla 2) + atribución `usuario_id` (cajero vía JWT) | Ídem |
| Créditos | Por venta (SD-1/2) | Por venta + por verificación IA |
| App cajero | **Nueva** (cola Realtime + detalle + botones) | Ídem (fallback) |
| F5 logística | Post-confirmación, común | Ídem |

## 7. Backlog de construcción V1 (orden propuesto)

1. **Migración 27**: enum `CONSUMO_VENTA` · servicio `VERIFICACION_MANUAL` (costo 0, tipo manual) · `fn_confirmar_pago` consume 1 crédito por venta (misma transacción) + audit con `usuario_id` del cajero · RLS cola de comprobantes por sucursal
2. **WF-21**: branch `verificacion_automatica` (false → ack + fin; true → OCR/WF-23 como hoy)
3. **App Flutter (cajero)**: wireframes cola + detalle + botones (F4) → Realtime
4. **F5**: datos de entrega + envíos (post-`PAGADO`, común a ambos modos)
5. **V2 (después)**: pasarela QR (SD-4) + webhook de pasarela + modo automático para alto tráfico

## 8. Qué NO cambia (esqueleto ya validado E2E)

- WF-02/03/04/10/12/13/14/20/80 · `fn_confirmar_pago` con guardas (22/25) · anti-duplicado · lista de espera event-driven · storage de comprobantes · el ack al comprador

## 9. Preguntas abiertas

1. ¿SD-1 (saldo negativo permitido) aprobado? — afecta facturación
2. ¿SD-2 (nuevo enum CONSUMO_VENTA) aprobado?
3. ¿SD-4 (Regla 5 reformulada para V2) aprobado?
4. ¿La bonificación de bienvenida (100 créditos) pasa a significar "100 ventas gratis"? — posicionamiento/precios
5. ¿El cajero puede verificar comprobantes de CUALQUIER pedido de su sucursal, o solo los de clientes que él/la sucursal atendió? (RLS scope)


---

## 10. Plan de desarrollo V1 (aprobado en orden)

1. **Migración 27** (próxima sesión): enum `CONSUMO_VENTA` · servicio `VERIFICACION_MANUAL` (costo 0) · consumo de crédito en `fn_confirmar_pago` (misma transacción, SD-1 saldo negativo permitido) · atribución `usuario_id` del cajero
2. **WF-21**: branch `verificacion_automatica` (false → ack + fin; true → OCR/WF-23 como hoy)
3. **App Flutter (F4)**: wireframes cola de comprobantes + detalle + botones (cajero) → Realtime
4. **F5**: datos de entrega + envíos (post-PAGADO)
5. **V2** (no MVP): pasarela QR (requerirá reformular Regla de Oro 5, SD-4) + modo automático
