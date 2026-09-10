# PROMPT — Codex: Auditoría + Rediseño de marca de la App Flutter RSUELVO

> **Directorio de trabajo:** `/home/nico/StudioProjects/rsuelvo/` (Flutter, package `rsuelvo`, SDK en `/home/nico/flutter`)
> **Assets de marca (fuente):** `/home/nico/rsuelvo/LOGOTIPO RSUELVO/`
> **Objetivo:** (1) auditar la app móvil y reportar hallazgos; (2) aplicar un **rediseño integral** basado en la filosofía de diseño del logotipo/favicons; (3) **integrar los favicons y logos en toda la app** (login, app bars, estados vacíos, launcher icon, splash). Sin romper ninguna funcionalidad.

---

## 0. Antes de tocar código

1. **Ejecutá `flutter analyze`** y guardá el estado inicial (debe ser 0 issues).
2. **Inspeccioná TODOS los assets** en `/home/nico/rsuelvo/LOGOTIPO RSUELVO/` (carpetas `Favicons WEB/` (SVG), `JPG/`, `PNG Sin Fondo/`) antes de decidir variantes. Los SVG son texto: leelos para extraer colores y geometría.
3. **Leé la app completa** (`lib/`): estructura, theme, pantallas de F4/F5/F6 (auth, verificaciones, envios, pedidos, dashboard, productos, creditos, configuracion, sucursales, usuarios, puntos_entrega) y widgets compartidos.

## 1. Filosofía de diseño (derivada del mark — usala como ley)

Paleta oficial extraída de los SVG:
- **Primario (marca/energía):** gradiente lineal diagonal `#2fac66` → `#38e0cc` (verde→turquesa, de abajo-izquierda a arriba-derecha)
- **Positivo:** `#202020` (casi negro — sobre fondos claros)
- **Negativo:** `#ededed` (casi blanco — sobre fondos oscuros/gradiente)

Lenguaje visual del mark (isotipo de entrega con **dos círculos perfectos** como ruedas, silueta sólida y un trazo diagonal ascendente):
- **Geometría limpia** y formas **redondeadas** → radios generosos y consistentes en toda la UI
- **Sólido, sin contornos** → superficies planas, bordes sutiles, cero skeuomorfismo
- **Diagonal ascendente** → sensación de movimiento/progreso: usar el gradiente en CTAs, indicadores de progreso y headers
- **Contraste alto y minimalismo** (menos elementos, mejor ejecutados)
- Neutros casi puros: fondos claros (`#FFFFFF`, `#F7F9FA`), textos `#202020`, secundarios `#5B6470`

## 2. FASE 1 — Auditoría (entregable: informe `AUDITORIA-App-RSUELVO.md` en la raíz del proyecto)

Revisá y clasificá (🔴 Alto / 🟡 Medio / 🟢 Bajo) con archivo:línea y propuesta concreta:
1. **Consistencia de marca:** colores hardcodeados fuera de `AppTheme` (hex sueltos en pantallas/widgets), radios/espaciados dispares, tipografías inconsistentes
2. **Accesibilidad:** contraste de texto sobre gradientes (≥4.5:1), tamaño de toques (<48dp), `Semantics`/labels en iconos, escalado de texto, estados de foco
3. **UX:** estados vacíos/carga/error faltantes o pobres, textos de feedback, overflow de textos largos, formularios (validación, teclado, scroll)
4. **Visual:** jerarquía, densidad, uso correcto de Cards/Badges/SnackBars, iconografía mezclada (estilos outline/filled)
5. **Técnico (solo capa visual):** widgets duplicados que deberían ser compartidos, `const` faltantes, `withOpacity` deprecado (usar `withValues(alpha:)`)
NO propongas cambios de lógica de negocio, BD, ni dependencias.

## 3. FASE 2 — Sistema de diseño de marca (`lib/core/theme.dart` + `lib/core/brand.dart`)

Reescribí `AppTheme` para que TODO derive de tokens de marca (mantené los nombres públicos existentes para no romper pantallas: `primary`, `primaryContainer`, `secondary`, `whatsappGreen`, `surface`, `cardBg`, `statusPending/Processing/Success/Error/Neutral`):
- `primary` = `#2fac66` · `secondary` = `#38e0cc`
- `primaryContainer` = tinte verde suave (ej. `#E4F7EC`) · `surface` = `#F7F9FA` · `cardBg` = `#FFFFFF`
- **`whatsappGreen` se mantiene `#25D366`** (integridad de WhatsApp, NO cambiar)
- Estados: mantener la semántica pero armonizar (éxito alineado a la marca `#2fac66`; pendiente ámbar; error rojo; procesando turquesa)
- Nuevo `lib/core/brand.dart` con: `brandGradient` (LinearGradient 135°, `#2fac66`→`#38e0cc`), `brandGradientColors`, helpers `brandGradientText` si aplica, y constantes de radios/espaciado (`radiusSm 10`, `radiusMd 14`, `radiusLg 20`) y escala de espaciado (4/8/12/16/24/32)
- `ColorScheme.fromSeed(seedColor: primary)` + overrides explícitos; `appBarTheme` blanco con título `#202020`; `cardTheme` radio `radiusMd`, borde `#EDF0F2`; botones radio `radiusSm`; inputs igual; snackbars radio `radiusSm`
- **Dark mode: NO implementar** (fuera de alcance); solo dejá los tokens del negativo listos como constantes (`brandDark = #202020`, `brandLight = #ededed`)

## 4. FASE 3 — Integración de assets (favicons/logos en TODA la app)

