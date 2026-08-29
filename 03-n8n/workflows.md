# RSUELVO — Guía completa de workflows n8n

> 🔧 **Complementos posteriores (canónicos):** convención de funciones = `fn_*` (D3, alias `rpc_*` documentados) · variables Meta actualizadas §5.3 · matriz de trazabilidad completa en [Matriz-Consistencia-WF-BD-HU](Matriz-Consistencia-WF-BD-HU.md) · adaptadores Meta según [Guía Meta WhatsApp Business](../04-OpenWA/Guia%20Meta%20WhatsApp%20Business.md).

## n8n Cloud 2.36.5 + Supabase + OpenAI GPT-4o Vision + OpenWA + Meta WhatsApp Cloud API

**Versión:** 1.0  
**Fecha:** 24 de agosto de 2026  
**Entorno:** n8n Cloud 2.36.5  
**Backend:** Supabase / PostgreSQL  
**IA:** OpenAI GPT-4o Vision  
**Canales WhatsApp:** OpenWA + Meta WhatsApp Cloud API

---

# 1. Objetivo de esta arquitectura

Los workflows de n8n tienen cinco responsabilidades:

1. Recibir mensajes de WhatsApp.
    
2. Normalizar mensajes provenientes de diferentes proveedores.
    
3. Orquestar el flujo conversacional.
    
4. Ejecutar IA y servicios externos.
    
5. Comunicar al cliente el resultado de las operaciones realizadas por el backend.
    

n8n **NO debe convertirse en la base de datos ni en el motor transaccional de RSUELVO**.

Las operaciones críticas deben ejecutarse mediante PostgreSQL/Supabase:

- creación de reservas;
    
- liberación de reservas;
    
- asignación de lista de espera;
    
- creación de pedidos;
    
- consumo de créditos;
    
- validación de stock;
    
- confirmación de pago;
    
- movimientos de inventario;
    
- auditoría.
    

La propia arquitectura de RSUELVO establece que las reservas deben crearse de forma atómica en PostgreSQL para evitar carreras cuando dos compradores intentan adquirir la última unidad.

---

# 2. Arquitectura definitiva

```text
                         WHATSAPP
                            │
              ┌─────────────┴─────────────┐
              │                           │
           OpenWA                     Meta Cloud
              │                           │
              ▼                           ▼
       WF-01 OpenWA                WF-02 Meta Webhook
              │                           │
              └─────────────┬─────────────┘
                            ▼
                   WF-03 Normalizador
                            │
                            ▼
                    WF-04 Router Core
                            │
          ┌─────────────────┼──────────────────┐
          │                 │                  │
          ▼                 ▼                  ▼
      SKU / STOCK       COMPROBANTE        ESTADO CHAT
          │                 │                  │
          ▼                 ▼                  │
     Supabase RPC       GPT-4o Vision          │
          │                 │                  │
          ▼                 ▼                  ▼
       Reserva          Verificación       Conversación
          │
          ▼
      Pedido / QR
          │
          ▼
       WhatsApp
```

---

# 3. Principio fundamental: n8n no decide el negocio

Incorrecto:

```text
n8n
 ↓
SELECT stock
 ↓
IF stock > 0
 ↓
INSERT reserva
```

Correcto:

```text
n8n
 ↓
RPC crear_reserva()
 ↓
PostgreSQL
 ├── valida SKU
 ├── valida comercio
 ├── bloquea inventario
 ├── verifica reserva concurrente
 ├── crea reserva
 ├── crea movimiento
 └── devuelve resultado
 ↓
n8n
 ↓
envía WhatsApp
```

Esto permite que:

```text
Cliente A ─┐
           ├── PostgreSQL
Cliente B ─┘
```

se resuelva correctamente incluso si ambos mensajes llegan prácticamente al mismo tiempo.

El modelo de datos establece explícitamente esta necesidad.

---

# 4. Workflows que debes crear

Recomiendo crear inicialmente estos workflows:

```text
WF-00  Error Handler Global
WF-01  WhatsApp - OpenWA Incoming
WF-02  WhatsApp - Meta Incoming
WF-03  WhatsApp - Normalizador
WF-04  WhatsApp - Router Conversacional

WF-10  Venta - Solicitud SKU
WF-11  Venta - Crear Reserva
WF-12  Venta - Lista de Espera
WF-13  Venta - Notificar Lista de Espera
WF-14  Venta - Aceptar Oportunidad

WF-20  Pago - Generar QR
WF-21  Pago - Recibir Comprobante
WF-22  Pago - Analizar Comprobante GPT-4o
WF-23  Pago - Verificar Comprobante
WF-24  Pago - Confirmar Pedido

WF-30  Reservas - Expiración
WF-31  Reservas - Liberación y siguiente cliente

WF-40  Logística - Solicitar Datos
WF-41  Logística - Crear Envío
WF-42  Logística - Seguimiento

WF-50  Créditos - Verificar Saldo
WF-51  Créditos - Consumo
WF-52  Créditos - Devolución

WF-60  Auditoría
WF-70  Health Check
WF-80  WhatsApp - Send Message
```

No necesariamente todos necesitan ser workflows independientes desde el primer día. Algunos pueden convertirse en sub-workflows reutilizables mediante `Execute Workflow`.

---

# 5. Credenciales que debes configurar primero

En n8n crea estas credenciales:

## 5.1 Supabase

Recomendación:

```text
Credential:
RSUELVO_SUPABASE_BACKEND
```

Debe utilizarse exclusivamente desde n8n.

Nunca:

```text
frontend → service_role
```

Nunca exponer la clave en:

- WhatsApp;
    
- frontend;
    
- código del navegador;
    
- respuestas de n8n.
    

El modelo de RSUELVO utiliza multi-tenancy y RLS para aislar los comercios.

---

## 5.2 OpenAI

Crear:

```text
OPENAI_RSUELVO
```

Usar tu proyecto/API key con acceso a GPT-4o.

OpenAI mantiene APIs para solicitudes multimodales y modelos capaces de analizar imágenes.

