

**Versión:** 1.0  
**Proyecto:** RSUELVO  
**Estado:** Normativa técnica obligatoria  
**Componentes afectados:** OpenWA, n8n, Supabase, WhatsApp y API oficial de Meta  
**Última actualización:** 24 de agosto de 2026

---

## 1. Propósito

Esta política establece las reglas técnicas y operativas que RSUELVO debe seguir al utilizar WhatsApp mediante OpenWA y/o la API oficial de Meta.

El objetivo es:

- Minimizar el riesgo de restricciones, bloqueos o suspensión de cuentas.
    
- Evitar comportamientos similares al spam.
    
- Garantizar que las automatizaciones sean transaccionales y legítimas.
    
- Evitar mensajes duplicados o excesivos.
    
- Mantener trazabilidad de todas las comunicaciones.
    
- Permitir detener automáticamente una instancia ante comportamientos anómalos.
    
- Mantener una arquitectura compatible con una futura migración o convivencia con la API oficial de Meta.
    

> **Importante:** ninguna configuración puede garantizar riesgo cero de bloqueo. La finalidad de esta política es reducir el riesgo mediante un comportamiento legítimo, controlado y técnicamente trazable.

---

# 2. Principio fundamental

RSUELVO utilizará WhatsApp como **canal transaccional de comunicación entre compradores, vendedores y el sistema**.

OpenWA no debe utilizarse como plataforma de marketing masivo, scraping, spam o contacto indiscriminado.

El sistema debe responder principalmente a interacciones iniciadas por los usuarios o relacionadas directamente con operaciones existentes.

### Flujo permitido

```text
Cliente
   │
   │ mensaje / comprobante / información del pedido
   ▼
WhatsApp
   │
   ▼
OpenWA / Meta API
   │
   ▼
n8n
   │
   ▼
Lógica de RSUELVO
   │
   ▼
Base de datos
   │
   ▼
Cola de mensajes
   │
   ▼
Rate Limiter
   │
   ▼
OpenWA / Meta API
   │
   ▼
Cliente
```

---

# 3. Alcance

Esta política aplica a:

- Todas las instancias de OpenWA utilizadas por RSUELVO.
    
- Todos los workflows de n8n relacionados con WhatsApp.
    
- Todos los servicios que puedan generar mensajes.
    
- Todas las tiendas conectadas a RSUELVO.
    
- La base de datos utilizada para registrar conversaciones y mensajes.
    
- La futura integración con la API oficial de WhatsApp Business de Meta.
    

Ningún workflow podrá saltarse estas reglas mediante una llamada directa a OpenWA.

---

# 4. Arquitectura de comunicación

La comunicación deberá dividirse conceptualmente en:

## 4.1 Recepción

```text
WhatsApp
   ↓
OpenWA / Meta API
   ↓
Webhook
   ↓
n8n
```

La recepción debe ser lo más pasiva posible.

El sistema recibe:

- mensajes;
    
- imágenes;
    
- comprobantes;
    
- códigos de producto;
    
- información de entrega;
    
- respuestas del comprador;
    
- eventos relevantes.
    

---

## 4.2 Procesamiento

```text
Webhook
   ↓
Normalización
   ↓
Identificación de tienda
   ↓
Identificación de usuario
   ↓
Idempotencia
   ↓
Procesamiento
   ↓
Actualización de BD
```

---

## 4.3 Envío

Todos los mensajes salientes deberán pasar por:

```text
Solicitud de mensaje
       ↓
Validación
       ↓
¿Permitido?
   ├── NO → cancelar
   └── SÍ
        ↓
Message Queue
        ↓
Rate Limiter
        ↓
Circuit Breaker
        ↓
OpenWA / Meta API
```

No se permitirá:

```text
Workflow
   ↓
HTTP Request
   ↓
OpenWA
```

sin pasar por las validaciones correspondientes.

---

# 5. Regla de no spam

RSUELVO queda prohibido de utilizarse para:

- envío masivo de mensajes;
    
- campañas no solicitadas;
    
- mensajes promocionales indiscriminados;
    
- spam;
    
- mensajes repetitivos;
    
- scraping de números de teléfono;
    
- compra o importación de listas de números;
    
- contacto automático con números que nunca interactuaron con la tienda;
    
- automatizaciones destinadas a evadir mecanismos de detección de WhatsApp.
    

El sistema debe priorizar siempre la **necesidad transaccional del mensaje**.

---

# 6. Regla de conversación iniciada por el usuario

