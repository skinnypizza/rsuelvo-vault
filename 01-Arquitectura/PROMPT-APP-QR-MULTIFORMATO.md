# PROMPT ANTIGRAVITY — Móvil: QR paquetes multi-formato

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
El QR de paquetes exige PNG (`paquetes_creditos_admin_screen.dart:32`,
`creditos_repository.dart:205 paqueteQrPath fijo + :212 validación`). El backend
no limita. Marca `brand.dart`. Reglas: jamás `service_role`, español, gate
SUPERADMIN, economía, sin capturas, `flutter analyze` limpio + tests con mocks.

## Cambio (sin cambios BD)
Aceptar `png/jpg/jpeg/webp`: validación por set, contentType real (`jpg`→`jpeg`),
path `paquetes/<id>.<ext>` con upsert (visualización usa el `qr_path` guardado,
compatible con los `.png` existentes). Mensaje de rechazo en español para otros
formatos. (Opcional futuro: HEIC de cámara iOS — NO en este prompt.)

## Verificación y entregable
Tests (formatos/extensión real/rechazo) + commit. Si un contrato no existe, reportar.
