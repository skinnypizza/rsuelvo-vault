# IAM-1/WEB — Alinear invitación + roles (implementación)

## OBJETIVO
Mismo contrato de invitación que backend/Flutter + cerrar N-2 (roles permitidos). Sin selector tenant (ver D-IAM-WEB-SCOPE).

## ALCANCE EXACTO
Solo invite/usuarios. Prohibido: selector de comercio, cambios de capabilities fuera de invite, N-1/N-3/N-5/N-6.

## REPOSITORIO
`skinnypizza/rsuelvo-web`, rama `main` (`app/`).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `07-Control-de-Calidad/Informe-IAM0-C-Web.md` (§ invitaciones + N-2)
- `app/src/data/api.ts` (llamadas invite / `fn_editar_usuario` / `fn_gestionar_vinculo`)
- Pantallas de usuarios/staff que inviten (mismo patrón que Flutter: sin secreto, con estados)
- `app/src/auth/permissions.ts` (NO renombrar ni duplicar; solo usar gates existentes)
- `01-Arquitectura/D-IAM-INVITACIONES.md`, `01-Arquitectura/D-IAM-WEB-SCOPE.md` (límites explícitos)

## DEPENDENCIAS
Backend IAM-1 desplegado (EF v9). No crear agentes persistentes.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- `permissions.ts` como referencia única; build + deploy Pages verdes; jamás secretos en frontend/logs

## CAMBIOS PERMITIDOS
Alinear UI invite al contrato v9 (roles permitidos = los del backend, cierra N-2) + estados Pendiente/Aceptada/Vencida/Revocada + actualizar `docs/solicitudes-backend.md` si menciona invite.

## CAMBIOS PROHIBIDOS
Selector tenant, tocar `highestRole`, packages/reports/solicitudes (N-1/N-3/N-5/N-6), MFA, permiso paralelo.

## PRUEBAS REQUERIDAS
`tsc`+build verdes; tests de invite actualizado; verificación: ningún response/UI/log contiene secreto.

## ENTREGABLES
Commit en `main` + deploy Pages verificado 200.

## DEFINITION OF DONE
Contrato invite idéntico a Flutter/backend; N-2 cerrado; build verde; alcance respetado.
