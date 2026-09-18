# PROMPT CODEX — Móvil paquete: cajero inventario + filtros + créditos E2E

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Backend LISTO (mig 72, verificado): `fn_registrar_movimiento_inventario(
p_id_sucursal, p_id_variante, p_tipo, p_cantidad, p_referencia_tipo?,
p_referencia_id?)` → `{ok, stock_actual}` / `{ok:false, codigo}` con
`sin_permiso/stock_insuficiente/tipo_invalido/cantidad_invalida/variante_invalida/sin_inventario`.
Cajero: SOLO su sucursal (server-side); tipos manuales ENTRADA/SALIDA/AJUSTE(con signo)/DEVOLUCION.
Marca `brand.dart`. Reglas: jamás `service_role`, español, gates por rol, economía,
sin capturas, `flutter analyze` limpio + tests con mocks (sin datos reales).

## Tareas (sin cambios BD)
1. **Cajero ajusta inventario:** en inventario por sucursal, botón Ajustar (solo
   cajero en su sucursal) → diálogo tipo+cantidad (AJUSTE admite signo) →
   RPC → feedback + refresh; errores del backend en español.
2. **Filtros reservas y envíos:** al entrar, solo última semana por defecto;
   filtro de rango de fechas + filtro por estado visibles; envíos: filtro por
   estado en todos los roles con acceso. Mantener paginación/orden existentes.
3. **Créditos E2E:** verificar y completar lo faltante del loop dueño-solicita
   (`solicitar_creditos_screen`) → staff-revisa (motivo visible, comprobante
   firmado al ver) con los contratos vigentes; sin inventar RPCs.

## Verificación y entregable
Tests (RPC, filtros, gates) + commit. Si un contrato no existe, reportar.
