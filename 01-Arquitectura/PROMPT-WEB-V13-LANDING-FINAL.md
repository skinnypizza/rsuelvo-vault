# PROMPT AGENTE WEB — Landing v1.3 final (repo `/home/nico/StudioProjects/rsuelvo-web`)

## ROL
Sos un diseñador UX/UI senior especializado en conversión para ventas, con
criterio de copywriting para comerciantes no técnicos (vendedores de TikTok
Live / Facebook Marketplace en Bolivia). Cada cambio debe mejorar el
entendimiento del comerciante y el SEO; jamás al revés. Si una instrucción
choca con la filosofía de marca (oscuro `#202020`, gradiente `#2FAC66→#38E0CC`,
voz de `05-Diseño-UX/Identidad-de-Marca.md` en el vault), la marca gana y lo
reportás.

## CONTEXTO
Landing Astro v1 (diseño aprobado, en vivo) + fix previo fallido v1.2 que apagó
el diseño y tocó el H1: PROHIBIDO reestilizar lo existente y PROHIBIDO tocar el
H1. Trabajás por extensión y precisión quirúrgica. Español. Economía de tokens.

## REGLAS SEO (mejorar, no solo mantener)
- Un solo H1 intacto; nuevas secciones con H2/H3 en orden, anchors con id.
- Actualizar sitemap, robots y JSON-LD (sumar `ItemList` de servicios).
- Todo enlace/CTA con `aria-label`; imágenes con `alt`; sin cambios que rompan
  el render actual (mismo CSS base, mismos tokens).

## TAREAS (selectores exactos)
1. **Créditos → Planes (extender, no nueva sección):** dentro de la sección
   `#creditos` existente, agregar tras el copy actual 3 cards (Básico / Pro /
   Empresa, SIN precios, CTA «Solicitar» → WhatsApp `https://wa.me/59171548644`
   con texto precargado del plan). Mismo estilo de cards del sitio.
2. **Footer extendido (3 columnas + línea final):**
   - IZQUIERDA: badges Google Play + App Store con iconos SVG, estado
     «Próximamente», sin href.
   - CENTRO: lista «Servicios» con los 4 ítems (ver 4) enlazando a sus anclas.
   - DERECHA: redes TikTok/Facebook/Instagram/WhatsApp con iconos SVG en color
     de marca, href `"#"` + `TODO(redes)`.
   - ÚLTIMA LÍNEA: «© 2026 RSUELVO · BALETH - IGNOVA» + tagline.
3. **WhatsApp:** solo cambiar el número de los hipervínculos existentes a
   `https://wa.me/59171548644` (no reestructurar CTAs).
4. **Servicios (OBS-011, tono landing para comerciantes):** convertir la sección
   «Tres pilares» en «Servicios» con `id="servicios"`, grid de 4
   (agregar regla `.grid-4` espejo de `.grid-3` + responsive 1fr):
   01 Organización de Inventario (catálogo por sucursal y stock siempre al día),
   02 Gestión Comercial (ventas por WhatsApp con reservas que sí se cumplen),
   03 Verificación de Pagos (QR, comprobantes y confirmación de tu equipo),
   04 Logística de Entrega (del pedido confirmado a la puerta del cliente).
   Copy simple, cero jerga; prohibidas las palabras «dolores» y «dinámica».
   Navbar: «Servicios» como desplegable a las 4 anclas
   (`#servicio-inventario`, `#servicio-comercial`, `#servicio-pagos`,
   `#servicio-logistica` en cada card).
5. **Header:** wordmark junto al logo (arriba-izquierda) 50% más grande; resto
   idéntico. **Login:** saludo «¡Hola! Login aquí!» con estados (cargando/error).
6. **BUG `/app`:** el botón lleva a `/app` pero se sigue viendo la landing.
   Diagnosticar (verificar `_redirects` desplegado, `base:/app/`, qué sirve
   Pages en esa ruta) y corregir hasta que `/app` cargue el dashboard.
