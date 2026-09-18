# PROMPT ANTIGRAVITY — Móvil: config dueño + navbar superadmin + menú perfil

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
4 fixes verificados por orquestador en fuente. Marca `brand.dart`. Reglas: jamás
`service_role`, español, economía, sin capturas, `flutter analyze` limpio + tests
con mocks (sin datos reales). Sin cambios BD ni lógica de negocio.

## 1. Rate-limit fuera de la vista dueño
En `configuracion_screen.dart` el campo `n_whatsapp_por_minuto` se muestra al
dueño (`isAdmin`): ocultarlo para dueño (gate `isStaff`), sin tocar el valor
guardado ni el contrato del repositorio.

## 2. Navbar superadmin saturada (`app_shell.dart:42-103`, 7 ítems)
Reducir a máximo 5 ítems primarios (ej. Inicio, Comercios, Autorizaciones,
Solicitudes, Créditos); el resto vive SOLO en el menú de perfil (ya existen ahí:
líneas ~268-310). Sin eliminar rutas ni gates.

## 3. Wrap de labels (iOS `CupertinoTabBar` ~563 + `NavigationBar` Android ~576)
«Autorizaciones» (y cualquier label largo) se parte en dos líneas. Una sola línea
siempre: escalado/fitted dentro del tamaño Cupertino estable ya implementado
(ver fix previo `role_dashboard_screen.dart:49`). En ambas plataformas.

## 4. Favicons en menú de perfil (líneas ~234-258)
El header del menú (avatar/nombre/rol/comercio) no lleva marca: agregar avatar
con favicon + `BrandMark` en el header, siguiendo `brand_widgets.dart` (no repetir
logos en vacíos/contenidos, regla vigente).

## Verificación y entregable
Tests (gates, navegación, labels en 320px) + commit. Si un contrato no existe, reportar.
