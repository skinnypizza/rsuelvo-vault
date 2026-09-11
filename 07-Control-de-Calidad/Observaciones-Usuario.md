# Observaciones y Sugerencias del Usuario — RSUELVO

> **Propósito:** Registro vivo de observaciones, sugerencias y requerimientos del usuario sobre el producto.
> **Fuente de verdad:** [[00-PROMPT-MAESTRO-RSUELVO]] v1.4-FINAL
> **Regla:** Cada observación se evalúa contra decisiones cerradas (D1-D12) y se clasifica antes de implementar.

---

## 📋 Instrucciones de Uso

### Formato por observación

```markdown
### OBS-XXX: [Título corto]
- **Categoría:** Funcional | UX | Regla de Negocio | Seguridad | Técnico | Logística | Monetización | Legal | Futuro
- **Sección afectada:** §X.X / WF-XX / Pantalla X / Tabla/fn_
- **Descripción:** [Qué observas o sugieres]
- **Propuesta de solución:** [Cómo lo resolverías, si tienes idea]
- **Impacto:** 🔴 Alto | 🟡 Medio | 🟢 Bajo
- **Bloquea construcción:** Sí | No
- **Estado:** ⬜ Pendiente | 🔄 En evaluación | ✅ Aceptada | ❌ Rechazada | 📦 P2 (futuro)
- **Resolución:** [Cuando se cierre] Decisión tomada + justificación
```

### Clasificación automática

| Si la observación es... | Se clasifica como... |
|-------------------------|----------------------|
| Corrección de algo existente | 🔧 Bug / Fix |
| Nueva funcionalidad en alcance actual | ✨ Enhacement |
| Funcionalidad fuera de fase actual | 📦 P2 (backlog) |
| Cambio de regla de negocio | ⚖️ Decisión (requiere D-nueva) |
| Mejora visual/UX | 🎨 UX |
| Riesgo de seguridad/fraude | 🔒 Seguridad |

---

## 📝 Observaciones Registradas

---

### OBS-001: Pregunta de confirmación para lista de espera
- **Categoría:** UX / Regla de Negocio
- **Sección afectada:** WF-12 (Lista de Espera) · WF-13 (Notificar Lista) · `fn_agregar_lista_espera` · HU-043/045
- **Descripción:** Cuando un producto está reservado o sin stock, el sistema agrega automáticamente al comprador a la lista de espera sin preguntar. El usuario sugiere incluir una pregunta al comprador para confirmar si desea continuar en la lista o ser removido, permitiendo que los siguientes compradores suban de posición.
- **Flujo actual:**
  ```
  SIN_STOCK → WF-12 agrega automáticamente → WF-13 notifica posición
  ```
- **Flujo propuesto:**
  ```
  SIN_STOCK → Pregunta "¿Deseas entrar a la lista de espera?"
      ├── SÍ → WF-12 agrega → WF-13 notifica posición
      └── NO → No se agrega / Se remueve de la lista
  ```
- **Propuesta de solución:**
  1. Modificar WF-10 para que en la rama `SIN_STOCK` envíe un mensaje preguntando al comprador si desea entrar a la lista de espera (similar al flujo de WF-13 con "Responde SI/NO")
  2. Crear WF-12-V2 o modificar WF-12 para que solo agregue cuando el comprador confirme "SI"
  3. Agregar opción de "NO" / "SALIR" en WF-13 cuando se notifica la oportunidad (actualmente solo procesa "SI")
  4. Crear función `fn_cancelar_lista_espera(id_lista_espera)` o usar `fn_aceptar_lista_espera` con estado `RECHAZADO`
- **Impacto:** 🟡 Medio
- **Bloquea construcción:** No
- **Estado:** 🔄 En evaluación
- **Resolución:** *(pendiente)*
- **Opción seleccionada:** **C** (preguntar al entrar + opción de salir al notificar) — registrada como sugerencia del usuario el 2026-09-06.

#### Análisis de impacto

