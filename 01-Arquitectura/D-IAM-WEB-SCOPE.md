# D-IAM-WEB-SCOPE — Staff global vs contexto tenant (resuelve C-03)

**Fecha:** 2026-09-21 · **Estado:** DECIDIDA · Responde a `Revision-ChatGPT-IAM0.md` C-03.

## Decisión

`rsuelvo-web` `/app` es **backoffice staff global de RSUELVO**, no cliente tenant-operativo. Sus usuarios (ROLE_SUPERADMIN/SYSADMIN/SUPPORT) operan cross-tenant por diseño: solicitudes, comercios, créditos, usuarios globales, reportes.

## Consecuencias

1. `highestRole` sobre roles staff es **intencional**, no el defecto de Flutter. No se impone selector de comercio a la web.
2. Prohibido en web: pantallas tenant-operativas (pedidos/pagos/inventario/logística viven en Flutter).
3. Toda mutación con `id_comercio` explícito debe verificarse en `fn_*`/RLS (nunca confiar el id del cliente). Casos a cerrar en IAM-6: N-5 (gates `users.invite`/`users.mutate` internos) y N-6 (`compras_select` permite SYSADMIN/SUPPORT ver depósitos — restringir en RLS o documentar excepción).
4. H-IAM-03-Web queda **resuelto por diseño**. La convergencia IAM-6 mapea capabilities→controles server-side, sin selector tenant.
