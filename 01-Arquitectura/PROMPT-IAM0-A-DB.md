# IAM-0/A — Auditoría DB/IAM backend (solo lectura)

## OBJETIVO
Inventariar el modelo IAM real en cloud + SQL canónico y determinar qué lifecycle existe ya y qué migración mínima pediría IAM-1/IAM-2. CERO cambios.

## ALCANCE EXACTO
Solo leer e informar. Nada de migraciones, nada de cloud-write, nada de archivos productivos.

## REPOSITORIO
`skinnypizza/rsuelvo-vault` (fuentes) + inspección READ-ONLY de Supabase cloud (`iwfaktlxebxtocmswdvv`, schema `rsuelvo`).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `02-Base-de-Datos/sql/03_tables.sql` → `tbl_usuarios`, `tbl_usuario_comercio`, `tbl_roles`, `tbl_comercios`, `tbl_sucursales`, `tbl_logs_auditoria` (columnas, defaults, constraints)
- `02_enums.sql:90-91` (códigos de rol canónicos), `06_functions.sql` + migs 58-78 (`fn_editar_usuario`, `fn_gestionar_vinculo`, helpers RLS/permisos)
- `08_rls.sql` + migs 58-78 (políticas que tocan usuarios/vínculos/comercios)
- `06-Integraciones/Edge-Function-invitar-usuario-comercio.md` (contrato invite v8: qué devuelve, qué persiste)
- `02-Base-de-Datos/Matriz de permisos.md` (qué dice hoy sobre usuarios/vínculos)

## DEPENDENCIAS
Ninguna (corre en paralelo con B/C/D). Su informe alimenta el contrato IAM-1.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Patrón `auth.uid() → tbl_usuarios.auth_user_id → tbl_usuario_comercio.id_comercio`; RLS siempre activo
- Reglas de Oro 2, 6, 7, 9 (atomicidad fn_*, RLS, idempotencia, auditoría)
- Flujos operativos vivos: pedidos/pagos/inventario/logística/créditos

## CAMBIOS PERMITIDOS
Ninguno en código/schema/cloud. Solo producir el informe.

## CAMBIOS PROHIBIDOS
`apply_migration`, `execute_sql` con write, deploy, seed, tocar RLS/funciones/tablas, crear agentes.

## PRUEBAS REQUERIDAS
Verificación read-only: cada afirmación del informe con cita (archivo:línea o query SELECT de comprobación). Listar breaking changes potenciales si IAM-1/IAM-2 tocaran cada objeto.

## ENTREGABLES
Informe con: 1) estado exacto por tabla (columnas de lifecycle: ¿existe `activo`? ¿`invited_by/accepted_at`?); 2) funciones de vínculos y su atomicidad; 3) RLS vigente sobre usuarios/vínculos; 4) qué falta para invitación un-solo-uso + estados INVITED/ACTIVE/SUSPENDED/REVOKED (migración mínima propuesta, SIN aplicar); 5) matriz actual→objetivo→objeto afectado.

## DEFINITION OF DONE
Cero cambios funcionales; inventario validado contra cloud real; breaking changes listados; propuesta de migración escrita pero NO aplicada.
