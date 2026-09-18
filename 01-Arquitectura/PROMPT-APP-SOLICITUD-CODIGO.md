# PROMPT ANTIGRAVITY — Solicitud → alta + ficha siempre visible (móvil)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Backend LISTO (mig 71): `fn_sugerir_codigo` anon, reserva por UNIQUE parcial,
`fn_alta_comercio(..., p_id_solicitud?)` consume + linaje. Marca `brand.dart`.
Reglas: jamás `service_role`, español, gate SUPERADMIN, economía, sin capturas,
`flutter analyze` limpio + tests con mocks (sin datos reales).

## Cambios (sin cambios BD)
1. **Ficha visible siempre:** la lista solo permite tap en PENDIENTE
   (`onTap: isPendiente ? ... : null`) → permitir ver ficha en cualquier estado;
   acciones (aprobar/rechazar) solo si PENDIENTE.
2. **Solicitud → alta:** en ficha APROBADA con código, botón «Crear comercio» →
   alta pre-rellenada (nombre/teléfono/tienda/código) + `p_id_solicitud`; tras
   crear, aviso + link a Autorizaciones.
3. **Alta Comercios:** campo código con sugerencias en vivo (`fn_sugerir_codigo`,
   debounce) + manejo de `codigo_en_uso/mismatch/solicitud_consumida` con
   alternativas.

## Verificación y entregable
Tests (mapeo, RPC, navegación) + commit. Si un contrato no existe, reportar.
