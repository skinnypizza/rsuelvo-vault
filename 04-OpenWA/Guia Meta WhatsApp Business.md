# RSUELVO — Guía Técnica de Meta WhatsApp Business API

> **Proyecto:** RSUELVO  
> **Propósito:** Definir la integración oficial de Meta WhatsApp Business Platform con RSUELVO, alineada con las historias de usuario, flujos, arquitectura, base de datos, n8n, Supabase y reglas de negocio del proyecto.
> 
> **Estado:** Diseño técnico  
> **Canal principal:** WhatsApp  
> **Proveedor recomendado para producción:** Meta WhatsApp Business Platform / Cloud API  
> **Orquestador:** n8n Cloud  
> **Backend transaccional:** Supabase / PostgreSQL  
> **Cliente comprador:** WhatsApp  
> **Aplicación administrativa:** Flutter

---

# 1. Objetivo

RSUELVO utiliza WhatsApp como canal de interacción con el comprador.

El comprador no necesita instalar una aplicación ni crear una cuenta dentro de RSUELVO.

Su interacción principal es:

```text
COMPRADOR
   │
   │ WhatsApp
   ▼
META WHATSAPP CLOUD API
   │
   ▼
WEBHOOK
   │
   ▼
n8n
   │
   ├── IA
   │
   ├── Supabase RPC
   │
   └── WhatsApp Cloud API
          │
          ▼
      COMPRADOR
```

La integración debe permitir implementar:

- recepción de mensajes;
    
- identificación del comprador;
    
- recepción de SKU;
    
- consulta de productos;
    
- respuesta de precio;
    
- gestión de reservas;
    
- gestión de lista de espera;
    
- envío de QR;
    
- recepción de comprobantes;
    
- descarga de medios;
    
- envío de estados de validación;
    
- recopilación de datos de envío;
    
- confirmación de compra;
    
- notificaciones;
    
- mensajes de errores;
    
- mensajes relacionados con reservas;
    
- mensajes relacionados con logística.
    

La API de Meta **no debe contener lógica de negocio de RSUELVO**.

Meta solamente debe funcionar como canal de comunicación.

---

# 2. Arquitectura oficial

La arquitectura objetivo es:

```text
                         ┌─────────────────────┐
                         │      COMPRADOR      │
                         │      WhatsApp       │
                         └──────────┬──────────┘
                                    │
                                    ▼
                     ┌──────────────────────────┐
                     │ META WHATSAPP CLOUD API  │
                     │                          │
                     │ Messages                 │
                     │ Media                    │
                     │ Templates                │
                     │ Webhooks                 │
                     └────────────┬─────────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │      n8n        │
                         │                 │
                         │ Webhook         │
                         │ Normalización   │
                         │ Routing         │
                         │ IA              │
                         │ RPC             │
                         │ Respuestas      │
                         └───────┬─────────┘
                                 │
               ┌─────────────────┼─────────────────┐
               │                 │                 │
               ▼                 ▼                 ▼
        ┌────────────┐    ┌────────────┐   ┌──────────────┐
        │ Supabase   │    │ OpenAI     │   │ Meta Cloud   │
        │ PostgreSQL │    │ Vision/IA  │   │ API          │
        └────────────┘    └────────────┘   └──────────────┘
               │
               ▼
        REGLAS DE NEGOCIO
```

---

# 3. Regla arquitectónica fundamental

## Meta no decide nada sobre el negocio

No se debe implementar:

```text
Webhook Meta
   ↓
IF stock > 0
   ↓
UPDATE inventario
   ↓
Crear reserva
```

La lógica correcta es:

```text
Webhook Meta
   ↓
n8n
   ↓
RPC PostgreSQL
   ↓
fn_solicitar_reserva()
   ↓
PostgreSQL decide
   ↓
RESULTADO
   ↓
n8n
   ↓
WhatsApp
```

Esto coincide con la arquitectura actual del vault: las funciones PostgreSQL deben encapsular las operaciones transaccionales y n8n actuar como orquestador.

---

# 4. Meta Business Manager

RSUELVO debe tener una estructura empresarial en Meta similar a:

```text
Meta Business Portfolio
│
├── Meta App
│
├── WhatsApp Business Account (WABA)
│
│   ├── Phone Number
│   │
│   ├── Message Templates
│   │
│   └── Business Profile
│
└── System User
       │
       └── Access Token
```

## Componentes

### 4.1 Meta Business Portfolio

Representa la organización que administra los activos empresariales.

Debe ser propiedad/controlado por RSUELVO o por la entidad que corresponda al despliegue.

---

# 5. Meta App

Se debe crear una aplicación de Meta destinada a integrar WhatsApp Business Platform.

La aplicación será utilizada para:

- autenticación;
    
- acceso a WhatsApp;
    
- configuración de webhooks;
    
- gestión de tokens;
    
- acceso a Graph API.
    

La aplicación debe permanecer separada de la lógica de RSUELVO.

---

# 6. WhatsApp Business Account

La WABA representa la cuenta empresarial de WhatsApp.

