# PROMPT ANTIGRAVITY — Bandeja de solicitudes en app móvil

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
La landing recibe postulaciones (tabla `tbl_solicitudes_alta`, fila real
PENDIENTE verificada) pero la app no las muestra. Backend LISTO: RLS
superadmin-lectura + `fn_resolver_solicitud_alta(p_id_solicitud, p_aprueba,
p_motivo)` → `{ok, nuevo}` / `{ok:false, codigo}`. Referencia cercana:
`lib/features/autorizaciones/` (lista+ficha+aprobar/rechazar).
Marca `brand.dart` + `Identidad-de-Marca.md`. Reglas: jamás `service_role`
(anon + RLS), español, gate SUPERADMIN en rutas/nav/dashboard, economía de
tokens, sin capturas, `flutter analyze` limpio + tests con mocks (prohibido
tocar datos reales).

## Cambio (sin cambios BD)
Pantalla **Solicitudes** (nav + ruta + gate): lista pendientes-primero
(nombre, tienda, teléfono, plan, fecha) → ficha (mensaje, origen) →
aprobar / rechazar con motivo (RPC). Tras resolver, refrescar. Aviso en ficha:
«aprobar no crea el comercio (va en Autorizaciones)». No tocar lo demás.

## Verificación y entregable
Pantalla + repo + gates + tests + commit. Si un contrato no existe, reportar.