---

## 5.3 Meta

Crear variables:

```text
META_GRAPH_API_VERSION
META_PHONE_NUMBER_ID
META_WABA_ID
META_BUSINESS_ID
META_APP_ID
META_APP_SECRET
META_ACCESS_TOKEN
META_VERIFY_TOKEN
META_WEBHOOK_SECRET
```

> Equivalencia con nombres anteriores: META_WA_ACCESS_TOKEN→META_ACCESS_TOKEN · META_WA_PHONE_NUMBER_ID→META_PHONE_NUMBER_ID · META_WA_BUSINESS_ACCOUNT_ID→META_BUSINESS_ID. Conjunto canónico = Guía Meta §8.

No deben aparecer hardcodeadas en los workflows.

---

## 5.4 OpenWA

Crear:

```text
OPENWA_BASE_URL
OPENWA_API_KEY
OPENWA_SESSION_ID
```

El adaptador OpenWA debe ser completamente independiente del adaptador Meta.

---

# 6. Regla de compatibilidad OpenWA + Meta

Nunca hagas esto:

```text
Workflow
   ↓
IF OpenWA
   ↓
lógica de negocio
   ↓
IF Meta
```

Haz esto:

```text
OpenWA ──────┐
             ▼
        NORMALIZADOR
             ▲
Meta ────────┘
             │
             ▼
       LÓGICA RSUELVO
```

La lógica interna solamente debe recibir un objeto normalizado.

---

# 7. Contrato interno de mensaje

Todos los mensajes recibidos deben transformarse a una estructura equivalente a:

```json
{
  "provider": "openwa",
  "channel": "whatsapp",
  "message_id": "external-message-id",
  "chat_id": "whatsapp-chat-id",
  "phone": "591XXXXXXXX",
  "type": "text",
  "text": "POL-001-M",
  "media": null,
  "timestamp": "2026-08-24T15:00:00Z",
  "raw": {}
}
```

Para Meta:

```json
{
  "provider": "meta",
  "channel": "whatsapp",
  "message_id": "wamid....",
  "chat_id": "591XXXXXXXX",
  "phone": "591XXXXXXXX",
  "type": "text",
  "text": "POL-001-M",
  "media": null,
  "timestamp": "2026-08-24T15:00:00Z",
  "raw": {}
}
```

El resto de RSUELVO nunca debería preocuparse por cuál proveedor recibió el mensaje.

---

# 8. WF-01 — WhatsApp OpenWA Incoming

## Objetivo

Recibir mensajes provenientes de OpenWA.

## Nodos

```text
Webhook
 ↓
Set / Edit Fields
 ↓
Code - Normalizar OpenWA
 ↓
Execute Workflow → WF-03
```

---

## Nodo 1 — Webhook

Método:

```text
POST
```

Path:

```text
/webhooks/whatsapp/openwa
```

Debe aceptar:

```text
JSON
```

---

## Nodo 2 — Normalizar OpenWA

Extraer:

```text
message_id
phone
chat_id
message_type
text
media
timestamp
```

Nunca enviar directamente el payload OpenWA al router.

---

## Nodo 3

Llamar:

```text
WF-03 WhatsApp - Normalizador
```

---

# 9. WF-02 — WhatsApp Meta Incoming

Este workflow será el adaptador oficial para Meta WhatsApp Cloud API.

Meta utiliza webhooks para entregar eventos de WhatsApp a una aplicación.

## Estructura

```text
Webhook GET/POST
       │
       ├── GET → verificación
       │
       └── POST → mensajes
```

---

# 10. Verificación del webhook Meta

Crear:

```text
Webhook
```

Path:

```text
/webhooks/whatsapp/meta
```

El endpoint debe soportar la verificación inicial de Meta.

Flujo:

```text
Webhook
   ↓
IF GET
   ↓
Validar verify token
   ↓
Responder challenge
```

El token configurado en Meta debe coincidir con:

```text
META_VERIFY_TOKEN
```

No uses el access token como verify token.

---

# 11. Recepción POST de Meta

Flujo:

```text
Webhook
 ↓
Respond 200
 ↓
Parse Meta Payload
 ↓
Filter message
 ↓
Normalize
 ↓
WF-03
```

La respuesta `200` debe devolverse rápidamente.

No hagas esto:

```text
Meta
 ↓
Webhook
 ↓
GPT-4o
 ↓
Supabase
 ↓
varias APIs
 ↓
respuesta HTTP
```

Primero acepta el webhook.

Después procesa.

Esto reduce problemas por timeouts y reintentos.

---

# 12. WF-03 — Normalizador WhatsApp

Este es uno de los workflows más importantes.

Entrada:

```text
OpenWA
```

o:

```text
Meta
```

Salida:

```text
RSUELVO Message Object
```

Tipos:

```text
text
image
document
audio
interactive
button
unknown
```

Para RSUELVO MVP nos interesan especialmente:

```text
text
image
```

---

# 13. Idempotencia

Antes de procesar un mensaje:

```text
message_id
```

debe comprobarse contra un registro de eventos.

Idealmente crear una tabla técnica:

```text
tbl_whatsapp_eventos
```

o equivalente en el SQL definitivo.

La lógica:

```text
¿message_id ya procesado?
       │
   ┌───┴───┐
  SI       NO
  │         │
  ▼         ▼
FIN       registrar
            │
            ▼
         procesar
```

Esto es fundamental porque los proveedores pueden reenviar eventos.

---

# 14. WF-04 — Router Conversacional

Entrada:

```text
Message Object
```

Primero:

```text
Buscar comercio
Buscar cliente
Buscar conversación/estado
```

El número de WhatsApp identifica al cliente dentro del comercio.

El diseño establece:

```text
UNIQUE(id_comercio, telefono_whatsapp)
```

por lo que nunca se debe tratar un número como cliente global de RSUELVO.

---

# 15. Determinar el comercio

La arquitectura actual de RSUELVO contempla:

```text
Un comercio
   ↓
WhatsApp
```

Por tanto:

```text
WhatsApp → comercio
```