Conceptualmente:

```text
Business Portfolio
       │
       ▼
      WABA
       │
       ├── Phone Number
       ├── Templates
       └── Business Profile
```

RSUELVO debe almacenar las referencias técnicas necesarias para saber qué WABA y qué número corresponden a cada integración.

---

# 7. Número de WhatsApp

El número conectado a Meta será el número que utilice RSUELVO para conversar con compradores.

Es importante diferenciar:

```text
Número telefónico
       ≠
WABA ID
       ≠
Phone Number ID
       ≠
Business Portfolio ID
```

RSUELVO debe trabajar principalmente con el **Phone Number ID** para las operaciones de mensajería de Cloud API.

---

# 8. Variables de configuración

Nunca introducir IDs ni tokens directamente dentro de los workflows.

Usar variables/credenciales:

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

El token jamás debe almacenarse:

- en Git;
    
- en archivos Markdown;
    
- en el vault;
    
- en código fuente;
    
- en nodos n8n visibles;
    
- en mensajes de logs.
    

---

# 9. Tokens

La arquitectura debe diferenciar:

```text
App Secret
Access Token
Verify Token
Webhook verification
```

El **Access Token** permite realizar operaciones autorizadas contra Graph API.

El **Verify Token** se utiliza para validar la configuración del webhook.

No son el mismo secreto.

---

# 10. System User

Para producción se recomienda utilizar una identidad de sistema apropiada para la integración en lugar de depender de credenciales personales de un administrador.

Conceptualmente:

```text
Meta Business
     │
     ▼
System User
     │
     ▼
WhatsApp assets
     │
     ▼
Access Token
     │
     ▼
n8n
```

El token debe recibir únicamente los permisos necesarios.

Principio:

> Least privilege.

---

# 11. Webhook de Meta

El webhook es la entrada principal de eventos hacia RSUELVO.

```text
WhatsApp
   ↓
Meta
   ↓
Webhook HTTPS
   ↓
n8n
```

El endpoint debe ser público y utilizar HTTPS.

Ejemplo conceptual (ruta canónica del vault — ver workflows.md WF-02):

```text
POST /webhooks/whatsapp/meta
```

No utilizar:

```text
http://localhost
```

ni endpoints internos de la infraestructura.

---

# 12. Verificación del webhook

Meta realizará una solicitud de verificación.

La integración debe validar:

```text
hub.mode
hub.verify_token
hub.challenge
```

Conceptualmente:

```text
Meta
 │
 │ GET verification
 ▼
Webhook
 │
 ├── verify token válido
 │
 └── devolver challenge
```

El endpoint debe rechazar tokens incorrectos.

---

# 13. Recepción de mensajes

Los mensajes entrantes deben entrar primero a un workflow de ingestión.

```text
META
 │
 ▼
WF-META-WEBHOOK
 │
 ├── validar evento
 ├── identificar tipo
 ├── normalizar payload
 ├── registrar evento
 └── enviar a router
```

No mezclar el webhook con todo el flujo comercial.

---

# 14. Normalización

Meta tiene una estructura de payload propia.

RSUELVO debe transformarla al **contrato interno canónico** definido en workflows.md §7 (fuente única), añadiendo los extras de Meta como campos opcionales:

```json
{
  "provider": "meta",
  "channel": "whatsapp",
  "message_id": "wamid....",
  "chat_id": "591XXXXXXXX",
  "phone": "591XXXXXXXX",
  "phone_number_id": "...",
  "type": "text",
  "text": "...",
  "media_id": null,
  "timestamp": "...",
  "raw": {}
}
```

Valores `provider` siempre en minúsculas (`meta`/`openwa`) y `type` en minúsculas (`text`/`image`/…), igual que el contrato existente. La lógica interna de RSUELVO debe trabajar con este modelo y no depender directamente del JSON de Meta.

---

# 15. Idempotencia

Esta es una de las reglas más importantes.

Un evento de Meta no debe procesarse dos veces.

La clave principal de deduplicación debe ser el identificador único del mensaje/evento recibido.

Conceptualmente:

```text
Meta event
    │
    ▼
¿message_id ya procesado?
    │
 ┌──┴──┐
 SI    NO
 │      │
 ▼      ▼
IGNORAR PROCESAR
```

Esto evita:

- reservas duplicadas;
    
- respuestas duplicadas;
    
- consumo doble de créditos;
    
- creación duplicada de pedidos;
    
- doble procesamiento de comprobantes.
    

---

# 16. Registro de eventos

Se recomienda mantener una capa de auditoría de eventos externos:

```text
META_EVENT
│
├── provider
├── event_id
├── message_id
├── phone_number_id
├── customer_phone
├── event_type
├── received_at
├── processed_at
├── processing_status
└── raw_payload
```

Si el schema actual no contempla una tabla específica para esto, debe evaluarse añadirla.

La tabla debe servir como frontera entre:

```text
Meta
   ↓
RSUELVO
```

y no sustituir la auditoría general del sistema.

---

# 17. Identificación del comprador

El comprador no posee una cuenta RSUELVO.

