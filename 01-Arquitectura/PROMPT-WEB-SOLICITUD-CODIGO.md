# PROMPT CODEX (Astra) — Solicitud → alta + campo código (web)

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
Backend LISTO (mig 71 + EF): `fn_sugerir_codigo(p_base)` anon → `{ok, base, sugerencias[5]}`;
solicitud con `codigo_sugerido` (reserva UNIQUE); `fn_alta_comercio(..., p_id_solicitud?)`
consume la reserva y guarda linaje (`comercios.id_solicitud`); códigos y errores:
`codigo_en_uso/mismatch/solicitud_consumida/solicitud_no_aprobada`.
Reglas: anon+RLS, español, economía, UN commit, builds+tests verdes.

## Cambios (solo `/app` + landing)
1. **Bandeja → alta:** en ficha de solicitud APROBADA con código, botón «Crear
   comercio» → alta wizard pre-rellenada (nombre/telefono/tienda/código) +
   `p_id_solicitud`; tras crear, aviso + link a Autorizaciones.
2. **Alta wizard:** campo código con sugerencias en vivo (`fn_sugerir_codigo`,
   debounce) + manejo de `codigo_en_uso/mismatch` con alternativas clicables.
3. **Landing form (`contratacion.ts`):** campo opcional código (3 chars, normaliza
   a mayúsculas) + envío; ante 409 mostrar `sugerencias` clicables; ante 201
   informar «código reservado». Sin tocar diseño.

## Verificación
Tests mocks (sugerir/reserva/consumo/mismatch) + builds verdes; commit «solicitud-codigo».
