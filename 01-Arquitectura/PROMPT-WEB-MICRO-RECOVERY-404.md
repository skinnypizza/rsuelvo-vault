# PROMPT CODEX (Astra) — Micro-fix: recovery route + 404 raíz

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
Dos fallos verificados por el orquestador:
1. El mail de recovery trae `{{ .ConfirmationURL }}` = `/app/auth/confirm?token_hash=…&type=recovery`,
   pero React solo atiende `/recuperar` → cae en NotFound. Por eso el reset "no funciona".
2. No existe `404.html`: una ruta raíz inexistente (`/jiajsi`) no muestra el 404 de marca.
Reglas: español, marca, economía de tokens, UN commit, builds+tests verdes.

## Cambios
1. **React:** agregar ruta `/auth/confirm` que reuse el flujo de recovery existente
   (`parseRecoveryLink` + `redeemRecoveryLink` + formulario; sirve también
   `?code=` PKCE). No duplicar lógica: redirigir a `/recuperar` preservando query
   o renderizar el mismo componente.
2. **Astro:** crear `landing/src/pages/404.astro` (genera `404.html`): logo,
   «Página no encontrada», tagline, botones Inicio (`/`) y WhatsApp
   (`https://wa.me/59171548644`), `noindex`. Sin tocar el resto.

## Verificación
`npm run build` genera `dist/404.html`; ruta `/auth/confirm?token_hash=x&type=recovery`
muestra el formulario (mock); commit «fix: recovery route + 404 raiz».