Esto está definido en la arquitectura:

```text
COMPRADOR
   ↓
WhatsApp
   ↓
Número telefónico
```

El teléfono debe convertirse en la identidad operacional del cliente.

El flujo debe ser:

```text
Número WhatsApp
      ↓
buscar tbl_clientes
      │
 ┌────┴────┐
 │         │
Existe    No existe
 │         │
 ▼         ▼
usar      crear
cliente   cliente
```

Nunca utilizar el número de WhatsApp como sustituto de una cuenta de autenticación administrativa.

---

# 18. Identificación del comercio

RSUELVO es multi-tenant.

Por lo tanto:

```text
Phone Number ID
       ↓
Integración WhatsApp
       ↓
id_comercio
```

El comercio nunca debe depender únicamente de un valor enviado por el usuario.

La relación debe resolverse desde la configuración interna de RSUELVO.

Esto es especialmente importante porque el vault define aislamiento por `id_comercio` mediante Supabase RLS.

---

# 19. Flujo de identificación

```text
Mensaje Meta
     ↓
Phone Number ID
     ↓
Buscar integración WhatsApp
     ↓
Obtener id_comercio
     ↓
Obtener cliente por teléfono
     ↓
Procesar mensaje
```

Esto evita:

```text
usuario → escribe id_comercio
```

como mecanismo de seguridad.

---

# 20. Router de mensajes

Después de normalizar el evento:

```text
META WEBHOOK
      ↓
MESSAGE ROUTER
      │
      ├── TEXT
      │
      ├── IMAGE
      │
      ├── DOCUMENT
      │
      ├── AUDIO
      │
      ├── LOCATION
      │
      └── UNKNOWN
```

Para el MVP, los tipos esenciales son:

```text
TEXT
IMAGE
```

---

# 21. Flujo de SKU

El flujo comercial definido por RSUELVO comienza cuando el comprador envía el SKU.

```text
COMPRADOR
   │
   │ FER1H001
   ▼
META
   ▼
n8n
   ▼
normalización
   ▼
fn_solicitar_reserva()
```

La función debe resolver atómicamente:

- SKU;
    
- comercio;
    
- inventario;
    
- reserva;
    
- lista de espera;
    
- condiciones del producto.
    

---

# 22. SKU inválido

```text
SKU
 ↓
validación
 ↓
NO VÁLIDO
 ↓
WhatsApp
 ↓
"SKU no encontrado"
```

No hacer consultas independientes desde n8n para después decidir.

---

# 23. Stock disponible

```text
SKU
 ↓
fn_solicitar_reserva()
 ↓
STOCK DISPONIBLE
 ↓
RESERVA_CREADA
 ↓
WhatsApp
```

La reserva y el bloqueo/descuento correspondiente deben estar protegidos por transacción.

---

# 24. Producto sin stock

Si no existe disponibilidad:

```text
fn_solicitar_reserva()
       ↓
SIN_STOCK
       ↓
¿Producto reservado?
       │
   ┌───┴────┐
   NO       SI
   │         │
   ▼         ▼
SIN STOCK   LISTA ESPERA
```

Esto corresponde al flujo MVP almacenado en el vault.

---

# 25. Lista de espera

La lista de espera debe ser controlada por PostgreSQL.

n8n solamente debe:

```text
mensaje
 ↓
fn_agregar_lista_espera()
 ↓
resultado
 ↓
respuesta WhatsApp
```

Nunca:

```text
SELECT posición
UPDATE posición
INSERT
```

desde diferentes nodos independientes.

---

# 26. Notificación de turno

Cuando una reserva vence:

```text
RESERVA
 ↓
EXPIRA
 ↓
liberar reserva
 ↓
buscar siguiente lista de espera
 ↓
notificar comprador
 ↓
¿acepta?
```

La notificación debe enviarse mediante Meta.

---

# 27. Respuesta a aceptación

Si el comprador acepta:

```text
ACEPTAR
 ↓
fn_aceptar_lista_espera()
 ↓
RESERVA_CREADA
 ↓
enviar QR
```

La función debe verificar nuevamente que la oportunidad siga disponible.

No confiar en que el estado que tenía n8n unos segundos antes siga siendo válido.

---

# 28. QR de pago

El QR es un activo del comercio.

La arquitectura actual establece que RSUELVO utiliza un QR estático del dueño y no genera QR dinámicos con monto.

Flujo:

```text
RESERVA
 ↓
obtener QR
 ↓
Meta
 ↓
WhatsApp
 ↓
comprador
```

El mensaje debe contener:

- producto;
    
- precio;
    
- comercio;
    
- instrucciones;
    
- QR;
    
- tiempo disponible para pagar.
    

---

# 29. Envío de imágenes

El comprador puede enviar el comprobante como imagen.

```text
IMAGE MESSAGE
      ↓
Meta media_id
      ↓
n8n
      ↓
Media API
      ↓
archivo
      ↓
OpenAI Vision
```

El `media_id` recibido por Meta no debe confundirse con una URL permanente.

