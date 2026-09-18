# PROMPT CODEX (Astra) — Bandeja de solicitudes en dashboard

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`, `/app`)
La landing ya recibe postulaciones (EF `solicitar-alta-comercio` → tabla
`tbl_solicitudes_alta`, verificado con fila real PENDIENTE) pero el panel no las
muestra. Backend LISTO: RLS superadmin-lectura + `fn_resolver_solicitud_alta`
(p_id_solicitud, p_aprueba, p_motivo) → `{ok, nuevo}` / `{ok:false, codigo}`.
Reglas: anon+RLS, español, economía de tokens, UN commit, builds+tests verdes.

## Cambio (solo `/app`, rol SUPERADMIN)
Nueva pantalla **Solicitudes** (nav + ruta): lista PENDIENTE primero
(nombre, tienda, teléfono, plan, fecha) → ficha (mensaje completo, origen) →
aprobar (RPC) / rechazar con motivo (RPC). Tras resolver, refrescar lista.
Aprobar NO crea el comercio (eso sigue en Autorizaciones/D17); mostrar aviso
«contactar al solicitante para el alta». No tocar lo demás.

## Verificación
Typecheck + tests (mock RPC/RLS) + build verdes; commit «bandeja solicitudes».