Como principio general:

> RSUELVO no deberá iniciar conversaciones con números desconocidos únicamente porque exista un número telefónico almacenado en la base de datos.

Un número almacenado en la BD **no constituye por sí mismo autorización para enviar mensajes**.

Los mensajes automáticos deberán estar relacionados con:

- una conversación existente;
    
- una compra;
    
- un pedido;
    
- un pago;
    
- una entrega;
    
- una solicitud realizada por el usuario;
    
- otra operación legítima de RSUELVO.
    

---

# 7. Regla de minimización de mensajes

RSUELVO debe enviar solamente los mensajes necesarios.

No se debe enviar:

```text
"Hola"
"¿Sigues ahí?"
"Recuerda tu pedido"
"¿Ya viste esto?"
"Tenemos novedades"
```

si no existe una razón transaccional concreta.

El sistema deberá preferir:

```text
Comprobante recibido.
Estamos verificando tu pago.
```

en lugar de múltiples mensajes innecesarios.

---

# 8. Mensajes agrupados

Cuando varias acciones puedan comunicarse en un único mensaje, deberá preferirse un solo mensaje.

### Incorrecto

```text
Pago recibido.

Estamos verificando.

Espera un momento.

Tu pedido está casi listo.
```

### Preferible

```text
Recibimos tu comprobante y estamos verificando el pago. Te avisaremos cuando el pedido quede confirmado.
```

Esto reduce:

- volumen de mensajes;
    
- riesgo de duplicación;
    
- ruido para el usuario;
    
- carga sobre OpenWA.
    

---

# 9. Rate Limiting

Todos los mensajes salientes deben pasar por un mecanismo de control de velocidad.

El sistema deberá controlar como mínimo:

- mensajes por instancia;
    
- mensajes por tienda;
    
- mensajes por número;
    
- mensajes por unidad de tiempo;
    
- cantidad de mensajes pendientes;
    
- cantidad de errores;
    
- cantidad de reintentos.
    

Los límites deberán ser configurables y no estar dispersos dentro de múltiples workflows.

---

# 10. Cola de mensajes

RSUELVO deberá utilizar una cola lógica para los mensajes salientes.

Conceptualmente:

```text
pending
   ↓
queued
   ↓
processing
   ↓
sent
```

Estados de error:

```text
failed
retry_pending
cancelled
```

La cola deberá impedir que múltiples workflows intenten enviar simultáneamente al mismo número o instancia sin coordinación.

---

# 11. Idempotencia

Toda operación relacionada con mensajes deberá ser idempotente cuando sea posible.

Cada evento recibido deberá disponer de un identificador único.

Ejemplo:

```text
message_id
```

Antes de procesar:

```text
¿message_id existe?

       ├── Sí
       │    ↓
       │  Ignorar evento duplicado
       │
       └── No
            ↓
         Procesar
            ↓
         Registrar
```

Esto es obligatorio especialmente para:

- webhooks;
    
- comprobantes;
    
- respuestas;
    
- confirmaciones;
    
- actualizaciones de pedidos.
    

---

# 12. Protección contra mensajes duplicados

Antes de enviar un mensaje, el sistema deberá comprobar si ya existe un envío equivalente.

Debe evitarse:

```text
Pedido confirmado
Pedido confirmado
Pedido confirmado
```

por:

- reintentos;
    
- ejecución simultánea de workflows;
    
- duplicación de webhooks;
    
- errores de red;
    
- reinicios de n8n.
    

---

# 13. Reintentos

Los errores de envío no deberán generar reintentos ilimitados.

El sistema utilizará una estrategia de **exponential backoff**.

Conceptualmente:

```text
Intento 1
   ↓
espera
   ↓
Intento 2
   ↓
espera mayor
   ↓
Intento 3
   ↓
evaluación
```

Después de superar el número máximo de reintentos:

```text
failed
```

y se generará un registro de error.

---

# 14. Circuit Breaker

RSUELVO deberá disponer de un mecanismo de **circuit breaker**.

Si una instancia presenta un comportamiento anormal:

```text
Errores elevados
       ↓
Rate limit
       ↓
Errores continúan
       ↓
Circuit Breaker
       ↓
PAUSAR ENVÍOS
```

El sistema no deberá seguir intentando enviar indefinidamente.

El circuito podrá tener estados:

```text
CLOSED
   ↓
OPEN
   ↓
HALF_OPEN
   ↓
CLOSED
```

