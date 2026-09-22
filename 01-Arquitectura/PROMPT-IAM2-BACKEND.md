# IAM-2B/BACKEND — Lifecycle de membresías (implementación, SOLO tras IAM-2A)

## DEPENDENCIA OBLIGATORIA
**IAM-2A Flutter verificado (SHA registrado) antes de aplicar mig 81.** Sin eso, NO-GO. Compatibilidad transitoria solo como fallback para legacy realmente desplegado.

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-MEMBERSHIP.md`: lifecycle ACTIVE/SUSPENDED/REVOKED con regla canónica única, N-4 por comercio, anti-duplicados. Sin esto no hay IAM-3.

## ALCANCE EXACTO
Solo backend: migración SQL + E2E lifecycle. Nada de UI (selector = IAM-3; `actualizarVinculo` por fn = sublote posterior).

## REPOSITORIO
Vault `02-Base-de-Datos/sql/` (nueva mig `81_membership_lifecycle.sql`, monolito al final).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-MEMBERSHIP.md` (contrato — implementar EXACTAMENTE lo aprobado; si la revisión lo modificó, manda la versión revisada)
- `02-Base-de-Datos/sql/68_usuarios_staff.sql` (fns a extender, estilo `{ok,codigo}`, gates)
- `02-Base-de-Datos/sql/79_invitaciones_seguras.sql` (`fn_aceptar_invitacion` — NO romper; agregar `FOR UPDATE` donde falte)
- `02-Base-de-Datos/sql/80_fix_invited_by_nullable.sql` (última mig: patrón)
- `07-Control-de-Calidad/Suite-Aceptacion-IAM.md` + `Reporte-IAM1.md` (casos IAM-D-007/013-018 a cubrir si son lifecycle)

## DEPENDENCIAS
Contrato D-IAM-MEMBERSHIP aprobado por revisión. Sin aprobación, NO codificar.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Contratos IAM-1 (invite/accept/revoke, invitaciones PENDIENTE) intactos y con regresión verde
- RLS, aislamiento tenant, auditoría, protección SUPERADMIN, `fn_es_service_role()` (mig 61)
- `activo` sigue legible para clientes viejos (trigger lo deriva; jamás escribirlo directo en fns nuevas)
- Flujos operativos vivos

## CAMBIOS PERMITIDOS
Mig 81: `CREATE OR REPLACE` mínimo de `fn_aceptar_invitacion` (solo regla N-4 por comercio + vigentes) · N-4 por comercio en `fn_gestionar_vinculo` · acciones SUSPENDER/REVOCAR (DESACTIVAR→SUSPENDER) · cascada editar→SUSPENDED (jamás REVOKED; sin auto-reactivación) · índice único parcial `WHERE estado IN ('ACTIVE','SUSPENDED')` con preflight + manejo `unique_violation` · `FOR UPDATE` faltantes · trigger canónico `activo=(estado='ACTIVE')` SOLO en Fase B (tras sublote Flutter verificado) o compatibilidad transitoria documentada.

## CAMBIOS PROHIBIDOS
Reescribir migs 68/79/80 · tocar invitaciones/accept salvo regla N-4 puntual · REVOKED por defecto en editar · trigger canónico en Fase A con cliente legacy sin migrar · selector UI · `selected.first` · MFA/SecurityEvent · N-1/N-3/N-5/N-6 · secretos en logs.

## PRUEBAS REQUERIDAS
E2E backend con fósiles (revertido): N-4 por comercio en AMBOS paths (gestionar + accept) · transiciones + terminalidad REVOKED + reingreso fila nueva · SUSPENDED reactiva misma fila · cascada editar sin auto-restaurar · A-no-afecta-B · duplicado concurrente (índice) · IAM-D-007 · regresión IAM-1 (10/10) + aislamiento 11 + grep cero secretos.

## ENTREGABLES
Mig 81 aplicada + verificada · informe E2E por caso · monolito + ESTADO-EJECUCION.

## DEFINITION OF DONE
Todos los casos E2E pasan; IAM-1 sigue 10/10; cero divergencia activo/estado (verificado por query); vault actualizado.
