# PROMPT ANTIGRAVITY — Móvil: QR por paquete + mostrar al solicitar

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Backend LISTO (mig 74, verificado): `tbl_paquetes_creditos.qr_path` (path en
`qr-pagos/paquetes/*.png`, UPDATE solo superadmin); firmar al ver con
`createSignedUrl`. Marca `brand.dart`. Reglas: jamás `service_role`, español,
gates por rol, economía, sin capturas, `flutter analyze` limpio + tests con
mocks (sin datos reales).

## Cambios (sin cambios BD)
1. **Paquetes (SUPERADMIN):** subir QR por paquete + guardar `qr_path`;
   ver/quitar actual.
2. **Solicitar (dueño):** al elegir paquete, mostrar su QR firmado; sin QR,
   aviso de pedir datos al staff.

## Verificación y entregable
Tests + commit. Si un contrato no existe, reportar.
