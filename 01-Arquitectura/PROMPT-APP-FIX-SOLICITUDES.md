# PROMPT ANTIGRAVITY — Fix ficha + aprobar solicitudes

## Contexto (código `/home/nico/StudioProjects/rsuelvo`, módulo `lib/features/solicitudes/`)
Dos bugs verificados por el orquestador contra el backend real (mig 70):
1. `fetchAll` selecciona solo `id_solicitud, estado, mensaje, origen, created_at`:
   la ficha no puede mostrar nombre/tienda/teléfono/plan.
2. `resolver` envía `p_decision` (string) pero `fn_resolver_solicitud_alta` recibe
   `(p_id_solicitud uuid, p_aprueba boolean, p_motivo text)` → el RPC falla y la
   app muestra "error de conexión". (El `p_decision` es de OTRA función, la de
   compras de créditos. No mezclar.)
Reglas: español, `flutter analyze` limpio + tests con mocks (sin tocar datos
reales), UN commit.

## Cambios
1. Select: `id_solicitud, estado, nombre, tienda, telefono, plan, mensaje, origen, created_at`;
   modelo + ficha los muestran (nombre+tienda destacados, teléfono con formato).
2. `resolver(id, apruebaBool, motivo)` → params `{p_id_solicitud, p_aprueba: true/false,
   p_motivo}`; `aprobar`/`rechazar` pasan booleano (motivo opcional, `''` si vacío).
   Mensajes de error reales (no genéricos) ante fallo RPC.

## Verificación
Tests del mapeo + RPC (mock con firma real) verdes; commit «fix: ficha y aprobar solicitudes».
