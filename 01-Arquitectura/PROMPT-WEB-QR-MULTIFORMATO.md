# PROMPT CODEX (Astra) — Web: QR paquetes multi-formato

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
El QR de paquetes solo acepta PNG/JPG: `accept` en `CreditsPage.tsx` (~l38),
regex + path fijo `.png` en `uploadPackageQr` (`api.ts:149-160`). El backend no
limita (buckets sin MIME). Reglas: español, economía, UN commit, builds+tests verdes.

## Cambio (solo `/app`)
Aceptar `png/jpg/jpeg/webp` (rechazar resto con mensaje): `accept` ampliado,
regex `^image\/(png|jpeg|jpg|webp)$`, extensión real del archivo (`jpg`→`jpeg`
en contentType), path `paquetes/<id>.<ext>` con `upsert:true`, `qr_path` con el
path real. `removePackageQr`/`signedPackageQrUrl` ya usan path guardado (verificar).
Límite 5 MB intacto.

## Verificación
Tests (formatos ok/rechazo/extensión real) + build verdes; commit «qr multi-formato».
