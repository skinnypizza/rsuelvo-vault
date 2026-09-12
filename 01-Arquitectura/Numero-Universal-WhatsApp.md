# Número universal de WhatsApp — RSUELVO (explicación familiar + técnica)

> **Estado:** documento informativo 2026-09-12. Nada implementado todavía.
> **Decisión pendiente:** aprobar el diseño de ruteo (D16 propuesta) antes de tocar código.
> Lectura previa: `00-Index/00-PROMPT-MAESTRO-RSUELVO.md` (vale como ley; este archivo no lo contradice).

---

## PARTE 1 — Para la familia (sin tecnicismos)

### La situación
RSUELVO usa **un solo número de WhatsApp para todos los comercios y sucursales**.
Cada sucursal tiene su **live exclusivo en TikTok**, pero todos los mensajes llegan al mismo número.

Piensen en el número como **la puerta de un shopping**: todos entran por ahí.
El problema: al entrar, hay que adivinar de qué tienda y sucursal viene cada persona.

### Lo que SÍ se sabe gratis: la tienda
El código del producto (SKU) empieza con 3 letras que son como la **placa del auto**:
identifican una sola tienda en todo el sistema (`FER`J01 = Feria, siempre).
Si el mensaje trae un código, la tienda se sabe sola.

### Lo que NO se sabe: la sucursal (ni los "hola")
El código es igual en Principal, Norte y Pampahasi. Y si alguien solo dice "hola",
no sabemos ni la tienda. Por eso el ruteo funciona en 3 capas, como un embudo:

1. **Link etiquetado del live (principal, cero esfuerzo):** cada live de TikTok publica
   su propio link de WhatsApp que llega pre-marcado con la sucursal
   (ej: `wa.me/<numero>?text=Hola%20NORTE`). Si el cliente entra por ahí, ya sabemos todo.
2. **Preguntar (respaldo):** si no se sabe, el sistema pregunta
   "¿de qué sucursal nos escribís? 1. Principal 2. Norte…".
3. **Recordar (comodidad):** si ya compró antes, se recuerda su última sucursal
   (siempre confirmable, nunca asumida a ciegas entre tiendas distintas).

### Los 3 riesgos a hablar en familia
1. **Cupo compartido:** WhatsApp limita mensajes por número; al ser uno solo, todas las
   tiendas consumen del mismo cupo. Vigilar al crecer.
2. **Reputación compartida (el más serio):** si una tienda hace spam y WhatsApp castiga
   el número, caen todas. Hacen falta reglas claras para las tiendas.
3. **El cliente ve "RSUELVO"**, no la tienda, en su chat. Decidir si es respaldo de marca
   aceptado o si molesta.

### Lo que NO cambia (garantizado)
- El **SKU sigue igual** en todas las sucursales (veredicto técnico 2026-09-12).
- Precios y stocks por sucursal siguen funcionando.
- La plata y los datos de cada tienda siguen separados: un comprador jamás ve nada
  de otra tienda.

### Decisiones pendientes de la familia
- [ ] Nombre visible del número (¿"RSUELVO" está bien?).
- [ ] Estrategia de plantillas Meta (son por cuenta, no por tienda).
- [ ] Formato del link por live (código de sucursal que trae pre-llenado).
- [ ] Reglas anti-spam para las tiendas (por la reputación compartida).
- [ ] Política de "recordar sucursal" (¿se pregunta siempre o se confía?).

---

## PARTE 2 — Para agentes (implicancias técnicas)

- `codigo_tienda` es **globalmente único** (`tbl_comercios_codigo_tienda_key` verificado):
  SKU[0:3] → una tienda → un comercio. Llave de ruteo de comercio sin canal.
- Sucursal: sin señal en el SKU; resolver por (a) código en `?text=` del link,
  (b) menú de sucursales, (c) última sucursal del cliente (confirmada).
- **Blast radius si se implementa:** reescritura del resolvedor WF-02/WF-04 (hoy resuelve
  por canal/`phone_number_id`); remodelo de `tbl_canal_whatsapp` (1 fila universal +
  ruteo por conversación); `fn_resolver_variante_por_sku` y `fn_identificar_*` revisados;
  WF-80 envía siempre por el mismo `phone_number_id`; rate-limit y quality globales
  (F7); re-auditoría RLS anti-fuga entre tenants; Matriz + Maestro (D16) actualizados.
- Identidad D10 intacta: `(id_comercio, telefono)`; un teléfono puede ser cliente de
  varios comercios (memoria siempre por par, nunca global por teléfono).
- STOP/opt-out por `(id_comercio, teléfono)` sigue correcto.
- **Nada de lo anterior está implementado.** Flujo: diseño → aprobación familiar →
  implementación por fases.