debe ser una relación inequívoca.

El router debe obtener:

```text
id_comercio
```

antes de ejecutar cualquier operación comercial.

Nunca aceptar:

```text
id_comercio
```

enviado libremente por el cliente.

---

# 16. Estado conversacional

El router necesita conocer qué está esperando RSUELVO.

Ejemplo:

```text
IDLE
ESPERANDO_SKU
RESERVA_ACTIVA
ESPERANDO_PAGO
ESPERANDO_COMPROBANTE
PAGO_VALIDANDO
ESPERANDO_DIRECCION
PEDIDO_CONFIRMADO
```

No recomiendo guardar esta lógica exclusivamente como `IF` gigantescos dentro de n8n.

Preferiblemente:

```text
Supabase
   ↓
estado actual
   ↓
n8n
```

> **Bloqueo / dependencia (WF-04, H3):** en el schema SQL v2 no existe una función `fn_*` canónica que exponga o gestione el estado conversacional del comprador. Por tanto, WF-04 NO realiza `SELECT` ni usa funciones inventadas para este fin. El routing actual se basa en el tipo de mensaje y en la detección de SKU; las transiciones de estado conversacional (IDLE → ESPERANDO_SKU → RESERVA_ACTIVA → …) quedan pendientes de una RPC futura o se gestionan dentro del contexto de WF-10/WF-21/WF-40. Esto respeta la Regla de Oro 3: n8n orquesta, no decide.

---

# 17. Router principal

Conceptualmente:

```text
Mensaje
   │
   ▼
¿Imagen?
 ├── SI → WF-21 Comprobante
 │
 └── NO
      │
      ▼
   ¿Texto?
      │
      ▼
¿Existe reserva activa?
 ├── SI → interpretar respuesta
 │
 └── NO
      │
      ▼
¿Parece SKU?
 ├── SI → WF-10
 │
 └── NO → menú/ayuda
```

---

# 18. WF-10 — Solicitud de SKU

Este es el flujo principal de compra.

Entrada:

```text
SKU
phone
id_comercio
```

Ejemplo:

```text
POL-001-M
```

---

# 19. Normalización del SKU

Antes de enviarlo al backend:

```text
trim()
uppercase()
remove unnecessary spaces
```

Ejemplo:

```text
" pol-001-m "
```

se convierte en:

```text
POL-001-M
```

Pero n8n no debe decidir si el SKU existe.

---

# 20. Llamar a Supabase

Debe existir una función/RPC equivalente conceptualmente a:

```text
rpc_solicitar_producto(...)
```

o:

```text
rpc_crear_reserva(...)
```

La función debe encargarse de:

```text
validar comercio
validar SKU
validar variante
validar sucursal
validar inventario
validar reserva activa
validar límites
crear reserva
actualizar stock reservado
crear movimiento
crear pedido
```

La documentación establece que el inventario pertenece a una sucursal y que:

```text
stock_disponible =
stock_actual - stock_reservado
```

---

# 21. Resultado de la RPC

El backend debería devolver algo parecido a:

```json
{
  "status": "RESERVA_CREADA",
  "id_reserva": "...",
  "id_pedido": "...",
  "sku": "POL-001-M",
  "nombre": "POLERA OVERSIZE",
  "precio": 150,
  "cantidad": 1,
  "expires_at": "..."
}
```

Posibles resultados:

```text
RESERVA_CREADA
SIN_STOCK
RESERVA_EXISTENTE
SKU_NO_ENCONTRADO
COMERCIO_INACTIVO
SUCURSAL_NO_DISPONIBLE
```

---

# 22. Si se crea reserva

n8n:

```text
RPC
 ↓
IF RESERVA_CREADA
 ↓
Enviar confirmación
 ↓
Generar QR
```

Mensaje conceptual:

```text
Producto reservado.

Producto: POLERA OVERSIZE
SKU: POL-001-M
Total: Bs XXX

Tu reserva tiene vigencia hasta: HH:MM.

Te enviaremos el QR para realizar el pago.
```

No colocar tiempos hardcodeados.

La tabla `tbl_comercio_config` contiene:

```text
tiempo_reserva_minutos
```

y esos valores deben venir del backend.

---

# 23. WF-12 — Lista de espera

Si la RPC devuelve:

```text
SIN_STOCK
```

n8n debe preguntar al backend:

```text
¿Existe lista de espera?
```

Pero preferiblemente la propia RPC debe resolver la decisión atómicamente.

Resultado:

```text
LISTA_ESPERA_CREADA
```

o:

```text
LISTA_ESPERA_LLENA
```

---

# 24. Crear posición en lista de espera

La tabla es:

```text
tbl_lista_espera
```

y contiene:

```text
id_lista_espera
id_comercio
id_sucursal
id_variante
id_cliente
posicion
estado
fecha_ingreso
...
```

La posición debe generarse en PostgreSQL, no:

```text
SELECT MAX(posicion)
```

en n8n.

Eso produciría carreras.

---

# 25. Respuesta al cliente

Ejemplo:

```text
Ese producto ya está reservado.

Puedes entrar a la lista de espera.

Tu posición actual: #2.

Cuando quede disponible te avisaremos.
```

La lista de espera no representa una venta garantizada.

---

# 26. WF-13 — Notificación de lista de espera

Debe ejecutarse cuando una reserva:

```text
VENCIDA
CANCELADA
LIBERADA
```

libera inventario.

Flujo:

```text
Trigger
 ↓
RPC liberar_reserva()
 ↓
RPC obtener_siguiente_lista()
 ↓
IF existe
 ↓
marcar NOTIFICADO
 ↓
enviar WhatsApp
```

---

# 27. No seleccionar el siguiente cliente en n8n

Incorrecto:

```text
SELECT *
FROM tbl_lista_espera
WHERE estado='ESPERANDO'
ORDER BY posicion
LIMIT 1
```

y luego actualizarlo desde n8n.

Correcto:

```text
RPC obtener_siguiente_oportunidad()
```

que haga todo dentro de una transacción.

