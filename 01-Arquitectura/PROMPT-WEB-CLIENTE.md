# PROMPT CODEX (Astra) — Cliente web RSUELVO completo (landing + dashboard)

## 0. Scaffolding (la carpeta NO existe: crearla)
- Crear `~/StudioProjects/rsuelvo-web/` (verificar padre con `ls` antes), `git init`
  local (sin remoto por ahora). Monorepo: `/landing` (Astro v5 SSG) + `/app`
  (Refine + Vite + MUI + TypeScript estricto). Node LTS + `.nvmrc`.
- Deploy único en Cloudflare Pages: build Astro a `dist/` + build Refine a
  `dist/app/`; `_redirects` con `/app/* /app/index.html 200`.
- Env por archivos `.env` NO commiteados: `PUBLIC_SUPABASE_URL`,
  `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (el dueño las provee; jamás
  `service_role` en el cliente). Dominio canónico: **https://rsuelvo.com**
  (landing en raíz, dashboard en `https://rsuelvo.com/app`).

## 1. Marca (única fuente, no inventar)
- Assets: `/home/nico/rsuelvo/LOGOTIPO RSUELVO/` (SVG en `Favicons WEB/` — leerlos
  como texto para geometría; PNG para uso). Favicon + OG desde estos archivos.
- Paleta EXACTA de `brand.dart` (app): oscuro `#202020` · claro `#EDEDED` ·
  gradiente `#2FAC66 → #38E0CC`.
- Voz: `05-Diseño-UX/Identidad-de-Marca.md` (tagline en headers, claim en landing).
- Skill `ignova-design`: usar estructura, secciones, SEO, a11y y performance;
  IGNORAR sus colores/fuentes/número (son de Ignova; sus fuentes son comerciales).

## 2. Landing `/` (Astro estático, todo el SEO)
Secciones: Header (tagline) · Hero (claim + CTA «Entrar al panel» → `/app` +
secundario WhatsApp) · 3 pilares (stock/pagos/envíos) · Cómo funciona (WhatsApp)
· Créditos · FAQ · CTA final · Footer. Español.
SEO: title/description/OG/canonical/twitter por página, `sitemap`, `robots.txt`,
JSON-LD (Organization + WebSite + SoftwareApplication), HTML semántico,
`loading=lazy`, `font-display:swap`, favicons reales.

## 3. Dashboard `/app/*` (Refine SPA, `noindex`, solo roles staff)
Login email/pass (Supabase Auth) + gate: `ROLE_SUPERADMIN` (todo),
`ROLE_SYSADMIN`/`ROLE_SUPPORT` (su alcance). Sin superadmin de prueba aún: el
E2E de login queda pendiente del email del dueño (verificar build + UI + gates).
Pantallas: Comercios (lista/ficha/alta wizard/suspender-reactivar) ·
Autorizaciones (pendientes→aprobar+invite/rechazar) · Créditos (revisar con
comprobante firmado al ver) · Reportes (depósitos, créditos+consumo, estados,
autorizaciones) · Usuarios (CRUD excepto SuperAdmin/Cajero/Repartidor).

## 4. Contratos backend (Supabase `iwfaktlxebxtocmswdvv`, schema `rsuelvo`)
Lecturas RLS directas; escrituras SOLO RPC: `fn_alta_comercio`
(p_nombre, p_codigo_tienda `^[A-Z0-9]{3}$` sin O, p_sucursal, p_telefono, p_email,
p_reserva_min=10, p_verificacion_automatica=false, p_bonus=100, p_estado) →
`{ok,...}`; `fn_cambiar_estado_comercio` (ACTIVO/SUSPENDIDO/BLOQUEADO/CANCELADO/
PENDIENTE_APROBACION); `fn_resolver_compra_creditos` (APROBAR/RECHAZAR);
`fn_solicitar_creditos` (solo dueño, no staff). Storage: `qr-pagos/<id>/tienda.png`,
`depositos-creditos/<id>/...` (firmar al ver). Invite dueño: EF
`invitar-usuario-comercio` (`supabase.functions.invoke` con JWT). Si un contrato
no existe, REPORTAR (no inventar columnas/tablas/fns).

## 5. Verificación y entregable
Ambos builds en verde; `dist/` desplegable; `/app` con `noindex`; gates por rol
probados con mocks; alta TEST de prueba queda CANCELADA (fósil, no borrar).
Commits claros por bloque. Economía de tokens: sin capturas ni artefactos.