| Artefacto | Cambio requerido |
|-----------|------------------|
| **WF-10** | Rama `SIN_STOCK` → enviar mensaje de confirmación antes de agregar |
| **WF-12** | Ya no se llama directamente desde WF-10; se invoca solo tras confirmación "SI" del comprador |
| **WF-13** | Agregar rama "NO" / "SALIR" para remover de lista y subir posiciones |
| **WF-14** | Actualmente solo procesa "SI"; podría extenderse para manejar "NO" también |
| **`fn_cancelar_lista_espera`** | Nueva función para marcar como `RECHAZADO` y liberar posición (alternativa: reusar estados existentes) |
| **tbl_lista_espera** | Sin cambios estructurales (el enum ya tiene `RECHAZADO` y `CANCELADO`) |

#### Alternativas

| Opción | Descripción | Pros | Contras |
|--------|-------------|------|---------|
| **A** | Pregunta al entrar a lista (antes de WF-12) | El comprador decide desde el inicio | Un paso más antes de confirmar reserva |
| **B** | Pregunta al notificar oportunidad (WF-13) | El comprador ya sabe su posición | Ya está agregado; remover es más complejo |
| **C** ✅ **SELECCIONADA** | Ambas: preguntar al entrar + opción de salir al notificar | Máxima flexibilidad y control de posiciones | Más complejidad en n8n |

#### 🅰️+C — Detalle de la Opción C (seleccionada)

**Momento 1 — Cuando el producto NO tiene stock (entrada a lista):**
```
SIN_STOCK → WF-10 pregunta "¿Quieres que te avisemos cuando haya stock? Responde SI/NO"
    ├── SI → WF-12 agrega a la lista (posición N) → "Estás en la posición #N"
    └── NO → No se agrega nada → fin
```
**Propósito:** Evitar "lista de espera basura". Solo entran interesados reales.

**Momento 2 — Cuando llega su turno (notificación de oportunidad):**
```
WF-13 notifica "¡Ya hay stock! Tienes 2 minutos. Responde SI/NO"
    ├── SI  → WF-14 reserva (sale de lista) → QR de pago
    ├── NO  → Se marca RECHAZADO → siguiente sube de posición → WF-13 notifica
    └── (no responde) → VENCIDO al vencer ventana → siguiente sube de posición
```
**Propósito:** Aquí se produce el **desplazamiento de posiciones**. Si alguien dice NO o deja vencer su turno, el siguiente comprador sube automáticamente.

**Ejemplo real:**
```
1) 3 personas piden el mismo producto agotado:
   - Ana: "SI" → posición #1
   - Beto: "SI" → posición #2
   - Carlos: "NO" → no entra (sin Momento 1, estaría en #3)

2) Llega stock: WF-13 notifica a Ana (pos #1) → Ana: "NO" → RECHAZADO → turno liberado

3) Beto sube de #2 → #1 → WF-13 lo notifica automáticamente → "SI" → reserva → QR
```

**Cambios en n8n:**
| Workflow | Cambio |
|----------|--------|
| **WF-10** | Rama `SIN_STOCK` → pregunta SI/NO (Momento 1), no agregar directo |
| **WF-12** | Solo se invoca si el comprador responde "SI" |
| **WF-04** | Reconocer "NO"/"SALIR" como declinación, no como texto libre |
| **WF-13** | Confirmar desplazamiento (siguiente sube) vía `fn_notificar_siguiente_lista_espera` + `VENCIDO` |
| **WF-14** | Rama "NO" → `RECHAZADO` → WF-13 notifica al siguiente |

**BD:** sin cambios estructurales (enum ya tiene `RECHAZADO`/`VENCIDO`/`CANCELADO`; `fn_notificar_siguiente_lista_espera` usa `SKIP LOCKED`).

> **Estado implementación (2026-09-08):** **Momento 1 ✅ y Momento 2 ✅ implementados, publicados y validados E2E.**
> - **Momento 2** (turno notificado): SI→reserva+QR / NO→turno liberado+siguiente sube (WF-04 or-dispatch + WF-14 Parse Decision, m31/m32).
> - **Momento 1** (SIN_STOCK, m35): WF-10 pregunta *"¿te avisamos cuando haya stock? SI/NO"* (estado en `tbl_lista_pendiente`, `fn_pendiente_lista`) → SI→WF-12 agrega vía `fn_aceptar_pendiente_lista` (guarda `YA_EN_LISTA` evita duplicados) → NO→`fn_rechazar_pendiente_lista`. Desambiguación SI/NO automática en WF-14: oportunidad primero, pendiente después.