### CLOSED

Los mensajes pueden enviarse normalmente.

### OPEN

Los envíos automáticos se detienen temporalmente.

### HALF_OPEN

Se permite una cantidad controlada de pruebas para determinar si el servicio se recuperó.

---

# 15. Detección de comportamiento anómalo

RSUELVO deberá monitorear indicadores como:

- aumento repentino de errores;
    
- incremento inusual de mensajes;
    
- múltiples fallos consecutivos;
    
- duplicaciones;
    
- desconexiones frecuentes;
    
- incremento de reintentos;
    
- acumulación de mensajes pendientes;
    
- comportamiento inesperado de una instancia.
    

Cuando se detecte una anomalía importante:

```text
Detectar
   ↓
Registrar
   ↓
Reducir velocidad
   ↓
Evaluar
   ↓
Pausar si corresponde
```

---

# 16. Opt-out

RSUELVO debe respetar las solicitudes explícitas de no recibir comunicaciones.

Ejemplos:

```text
STOP
NO QUIERO
NO ME CONTACTEN
```

El sistema deberá registrar la decisión.

Conceptualmente:

```text
contact_preferences
-------------------
phone
opted_out
opted_out_at
```

Si:

```text
opted_out = true
```

no deberán enviarse comunicaciones automáticas no esenciales.

---

# 17. Separación por tienda

Cada número de WhatsApp asociado a RSUELVO deberá pertenecer a una única tienda.

Principio:

```text
1 WhatsApp
      ↓
1 Tienda
```

No se deberá mezclar:

```text
Tienda A
   ↓
WhatsApp A

Tienda B
   ↓
WhatsApp B
```

Una instancia no deberá utilizarse arbitrariamente como identidad de múltiples tiendas.

---

# 18. Aislamiento de sesiones

Cada instancia deberá disponer de identificación propia.

Como mínimo deberá poder determinarse:

```text
instance_id
store_id
phone_number
provider
status
created_at
last_seen_at
```

Esto permitirá conocer exactamente qué tienda y qué instancia originaron un mensaje.

---

# 19. Compatibilidad con Meta API

La arquitectura de RSUELVO deberá diseñarse de manera que la lógica de negocio no dependa directamente de OpenWA.

Se deberá utilizar conceptualmente una capa de abstracción:

```text
RSUELVO
   ↓
WhatsApp Messaging Service
   ↓
┌───────────────┬───────────────┐
│    OpenWA     │    Meta API   │
└───────────────┴───────────────┘
```

Esto permitirá cambiar de proveedor sin modificar toda la lógica de negocio.

---

# 20. Prohibición de evasión

RSUELVO no deberá implementar mecanismos cuyo propósito sea evadir deliberadamente las restricciones o sistemas de detección de WhatsApp.

Queda fuera de arquitectura:

- técnicas para engañar sistemas anti-spam;
    
- falsificación de comportamiento humano;
    
- generación artificial de actividad;
    
- rotación artificial de cuentas para continuar enviando después de una restricción;
    
- automatización diseñada para ocultar el volumen real;
    
- utilización de múltiples cuentas para eludir límites.
    

La seguridad se conseguirá mediante **uso legítimo y controlado**, no mediante evasión.

---

# 21. Registro de mensajes

RSUELVO deberá mantener trazabilidad suficiente de los mensajes.

La estructura conceptual mínima deberá registrar:

```text
WhatsAppMessageLog
------------------
id
instance_id
store_id
phone
direction
message_type
provider
provider_message_id
status
retry_count
error_code
error_message
created_at
sent_at
```

Para mensajes entrantes también deberá conservarse el identificador proporcionado por el proveedor.

---

# 22. Auditoría

Los eventos críticos deberán quedar registrados.

Ejemplos:

```text
MESSAGE_RECEIVED
MESSAGE_QUEUED
MESSAGE_SENT
MESSAGE_FAILED
MESSAGE_RETRY
MESSAGE_CANCELLED
RATE_LIMIT_TRIGGERED
CIRCUIT_OPENED
CIRCUIT_CLOSED
INSTANCE_CONNECTED
INSTANCE_DISCONNECTED
OPT_OUT_REGISTERED
```

Esto permitirá investigar incidentes sin depender exclusivamente de los logs de n8n.

---

# 23. Regla de fallo seguro

Cuando el sistema no pueda determinar con seguridad si un mensaje debe enviarse:

> **No enviar.**