Esto evita:

```text
Workflow A → Cliente #1
Workflow B → Cliente #1
```

---

# 28. Mensaje de oportunidad

```text
¡Tu producto está disponible!

SKU: POL-001-M
Producto: POLERA OVERSIZE
Precio: Bs XXX

Tienes X minutos para aceptar la reserva.

Responde:

SI → aceptar
NO → liberar oportunidad
```

El tiempo debe salir de:

```text
tiempo_aceptacion_lista_espera_minutos
```

---

# 29. WF-14 — Aceptar oportunidad

Cuando el cliente responde:

```text
SI
```

n8n llama:

```text
RPC aceptar_oportunidad_lista(...)
```

La función debe:

```text
validar estado NOTIFICADO
validar expiración
validar inventario
crear reserva
actualizar lista
actualizar inventario
```

Todo atómicamente.

---

# 30. WF-20 — Generar QR

Después de crear el pedido:

```text
tbl_pedidos
```

se genera el cobro.

La arquitectura separa explícitamente:

```text
QR
 ↓
Cobro
 ↓
Comprobante
 ↓
Verificación
```

n8n debe obtener la configuración del método de pago y llamar al servicio correspondiente.

---

# 31. Crear `tbl_qr_cobros`

La estructura contempla:

```text
id_qr_cobro
id_comercio
id_pedido
id_metodo_pago
monto
referencia
qr_url
estado
created_at
```

Idealmente la RPC crea este registro y n8n únicamente envía:

```text
qr_url
```

al comprador.

---

# 32. WF-21 — Recibir comprobante

El cliente envía:

```text
imagen
```

El flujo es:

```text
WhatsApp
 ↓
Normalizador
 ↓
Detectar image
 ↓
Descargar media
 ↓
Guardar Storage
 ↓
Crear comprobante
 ↓
Crear verificación
 ↓
Verificar créditos
 ↓
GPT-4o Vision
 ↓
Validación backend
 ↓
Resultado
```

---

# 33. Descargar imagen desde Meta

Para Meta:

```text
Webhook
 ↓
media_id
 ↓
GET media metadata
 ↓
obtener URL temporal
 ↓
GET binary media
```

El token de Meta debe utilizarse únicamente en n8n/backend.

Nunca:

```text
cliente → access token
```

---

# 34. OpenWA y medios

OpenWA puede entregar diferentes representaciones dependiendo de la configuración.

El normalizador debe convertir cualquier representación a:

```text
binary image
```

o:

```text
temporary media URL
```

No permitas que WF-22 conozca la estructura específica de OpenWA.

---

# 35. Guardar comprobante

Guardar primero el archivo en:

```text
Supabase Storage
```

y después:

```text
tbl_comprobantes_pago
```

con:

```text
archivo_url
```

o path equivalente.

La documentación de RSUELVO recomienda precisamente almacenar el archivo en Supabase Storage y conservar la referencia en PostgreSQL.

---

# 36. Crear `tbl_comprobantes_pago`

Datos mínimos:

```text
id_comprobante
id_comercio
id_pedido
id_cliente
tipo_archivo
archivo_url
estado
created_at
```

Inicialmente:

```text
estado = RECIBIDO
```

---

# 37. WF-22 — Análisis GPT-4o Vision

Aquí sí debes utilizar tus créditos de GPT-4o.

La función de GPT-4o será:

**extraer información del comprobante**, no decidir por sí solo que el pago es auténtico.

Esto es muy importante.

La IA puede devolver:

```json
{
  "is_payment_receipt": true,
  "payer_name": "...",
  "amount": 150,
  "operation_number": "...",
  "payment_date": "...",
  "currency": "BOB",
  "merchant_name": "...",
  "confidence": 0.94
}
```

Pero:

```text
GPT = extracción/análisis
PostgreSQL = decisión comercial
```

---

# 38. Prompt de GPT-4o Vision

El prompt debe pedir exclusivamente extracción estructurada.

Ejemplo conceptual:

```text
Analiza esta imagen como comprobante de pago.

Extrae únicamente la información visible.

No inventes valores.

Si un campo no puede determinarse, devuelve null.

Determina:

- si parece ser un comprobante;
- nombre del pagador;
- monto;
- moneda;
- fecha;
- número de operación;
- nombre del receptor/comercio;
- banco/proveedor si aparece;
- nivel de confianza.

No determines que el pago sea legítimo únicamente por apariencia.
La validación final será realizada por el sistema.
```

---

# 39. Structured Output

La respuesta debe ser JSON estructurado:

```json
{
  "is_payment_receipt": true,
  "payer_name": null,
  "amount": null,
  "currency": null,
  "payment_date": null,
  "operation_number": null,
  "merchant_name": null,
  "provider": null,
  "confidence": 0
}
```

Nunca utilices texto libre como resultado principal.

---

# 40. Validaciones posteriores a GPT-4o

Supongamos que GPT devuelve:

```text
amount = 150
operation_number = 123456
```

n8n NO debe hacer:

```text
confidence > 0.8
→ pago válido
```

Debe llamar al backend:

```text
RPC validar_comprobante(...)
```

El backend compara:

```text
monto del pedido
       VS
monto detectado

referencia del QR
       VS
operación detectada

cliente
       VS
pagador

estado del pedido
       VS
estado actual
```

---

# 41. WF-23 — Verificar comprobante

Flujo:

```text
tbl_comprobantes_pago
        │
        ▼
tbl_verificaciones
        │
        ▼
RPC consumir_creditos_verificacion()
        │
        ▼
GPT-4o
        │
        ▼
RPC validar_resultado()
        │
        ▼
VALIDO / INVALIDO
```

La tabla `tbl_verificaciones` contempla:

```text
tipo_verificacion
estado
resultado
confianza
creditos_consumidos
fecha_inicio
fecha_fin
```

---

# 42. Créditos

El costo nunca debe estar hardcodeado en n8n.

Incorrecto:

```text
credits -= 1
```

Correcto:

```text
RPC iniciar_verificacion()
```