---

### OBS-002: Formato y redacción de los mensajes de reserva y lista de espera
- **Categoría:** UX
- **Sección afectada:** WF-10 (mensaje reserva creada) · WF-12/13 (mensajes lista de espera) · §22/§26-28 de `workflows.md`
- **Descripción:** El comprador recibe mensajes que pueden mejorarse en formato y claridad. Hay 3 puntos:
  1. **Mensaje de reserva creada (cuando envía SKU con stock):** debe tener un formato claro con: aviso de reserva confirmada, SKU, descripción de la variante del producto, monto, vigencia y mención del envío de comprobante para verificación.
  2. **Mensaje de lista de espera (Momento 2):** actualmente llega un texto ambiguo tipo *"ese producto ya está reservado o sin stock"*. Solo se debería mostrar la opción de "producto reservado" (no la de "sin stock"). Formato propuesto: *"Producto ya reservado, estás en lista de espera, posición #N, te avisaremos cuando esté disponible."*
  3. **Mensaje de oportunidad disponible (cuando se notifica al siguiente comprador):** formato propuesto: *"SKU, descripción de la variante del producto, monto, tienes 10 minutos para aceptar la reserva, responde SI para aceptar y NO para liberar la oportunidad."* (Nota: el tiempo debe venir de `tiempo_aceptacion_lista_espera_minutos`, no hardcodeado — Regla de Oro 10).
- **Propuesta de solución:**
  1. Reformatear el "Build Output" de WF-10 para el mensaje de reserva creada (aviso + SKU + variante + monto + vigencia + aviso de envío de comprobante).
  2. Corregir el texto de WF-12 (lista de espera) para que diga "producto ya reservado, posición #N" y quite la mención ambigua a "sin stock".
  3. Reformatear el mensaje de WF-13 (notificación de oportunidad) con SKU + variante + monto + tiempo configurable + instrucción SI/NO explícita.
- **Impacto:** 🟢 Bajo (cambio de texto/UX, no de lógica de negocio)
- **Bloquea construcción:** No
- **Estado:** 🟡 En validación (test 2026-09-08) — WF-12 ✅ y WF-13 ✅ validados; **WF-20 resuelto: campo "Referencia" eliminado del mensaje con QR** (v `7599e6c9`, verificado en E2E 2026-09-08); WF-10 ya no envía mensaje duplicado (unificado en WF-20).
- **Resolución:** reformateados los 3 mensajes según propuesta (Claude/n8n: WF-10 v`332bd37d`, WF-12 v`eb06f845`, WF-13 v`5632aa56`). Fix adicional hallado en producción: bloques jsCode duplicados en WF-10 ocultaban el cálculo de `hora_expiracion` (placeholder `[HH:MM]` salía vacío) — corregido con `DateTime.fromISO(...).setZone('America/La_Paz')`; misma corrupción (parameters anidados duplicados) reparada en WF-12/WF-13. WF-13 ya traía el lookup de variante + config (`tiempo_aceptacion_lista_espera_minutos`), sin hardcodeo (Regla 10).

#### Resultado del test de validación (2026-09-08)

| Mensaje | Estado |
|---------|--------|
| **WF-10** — Respuesta al SKU (reserva confirmada) | ⚠️ **Persiste campo "Referencia"** — no estaba en la propuesta OBS-002 (origen probable: caption del QR en WF-20 o línea residual en WF-10). Requiere quitarse. |
| **WF-12** — Primer mensaje lista de espera | ✅ **CUMPLE** — "📋 Producto ya reservado / Posición: #N", sin ambigüedad |
| **WF-13** — Notificación al primero de la lista | ✅ **CUMPLE** — "🎯 ¡Ya está disponible!" con sku/variante/monto/minutos + SI/NO |

**Acción pendiente:** localizar y eliminar el campo `Referencia` del texto que recibe el comprador al enviar SKU (revisar WF-10 "Build Mensaje Reserva Confirmada" y WF-20 "Preparar WF-80 Input" / caption del QR). La propuesta OBS-002 para este mensaje sólo contempla: aviso ✅, Producto, SKU, Monto, Vigencia y mención del comprobante.

