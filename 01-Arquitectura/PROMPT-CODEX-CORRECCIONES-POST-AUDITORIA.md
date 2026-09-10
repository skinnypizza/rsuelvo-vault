# PROMPT — Codex: Correcciones post-auditoría (app Flutter RSUELVO)

> **Directorio:** `/home/nico/StudioProjects/rsuelvo/`
> **Contexto:** la auditoría + rediseño de marca ya se ejecutó en otra sesión. El informe `AUDITORIA-App-RSUELVO.md` está en la raíz del proyecto: contiene una tabla de hallazgos con una columna **"Resolución"** que indica qué ya fue aplicado.
> **Objetivo de esta tarea:** corregir únicamente lo que la auditoría dejó **abierto, parcial o limitado**. NO rehacer el rediseño.
> **Restricción de eficiencia:** NO uses capturas de pantalla, NO instales APKs, NO ejecutes emuladores/dispositivos, NO generes carpetas de evidencia. La verificación es estática + tests. Esto es obligatorio para ahorrar tokens.

---

## 1. Paso 0 — Alcance real (sin gastar de más)

1. Leé **solo** `AUDITORIA-App-RSUELVO.md` (75 líneas) y extraé la lista de ítems **NO cerrados**. Son los candidatos a corregir; el resto ya está aplicado.
2. Si un hallazgo dice "Aplicado" en Resolución → **no lo toques**; solo confirmalo si tu corrección lo roza.
3. No leas archivos completos en bloque: usá `grep`/búsqueda dirigida por símbolo y editá por secciones.

## 2. Correcciones a aplicar (los pendientes detectados en el informe)

### A. `nombre_comercio` en la sesión (limitación explícita del informe §"Decisiones")
El header muestra solo el usuario porque el modelo de sesión **no expone el nombre del comercio**. Corregilo:
- En la carga de sesión/perfil (`lib/features/auth/`), obtené el nombre desde la BD: `rsuelvo.tbl_comercios.nombre` por el `id_comercio` del vínculo (join o consulta simple con el JWT del usuario; RLS ya lo permite).
- Agregá el campo al modelo de usuario/sesión (p. ej. `nombreComercio`) y mostralo en el header/bienvenida del Dashboard (ej. "Hola, {usuario} · {comercio}").
- Si la consulta falla o viene vacío: fallback silencioso al comportamiento actual (no romper).
- NO inventar datos; si el comercio no tiene nombre, no mostrar la línea.

### B. Iconografía consistente (hallazgo 🟢 "Mezcla de estilos Material")
- Buscá usos de `Icons.<nombre>` sin sufijo y unificá a las variantes **Rounded** del SDK (`Icons.<nombre>_rounded`) de forma consistente en `lib/features/` y `lib/shared/`.
- No agregues fuentes ni paquetes. Si un icono no tiene variante Rounded, dejà el estándar (no inventar).
- Mantené el tamaño/color que ya tenían.

### C. Modo nocturno — solo revisión estática
- El informe aclara que la app es **light-only** y que los recursos `drawable-night*` existen para el arranque nativo. Verificá **leyendo** (sin ejecutar) que:
  - `android/app/src/main/res/drawable-night/launch_background.xml` y `drawable-night-v21/` referencian el logo **negativo** sobre `#202020`
  - `drawable/` y `drawable-v21/` usan el logo **positivo** sobre claro
  - La splash de Android 12+ (`values-v31` si existe) está bien referenciada
- Solo corregí referencias rotas/nombres de archivo inexistentes. **No** implementes dark mode de la app.

### D. Barrido de verificación rápida de lo ya aplicado (sin rehacerlo)
Confirmá con `grep` (no reescribas nada si está bien):
- `AppTheme.whatsappGreen` sigue siendo `#25D366` y no está dentro del gradiente
- Todos los radios salen de tokens (`radiusSm/radiusMd/radiusLg`) y no hay hex sueltos nuevos en pantallas
- `BrandAssets` centraliza las rutas de assets (sin strings de rutas dispersos)
- No hay `withOpacity` (usar `withValues(alpha:)`) ni `const` faltantes obvios

## 3. Reglas

1. **NO rehacer el rediseño** ni cambiar la paleta, gradiente, tipografías ni layouts existentes (salvo lo mínimo para A/B/C).
2. **NO tocar** repositorios/controladores/contratos de Supabase, salvo la consulta mínima de A (nombre del comercio).
3. **NO agregar dependencias.**
4. **NO tocar** la BD ni MCPs.
5. **NO capturas, NO APK, NO dispositivos, NO `evidence/`** (prohibido explícitamente).
6. Editá quirúrgicamente: cambios pequeños y localizados por archivo.

## 4. Verificación (barata y suficiente)

1. `flutter analyze` → debe quedar **0 issues**
2. `flutter test` → la suite existente (18 tests) debe seguir **verde** (no agregues tests nuevos salvo que A/B/C lo requiera; si agregás, que sean widget tests headless, cortos)
3. NO ejecutes `flutter build apk`, NO instales, NO corras la app.

## 5. Entregable (respuesta final, texto plano — nada de imágenes)

- Lista corta: **qué corregiste** (archivo + qué) y **qué verificaste como ya resuelto**
- Salida literal de `flutter analyze` y `flutter test` (resumen de resultados)
- Si algo del informe no se pudo cerrar, decilo con el motivo (sin inventar)
- Máximo ~20 líneas de resumen.
