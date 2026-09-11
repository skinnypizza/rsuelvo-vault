# INTERVENCIÓN SEPARADA — 5 fixes funcionales verificados en JSON live (n8n `rsuelvotest`)

> Alcance: corrección funcional, NO optimización de ejecuciones. Verificados por el orquestador
> contra los grafos publicados. Releer cada workflow antes de tocarlo y publicar al final.
> Reglas: WF-80 no se toca (D9/D11); lógica de negocio solo en `fn_*` (Reglas 2/3); sin `service_role`
> nuevo; citar `HU-xxx` + `WF-xx` en cada cambio y actualizar la Matriz en el mismo acto.

## F1 — WF-24 apunta al workflow equivocado (HU-076,078–081)
- Workflow: `RSU | 24 | Pago | Confirmar Pedido` (`JU4QtP0vkAC7m3n1`, versión `18794c5d`).
- Nodo `Send Confirm via WF-80` (`cb0277a0`): `workflowId.value = 53xUuvoriN3fqvHD` (**WF-22**, extractor OCR)
  → debe ser **`7V6MIPuGbdx9s0lT` (WF-80)**.
- Además el nodo tiene `workflowInputs.value = {}` vacío: mapear las entradas del contrato WF-80
  (`id_comercio, phone, provider, type, text`) desde `Build WF-80 Confirm`, espejando el patrón que
  ya funciona en WF-13 (`Send via WF-80`).

## F2 — WF-24: espacio final en el IF + rama falsa indiscriminada (HU-076)
- Mismo workflow. Nodo `If` (`c9b63011`): `leftValue = "={{ $json.resultado }} "` (espacio final)
  → quitar el espacio. En la misma edición, discriminar la rama falsa: hoy todo lo no
  `PAGO_CONFIRMADO` cae en "reserva vencida"; tipar `YA_PROCESADO`/error técnico vs vencimiento real.

## F3 — WF-24: texto incompatible con OBS-003 (HU-078–081)
- Nodo `Build WF-80 Confirm` (`2dca4623`): el texto pide "Nombre / Dirección / Referencia / Teléfono".
  OBS-003 eliminó la dirección libre (puntos de entrega por sucursal) y WF-25-A ya solicita el nombre.
  → Reducir a aviso de pago verificado + pedido de **nombre de quien recibe** únicamente.
  Coordinar con WF-25-A para un único aviso PAGADO+nombre (sin duplicar mensajes).

## F4 — WF-20: `media_url` con ruta común en vez de por comercio (HU-042,056)
- Workflow: `RSU | 20 | Pago | Generar QR` (`1FYWXdVw2swlFYcg`, versión `7d66e796`).
- Nodo `Generar Cobro (RPC)` construye `.../qr-pagos/<id_comercio>/tienda.png` (correcto, QR estático
  por comercio, Regla de Oro 5), pero `Preparar WF-80 Input` (`a3af7ffc`) envía
  `media_url = .../qr-pagos/tienda.png` (ruta común inexistente).
  → `media_url` debe usar la misma ruta por comercio que el cobro.

## F5 — WF-12: precheck de capacidad/duplicado en n8n (anti-Regla 3) (HU-043,044)
- Workflow: `RSU | 12 | Lista de Espera` (`n9VUH43N8i7s9Rn2`, versión `f5ff4d52`).
- Nodos `Check Lista Espera` (SELECTs directos a `tbl_lista_espera` + `tbl_comercio_config`) e IFs
  `Ya en lista?` / `Capacidad llena?` deciden en n8n antes de llamar a `fn_agregar_lista_espera`.
  → Requiere **migración 41** (la aplica el orquestador): extender `fn_agregar_lista_espera` para que
  imponga máximo por producto y unicidad vigente, devolviendo resultado estructurado
  (`AGREGADO {posicion}` / `YA_EN_LISTA {posicion}` / `LISTA_LLENA`); luego simplificar WF-12 a
  una sola RPC + switch de mensajes. No eliminar los mensajes de usuario en el proceso.

## Criterio de aceptación
Publicar F1–F4 (solo n8n) y dejar F5 en espera de la migración 41; probar reserva→QR (F4),
confirmación automática (F1–F3) y alta en lista (sin regresión) antes de cerrar.