#### Detalle de mensajes propuestos

**1. Mensaje de reserva creada (WF-10):**
```
✅ Reserva confirmada

Producto: [Descripción de la variante]
SKU: [SKU]
Monto: Bs [precio]

Tu reserva tiene vigencia hasta: [HH:MM].
Envía el comprobante de tu pago por este chat para verificarlo y confirmar tu
reserva.
```

**2. Mensaje de lista de espera (WF-12) — Momento 1/2:**
```
📋 Producto ya reservado

Estás en lista de espera.
Posición: #N

Te avisaremos cuando esté disponible.
```

**3. Mensaje de oportunidad disponible (WF-13) — notificación al siguiente:**
```
🎯 ¡Ya está disponible!

Producto: [Descripción de la variante]
SKU: [SKU]
Monto: Bs [precio]

Tienes [tiempo_aceptacion_lista_espera_minutos] minutos para aceptar la reserva.
Responde SI para aceptar y NO para liberar la oportunidad.
```

> Los tiempos (`[HH:MM]`, `[minutos]`) deben venir de `tbl_comercio_config` (`tiempo_reserva_minutos`, `tiempo_aceptacion_lista_espera_minutos`), no hardcodeados (Regla de Oro 10).

---

### OBS-003: Puntos de entrega/envío configurables por sucursal y selección guiada por el comprador
- **Categoría:** Funcional / Logística
- **Sección afectada:** `tbl_sucursales` · `tbl_puntos_entrega` (nueva) · `tbl_transportadoras` (nueva) · `tbl_envios` · WF-25-A/B (solicitud y registro de datos de entrega) · Pantalla envíos
- **Descripción:** Las tiendas con las que trabajaremos tienen **puntos de entrega y envío establecidos por ciudad**. El comprador **siempre elige un punto** al entrar al flujo de envío; **no existe entrega a domicilio ni dirección libre**. Los envíos a otras ciudades se hacen mediante **empresas de transporte ajenas**, cuyas **sucursales en cada ciudad** son el punto de entrega.
- **Aclaraciones del usuario (2026-09-07):**
  1. El comprador **siempre elige un punto** de entrega/envío (no hay dirección libre ni envío a domicilio).
  2. El envío es **por cobrar (contra entrega)**: los costos de envío son **ajenos a RSUELVO** y pasan directamente a las transportadoras. RSUELVO **no cobra ni muestra el costo** de envío — la transportadora gestiona su propia tarifa al entregar.
  3. Los puntos de entrega están **asociados a una sucursal** (cada sucursal tiene su propio catálogo de puntos).
  4. Consecuencia de (2): no hay cobro de envío ni comprobante adicional dentro de RSUELVO.
- **Flujo actual (WF-25-A/B):**
  ```
  Pedido PAGADO → WF-25-A pide NOMBRE:/DIRECCIÓN:/REFERENCIA:/TELÉFONO:
  → comprador responde texto libre → fn_registrar_entrega
  ```
- **Flujo propuesto (reemplaza el actual):**
  ```
  Pedido PAGADO → WF-25-A pregunta nombre
  → WF-25-B muestra las OPCIONES de la sucursal (catálogo configurado):
       1. Retiro en tienda/sucursal (misma ciudad)
       2. Punto de entrega local de la ciudad [nombre del punto]
       3. Envío a otra ciudad vía [transportadora] → [sucursal/ciudad destino]
  → comprador elige opción (número)
  → [si ENVIO_TRANSPORTE] se confirma la ciudad/sucursal destino
  → se crea el envío (RSUELVO registra el punto elegido, sin costo de envío)
  → la transportadora cobra al destinatario por fuera de RSUELVO
  ```