Es preferible retrasar o cancelar un mensaje que realizar un envío incorrecto, duplicado o no autorizado.

---

# 24. Principio de mínima automatización

RSUELVO automatizará únicamente las tareas necesarias para cumplir su función.

El objetivo no será maximizar el número de mensajes enviados.

El objetivo será:

```text
Menos mensajes
+
Mensajes relevantes
+
Mensajes oportunos
+
Mensajes trazables
=
Comunicación segura
```

---

# 25. Reglas específicas para n8n

Ningún workflow deberá:

- enviar directamente grandes cantidades de mensajes;
    
- realizar loops ilimitados sobre números telefónicos;
    
- hacer reintentos infinitos;
    
- ignorar errores de OpenWA;
    
- duplicar eventos;
    
- enviar mensajes sin comprobar el estado de la conversación;
    
- saltarse el rate limiter;
    
- saltarse la cola;
    
- saltarse el circuit breaker.
    

Los workflows deberán delegar el envío al servicio/capa correspondiente.

---

# 26. Regla para nuevos workflows

Antes de aprobar un nuevo workflow que utilice WhatsApp deberá verificarse:

- ¿El mensaje tiene una razón transaccional?
    
- ¿El usuario inició o provocó la interacción?
    
- ¿Existe una operación asociada?
    
- ¿El número está correctamente identificado?
    
- ¿El mensaje puede duplicarse?
    
- ¿Pasa por idempotencia?
    
- ¿Pasa por rate limiting?
    
- ¿Pasa por la cola?
    
- ¿Pasa por circuit breaker?
    
- ¿Existe registro de auditoría?
    
- ¿Qué ocurre si OpenWA falla?
    
- ¿Qué ocurre si el mensaje se procesa dos veces?
    
- ¿Qué ocurre si el usuario solicita no recibir mensajes?
    

Si alguna respuesta es negativa, el workflow no deberá pasar a producción.

---

# 27. Reglas de emergencia

Si una instancia presenta comportamiento sospechoso o errores anormales:

```text
1. Detener envíos automáticos.
2. Mantener recepción si es segura.
3. Registrar el incidente.
4. Identificar la instancia afectada.
5. Revisar logs.
6. Revisar volumen de mensajes.
7. Revisar errores y reintentos.
8. Determinar causa.
9. Corregir.
10. Realizar recuperación controlada.
```

Nunca se deberá responder a una anomalía aumentando automáticamente la velocidad de envío.

---

# 28. Objetivo de la política

La política establece una filosofía clara para RSUELVO:

> **RSUELVO no debe intentar comportarse como un usuario humano para evitar ser detectado. Debe comportarse como un sistema legítimo, transaccional, controlado, predecible y respetuoso con los usuarios.**

OpenWA será tratado como un **proveedor de transporte de mensajes**, no como un mecanismo para realizar spam o evadir las políticas de WhatsApp.

---

# 29. Regla de oro

Toda implementación de WhatsApp en RSUELVO deberá cumplir:

```text
LEGÍTIMO
    +
RELEVANTE
    +
LIMITADO
    +
IDEMPOTENTE
    +
TRAZABLE
    +
CONTROLADO
    +
RECUPERABLE
```

Si una funcionalidad no puede cumplir estos principios, deberá ser revisada antes de implementarse.

---

## 30. Estado de cumplimiento

Una implementación se considerará **apta para producción** únicamente cuando:

-  exista rate limiting;
    
-  exista cola de mensajes;
    
-  exista idempotencia;
    
-  existan límites de reintentos;
    
-  exista exponential backoff;
    
-  exista circuit breaker;
    
-  exista registro de mensajes;
    
-  exista auditoría;
    
-  exista control de opt-out;
    
-  exista aislamiento por tienda;
    
-  exista identificación de instancia;
    
-  los workflows no puedan saltarse los controles;
    
-  se haya probado la recuperación ante errores;
    
-  se haya probado la duplicación de webhooks;
    
-  se haya probado la caída de OpenWA;
    
-  se haya probado la acumulación de mensajes;
    
-  se haya verificado la compatibilidad arquitectónica con Meta API.
    

---

# 31. Vigencia

Esta política forma parte de las reglas técnicas de RSUELVO y deberá aplicarse a cualquier nueva integración, workflow o modificación relacionada con WhatsApp.

Cualquier excepción deberá documentarse y aprobarse antes de desplegarse en producción.

**Fin de la Política Técnica de Uso de WhatsApp y OpenWA — RSUELVO**