El workflow debe obtener el recurso multimedia siguiendo el flujo oficial de Meta.

---

# 30. Comprobante de pago

El flujo actual de RSUELVO contempla:

```text
COMPROBANTE
   ↓
OCR / Vision
   ↓
extraer datos
   ↓
validar
   ├── monto
   ├── referencia
   ├── fecha
   ├── beneficiario
   └── duplicidad
   ↓
resultado
```

La IA no debe confirmar directamente una venta.

La IA únicamente proporciona datos/resultado para que la lógica de negocio pueda tomar una decisión.

---

# 31. Verificación de pago

La arquitectura actual define funciones como:

```text
fn_consumir_creditos()
fn_confirmar_pago()
fn_rechazar_verificacion()
```

y el sistema debe mantener el consumo de créditos dentro de operaciones transaccionales.

Flujo recomendado:

```text
Comprobante
     ↓
IA
     ↓
resultado estructurado
     ↓
PostgreSQL
     ↓
validación server-authoritative
     ↓
CONFIRMADO / RECHAZADO
```

---

# 32. No confiar en la IA

Nunca:

```text
GPT dice OK
 ↓
venta confirmada
```

Debe ser:

```text
GPT
 ↓
datos extraídos
 ↓
PostgreSQL
 ↓
reglas de negocio
 ↓
resultado definitivo
```

La IA no debe poder modificar:

- stock;
    
- créditos;
    
- reservas;
    
- pedidos;
    
- estados financieros.
    

---

# 33. Confirmación de pago

Si PostgreSQL confirma:

```text
PAGO_VALIDO
```

n8n envía:

```text
WhatsApp
 ↓
"Pago confirmado"
```

Después:

```text
solicitar datos de envío
```

---

# 34. Datos de envío

El flujo debe solicitar la información necesaria para crear el envío.

Conceptualmente:

```text
PAGO CONFIRMADO
       ↓
solicitar dirección
       ↓
comprador responde
       ↓
normalizar
       ↓
validar
       ↓
guardar
```

No crear el pedido definitivo hasta completar las condiciones necesarias.

---

# 35. Confirmación de compra

Flujo:

```text
PAGO
 ↓
ENVÍO
 ↓
CONFIRMACIÓN
 ↓
fn_crear_pedido_desde_reserva()
 ↓
fn_crear_envio()
 ↓
PEDIDO CONFIRMADO
```

La base de datos establece explícitamente que una reserva no equivale a una venta; la venta se confirma después de validar el pago.

---

# 36. Mensajes de Meta

RSUELVO debe diferenciar:

```text
Mensajes iniciados por comprador
```

de:

```text
Mensajes iniciados por RSUELVO
```

Esto es fundamental para cumplir las reglas de WhatsApp Business Platform.

Los mensajes iniciados por el negocio fuera de la ventana de atención aplicable deben utilizar el mecanismo de plantillas correspondiente.

---

# 37. Plantillas

RSUELVO debe mantener plantillas para eventos como:

```text
RESERVA_EXPIRADA
TURNO_DISPONIBLE
PAGO_CONFIRMADO
PEDIDO_CONFIRMADO
ENVIO_CREADO
ENVIO_EN_RUTA
ENVIO_ENTREGADO
ENVIO_NO_ENTREGADO
```

Las plantillas deben gestionarse en Meta y sus identificadores deben mantenerse en configuración.

Ejemplo:

```text
META_TEMPLATE_RESERVA
META_TEMPLATE_TURNO
META_TEMPLATE_PEDIDO
META_TEMPLATE_ENVIO
```

No escribir nombres de plantilla directamente en decenas de workflows.

---

# 38. Catálogo de plantillas

Se recomienda una configuración interna:

```text
template_code
       ↓
template_name
       ↓
language
       ↓
parameters
       ↓
Meta
```

Por ejemplo:

```text
RESERVA_EXPIRADA
       ↓
rsuelvo_reserva_expirada
       ↓
es
       ↓
[producto, sku]
```

---

# 39. Idioma

Las plantillas deben declarar explícitamente el idioma utilizado.

No asumir:

```text
language = es
```

sin comprobar que exista una plantilla aprobada para ese idioma.

---

# 40. Envío de mensajes

La capa de integración debe abstraer Meta.

En lugar de que todos los workflows construyan manualmente llamadas HTTP:

```text
POST Graph API
```

crear un subworkflow conceptual:

```text
WF-META-SEND-MESSAGE
```

Entrada:

```json
{
  "phone_number_id": "...",
  "to": "...",
  "type": "text",
  "content": {}
}
```

Salida:

```json
{
  "provider": "meta",
  "message_id": "...",
  "status": "accepted"
}
```

---

# 41. Tipos de envío

El adaptador debe contemplar al menos:

```text
TEXT
IMAGE
DOCUMENT
TEMPLATE
```

Y posteriormente:

```text
INTERACTIVE
LOCATION
```

si el producto evoluciona hacia esos casos.

---

# 42. Capa WhatsApp de RSUELVO

Se recomienda esta abstracción:

```text
RSUELVO WHATSAPP SERVICE
│
├── sendText()
├── sendImage()
├── sendTemplate()
├── sendDocument()
├── downloadMedia()
├── markAsRead()
└── parseIncomingEvent()
```

Implementación:

```text
WhatsAppService
      │
      ├── MetaCloudApiAdapter
      │
      └── OpenWaAdapter
```

Esto permite cambiar de proveedor sin reescribir la lógica comercial.

---

# 43. OpenWA vs Meta

La arquitectura existente utiliza OpenWA.

Sin embargo, para una integración empresarial estable se recomienda que:

```text
Lógica RSUELVO
      │
      ▼
WhatsApp abstraction
      │
      ├── Meta Cloud API
      │
      └── OpenWA
```

No:

```text
Lógica RSUELVO
      ↓
OpenWA directamente
```

Meta debe ser tratado como el proveedor oficial de producción cuando se requiera la plataforma empresarial oficial.

---

# 44. No mezclar proveedores sobre el mismo número

No diseñar:

```text
mismo número
    ├── OpenWA
    └── Meta Cloud API
```

como estrategia normal de producción.

La integración debe definir claramente quién es el propietario operacional del número.

Para migrar:

```text
OpenWA
   ↓
migración/alta oficial
   ↓
Meta
   ↓
Cloud API
```

La migración debe planificarse antes de mover producción.

---

## 45. Arquitectura n8n

> **Nota canónica:** la numeración oficial de workflows del vault es la de `workflows.md` (WF-00…WF-80, formato `RSU | nn | Módulo`). Los identificadores siguientes son **adaptadores específicos de Meta** y se mapean así: WF01→WF-02 · WF02/WF03→WF-03/04 · WF04-09→WF-10…24/40-42 según dominio · WF10→WF-80 · WF11→(parte de WF-21) · WF12→WF-00 · WF13→política §13. No crear una numeración paralela en producción.

Se recomienda dividir los adapters Meta así:
```text
WF01_META_WEBHOOK
WF02_META_NORMALIZE
WF03_META_ROUTER
WF04_SKU
WF05_RESERVA
WF06_LISTA_ESPERA
WF07_PAGO
WF08_COMPROBANTE_IA
WF09_ENVIO
WF10_META_SEND
WF11_META_MEDIA
WF12_META_ERROR
WF13_META_RETRY
```

No crear un workflow gigantesco.

---

# 46. WF01 — Meta Webhook

Responsabilidades:

- recibir webhook;
    
- validar estructura;
    
- registrar evento;
    
- responder rápidamente;
    
- evitar procesamiento pesado.
    

```text
META
 ↓
Webhook
 ↓
validación
 ↓
acknowledgement
 ↓
procesamiento asíncrono
```

El webhook no debería esperar a que GPT-4o Vision termine.

---

# 47. WF02 — Normalización

Transforma:

```text
Meta JSON
```

en:

```text
RSUELVO Message DTO
```

Ejemplo (alineado al contrato canónico — claves en minúscula):

```json
{
  "provider": "meta",
  "channel": "whatsapp",
  "id_comercio": "...",
  "phone": "591XXXXXXXX",
  "message_id": "...",
  "type": "image",
  "text": null,
  "media_id": "...",
  "received_at": "..."
}
```

---

# 48. WF03 — Router

```text
Message DTO
     │
     ├── TEXT → conversación
     │
     ├── IMAGE → comprobante
     │
     ├── DOCUMENT → comprobante/documento
     │
     └── OTHER → fallback
```

---

# 49. Estado conversacional

n8n no debe intentar inferir toda la conversación únicamente a partir del historial.

El estado importante debe persistirse.

Ejemplo conceptual:

```text
cliente
 ↓
contexto actual
 ↓
RESERVA
 ↓
ESPERANDO_PAGO
 ↓
ESPERANDO_ENVIO
 ↓
CONFIRMADO
```

El estado debe estar asociado al comercio y cliente.

---

# 50. Máquina de estados

> **Alineación canónica:** los estados conversacionales oficiales están en workflows.md §16: `IDLE, ESPERANDO_SKU, RESERVA_ACTIVA, ESPERANDO_PAGO, ESPERANDO_COMPROBANTE, PAGO_VALIDANDO, ESPERANDO_DIRECCION, PEDIDO_CONFIRMADO`. La máquina siguiente es el equivalente conceptual; implementar SIEMPRE los nombres canónicos.

Una máquina conceptual:

```text
INICIO (= IDLE)
  │
  ▼
SKU_RECIBIDO (= ESPERANDO_SKU)
  │
  ▼
RESERVA_CREADA (= RESERVA_ACTIVA)
  │
  ▼
ESPERANDO_PAGO
  │
  ├── PAGO_RECIBIDO
  │       │
  │       ▼
  │   VERIFICANDO (= ESPERANDO_COMPROBANTE / PAGO_VALIDANDO)
  │       │
  │       ├── RECHAZADO (→ ESPERANDO_COMPROBANTE, reenvío)
  │       │
  │       └── CONFIRMADO (= PEDIDO_CONFIRMADO)
  │                │
  │                ▼
  │          ESPERANDO_ENVIO (= ESPERANDO_DIRECCION)
  │                │
  │                ▼
  │             PEDIDO
  │
  └── EXPIRADO (reserva VENCIDA → vuelve a IDLE)
```