La función consulta:

```text
tbl_servicios_creditos
```

y obtiene:

```text
costo_creditos
```

La documentación establece explícitamente que el costo no debe estar hardcodeado en n8n.

---

# 43. Consumo atómico de créditos

La operación debe ser:

```text
BEGIN

bloquear cuenta de créditos

consultar saldo

IF saldo < costo
    ROLLBACK
    devolver SIN_CREDITOS

saldo_anterior = saldo

saldo_nuevo = saldo - costo

actualizar cuenta

insertar movimiento

COMMIT
```

Nunca:

```text
n8n SELECT saldo
n8n IF
n8n UPDATE saldo
```

porque dos verificaciones simultáneas podrían gastar el mismo saldo.

---

# 44. `tbl_movimientos_creditos`

Debe registrarse:

```text
tipo = CONSUMO_VERIFICACION
cantidad = -N
referencia_tipo = VERIFICACION
referencia_id = id_verificacion
```

La arquitectura de créditos ya define este mecanismo.

---

# 45. ¿Qué ocurre si no hay créditos?

Resultado:

```text
SIN_CREDITOS
```

No ejecutar GPT.

El comprobante puede quedar:

```text
RECIBIDO
```

y la verificación:

```text
BLOQUEADA
```

Respuesta:

```text
Recibimos tu comprobante.

El comercio no puede completar la verificación en este momento.
Te avisaremos cuando el proceso continúe.
```

---

# 46. WF-24 — Confirmar pedido

Si el backend determina:

```text
VALIDO
```

entonces:

```text
RPC confirmar_pago(...)
```

debe:

```text
validar reserva
validar comprobante
validar estado
confirmar pedido
actualizar reserva
actualizar inventario
registrar movimiento
crear estado logístico si corresponde
```

El estado del pedido pasa progresivamente por:

```text
CREADO
ESPERANDO_PAGO
PAGO_RECIBIDO
PAGO_VALIDANDO
PAGADO
```

Los estados están definidos en el modelo de datos.

---

# 47. Después del pago

n8n envía:

```text
Pago verificado correctamente.

Pedido: #XXXX

Ahora necesito los datos de entrega.

Envíame:

Nombre:
Dirección:
Referencia:
Teléfono:
```

---

# 48. WF-40 — Solicitar datos de envío

No crear el envío hasta que los datos estén completos.

Estado conversacional:

```text
ESPERANDO_DIRECCION
```

Cuando el cliente responde, n8n extrae:

```text
nombre
direccion
referencia
telefono
```

Si el MVP solamente necesita:

```text
direccion
```

mantenerlo simple.

---

# 49. WF-41 — Crear envío

n8n llama:

```text
RPC crear_envio(...)
```

La tabla contempla:

```text
id_envio
id_comercio
id_pedido
id_sucursal
direccion
referencia
telefono_contacto
id_repartidor
estado
numero_guia
```

Estado inicial:

```text
PENDIENTE
```

---

# 50. WF-42 — Seguimiento

Los estados son:

```text
PENDIENTE
PREPARANDO
ASIGNADO
EN_RUTA
ENTREGADO
NO_ENTREGADO
CANCELADO
```

Cada modificación debe crear:

```text
tbl_env_seguimiento_estados
```

No sobrescribir simplemente el estado anterior sin historial.

---

# 51. WF-30 — Expiración de reservas

Este workflow debe utilizar:

```text
Schedule Trigger
```

Ejemplo:

```text
cada 1 minuto
```

Pero no debería buscar reservas y actualizarlas individualmente desde n8n.

Debe llamar:

```text
RPC procesar_reservas_expiradas()
```

La función PostgreSQL:

```text
buscar reservas vencidas
 ↓
bloquearlas
 ↓
liberar stock
 ↓
actualizar estado
 ↓
registrar movimiento
 ↓
devolver variantes liberadas
```

---

# 52. WF-31 — Liberación y lista de espera

Después de:

```text
procesar_reservas_expiradas()
```

n8n recibe:

```json
[
  {
    "id_variante": "...",
    "id_sucursal": "...",
    "stock_liberado": 1
  }
]
```

Después:

```text
Execute Workflow
→ WF-13
```

para obtener la siguiente persona.

---

# 53. Regla importante sobre expiración

No hagas:

```text
Schedule
 ↓
for each reservation
 ↓
UPDATE
 ↓
SELECT next customer
 ↓
UPDATE
```

Esto genera múltiples operaciones y aumenta el riesgo de carreras.

Haz:

```text
Schedule
 ↓
RPC procesar_expiraciones()
```

Una operación transaccional.

---

# 54. Anti-spam / protección de conversaciones

n8n debe implementar controles de aplicación como:

```text
message_id idempotente
rate limiting lógico
deduplicación
estado conversacional
```

Pero **no debe intentar evadir los mecanismos antiabuso de WhatsApp**.

Para una operación compatible con Meta, prioriza:

- mensajes iniciados por el usuario;
    
- respuestas relevantes;
    
- plantillas aprobadas cuando correspondan;
    
- opt-in adecuado;
    
- no enviar mensajes masivos no solicitados;
    
- no generar conversaciones artificiales;
    
- no bombardear al mismo número;
    
- respetar ventanas y políticas de Meta.
    

Meta es el canal oficial que debe considerarse la referencia de compatibilidad.

---

# 55. OpenWA

OpenWA debe tratarse como un adaptador alternativo.

No debe utilizarse n8n para:

```text
rotar cuentas
simular comportamiento humano
evadir detección
evitar límites
ocultar automatización
```

La estrategia segura es:

```text
mensajes legítimos
+
bajo volumen
+
respuestas provocadas por el cliente
+
idempotencia
+
backoff ante errores
+
sin campañas automatizadas agresivas
```

Si OpenWA y Meta están disponibles, la lógica de negocio permanece exactamente igual.

---

# 56. Política de envío

Todos los envíos deben pasar por:

```text
WF-SEND-WHATSAPP
```

No permitir que cada workflow haga sus propios HTTP Request a OpenWA/Meta.

