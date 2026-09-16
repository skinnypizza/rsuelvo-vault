# PROMPT CODEX (Astra) — Web v1.2: auth completo + landing corregida

## 0. Alcance (repo `/home/nico/StudioProjects/rsuelvo-web`)
Dos bloques en un solo commit por bloque. Sin tocar backend (no hay migraciones
en este prompt). Español, marca `brand.dart` + `Identidad-de-Marca.md`, anon+RLS,
economía de tokens. Placeholders del dueño abajo ([DUEÑO]).

## A. Auth completo (`/app`)
1. **Recovery** (de `PROMPT-WEB-RECOVERY.md`): canjear `?code=`/`?token_hash=` y
   formulario de nueva contraseña; errores en español.
2. **Cambiar contraseña** logueado: pantalla Perfil (email, rol, comercio) +
   cambio de pass con confirmación.
3. **Login UX**: botón con estados (cargando/error), foco inicial en email,
   mensaje de rol-denegado dedicado (no un 404 genérico) + página 404 con
   WhatsApp de soporte (`https://wa.me/59171548644`).
4. Tests con mocks + build verde. Auto-registro público: EXCLUIDO a propósito
   (las altas las crea el staff, D17); el que quiera contratar usa el formulario
   de §B.

## B. Landing (copy EXACTO, no inventar)
- **HERO:** titular «tus ventas, sin caos» (reemplaza «tu operación, resueltas»);
  subtítulo claim «Organiza tu stock, valida cada pago y despacha a tiempo.»;
  CTA primario «Entrar al panel» → `/app`, secundario WhatsApp soporte
  (`https://wa.me/59171548644`).
- **Dolores** (sección, explicar que RSUELVO ordena): «Sin sobreventas: el stock
  se reserva atómicamente. Sin comprobantes perdidos: cada pago queda trazado.
  Sin envíos tardíos: cada pedido llega a ruta con guía. Menos caos en el chat,
  más ventas en tu negocio.»
- **Ventas por redes:** «Hecha para quienes venden por TikTok Live, Facebook
  Marketplace y WhatsApp: el cliente pide por chat y tu operación corre sola.»
- **Dinámica RSUELVO** (el flujo que adopta el vendedor): 1) Publicás SKUs →
  2) El cliente reserva por WhatsApp → 3) Paga al QR y manda comprobante →
  4) Confirmás el pago → 5) Se genera el envío con guía. (5 pasos numerados.)
- **Planes de recarga:** Básico / Pro / Empresa (créditos para verificaciones y
  ventas). SIN precios por ahora (cards sin monto, CTA «Solicitar»).
- **Servicios:** ancla `#servicios` en navbar y footer (contenido: gestión
  comercial por WhatsApp, verificación de pagos, logística con guías).
- **Solicitud de contratación:** formulario (nombre, teléfono, nombre tienda,
  mensaje) que abre WhatsApp de soporte (wa.me/59171548644) con el texto precargado. Sin backend.
- **Descargas app:** badges Google Play + App Store en estado «Próximamente»
  SIN href (no clicables, solo visual).
- **Footer:** redes TikTok/Facebook/Instagram/WhatsApp con hrefs `"#"` y
  `TODO(redes)` en código (estructura lista, URLs pendientes de creación);
  contacto WhatsApp `https://wa.me/59171548644` (soporte); Servicios;
  línea «© 2026 RSUELVO · BALETH - IGNOVA», tagline «Del stock a la entrega.»
- **UI:** wordmark ~25% más grande; botones verdes con letra NEGRA → blanca
  (contraste); resto intacto.
- SEO: nuevas secciones con anchors, titles y JSON-LD actualizados si aplica.

## Verificación y entregable
Typecheck + tests + builds verdes; un commit por bloque (auth / landing);
reportar versiones. Placeholders `[DUEÑO]` visibles donde falten datos.