---

# 51. Errores

Los errores de Meta deben diferenciarse de los errores de negocio.

```text
META ERROR
     ≠
BUSINESS ERROR
```

Ejemplos:

```text
Meta:
token inválido
rate limit
media inexistente
endpoint incorrecto
```

versus:

```text
RSUELVO:
SKU inexistente
sin stock
reserva expirada
pago rechazado
datos de envío incompletos
```

---

# 52. Reintentos

No reintentar indiscriminadamente.

Clasificar:

```text
RETRYABLE
NON_RETRYABLE
```

Ejemplos potencialmente reintentables:

```text
timeout
error temporal
servicio temporalmente no disponible
```

Ejemplos no reintentables:

```text
token inválido
número inválido
template inexistente
payload inválido
```

---

# 53. Idempotencia de respuestas

Una respuesta enviada por n8n debe poder rastrearse:

```text
business_operation_id
       ↓
message_id
       ↓
Meta response
```

Esto permite saber:

```text
¿RSUELVO intentó enviar?
¿Meta aceptó?
¿Meta devolvió error?
¿se reintentó?
```

---

# 54. Auditoría

Toda operación relevante debe poder reconstruirse:

```text
Cliente
 ↓
mensaje Meta
 ↓
evento
 ↓
workflow n8n
 ↓
RPC
 ↓
resultado BD
 ↓
mensaje Meta
```

La auditoría es especialmente importante para:

- pagos;
    
- créditos;
    
- reservas;
    
- pedidos;
    
- cambios de estados;
    
- errores.
    

---

# 55. Seguridad

Nunca guardar en el vault:

```text
META_ACCESS_TOKEN
META_APP_SECRET
```

El vault puede documentar:

```text
META_ACCESS_TOKEN = [secret manager]
```

pero nunca el secreto real.

---

# 56. Secretos en n8n

Los secretos deben almacenarse mediante las credenciales/secret management apropiadas de n8n.

No:

```text
HTTP Request
Authorization:
Bearer EAAxxxxxxxx
```

dentro de un nodo compartido o exportado.

---

# 57. Logs

Nunca registrar:

```text
access_token
app_secret
```

Evitar también almacenar innecesariamente:

```text
comprobantes completos
datos sensibles
información financiera
```

Los logs deben contener identificadores técnicos.

---

# 58. Multi-tenant

El flujo debe ser:

```text
Meta Phone Number ID
        ↓
WhatsApp Integration
        ↓
id_comercio
        ↓
cliente
        ↓
operación
```

Nunca:

```text
mensaje → id_comercio enviado por cliente
```

como fuente de autoridad.

---

# 59. Relación con Supabase RLS

La arquitectura de RSUELVO utiliza:

```text
auth.uid()
   ↓
tbl_usuarios
   ↓
tbl_usuario_comercio
   ↓
id_comercio
   ↓
RLS
```

n8n debe utilizar el mecanismo backend apropiado para ejecutar operaciones server-side.

Cuando una operación pueda afectar datos de negocio, debe pasar por las funciones PostgreSQL correspondientes.

---

# 60. Funciones PostgreSQL relacionadas

La integración WhatsApp debe consumir las funciones existentes/diseñadas:

```text
fn_solicitar_reserva()
fn_agregar_lista_espera()
fn_aceptar_lista_espera()
fn_crear_pedido_desde_reserva()
fn_consumir_creditos()
fn_confirmar_pago()
fn_rechazar_verificacion()
fn_crear_envio()
```

Estas funciones están documentadas como la interfaz que n8n debe consumir.

---

# 61. Regla: n8n no modifica directamente reglas críticas

No hacer desde n8n:

```text
UPDATE inventario
UPDATE reservas
UPDATE créditos
UPDATE pedidos
```

para operaciones críticas.

Usar:

```text
n8n
 ↓
RPC
 ↓
PostgreSQL
```

---

# 62. Créditos de IA

El sistema utiliza créditos del comercio.

La operación debe ser atómica:

```text
verificación IA
       │
       ▼
validar crédito
       │
       ▼
bloquear cuenta
       │
       ▼
consumir crédito
       │
       ▼
registrar movimiento
```

No:

```text
SELECT créditos
 ↓
IF créditos > 0
 ↓
UPDATE créditos
```

porque existe riesgo de concurrencia.

---

# 63. Concurrencia

Casos críticos:

```text
Dos compradores
     │
     ▼
mismo SKU
     │
     ▼
última unidad
```

La base de datos debe decidir quién obtiene la reserva.

n8n no debe intentar resolver carreras mediante `IF`.

---

# 64. Duplicación de comprobantes

Caso:

```text
Comprador
 ↓
envía comprobante
 ↓
Meta entrega evento
 ↓
n8n procesa
 ↓
Meta/n8n repite evento
```