Crear un subworkflow:

```text
WF-80 WhatsApp - Send Message
```

Entrada:

```json
{
  "provider": "meta",
  "phone": "591...",
  "type": "text",
  "text": "..."
}
```

o:

```json
{
  "provider": "openwa",
  "phone": "591...",
  "type": "text",
  "text": "..."
}
```

---

# 57. WF-80 — Send WhatsApp

Estructura:

```text
Execute Workflow Trigger
        │
        ▼
   IF opt-out? ──fn_cliente_optado()──→ SI → omitir envío
        │ NO
        ▼
       IF
   ┌────┴────┐
 Meta       OpenWA
 │             │
 ▼             ▼
HTTP Request  HTTP Request
 │             │
 └──────┬──────┘
        ▼
      Result
```

Esto evita duplicar la lógica de envío.

> **Responsabilidad H7:** la verificación de opt-out antes de cada envío (`fn_cliente_optado(id_comercio, telefono_whatsapp)`) es responsabilidad exclusiva de WF-80. Los workflows upstream (WF-04, WF-10, WF-21, etc.) solo registran la preferencia mediante `fn_registrar_opt_out`; nunca deciden por sí solos si se puede enviar un mensaje.

---

# 58. Meta — envío de mensajes

Para Meta:

```text
HTTP Request
```

debe llamar al endpoint de mensajes del número configurado.

El request conceptualmente contiene:

```text
Authorization: Bearer META_WA_ACCESS_TOKEN
Content-Type: application/json
```

y:

```json
{
  "messaging_product": "whatsapp",
  "to": "591XXXXXXXX",
  "type": "text",
  "text": {
    "body": "Mensaje"
  }
}
```

El endpoint exacto debe mantenerse parametrizado por la versión de Graph API utilizada por tu aplicación Meta.

---

# 59. No mezclar IDs de proveedores

Nunca usar:

```text
Meta wamid
```

como si fuera:

```text
OpenWA message ID
```

El sistema debe guardar:

```text
provider
external_message_id
```

Por ejemplo:

```text
provider = META
external_message_id = wamid...
```

o:

```text
provider = OPENWA
external_message_id = ...
```

---

# 60. Estado de conversación

Una recomendación importante es separar:

```text
estado comercial
```

de:

```text
estado conversacional
```

Ejemplo:

```text
Pedido:
PAGO_VALIDANDO

Conversación:
ESPERANDO_RESULTADO_VERIFICACION
```

No mezclar ambos.

---

# 61. Manejo de errores

Crear:

```text
WF-00 Error Handler Global
```

Debe capturar:

```text
HTTP 400
HTTP 401
HTTP 403
HTTP 404
HTTP 429
HTTP 500
timeout
Supabase error
OpenAI error
Meta error
OpenWA error
```

---

# 62. Errores 429

Para Meta/OpenWA/OpenAI:

```text
429
 ↓
Wait
 ↓
Retry
```

Pero con límites controlados.

Nunca:

```text
retry infinito
```

Usar:

```text
1
2
4
8
```

segundos como backoff inicial, con un máximo razonable.

---

# 63. Error de OpenAI

Si GPT-4o falla:

```text
No marcar comprobante como inválido.
```

Debe quedar:

```text
RECIBIDO
```

o:

```text
PROCESANDO
```

según el estado definido.

El error técnico no significa:

```text
pago inválido
```

---

# 64. Error de Meta

Si Meta falla al enviar:

```text
guardar error
```

y permitir reintento.

No repetir automáticamente indefinidamente.

---

# 65. Auditoría

El modelo tiene:

```text
tbl_logs_auditoria
```

con:

```text
id_log
id_comercio
id_usuario
accion
tabla
registro_id
datos_anteriores
datos_nuevos
ip
user_agent
created_at
```

Cada operación crítica debe generar auditoría.

Ejemplos:

```text
RESERVA_CREADA
RESERVA_LIBERADA
LISTA_ESPERA_CREADA
PEDIDO_CREADO
COMPROBANTE_RECIBIDO
VERIFICACION_EJECUTADA
CREDITO_CONSUMIDO
PAGO_VALIDADO
PEDIDO_CONFIRMADO
ENVIO_CREADO
```

---

# 66. Qué debe hacer n8n y qué debe hacer Supabase

## n8n

```text
✓ Webhooks
✓ HTTP APIs
✓ WhatsApp
✓ OpenAI
✓ Normalización
✓ Routing
✓ Orquestación
✓ Retries
✓ Temporizadores
✓ Integraciones
✓ Manejo de archivos
```

## Supabase/PostgreSQL

```text
✓ PK/FK
✓ Constraints
✓ RLS
✓ Inventario
✓ Reservas
✓ Concurrencia
✓ Lista de espera
✓ Pedidos
✓ Créditos
✓ Ledger
✓ Estados comerciales
✓ Auditoría
✓ Transacciones
```

---

# 67. No hacer en n8n

Nunca implementar:

```text
SELECT stock
IF stock > 0
INSERT reserva
```

Nunca:

```text
SELECT MAX(posicion)
INSERT posicion + 1
```

Nunca:

```text
SELECT saldo
UPDATE saldo
```

Nunca:

```text
SELECT pedido
IF estado = X
UPDATE pedido
```

si la operación requiere consistencia transaccional.

---

# 68. RPCs que el SQL de RSUELVO debe exponer

Para que los workflows sean limpios, recomiendo que el SQL definitivo exponga funciones equivalentes a:

```text
rpc_identificar_comercio_por_whatsapp()

rpc_obtener_cliente()

rpc_crear_cliente()

rpc_solicitar_sku()

rpc_crear_reserva()

rpc_agregar_lista_espera()

rpc_aceptar_oportunidad()

rpc_procesar_reservas_expiradas()

rpc_obtener_siguiente_lista_espera()

rpc_crear_pedido()

rpc_generar_cobro()

rpc_crear_comprobante()

rpc_iniciar_verificacion()

rpc_consumir_creditos()

rpc_registrar_resultado_verificacion()

rpc_confirmar_pago()

rpc_crear_envio()

rpc_actualizar_estado_envio()

rpc_registrar_auditoria()
```

