# PROMPT CODEX (Astra) — Web: verificar filtro de reportes por rol

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
`ReportsPage.tsx` ya deshabilita 2 tipos a no-sensibles. Verificar y completar:
- SUPERADMIN: 4 tipos (`depositos, creditos, estados, autorizaciones`).
- SYSADMIN/SUPPORT: solo `creditos` + `estados` (nunca `depositos` ni
  `autorizaciones`, ni siquiera deshabilitados: que no se listen).
- La capability `reports.sensitive` ya existe (`permissions.ts`): usarla para
  ocultar (no solo deshabilitar) + tests. Sin tocar backend.
Reglas: español, economía, UN commit, builds+tests verdes.
