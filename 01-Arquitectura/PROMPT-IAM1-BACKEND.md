# IAM-1/BACKEND — Invitaciones seguras (implementación)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-INVITACIONES.md`: eliminar `password_temporal` del contrato y dejar operativa la invitación de un solo uso. Sin esto no avanzan Flutter/Web/QA.

## ALCANCE EXACTO
Migración SQL + reescritura EF `invitar-usuario-comercio` + `fn_aceptar_invitacion` + tests SQL. Nada de UI.

## REPOSITORIO
Vault `02-Base-de-Datos/sql/` (nueva mig `79_invitaciones_seguras.sql`, monolito al final) + `supabase/functions/invitar-usuario-comercio/` (fuente EF) + doc `06-Integraciones/Edge-Function-invitar-usuario-comercio.md`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-INVITACIONES.md` (contrato definitivo — implementar EXACTAMENTE esto)
- `02-Base-de-Datos/sql/68_usuarios_staff.sql` (estilo `fn_*`, gates, `{ok,codigo}`)
- `02-Base-de-Datos/sql/78_transportadoras_tenant.sql` (última mig: patrón RLS+GRANT)
- `06-Integraciones/Edge-Function-invitar-usuario-comercio.ts` (fuente v8 a reescribir)
- `07-Control-de-Calidad/Suite-Aceptacion-IAM.md` (casos IAM-D a satisfacer)

## DEPENDENCIAS
Ninguna (primero del lote). Flutter/Web/QA dependen de este entregable.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Respuesta EF: jamás `password_temporal` ni secreto alguno (verificable por grep + test)
- Reglas de Oro 2, 6, 7, 9; `fn_es_service_role()` intacto (mig 61); flujos operativos vivos
- `tbl_usuario_comercio.activo` sigue funcionando (columnas nuevas aditivas, sincronizadas)

## CAMBIOS PERMITIDOS
Mig 79 (columnas lifecycle + `tbl_invitaciones` + índice parcial + `fn_aceptar_invitacion` + RLS deny-by-default + GRANTs) · EF v9 (invite nativo / accept / revoke, idempotencia por índice parcial, `email existe→vincular`) · actualizar EF-doc (eliminar "mostrar/copiar") · monolito.

## CAMBIOS PROHIBIDOS
Token/código propio (Supabase único secreto) · UNIQUE global (email,comercio) · tocar `cajero_multiplo`/N-4 (IAM-2) · selector multi-comercio/MFA/SecurityEvent · N-1/N-3/N-5/N-6 · secretos en logs.

## PRUEBAS REQUERIDAS
Suite SQL: crear→aceptar nuevo, aceptar existente, idempotente (reintento mismo PENDIENTE), expirada (sin depender de cron), consumida, revocada, email distinto (rechazo), rol no permitido, sucursal otro tenant, atacante sin permiso, `activo` legacy sincronizado. Aislamiento 11 casos verde.

## ENTREGABLES
Mig 79 aplicada en cloud + verificada · EF v9 desplegada + probada viva con fósiles · EF-doc actualizado · informe de pruebas.

## DEFINITION OF DONE
Ningún response/log contiene secreto; los 11 casos IAM-D pasan en cloud; regresión verde; vault actualizado + ESTADO-EJECUCION.