El nombre exacto debe coincidir con el `schema.sql` final.

---

# 69. Arquitectura de una compra completa

El flujo final queda:

```text
CLIENTE
   │
   │ "POL-001-M"
   ▼
WHATSAPP
   │
   ▼
n8n
   │
   ▼
NORMALIZADOR
   │
   ▼
ROUTER
   │
   ▼
RPC SOLICITAR SKU
   │
   ├── SIN STOCK
   │      ↓
   │   LISTA ESPERA
   │
   └── STOCK
          ↓
       RESERVA
          ↓
       PEDIDO
          ↓
          QR
          ↓
       CLIENTE PAGA
          ↓
       COMPROBANTE
          ↓
       GPT-4o Vision
          ↓
       RESULTADO OCR
          ↓
       RPC VALIDACIÓN
          ↓
      ┌───┴────┐
   INVÁLIDO   VÁLIDO
      │          │
      ▼          ▼
   RECHAZAR   CONFIRMAR
                 │
                 ▼
             PEDIDO PAGADO
                 │
                 ▼
           DATOS DE ENVÍO
                 │
                 ▼
              ENVÍO
                 │
                 ▼
            SEGUIMIENTO
```

---

# 70. Flujo de concurrencia

Caso:

```text
Stock = 1

Cliente A → SKU
Cliente B → SKU
```

Ambos llegan simultáneamente:

```text
n8n A ───────┐
             │
n8n B ───────┼──→ PostgreSQL
             │
             ▼
      TRANSACCIÓN / LOCK
             │
        ┌────┴─────┐
        │           │
     Cliente A   Cliente B
       reserva    espera
```

Resultado obligatorio:

```text
A → RESERVA ACTIVA
B → LISTA DE ESPERA
```

Nunca dos reservas.

---

# 71. Flujo de comprobante

```text
Cliente
   │
   ▼
Imagen
   │
   ▼
Meta/OpenWA
   │
   ▼
n8n
   │
   ▼
Storage
   │
   ▼
tbl_comprobantes_pago
   │
   ▼
tbl_verificaciones
   │
   ▼
Créditos
   │
   ▼
GPT-4o Vision
   │
   ▼
Datos estructurados
   │
   ▼
PostgreSQL
   │
   ├── INVALIDO
   │
   └── VALIDO
          │
          ▼
       Pedido
```

---

# 72. Regla para GPT-4o

GPT-4o debe responder:

```text
¿Qué información aparece en la imagen?
```

No:

```text
¿Debo aprobar esta venta?
```

La segunda pregunta pertenece al backend.

Esto evita que una alucinación o interpretación visual incorrecta pueda modificar directamente:

```text
stock
pedido
dinero
créditos
```

---

# 73. Estado de un comprobante

Flujo:

```text
RECIBIDO
   ↓
PROCESANDO
   ↓
VALIDO
```

o:

```text
RECIBIDO
   ↓
PROCESANDO
   ↓
INVALIDO
```

También:

```text
RECIBIDO
   ↓
PROCESANDO
   ↓
RECHAZADO
```

si existe una condición de negocio que lo requiera.

Estos estados están definidos en el diseño de datos.

---

# 74. Orden recomendado de construcción

No construyas los 20 workflows de una vez.

Hazlo en este orden:

## Fase 1 — Infraestructura

```text
[ ] Supabase
[ ] SQL definitivo
[ ] RPCs
[ ] RLS
[ ] Storage
[ ] credenciales n8n
```

## Fase 2 — WhatsApp

```text
[ ] WF-01 OpenWA
[ ] WF-02 Meta
[ ] WF-03 Normalizador
[ ] WF-80 Sender
```

## Fase 3 — Venta

```text
[ ] WF-04 Router
[ ] WF-10 SKU
[ ] WF-11 Reserva
[ ] WF-12 Lista de espera
[ ] WF-13 Notificación
[ ] WF-14 Aceptación
```

## Fase 4 — Pago

```text
[ ] WF-20 QR
[ ] WF-21 Comprobante
[ ] WF-22 GPT-4o
[ ] WF-23 Verificación
[ ] WF-24 Confirmación
```

## Fase 5 — Reservas

```text
[ ] WF-30 Expiración
[ ] WF-31 Liberación
```

## Fase 6 — Logística

```text
[ ] WF-40 Datos envío
[ ] WF-41 Crear envío
[ ] WF-42 Seguimiento
```

## Fase 7 — Observabilidad

```text
[ ] WF-00 Error handler
[ ] WF-60 Auditoría
[ ] WF-70 Health check
```

---

# 75. Pruebas obligatorias

Antes de producción:

## SKU

```text
[ ] SKU válido
[ ] SKU inválido
[ ] SKU con espacios
[ ] SKU lowercase
[ ] SKU inexistente
```

## Inventario

```text
[ ] stock = 0
[ ] stock = 1
[ ] stock > 1
[ ] dos compradores simultáneos
```

## Reservas

```text
[ ] reserva creada
[ ] reserva existente
[ ] reserva expirada
[ ] reserva cancelada
```

## Lista de espera

```text
[ ] primera posición
[ ] segunda posición
[ ] lista llena
[ ] aceptación
[ ] rechazo
[ ] expiración
```

## Pagos

```text
[ ] comprobante correcto
[ ] comprobante ilegible
[ ] monto incorrecto
[ ] operación incorrecta
[ ] imagen que no es comprobante
[ ] GPT-4o error
[ ] saldo de créditos insuficiente
```

## WhatsApp

```text
[ ] OpenWA mensaje texto
[ ] OpenWA imagen
[ ] Meta mensaje texto
[ ] Meta imagen
[ ] mensaje duplicado
[ ] mensaje fuera de orden
[ ] error HTTP
[ ] retry
```

---

# 76. Prueba crítica de concurrencia

Esta prueba es obligatoria.

Crear:

