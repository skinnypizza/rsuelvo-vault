# PROMPT CODEX (Astra) — Recovery de contraseña en `/app`

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`, app Refine+MUI)
Los links de recovery de Supabase Auth (`?code=` o `?token_hash=&type=recovery`)
caen en el Site URL sin pantalla que los atienda: hoy es imposible fijar nueva
contraseña. Reglas: anon + RLS, español, economía de tokens, commits claros.

## Cambio (solo `/app`, sin tocar backend)
1. En la ruta raíz del dashboard, detectar `code` (PKCE: `exchangeCodeForSession`)
   o `token_hash`+`type=recovery` (verify) y canjear por sesión.
2. Con sesión de recovery, mostrar formulario "Nueva contraseña" (mínimo 8,
   confirmación) → `supabase.auth.updateUser({password})` → redirigir a login
   con aviso de éxito. Errores (link vencido/usado) en español.
3. No romper login ni gates; test del flujo con mocks.

## Verificación y entregable
Typecheck + tests + build verdes; commit. Probar con un link de mentira que el
flujo de error sea legible.
