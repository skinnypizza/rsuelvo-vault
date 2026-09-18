# PROMPT CODEX (Astra) — Web: habilitar usuarios + solicitudes sysadmin

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
Backend LISTO (migs 68/73 + EF v8, verificado): `fn_editar_usuario`,
`fn_gestionar_vinculo` (CREAR/DESACTIVAR, invariantes), EF invite roles 2/3/4,
solicitudes legibles/resolubles por SUPERADMIN y SYSADMIN. Prohibido SUPERADMIN
por invite o edición (`protegido`); sysadmin NO ve usuarios globales.
Reglas: anon+RLS, español, economía, UN commit, builds+tests verdes.

## Cambios (solo `/app`)
1. **Usuarios:** habilitar editar (nombre/apellido/teléfono/activo) y
   activar/desactivar vínculos vía `fn_editar_usuario` + `fn_gestionar_vinculo`;
   habilitar invitar SYSADMIN/SUPPORT (superadmin) vía EF; mostrar `protegido`
   como aviso, no como error crudo. Solo SUPERADMIN.
2. **Solicitudes sysadmin:** misma pantalla para SYSADMIN (leer + aprobar/rechazar);
   mantener SUPERADMIN. Capability nueva o reuse con gate por rol (seguir patrón
   `permissions.ts` + tests).

## Verificación
Typecheck + tests (mocks de nuevos RPC) + build verdes; commit «usuarios+solicitudes-sysadmin».