```text
Stock = 1
```

Enviar simultáneamente:

```text
Cliente A → SKU
Cliente B → SKU
```

Resultado esperado:

```text
1 reserva
1 lista de espera
```

Después:

```text
Reserva vence
```

Resultado:

```text
stock liberado
Cliente B notificado
```

Esta prueba demuestra que la arquitectura realmente respeta el modelo de RSUELVO.

---

# 77. Prueba crítica de créditos

Configurar:

```text
saldo = 1
costo_verificación = 1
```

Enviar dos comprobantes simultáneamente.

Resultado:

```text
Verificación A → 1 crédito
Verificación B → SIN_CREDITOS
```

Nunca:

```text
saldo = -1
```

ni:

```text
saldo = 0
dos verificaciones aprobadas
```

---

# 78. Prueba de idempotencia

Enviar dos veces exactamente el mismo evento:

```text
message_id = ABC123
```

Resultado:

```text
primera ejecución → procesa
segunda ejecución → ignora
```

Nunca:

```text
dos reservas
dos pedidos
dos verificaciones
```

---

# 79. Prueba OpenWA / Meta

El mismo mensaje:

```text
POL-001-M
```

debe producir exactamente la misma operación comercial independientemente de:

```text
OpenWA
```

o:

```text
Meta
```

La única diferencia debe ser:

```text
provider
```

y el mecanismo utilizado para enviar/recibir.

---

# 80. Estructura recomendada de nombres en n8n

Usar nombres consistentes:

```text
RSU | 00 | Error Handler
RSU | 01 | WhatsApp | OpenWA Incoming
RSU | 02 | WhatsApp | Meta Incoming
RSU | 03 | WhatsApp | Normalize
RSU | 04 | WhatsApp | Router

RSU | 10 | Sales | SKU
RSU | 11 | Sales | Reservation
RSU | 12 | Sales | Waitlist
RSU | 13 | Sales | Waitlist Notify
RSU | 14 | Sales | Waitlist Accept

RSU | 20 | Payment | QR
RSU | 21 | Payment | Receipt
RSU | 22 | Payment | GPT4o Vision
RSU | 23 | Payment | Verify
RSU | 24 | Payment | Confirm

RSU | 30 | Reservation | Expiration
RSU | 31 | Reservation | Release

RSU | 40 | Logistics | Address
RSU | 41 | Logistics | Shipment
RSU | 42 | Logistics | Tracking

RSU | 60 | Audit
RSU | 70 | Health Check
RSU | 80 | WhatsApp | Send
```

---

# 81. Estructura interna recomendada

Cada workflow debe seguir aproximadamente:

```text
TRIGGER
   ↓
VALIDATE
   ↓
NORMALIZE
   ↓
BUSINESS RPC
   ↓
DECISION
   ↓
EXTERNAL SERVICE
   ↓
AUDIT
   ↓
RESPONSE
```

No crear workflows gigantescos de cientos de nodos.

---

# 82. Principio final de seguridad

La arquitectura completa debe respetar:

```text
CLIENTE
   ↓
WhatsApp
   ↓
n8n
   ↓
Supabase RPC
   ↓
PostgreSQL
```

Nunca:

```text
CLIENTE
   ↓
n8n
   ↓
UPDATE DATABASE DIRECTO
```

para operaciones críticas.

Y nunca:

```text
CLIENTE
   ↓
n8n
   ↓
GPT
   ↓
DECISIÓN FINANCIERA DIRECTA
```

---

# 83. Arquitectura final resumida

```text
                         ┌───────────────────┐
                         │     META API      │
                         └─────────┬─────────┘
                                   │
                         ┌─────────▼─────────┐
                         │      OPENWA       │
                         └─────────┬─────────┘
                                   │
                                   ▼
                         ┌───────────────────┐
                         │       n8n         │
                         │                   │
                         │ Normalize         │
                         │ Router            │
                         │ OpenAI            │
                         │ WhatsApp          │
                         │ Retry             │
                         │ Scheduling         │
                         └─────────┬─────────┘
                                   │
                         ┌─────────▼─────────┐
                         │     SUPABASE      │
                         │                   │
                         │ RPC               │
                         │ PostgreSQL        │
                         │ RLS               │
                         │ Storage           │
                         │ Audit             │
                         └─────────┬─────────┘
                                   │
                         ┌─────────▼─────────┐
                         │     RSUELVO       │
                         │                   │
                         │ Comercio          │
                         │ Inventario        │
                         │ Reservas          │
                         │ Lista espera      │
                         │ Pedidos           │
                         │ Pagos             │
                         │ Créditos          │
                         │ Envíos            │
                         └───────────────────┘
```

---

# 84. Conclusión

La implementación correcta de RSUELVO en n8n 2.36.5 no consiste en hacer un único workflow enorme.

La arquitectura correcta es:

```text
                WHATSAPP
                   │
          ┌────────┴────────┐
          │                 │
        OpenWA             Meta
          │                 │
          └────────┬────────┘
                   ▼
              NORMALIZER
                   │
                   ▼
                ROUTER
                   │
       ┌───────────┼────────────┐
       ▼           ▼            ▼
      SKU       COMPROBANTE   ESTADO
       │           │
       ▼           ▼
    SUPABASE    GPT-4o
       │           │
       └─────┬─────┘
             ▼
        SUPABASE RPC
             │
             ▼
        RSUELVO DB
```

La decisión clave es mantener **toda la lógica crítica de negocio en PostgreSQL/Supabase**, tal como exige el diseño de RSUELVO: reservas atómicas, inventario, lista de espera, pedidos, créditos y auditoría.

n8n queda como **capa de orquestación e integración**, OpenAI como **motor de extracción visual**, y OpenWA/Meta como **transportes de WhatsApp intercambiables**.

La documentación de n8n y OpenAI debe consultarse contra la versión concreta de los nodos disponibles en tu instancia, especialmente para los nodos de OpenAI y las credenciales; OpenAI actualmente documenta su API como una plataforma para solicitudes multimodales y generación estructurada.