# IAM-7/BACKEND — Tablas y funciones de consentimiento (implementación, SOLO tras aprobación)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-CONSENTIMIENTO.md`: documentos versionados + aceptaciones con evidencia. Sin esto no avanzan clientes.

## ALCANCE EXACTO
Solo backend: migración SQL + seed v1 + E2E SQL. Nada de UI.

## REPOSITORIO
Vault `02-Base-de-Datos/sql/` (nueva mig + monolito al final).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-CONSENTIMIENTO.md` (manda la versión revisada)
- `02-Base-de-Datos/sql/88_guard_regression_test.sql` (última mig: patrón + estilo `{ok,codigo}`)
- Tablas de referencia: `tbl_contact_preferences` (NO fusionar; dominio distinto), `tbl_usuarios`

## DEPENDENCIAS
Contrato aprobado. Sin eso, NO codificar.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Reglas de Oro 2, 6, 7, 9; `fn_es_service_role()`/`fn_tiene_aal2()` intactos; IAM-1..6 sin regresión; `fn_verificar_guards_sanos()` verde.

## CAMBIOS PERMITIDOS
Mig aditiva (`tbl_documentos_legales`, `tbl_aceptaciones`, UNIQUE usuario+doc+versión, RLS deny-by-default + GRANTs, `fn_aceptar_documento`, `fn_documentos_pendientes`, seed v1 TERMINOS/PRIVACIDAD) + triggers de `updated_at` si aplica.

## CAMBIOS PROHIBIDOS
Bloquear flujos existentes por defecto (la obligatoriedad la aplica la UI tras revisión) · KYC/biometría · SecurityEvent · tocar contact_preferences · secretos en logs.

## PRUEBAS REQUERIDAS
E2E SQL con fósiles: seed visible, pendientes correctos, aceptar registra evidencia (usuario+versión+fecha+canal), re-aceptación por versión nueva, UNIQUE impide duplicado, RLS deny-by-default verificado, regresión aislamiento 11.

## ENTREGABLES
Mig aplicada + verificada · informe E2E por caso · monolito + ESTADO-EJECUCION.

## DEFINITION OF DONE
Casos verdes; cero cambios fuera del alcance; vault actualizado.