- **Diseño de datos (propuesta):**
  1. **Tabla `tbl_puntos_entrega`** (catálogo POR SUCURSAL):
     | Campo | Descripción |
     |-------|-------------|
     | `id_punto_entrega` | PK |
     | `id_sucursal` | FK → `tbl_sucursales` (obligatorio — puntos por sucursal) |
     | `tipo` | `RETIRO_EN_TIENDA` \| `PUNTO_LOCAL` \| `ENVIO_TRANSPORTE` |
     | `nombre` | Nombre visible del punto (ej: "Oficina Central" / "Envío Cbba") |
     | `ciudad` | Ciudad del punto (destino si es transporte) |
     | `direccion` | Dirección del punto |
     | `referencia` | Referencia / horarios |
     | `id_transportadora` | FK → `tbl_transportadoras` (solo si `ENVIO_TRANSPORTE`) |
     | `activo` | Visible para el comprador |
     | `orden` | Para mostrar las opciones ordenadas |
     > **Sin `costo`**: el envío es por cobrar y el costo pertenece a la transportadora, no a RSUELVO.
  2. **Tabla `tbl_transportadoras`** (empresas de envío externas):
     | Campo | Descripción |
     |-------|-------------|
     | `id_transportadora` | PK |
     | `nombre` | Nombre de la empresa (ej: "Expreso Bolívar") |
     | `ciudades` | Ciudades donde opera |
     | `activo` | — |
  3. **`tbl_envios`** — agregar FK `id_punto_entrega` y enlazar el envío al punto elegido:
     - `direccion`/`referencia` pasan a registrarse desde el punto seleccionado (se pueden conservar como denormalización para la hoja de ruta del repartidor)
     - Para `ENVIO_TRANSPORTE`, `numero_guia` documenta el seguimiento externo (ya soportado por la máquina de estados `EN_RUTA`/`ENTREGADO`)

- **Impacto:** 🔴 Alto (requiere esquema BD nuevo + rediseño de WF-25-A/B)
- **Bloquea construcción:** Parcialmente (afecta F5/F4 envíos; no bloquea flujo de reserva/pago)
- **Estado:** ✅ Implementada — **BD ✅ m33** · **n8n ✅ 2026-09-08** (WF-25-A/B guiado por puntos + reglas WF-04, validado E2E: menú con horarios, ciudad/zona, envío Beni) · **Wireframes ⬜ gradual** · **App Flutter ⬜ (F4/Antigravity)**
- **Resolución:** *(en curso)*

#### Notas
- La selección de puntos debe respetar la Regla de Oro 3 (n8n orquesta, BD decide): el catálogo de puntos vive en BD y se expone vía `fn_*`/RPC (ej. `fn_listar_puntos_entrega(id_sucursal)`); n8n solo muestra las opciones y captura la elección.
- Este cambio **elimina** la captura de dirección libre de WF-25-B y la reemplaza por selección guiada (respuesta numérica → se resuelve el punto en BD).
- No se cobra envío: el comprador paga solo el producto vía QR (RSUELVO); la transportadora cobra aparte al destinatario.

#### Decisiones de diseño cerradas (2026-09-07)
1. **El repartidor (ROLE_LOGISTICS_AGENT) sobrevive**: es quien lleva los productos a los puntos de entrega (incl. despachar a la transportadora).
2. **Saltos de estado permitidos**: la máquina de `fn_actualizar_estado_envio` se amplía para permitir transiciones directas (ej. `PREPARANDO→ENTREGADO` en retiro/punto, sin ASIGNADO/EN_RUTA).
3. **ENVIO_TRANSPORTE**: la tienda despacha el paquete a la transportadora y **registra `numero_guia` al entregarlo** (la transportadora lo recoge/despacha y cobra al destinatario por fuera de RSUELVO).
4. **Wireframes**: se rediseñan gradualmente (pantalla de envío + app repartidor; no bloquea la migración 33).

> **Actualización 2026-09-08:** rewrite n8n ✅ completado (WF-25-A/B guiado por puntos + reglas WF-04, ver bitácora) — queda wireframe gradual y app Flutter.

---

