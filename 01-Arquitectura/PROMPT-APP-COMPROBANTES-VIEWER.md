# PROMPT APP — Visor de comprobantes por path (firmar al ver)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Bug real: `archivo_url` guarda URLs firmadas con expiración (7 días) y links
Meta lookaside (transitorios) — los comprobantes viejos no se ven. Backend LISTO
(mig 64, verificado): nueva columna `archivo_path` (`<id_comercio>/<archivo>` en
bucket `comprobantes-pago`, 9/12 paths recuperados y con objeto vivo) + policies
de lectura tenant/staff. Reglas: jamás `service_role` (anon + RLS), español,
economía de tokens, sin capturas/APK.

## Feature (sin cambios BD)
Al visualizar un comprobante (imagen y PDF): si `archivo_path` existe, firmar
al momento con `createSignedUrl(path, 3600)` y mostrar; si es NULL (3 legacy),
fallback a `archivo_url` con mensaje "archivo no disponible, pedir reenvío" si
falla. Reutilizar repositorio/estilos; `flutter analyze` limpio + test con
Storage mock (prohibido tocar el bucket real).

## Entregable
Visor corregido + test + commit. Si algún contrato no existe, reportar.
