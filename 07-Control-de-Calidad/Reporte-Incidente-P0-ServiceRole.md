# Reporte Incidente P0 — `fn_es_service_role()` universalmente TRUE

**Fecha detección:** 2026-09-22 (diagnóstico IAM-5: `fn_cerrar_comercio` aal1 no devolvía `mfa_requerido`) · **Mitigado:** mismo día, mig 87 · **Estado:** CERRADO con deuda de telemetría declarada.

## Causa raíz
Mig 76 añadió `OR current_user IN ('postgres','service_role')` para identidad backend/n8n. Todas las fns son `SECURITY DEFINER` con owner `postgres` → `current_user='postgres'` siempre → helper TRUE para cualquier `authenticated`, con o sin JWT.

## Ventana vulnerable
2026-09-19 (aplicación mig 76, incidente FEE) → 2026-09-22 (mig 87). Aproximada por bitácora; commits `c126814`→`1bb0423`.

## Superficie afectada
1. **Lectura global:** `audit_sysadmin_select` (única policy con el helper) → cualquier logueado leía `tbl_logs_auditoria` sin scope. Verificado en vivo (dueno@test).
2. **Mutación administrativa:** gates `if not (fn_es_service_role() or ...)` en `fn_gestionar_vinculo`, `fn_editar_usuario`, `fn_alta_comercio`, `fn_cambiar_estado_comercio`, resolver-solicitudes → cualquier autenticado pasaba el gate (RLS de filas seguía según policies, pero la autorización de rol estaba abierta).
3. **Mutación tenant/operativa:** helpers `fn_tiene_acceso_comercio/sucursal`, `fn_es_admin_comercio`, `fn_tiene_rol_comercio`, `fn_puede_*` (todos `OR` con el helper) → RLS tenant abierta cross-tenant para lectura Y escritura en tablas que los usan (comercios, inventario, pedidos, usuarios, créditos, etc.).
4. **Invitaciones/altas/solicitudes:** gates con el helper igualmente abiertos.

## Evidencia de explotación
- Mutaciones sensibles en ventana: 100% atribuibles a fósiles propios (dueno/cajero E2E documentado) o flujos service (triggers/n8n); 0 actores terceros; 0 cambios en roles; 0 DELETE en usuarios/comercios.
- **Lecturas: exposición potencial NO cuantificable** (sin telemetría SELECT). No se declara PASS de no-explotación en lectura.
- Mitigante: ventana de 3 días, proyecto sin tráfico real (fósiles + FEE creado 09-19 sin operación), atacantes requerirían credenciales válidas + conocimiento del schema.

## Acciones correctivas
- Mig 87: JWT manda con JWT; `current_user` solo si `auth.jwt() IS NULL` (n8n/PG directo preservado; verificado `backend_identity=true`).
- Overload fantasma `fn_gestionar_vinculo(5p)` eliminado (PGRST203).
- Mig 88: `fn_verificar_guards_sanos()` permanente (falla si vuelve el bypass; verificado `ok:true`).
- Re-verificado: helper false para dueno, audit scoped FER, gates restaurados, AAL guard dispara.

## n8n
Ningún workflow llama fns con guards nuevos (grep vault vacío salvo mención histórica). Server-to-server (service_role key / PG directo) compatible por diseño. IAM-5 guards NO aplicados a RPCs operativas de ventas.

## Estado FER
Cierre accidental `CANCELADO` durante diagnóstico (E2E cerrar aal1, comercio fósil sin tráfico) → revertido a `ACTIVO` minutos después en la misma sesión. 0 pedidos FER el 2026-09-22; sin efectos derivados.

## Preventivas
- `fn_verificar_guards_sanos()` en cada lote que toque helpers/RLS.
- Prohibido `current_user` como OR incondicional en SECURITY DEFINER (documentado en contrato).
- E2E negativos con JWT humano en cada cambio de guards (`solo superadmin` / `mfa_requerido`).
