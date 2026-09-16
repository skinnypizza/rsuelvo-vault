# PROMPT CODEX — QR del comercio (dueño, app Flutter)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`, código `/home/nico/StudioProjects/rsuelvo`)
Rol dueño (`ROLE_TENANT_ADMIN`, roles expandidos 2026-09-15): configura el QR
estático de su comercio desde la app. Backend LISTO (mig 62, verificado):
policies `qr_pagos_dueno_*` sobre bucket `qr-pagos` — el dueño (vínculo ADMIN del
comercio) puede SELECT/INSERT/UPDATE solo en path `<id_comercio>/...`
(`fn_es_admin_comercio` sobre el primer segmento; superadmin global aparte).
Convención de path: `qr-pagos/<id_comercio>/tienda.png`.
Reglas: jamás `service_role` en Flutter (anon + RLS), español, marca en
`brand.dart`, economía de tokens, sin capturas/APK.

## Feature (implementar directo, sin cambios BD)
Pantalla "QR de mi comercio" (gate: solo dueño; enlazada desde ficha/config del
comercio): muestra el QR actual (download del path; placeholder si no existe),
botón subir/reemplazar (PNG/JPG, galería/cámara), confirmación antes de
sobrescribir, mensaje de éxito/error en español. Reutilizar repositorio/estilos
existentes; Storage API directo de supabase-flutter, sin RPC.

## Verificación y entregable
`flutter analyze` limpio + test con Storage MOCK (PROHIBIDO subir archivos de
prueba al bucket real: ni `test-*.png` ni nada; la verificación visual con el QR
real la hace el dueño). Commit con mensaje claro. Si algún contrato no existe,
reportar en vez de inventar.