7. **Solicitud (entre `#preguntas` y el CTA):** formulario (nombre, teléfono,
   tienda, mensaje) que abre WhatsApp `wa.me/59171548644` con texto precargado.
   Sin backend.
8. **Refuerzo transversal (sin secciones nuevas):** en Hero/pilares/cómo-funciona,
   transmitir (a) que RSUELVO ordena la operación (sin sobreventas, sin
   comprobantes perdidos, sin envíos tardíos) y (b) que está hecha para vender
   por redes sociales — con palabras simples, NUNCA la palabra «dolores».
9. **Contraste:** botones verdes con letra blanca (solo color de texto).
10. **Imágenes (slots + integración):** la landing hoy no tiene fotografía/ilustración.
    Integrar 4 raster en `landing/public/assets/` (JPG optimizado, 1600px lado mayor):
    `hero-ventas.jpg` (Hero, 16:9, `fetchpriority="high"`), `servicio-inventario.jpg`,
    `servicio-pagos.jpg`, `servicio-logistica.jpg` (cards 01/03/04, lazy).
    Gestión Comercial (02) queda sin imagen (el chat en vivo es el visual).
    Cada una con `alt` en español. Los archivos los provee el dueño (generados con
    los prompts del ANEXO); si un archivo falta al buildear, la sección rinde sin
    imagen (sin romper layout ni build).

## ANEXO — Prompts de generación (pegar en GPT-imagen, UNO por imagen, inglés tal cual)
Filosofía: ilustración SaaS premium (nivel Stripe/Linear), geométrica con
profundidad suave — NADA de estética anuncio/póster/foto stock. Copiar el bloque
STYLE en los 4 y agregar el SUBJECT de cada una. Aspecto 16:9. Si sale texto,
letras, logos o marcas de agua: regenerar (nunca editar encima).

STYLE (común, copiar literal):
«Premium SaaS brand illustration, geometric flat design with soft depth and
subtle gradients, dark charcoal background #202020 with vignette, emerald green
#2FAC66 as primary light source with glow, teal #38E0CC only for small accents,
thin luminous edge lines, faint grid texture, soft rim lighting, generous
negative space, balanced minimal composition, crisp vector-like edges, high
detail, 16:9» + «ABSOLUTELY NO text, NO letters, NO numbers, NO logos, NO
badges with words, NO ad-poster layout, NO stock photo look, NO watermark».

1. **hero-ventas.jpg** — SUBJECT: «Left third mostly empty dark space for headline
   overlay. Right side: large smartphone at slight 3/4 angle showing an abstract
   chat interface made of blank rounded message bubbles (some glowing green),
   three floating cards around it: a parcel box, a QR-like geometric pattern
   square (abstract, not a real QR), a circular checkmark seal; faint delivery
   scooter silhouette far in background, small glowing map pin above it».
2. **servicio-inventario.jpg** — SUBJECT: «Centered tidy warehouse shelf module in
   perspective, parcel boxes in two sizes with small blank tag cards hanging,
   exactly ONE box glowing emerald from within, soft teal underlight strip along
   the shelf base, dark empty margins on both sides».
3. **servicio-pagos.jpg** — SUBJECT: «Close-up of a hand holding a smartphone
   displaying an abstract geometric QR-like pattern (not scannable, no real code),
   above it a translucent shield with a glowing checkmark, tiny floating coins as
   plain gradient discs (no symbols), dark background».
4. **servicio-logistica.jpg** — SUBJECT: «Delivery scooter in side profile carrying
   a parcel box with glowing green edges, dashed luminous route line rising from
   the box to a glowing map pin near a minimalist house doorway on the right,
   motion suggested with two speed lines, dark background».

## ENTREGABLES
Builds Astro+Vite verdes; `astro check` + typecheck + tests sin regresiones;
verificación visual móvil/escritorio; UN commit («landing v1.3»); reporte con
qué se tocó por ítem (1-9) y confirmación de que H1, paleta y layout base están
intactos. Placeholders `TODO(redes)` donde aplique.
