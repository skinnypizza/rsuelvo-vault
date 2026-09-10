> **Traído al vault:** 2026-09-10 · autor: Codex (auditoría + rediseño de marca) · evidencia visual en `07-Control-de-Calidad/evidencia-app-brand-2026-09-10/`
> **Prompt origen:** [[PROMPT-CODEX-AUDITORIA-REDISENO-BRAND]] · **Código:** `/home/nico/StudioProjects/rsuelvo/`

# Auditoría y rediseño visual — RSUELVO

Fecha: 10/09/2026. Alcance: Flutter Android, F4/F5/F6, presentación y recursos de marca.

## Estado inicial y límites

`flutter analyze`: **No issues found! (ran in 5.4s)** antes de modificar código.
El árbol de trabajo ya contenía cambios en rutas, modelos, pantallas y módulos F6; se conservaron. Se guardó una instantánea local inicial en `/tmp/rsuelvo-before` para comparar el trabajo de esta sesión. No se agregaron dependencias ni se modificaron repositorios, controladores, modelos, rutas, formatos monetarios o reglas de negocio. No se utilizó el MCP de Supabase ni se ejecutaron consultas directas. La navegación del dispositivo utiliza los flujos normales de la aplicación.

## Assets inspeccionados

Se revisaron los seis JPG, los seis PNG RGBA de 2000×2000 y el texto completo de los tres SVG. El JPG Alterno lleva fondo verde/turquesa; Secundario lleva fondo oscuro. Se prefirieron los PNG transparentes.

Los SVG comparten un `viewBox` de 1251.94×1012.49 y un trazado sólido: ruedas circulares de radio 78.74, cuerpo redondeado y diagonal ascendente. Positivo usa `#202020`, Negativo `#ededed`; Primario declara `#2fac66`→`#38e0cc`, con coordenadas (-109.64,749.88)→(1500.96,153.56) y segundo stop en 0.91. El sistema UI sigue la diagonal abajo-izquierda→arriba-derecha solicitada.

**Favicon Alterno.png es el negativo**, no un icono circular. No existe un PNG llamado Favicon Negativo ni un logo PNG Alterno separado. Se conservaron los originales y se generaron variantes `UI.png` recortando únicamente transparencia exterior. Las rutas de uso Flutter están centralizadas en `BrandAssets`. Los tres SVG quedan como referencia y no se renderizan en Flutter.

## Hallazgos iniciales

Las referencias de esta tabla corresponden a las líneas de la instantánea anterior al rediseño; el formato y las extracciones de widgets cambian las líneas finales.

| Prioridad | Categoría y referencia inicial | Hallazgo y propuesta | Resolución |
|---|---|---|---|
| 🔴 Alto | Marca — `lib/core/theme.dart:6` | Primario índigo ajeno al mark. Derivar tema, esquema y superficies de tokens oficiales. | Aplicado. Verde/turquesa, neutros, radios y estados comunes. |
| 🟡 Medio | Marca — `lib/features/dashboard/dashboard_screen.dart:89`, `lib/shared/widgets/status_badge.dart:25` | Azules y violetas dispersos. Sustituir hex por tokens y armonizar estados. | Aplicado en pantallas y widgets visuales. |
| 🔴 Alto | Accesibilidad — `lib/features/auth/login_screen.dart:219`, `lib/features/creditos/creditos_screen.dart:199` | Blanco sobre verde/turquesa puro no alcanza 4.5:1. No basta sustituir colores. | Gradiente oficial con capa `brandDark` al 55% bajo contenido blanco/negativo; prueba de 101 muestras. |
| 🟡 Medio | Marca — `lib/features/auth/login_screen.dart:74`, `lib/features/shell/app_shell.dart:101` | Icono genérico y marca textual sin los recursos oficiales. | Logo negativo en login/dashboard, favicon primario de 28dp y avatar de 24dp. |
| 🟡 Medio | UX — `lib/features/productos/productos_list_screen.dart:44`, `lib/features/creditos/creditos_screen.dart:301`, `lib/features/usuarios/usuarios_list_screen.dart:91` | Listas vacías solo textuales o con ilustración genérica. | Marca positiva tenue en vacíos de listas, dashboard y detalles sin productos; mensajes conservados. |
| 🔴 Alto | Accesibilidad — `lib/features/creditos/creditos_screen.dart:531` | CTA de paquetes con mínimo 24dp y `shrinkWrap`. | Mínimo 48dp y área táctil padded. |
| 🟡 Medio | Accesibilidad — `lib/features/auth/login_screen.dart:196`, `lib/features/usuarios/usuario_edit_dialog.dart:119`, `lib/features/envios/envio_detail_screen.dart:485` | Iconos sin etiqueta accesible. | Tooltips mostrar/ocultar contraseña, cerrar y quitar foto; carga con Semantics. |
| 🟡 Medio | UX — `lib/features/dashboard/dashboard_screen.dart:386` | Título de métrica en Row sin flex: riesgo con 360dp/texto grande. | Expanded para permitir salto de línea. |
| 🟡 Medio | UX — `lib/features/creditos/creditos_screen.dart:50` | Título del diálogo de recargas sin flex. Desborde confirmado en Samsung durante la revisión. | Expanded y diálogo desplazable. |
| 🟡 Medio | Formularios — `lib/features/puntos_entrega/punto_entrega_form_dialog.dart:353`, `lib/core/theme.dart:67` | Selectores y ayudas largas pueden recortarse. | Selectores String expandidos, ayudas/errores de hasta cuatro líneas, foco verde visible. Validaciones intactas. |
| 🟡 Medio | Visual — `lib/features/sucursales/sucursales_list_screen.dart:214`, `lib/features/creditos/creditos_screen.dart:201` | Radios dispares, sombras locales fuertes y gradiente separado. | Tokens 10/14/20, pill, una elevación global y BrandPanel compartido. |
| 🟢 Bajo | Iconografía — `lib/features/shell/app_shell.dart:34`, pantallas F4/F5/F6 | Mezcla de estilos Material. | Variantes Rounded disponibles en el SDK, sin fuentes ni paquetes nuevos. |
| 🟢 Bajo | Técnico — `lib/shared/widgets/error_snackbar.dart:150`, `lib/shared/widgets/status_badge.dart:5` | Presentación duplicada y falta de tokens. | Helpers públicos conservados, BrandPanel/BrandMark/BrandEmpty/BrandLoading compartidos. |
| 🟢 Bajo | Técnico — `lib/` completo | Buscar `withOpacity` y const faltantes antes de proponer cambios. | No había usos de withOpacity; se mantiene withValues. Analyzer inicial y final comprueban lints de const. |
| 🟡 Medio | Recursos — `android/app/src/main/res/drawable/launch_background.xml:1`, `web/favicon.png` | Recursos Flutter genéricos. | Launcher por densidad, favicon web, splash positivo/negativo y configuración Android 12+. |