### OBS-004: Foto de guía (transportadora) o código de retiro (paquetería) enviada al comprador
- **Categoría:** Funcional / Logística + App móvil
- **Sección afectada:** App Flutter (pantalla logística del repartidor) · `tbl_envios` · Storage (bucket nuevo) · `fn_set_numero_guia` (extensión) · WF-25-C + WF-80 (notificación imagen)
- **Origen:** observación de campo (2026-09-08, compras reales por TikTok): los negocios de paquetería que reciben paquetes de vendedores entregan un **código de retiro**, y las transportadoras emiten una **guía** — en ambos casos el documento se comunica al comprador **como FOTO** (imagen completa con todo el detalle), no como texto.
- **Descripción:** RSUELVO hoy registra `numero_guia` (texto) y notifica el texto por WhatsApp — insuficiente. El repartidor debe poder **capturar/subir una foto** desde la app (cámara o galería) y el comprador debe recibirla por WhatsApp.
- **Requisitos:**
  1. **App Flutter (logística):** en la ficha del envío, captura de foto al entregar el paquete: (a) en **paquetería/punto local** → foto del **código de retiro**; (b) en **transportadora** → foto de la **guía**.
  2. **Storage:** bucket `guias-envios` (privado, patrón `comprobantes-pago`) — ruta `{id_comercio}/{id_envio}.jpg`.
  3. **BD:** columna nueva `tbl_envios.guia_foto_url text`.
  4. **fn:** extender `fn_set_numero_guia` (o nueva `fn_registrar_guia`): aceptar **PUNTO_LOCAL** (código de retiro) además de `ENVIO_TRANSPORTE`; guardar texto opcional + `guia_foto_url`; disparar notificación pg_net.
  5. **WhatsApp:** envío al comprador vía WF-80 como **imagen** (`type:'image'` + `media_url` + caption con punto/transportadora) — mismo patrón que el QR de pago.
- **Impacto:** 🔴 Alto (app móvil + BD + Storage + n8n)
- **Bloquea construcción:** F4 (app Flutter) — depende de la app
- **Estado:** 📦 Registrada 2026-09-08 — implementación con Antigravity (el prompt F4 incluirá este flujo)
- **Resolución:** *(pendiente)*

---

### OBS-005: Ciudad de destino en UN SOLO mensaje del comprador (m38: solo ciudad, zona eliminada)
- **Categoría:** Funcional / Logística (UX conversacional)
- **Sección afectada:** WF-25-B (Msg Pide Ciudad + IF) · `fn_procesar_captura_destino` · `fn_entrega_captura_estado` · `tbl_entrega_captura`
- **Descripción:** en el flujo de envío por transportadora, el comprador responde **únicamente la ciudad/población en un solo mensaje** (texto libre, 120 chars max). La **zona se eliminó del flujo** por decisión del dueño (m38): `fn_procesar_captura_destino` toma el texto completo como ciudad y anula `destino_zona`. (m37 había implementado formato `CIUDAD:/ZONA:`; superado por m38.)
- **Requisitos:**
  1. WF-25-B tras elegir punto transporte: UNA pregunta "¿A qué ciudad o población se envía?".
  2. `fn_procesar_captura_destino` usa el texto como ciudad; dígito = re-selección de punto.
  3. `fn_entrega_captura_estado` → paso único `DESTINO`.
- **Impacto:** 🟢 Bajo
- **Bloquea construcción:** No
- **Estado:** ✅ Resuelta (2026-09-09, m38)
- **Resolución:** implementada y validada — pregunta solo-ciudad + captura en 1 mensaje; zona fuera del flujo.

---

### OBS-006: Sin pregunta SI/NO cuando la lista de espera está llena
- **Categoría:** Funcional / Conversacional (UX Momento 1)
- **Sección afectada:** WF-10 (rama lista llena + IF) · `fn_solicitar_reserva` (m43)
- **Descripción:** con la lista llena, un comprador nuevo hoy recibe la pregunta SI/NO de Momento 1 solo para que luego le digan que no hay lugar. Debe recibir directo en el primer mensaje: "Lo sentimos, el producto que busca no tiene stock y la lista de espera está llena".
- **Requisitos:**
  1. `fn_solicitar_reserva` (m43) devuelve `lista_llena/activos/maximo` en SIN_STOCK cuando no está en lista.
  2. WF-10: rama directa con ese texto (sin pendiente, sin pregunta); la pregunta se mantiene si hay cupo; el atajo ya_en_lista tiene prioridad.
