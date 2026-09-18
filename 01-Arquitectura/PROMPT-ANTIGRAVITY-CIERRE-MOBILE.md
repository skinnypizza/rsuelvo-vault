# PROMPT ANTIGRAVITY — Cierre rediseño mobile (continuación verificada)

## ROL
Product Designer mobile senior (UX/UI) + ingeniero Flutter senior. Implementás,
no sugerís. Base: el prompt de rediseño integral ya ejecutado por Astra (vale
todo su brief: marca desde SVG, premium sobrio, iOS adaptado, a11y, perf, sin
funciones nuevas, sin romper contratos). Este prompt es CONTINUACIÓN + 5 fixes.

## ESTADO VERIFICADO POR ORQUESTADOR (no repetir)
- Base `2d69d6e` + árbol SUCIO con el rediseño (sin commitear; lo commiteás vos al final).
- `flutter analyze`: 0 issues. Suite: **208/208** (`mobile_redesign_test` + resto).
- Sin secretos, sin escrituras a BD, sin dependencias nuevas. Tokens en
  `core/theme.dart` + `core/brand.dart` (verde `#2FAC66`, turquesa `#38E0CC`,
  carbón `#202020`, negativo `#EDEDED`, extensiones `#176B49`/`#16766E`).
- No existe `WillPopScope`/`PopScope` en `lib/` (causa del bug 5).

## 5 FIXES (alcance cerrado)
1. **Dashboards** (`dashboard_screen`, `role_dashboard_screen`, `staff_dashboard_screen`):
   auditar jerarquía, espaciados y legibilidad de métricas; mejorar sin agregar
   métricas ni datos (prohibido por brief).
2. **Botones→destino**: auditar TODA navegación (botones, cards, tabs, gestos):
   tabla destino-esperado vs real; corregir muertos o errados. No cambiar rutas.
3. **Emojis → SVG (~15 en 5 archivos)**: `error_snackbar.dart`,
   `verificacion_detail_screen.dart`, `staff_dashboard_screen.dart`,
   `dashboard_screen.dart`, `role_dashboard_screen.dart` (✅👋🚫⚠🛵🚚📦📋❌).
   Reemplazar por iconos SVG del color de marca (usar set existente; si falta
   uno, dibujarlo con la geometría del isotipo). Cero emojis en UI al final.
4. **Tab «Verificaciones»** (`role_dashboard_screen.dart:49`, shell): el texto
   parte en dos líneas («Verificacione»+«s»). Corregir sizing (escalado/fitted,
   respetando el tamaño estable Cupertino ya implementado) sin romper tabs.
5. **Back Android**: hoy cierra la app (sin handler). Implementar `PopScope`:
   navegación interna hace pop primero; en raíz, doble-tap para salir con
   feedback (snackbar «Presiona de nuevo para salir»); iOS intacto (gesto borde).

## VERIFICACIÓN Y ENTREGA
`format` + `analyze` 0 + suite completa verde (incluir tests de: multirol sin
`.single()`, rutas de los fixes 2/4/5, cero emojis en widgets clave); widget
matrix existente si aplica; commit final; reporte conciso (fixes, archivos,
pendientes solo-físico). Si algo funcional es ambiguo, preguntar; lo visual
reversible se decide y continúa.
