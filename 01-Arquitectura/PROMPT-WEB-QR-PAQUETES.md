# PROMPT CODEX (Astra) — Web: QR por paquete + mostrar al solicitar

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
Backend LISTO (mig 74, verificado): `tbl_paquetes_creditos.qr_path` (path en
`qr-pagos/paquetes/*.png`, UPDATE solo superadmin, lectura pública catalogada);
el QR se sube por Storage API al path y se guarda el path en la fila; al
visualizar se firma (`createSignedUrl`). Reglas: anon+RLS, español, economía,
UN commit, builds+tests verdes.

## Cambios (solo `/app`)
1. **Paquetes (SUPERADMIN):** en la gestión de paquetes/créditos, subir QR por
   paquete (PNG/JPG → `qr-pagos/paquetes/<id_paquete>.png`) y guardar `qr_path`;
   ver/quitar el actual.
2. **Solicitar (dueño):** al elegir paquete en la solicitud, mostrar su QR
   (firmado al ver) junto a los datos para el depósito; sin QR configurado,
   aviso «el staff te pasará los datos».

## Verificación
Typecheck + tests (mocks Storage/RLS) + build verdes; commit «qr-paquetes».