## Decisiones y accesibilidad

La marca original permanece intacta en los PNG. El oscurecimiento se aplica al fondo de headers y CTAs para cumplir AA con texto blanco, sin inventar otro color de marca. Los badges usan tinte semántico al 12% y tinta oscurecida por composición con `brandDark`; sus etiquetas conservan el significado sin depender del color. El botón de WhatsApp conserva `#25D366` y usa texto oscuro legible; queda excluido explícitamente del gradiente.

Solo hay tema claro Flutter. Los recursos night se limitan al arranque nativo. `drawable-v21` conserva fondo claro porque v21 indica API, no modo nocturno; las carpetas `drawable-night` y `drawable-night-v21` seleccionan negativo sobre oscuro. Android 12+ tiene favicon centrado con margen seguro en su splash del sistema.

El modelo de sesión contiene nombre de usuario e identificador de comercio, pero **no nombre de comercio**. No se inventó ese nombre ni se amplió un contrato o consulta para obtenerlo: el header muestra el nombre del usuario y el resumen operativo. Esta parte de la solicitud queda limitada por los datos existentes.

## Verificación

- `flutter analyze --no-pub`: **0 issues**.
- `flutter test --no-pub`: **18 tests passed**. Incluye contraste AA del gradiente en 101 muestras, login a 360dp con escala 1×/2×, teclado/validación, estados vacíos de Dashboard, Envíos, Pedidos, Productos, Usuarios, Sucursales y Verificaciones a 360dp y 130%, badges, CTA primario y CTA destructivo.
- `flutter build apk --debug --no-pub`: **OK**, generado en `build/app/outputs/flutter-apk/app-debug.apk`.
- Samsung SM-A556E, Android 16: APK instalado y abierto correctamente. Se navegaron Dashboard, Pedidos, detalle de pedido, Envíos, Productos, Puntos de Entrega, Créditos, Configuración, Sucursales y menú de Usuarios. No se guardaron formularios ni se confirmaron pagos.
- Launcher y splash: el APK final se instaló; el dispositivo mostró el arranque y la app abrió con el favicon nítido. No hay emulador disponible para una prueba independiente de modo nocturno; los recursos `drawable-night*` y Android 12+ quedaron declarados.
- WhatsApp: en el detalle de pedido se verificó el CTA verde y se conservó `AppTheme.whatsappGreen` (`#25D366`), excluyéndolo del gradiente general.

Las capturas de evidencia se guardan en `evidence/brand/`: dashboard, pedidos, detalle, envíos, puntos de entrega, productos, créditos, configuración y sucursales.

## Resumen de cambios por archivo

- `lib/core/brand.dart`: gradiente, colores positivo/negativo, radios, espacios, movimiento y rutas `BrandAssets`.
- `lib/core/theme.dart`: Material 3 claro basado en tokens, superficies, inputs, botones, navegación, diálogos y SnackBars.
- `lib/shared/widgets/brand_widgets.dart`: `BrandMark`, `BrandPanel`, `BrandEmpty` y `BrandLoading` compartidos.
- `lib/features/auth/login_screen.dart`: hero de marca negativo sobre gradiente y formulario en Card.
- `lib/features/dashboard/dashboard_screen.dart`: bienvenida de marca, favicon y estados vacíos.
- `lib/features/shell/app_shell.dart`: favicon en Dashboard, avatar de favicon y tooltips de perfil.
- `lib/shared/widgets/status_badge.dart` y `error_snackbar.dart`: tintes semánticos, radios y contraste.
- Pantallas/dialogs F4/F5/F6: tokens de color y radio, vacíos con marca, textos flexibles, foco y áreas táctiles.
- `pubspec.yaml`, `assets/brand/`, `web/favicon.png`: assets transparentes y referencia SVG sin dependencias nuevas.
- `android/app/src/main/res/`: launcher por densidad y splash claro/oscuro, incluido Android 12+.
- `test/brand_visual_test.dart`: contraste, escalado, teclado, validación, vacíos, badges y CTAs.

## Antes / Después

Antes, RSUELVO mezclaba índigo, azul, teal y violetas con iconos genéricos, radios variables y vacíos textuales. Después, la app usa una identidad verde→turquesa coherente, superficies redondeadas de baja elevación, favicon en la navegación, logo completo en login/dashboard, estados vacíos con marca y controles legibles al ampliar texto, manteniendo los flujos y datos operativos existentes.