El resultado debe ser:

```text
primer evento → procesa
segundo evento → detecta duplicado → no consume crédito nuevamente
```

---

# 65. Estado de un comprobante

Conceptualmente (usando los enums canónicos de la BD — `estado_comprobante`):

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
INVALIDO / RECHAZADO
```

Los estados definitivos deben ser controlados por PostgreSQL.

---

# 66. Envíos

Después de confirmar el pago:

```text
fn_crear_envio()
```

El comprador puede recibir:

```text
Pedido confirmado.
Tu pedido es RS-XXXXX.
```

Después, el sistema logístico puede emitir:

```text
EN_RUTA
ENTREGADO
NO_ENTREGADO
```

y utilizar Meta para notificaciones.

---

# 67. Roles administrativos

El canal WhatsApp pertenece principalmente al comprador.

Los roles internos continúan utilizando Flutter:

```text
TENANT_ADMIN
TENANT_CASHIER
LOGISTICS_AGENT
SUPPORT
SYSADMIN
SUPERADMIN
```

La arquitectura del vault define esos seis roles canónicos.

WhatsApp no debe convertirse en una interfaz administrativa improvisada.

---

# 68. Métricas

Debe poder medirse:

```text
mensajes recibidos
mensajes enviados
SKU solicitados
reservas creadas
listas de espera
comprobantes recibidos
comprobantes verificados
comprobantes rechazados
pedidos creados
errores Meta
errores n8n
tiempo de respuesta
```

---

# 69. Correlation ID

Cada operación importante debería disponer de un identificador:

```text
correlation_id
```

Ejemplo:

```text
RSV-20260824-000123
```

Ese ID puede relacionar:

```text
Meta event
n8n execution
reserva
pago
pedido
envío
logs
```

---

# 70. Estructura recomendada de integración

```text
RSUELVO
│
├── WhatsApp
│   ├── Meta
│   │   ├── Webhook
│   │   ├── Messages
│   │   ├── Media
│   │   └── Templates
│   │
│   └── OpenWA
│       └── Legacy adapter
│
├── n8n
│   ├── ingestion
│   ├── routing
│   ├── commerce
│   ├── payments
│   ├── logistics
│   └── notifications
│
└── Supabase
    ├── business rules
    ├── transactions
    ├── RLS
    └── audit
```

---

# 71. Flujo completo final

```text
┌──────────────┐
│  COMPRADOR   │
└──────┬───────┘
       │
       │ SKU
       ▼
┌──────────────┐
│    META      │
│  WHATSAPP    │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│     n8n      │
│   WEBHOOK    │
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ NORMALIZAR EVENTO│
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ IDENTIFICAR      │
│ COMERCIO/CLIENTE │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ ROUTER           │
└───────┬──────────┘
        │
        ▼
┌──────────────────┐
│ fn_solicitar_    │
│ reserva()        │
└────────┬─────────┘
         │
         ├── SIN STOCK
         │
         ├── LISTA ESPERA
         │
         └── RESERVA
                  │
                  ▼
          ┌──────────────┐
          │ META WHATSAPP│
          │ QR + INFO    │
          └──────┬───────┘
                 │
                 ▼
             COMPRADOR
                 │
                 │ comprobante
                 ▼
             META MEDIA
                 │
                 ▼
                n8n
                 │
                 ▼
          GPT-4o Vision
                 │
                 ▼
        datos estructurados
                 │
                 ▼
        PostgreSQL/RPC
                 │
          ┌──────┴──────┐
          │             │
       RECHAZADO     CONFIRMADO
          │             │
          ▼             ▼
        META        DATOS ENVÍO
                        │
                        ▼
                  fn_crear_pedido
                        │
                        ▼
                   fn_crear_envio
                        │
                        ▼
                       META
                        │
                        ▼
                    COMPRADOR