1. Copiá desde `/home/nico/rsuelvo/LOGOTIPO RSUELVO/` a `assets/brand/`:
   - `PNG Sin Fondo/` → logos y favicons (positivo, negativo, primario, alterno)
   - `Favicons WEB/` → los 3 SVG (para referencia/uso futuro)
   - Usá **PNG en la app** (`flutter_svg` está PROHIBIDO — no agregar dependencias)
2. Declaralos en `pubspec.yaml` (`assets: - assets/brand/`)
3. **Reglas de uso por variante (respetalas siempre):**
   - Sobre fondo claro (blanco/superficie) → **Positivo** (`#202020`) o **Primario** (gradiente) según jerarquía
   - Sobre fondo oscuro o **gradiente de marca** → **Negativo** (`#ededed`)
   - Momentos de marca → **Primario** (favicon gradiente)
4. **Dónde integrarlos:**
   - **Login:** hero con el logo completo (favicon + wordmark) sobre gradiente de marca; el formulario en una card blanca
   - **App bar / headers:** favicon pequeño (24–28dp) junto al título en el Dashboard; en las demás pantallas, título estándar
   - **Dashboard:** card de bienvenida con `brandGradient` + marca negativa + nombre del usuario y comercio
   - **Estados vacíos:** favicon/posotivo tenue como ilustración en TODAS las listas vacías
   - **Navegación/shell:** si hay avatar o ícono de perfil, usar el favicon primario en círculo
   - **Launcher icon:** reemplazar `android/app/src/main/res/mipmap-*/ic_launcher.png` por `Favicon Primario.png` escalado al tamaño de cada densidad (mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192) — **sin dependencias nuevas** (copiar PNGs a mano). Si existe `ic_launcher_round.png`, reemplazarlo también (usa `Favicon Alterno.png` si es más apropiado por el círculo)
   - **Splash Android:** `android/app/src/main/res/drawable/launch_background.xml` → fondo blanco + logo **Positivo** centrado (y la variante `drawable-v21`/night con **Negativo** sobre `#202020`) — sin dependencias
   - **Web (si el proyecto compila web):** reemplazar `web/favicon.png` por `Favicon Primario.png`
5. Verificá visualmente que ninguna variante quede "invisible" por fondo (contraste).

## 5. FASE 4 — Rediseño de componentes y pantallas (capa visual únicamente)

- **CTAs principales** (login, confirmar pago, registrar guía, guardar): `brandGradient` con texto blanco; los secundarios: outline con `primary`; los destructivos: rojo semántico
- **Cards y superficies:** radio `radiusMd`, borde sutil, sombra muy tenue (una sola elevación global)
- **Badges de estado (StatusBadge):** fondo tintado al 12% + texto del color semántico, radio `radiusFull` tipo pill
- **SnackBars:** conservar los helpers existentes (`showSuccessSnackBar`, `showErrorSnackBar`, `mensajeResultado*`) — solo restilizado visual
- **Inputs:** foco con borde `primary`, relleno blanco, radio `radiusSm`
- **Jerarquía tipográfica:** títulos 20/18 semibold `#202020`; cuerpo 14–15 `#202020`; secundarios 12–13 `#5B6470`; números de dinero destacados
- **Microinteracciones:** transiciones suaves (150–250ms) en cambios de estado y al cargar listas; NO agregar animaciones complejas
- **Iconografía:** un solo estilo (Material Symbols Rounded/outline coherente con el mark redondeado)

NO cambiar: flujos, validaciones, llamadas a repositorios/fns, textos legales/mensajes de negocio, la lógica de roles/rutas.

## 6. FASE 5 — Verificación (checkpoints obligatorios)

1. `flutter analyze` → **0 issues**
2. `flutter build apk --debug` → OK
3. Checklist manual (reportar resultado):
   - [ ] Login muestra logo sobre gradiente; texto legible (contraste)
   - [ ] Launcher icon visible en el cajón de apps del dispositivo/emulador
   - [ ] Splash muestra el logo correcto (claro/oscuro)
   - [ ] App bar y dashboard con favicon nítido (sin pixelado, tamaño correcto)
   - [ ] Estados vacíos con ilustración de marca
   - [ ] Botones principales con gradiente y contraste AA
   - [ ] TODAS las pantallas de F4/F5/F6 siguen funcionando igual (navegar por cada una)
   - [ ] `whatsappGreen` intacto en el botón de WhatsApp
4. Entregá al final: `AUDITORIA-App-RSUELVO.md` + resumen de cambios por archivo + evidencia de analyze/build.

## 7. Prohibiciones

1. NO tocar la BD ni el MCP de Supabase (ni lectura forzada; no hace falta).
2. NO agregar dependencias de ningún tipo (`flutter_svg`, `flutter_launcher_icons`, `google_fonts`, etc. — PROHIBIDAS). Todo se resuelve con los assets PNG y Material 3.
3. NO cambiar lógica de negocio, repositorios, controladores, rutas ni contratos con Supabase.
4. NO inventar colores fuera de la paleta de la marca (excepto semánticos de estado).
5. NO eliminar funcionalidad ni pantallas; el rediseño es visual y de marca.
6. NO romper el idioma español ni los formatos (`Bs`, `America/La_Paz`).
7. NO implementar dark mode (solo tokens listos).
8. NO hardcodear rutas de assets: centralizalas en `lib/core/brand.dart` (ej. `BrandAssets.logoPrimario`).

## 8. Notas

- El proyecto usa Riverpod + go_router + supabase_flutter; la app es para Android (el build objetivo es el APK debug).
- Credenciales de prueba no hacen falta para esta tarea (es visual); el foco es análisis + rediseño + assets.
- Si un asset JPG tiene fondo (no transparente), usalo solo donde el fondo coincida o preferí SIEMPRE los PNG sin fondo para UI.
- Terminá con un párrafo "Antes/Después" describiendo la mejora percibida por el usuario.