- **Impacto:** 🟢 Bajo (1 migración + 1 IF/1 Build en WF-10)
- **Bloquea construcción:** No
- **Estado:** ✅ Resuelta (2026-09-11)
- **Resolución:** implementada y validada E2E — comprador 1 con cupo lleno recibe directo el mensaje (WF-80 #546 con id_comercio, Log Send); sin fila ni pendiente creados.

---

## 📊 Resumen de Estado

| Estado | Cantidad |
|--------|----------|
| ⬜ Pendientes | 0 |
| 🔄 En evaluación | 5 |
| ✅ Aceptadas | 0 |
| ❌ Rechazadas | 0 |
| 📦 P2 (futuro) | 0 |

---

## 📎 Referencias

- **PROMPT MAESTRO:** `00-Index/00-PROMPT-MAESTRO-RSUELVO.md`
- **Decisiones cerradas:** §5 del PROMPT MAESTRO (D1-D14)
- **Backlog HU:** `06-Backlog-HU/01-Backlog-Historias-de-Usuario.md`
- **Matriz WF-BD-HU:** `03-n8n/Matriz-Consistencia-WF-BD-HU.md`
- **Bitácora de avance:** `00-Index/ESTADO-EJECUCION.md`
- **WF-12 (Lista de Espera):** `03-n8n/workflows.md` §23-25
- **WF-13 (Notificar Lista):** `03-n8n/workflows.md` §26-28
- **WF-14 (Aceptar Oportunidad):** `03-n8n/workflows.md` §29

---

## 🔄 Historial de Cambios

| Fecha | Observación | Acción |
|-------|-------------|--------|
| 2026-09-06 | — | Archivo creado |
| 2026-09-06 | OBS-001 | Registrada — pregunta confirmación lista de espera |
| 2026-09-06 | OBS-001 | Opción C seleccionada — preguntar al entrar + opción de salir al notificar (registrada como sugerencia) |
| 2026-09-07 | OBS-001 | Momento 2 implementado en n8n (WF-04 `qLyBczowLOcnNXe5` y WF-14 `MLgnwfXbg7HnWVHC` publicados; usa `fn_rechazar_lista_espera` m31). Pendiente: Momento 1 (WF-10/WF-12) + tests T-A/T-B |
| 2026-09-07 | OBS-001 | **T-A/T-B VALIDADOS E2E** (NO→RECHAZADO+desplazamiento / SI→reserva→QR→PAGADO). Hallazgos H-16/H-17/H-18 → resueltos con migración 32 (turno único por cliente) |
| 2026-09-07 | OBS-002 | Registrada — formato y redacción de mensajes de reserva y lista de espera (reserva creada / lista espera / oportunidad disponible) |
| 2026-09-07 | OBS-003 | Registrada — puntos de entrega/envío configurables por tienda y selección por el comprador (reemplaza captura de dirección libre; requiere tabla nueva) |
| 2026-09-07 | OBS-003 | Reformulada con respuestas del usuario: puntos por sucursal, comprador siempre elige, envío por cobrar (costo ajeno a RSUELVO, sin cobro ni comprobante adicional) |
| 2026-09-08 | OBS-002 | Test de validación en producción: **WF-12 ✅ y WF-13 ✅ cumplen**; **persiste campo "Referencia" en la respuesta al SKU (WF-10/WF-20)** — hallazgo pendiente de corrección |
| 2026-09-08 | OBS-004 | Registrada — foto de guía/código de retiro enviada al comprador por WhatsApp (app logística Flutter, Storage, extensión fn_set_numero_guia)
| 2026-09-09 | OBS-005 | Implementada (m37 + WF-25-B): destino ciudad+zona en UN solo mensaje con formato CIUDAD: X, ZONA: Y; FB: FORMATO_INVALIDO con ejemplo
| 2026-09-09 | OBS-005 | **m38 (decisión del dueño): zona ELIMINADA — solo ciudad** (texto libre 1 mensaje; destino_zona=NULL); sección OBS-005 corregida en consecuencia |
| 2026-09-11 | OBS-005 | Corrección documental: el informe de optimización P1 proponía reintroducir CIUDAD+ZONA (seguía texto m37) — **P1 invalidado**, se mantiene solo-ciudad |
| 2026-09-11 | OBS-006 | Registrada — respuesta directa con lista llena (dueño); migración 43 aplicada y validada (buyer1→llena 1/1) |
| 2026-09-11 | OBS-006 | Resuelta y validada E2E (WF-80 #546: mensaje directo a comprador 1, sin pregunta; cupo restaurado a 5) |