```

---

# 72. Checklist de implementación

-  Crear/configurar Meta Business Portfolio.
    
-  Crear Meta App.
    
-  Crear/configurar WABA.
    
-  Registrar número de WhatsApp.
    
-  Configurar Business Profile.
    
-  Configurar permisos necesarios.
    
-  Crear System User.
    
-  Generar/configurar access token.
    
-  Configurar webhook HTTPS.
    
-  Implementar verificación del webhook.
    
-  Crear workflow de ingestión en n8n.
    
-  Implementar deduplicación.
    
-  Implementar normalización Meta → RSUELVO.
    
-  Resolver Phone Number ID → comercio.
    
-  Resolver teléfono → cliente.
    
-  Implementar router.
    
-  Implementar envío de texto.
    
-  Implementar envío de imágenes.
    
-  Implementar descarga de medios.
    
-  Implementar templates.
    
-  Implementar workflow SKU.
    
-  Conectar `fn_solicitar_reserva()`.
    
-  Conectar lista de espera.
    
-  Conectar aceptación de turno.
    
-  Conectar QR.
    
-  Conectar comprobante.
    
-  Conectar Vision.
    
-  Implementar idempotencia de comprobantes.
    
-  Conectar `fn_confirmar_pago()`.
    
-  Conectar `fn_rechazar_verificacion()`.
    
-  Implementar captura de envío.
    
-  Conectar `fn_crear_pedido_desde_reserva()`.
    
-  Conectar `fn_crear_envio()`.
    
-  Implementar notificaciones logísticas.
    
-  Implementar reintentos.
    
-  Implementar logs.
    
-  Implementar correlation IDs.
    
-  Probar concurrencia.
    
-  Probar duplicación de webhooks.
    
-  Probar expiración de reservas.
    
-  Probar recuperación ante errores de Meta.
    
-  Probar migración OpenWA → Meta.
    
-  Realizar pruebas end-to-end.
    

---

# 73. Criterios de aceptación

La integración se considera correctamente implementada cuando:

1. Un comprador puede enviar un SKU por WhatsApp.
    
2. Meta entrega el mensaje a n8n.
    
3. n8n identifica correctamente el comercio.
    
4. n8n identifica/crea el cliente.
    
5. PostgreSQL decide si existe stock.
    
6. PostgreSQL crea la reserva de forma atómica.
    
7. n8n responde mediante Meta.
    
8. El QR puede enviarse correctamente.
    
9. El comprobante puede recibirse.
    
10. El media ID puede convertirse en el archivo correspondiente.
    
11. Vision puede analizar el comprobante.
    
12. PostgreSQL decide el resultado definitivo.
    
13. Un comprobante duplicado no consume créditos nuevamente.
    
14. Un pago válido puede convertirse en pedido.
    
15. El envío puede crearse.
    
16. Las notificaciones llegan al comprador.
    
17. Los eventos pueden auditarse.
    
18. Un error de Meta no corrompe una operación de negocio.
    
19. Una repetición de webhook no duplica operaciones.
    
20. Ningún secreto de Meta aparece en el repositorio.
    
21. Ninguna regla crítica depende exclusivamente de n8n.
    
22. El comercio A nunca puede operar accidentalmente sobre datos del comercio B.
    

---

# 74. Regla de oro de RSUELVO

La integración debe respetar siempre esta separación:

```text
META
   =
CANAL

n8n
   =
ORQUESTACIÓN

OPENAI
   =
EXTRACCIÓN / IA

POSTGRESQL
   =
VERDAD Y REGLAS DE NEGOCIO

SUPABASE
   =
BACKEND + RLS + DATA

FLUTTER
   =
INTERFAZ ADMINISTRATIVA

COMPRADOR
   =
WHATSAPP
```

La arquitectura de RSUELVO ya establece precisamente esta separación entre WhatsApp, n8n, Supabase y Flutter.

---

# 75. Documentación oficial que debe acompañar esta guía

Para la implementación real se debe contrastar esta guía con la documentación vigente de Meta sobre:

- WhatsApp Business Platform.
    
- Cloud API.
    
- Graph API.
    
- Webhooks.
    
- Media.
    
- Message Templates.
    
- Business Management API.
    
- Embedded Signup, si posteriormente RSUELVO permite onboarding de comercios.
    
- permisos y tokens.
    
- límites y políticas de mensajería.
    

**No fijar una versión de Graph API permanentemente en la documentación de RSUELVO.**

La versión debe mantenerse como configuración:

```text
META_GRAPH_API_VERSION
```

y actualizarse de forma controlada cuando Meta retire la versión utilizada.

---

# 76. Decisión recomendada para RSUELVO

La arquitectura definitiva debería quedar:

```text
                    RSUELVO
                       │
                       ▼
              WHATSAPP SERVICE
                       │
             ┌─────────┴─────────┐
             │                   │
             ▼                   ▼
       META CLOUD API         OPENWA
        PRODUCCIÓN          LEGACY/DEV
             │
             ▼
            n8n
             │
       ┌─────┴─────┐
       ▼           ▼
    OpenAI      Supabase
                   │
                   ▼
              PostgreSQL
                   │
             REGLAS ACID
```

La lógica comercial **no debe saber si el mensaje vino de Meta u OpenWA**.

Solo debe recibir:

```text
IncomingMessage
```

y producir:

```text
OutgoingMessage
```

De esta manera, RSUELVO puede migrar completamente de OpenWA a Meta sin reconstruir el sistema comercial.

---

## Referencias internas del vault

- `01-Arquitectura/arquitectura-general.md`
    
- `01-Arquitectura/Diagrama de Flujo DEFINIDO MVP.mermaid`
    
- `02-Base-de-Datos/Rsuelvo_Documentacion_Base_de_Datos.md`
    
- `02-Base-de-Datos/Funciones principales que n8n debería consumir.md`
    
- `02-Base-de-Datos/sql/06_functions.sql`
    
- `02-Base-de-Datos/sql/07_triggers.sql`
    
- `02-Base-de-Datos/sql/08_rls.sql`
    
- `02-Base-de-Datos/sql/09_views.sql`
    
- `02-Base-de-Datos/sql/12_cron.sql`