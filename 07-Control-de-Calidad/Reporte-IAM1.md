# Reporte QA IAM-1

**Fecha:** 2026-09-22  
**Alcance:** IAM-D + REG-D, solo fósiles de prueba. No se modificaron código, BD, cloud ni producción.  
**Resultado global:** **BLOQUEADO**.

## Evidencia y condiciones de ejecución

- Suite y contratos revisados: `Suite-Aceptacion-IAM.md`, `D-IAM-INVITACIONES` incluido en el bundle, `Informe-IAM0-B-Flutter.md`, `Informe-IAM0-C-Web.md` y `PROMPT-IAM1-QA.md`.
- Backend: evidencia previa del orquestador, 2026-09-21, 10/10: invitación existente/reintento, aceptación, re-aceptación, revocación/re-revocación, expiración inline y deny-by-default SELECT; fósiles revertidos.
- Regresión: evidencia previa del orquestador, 2026-09-21, 5/5, sin secretos; fósiles revertidos.
- Flutter probado/revisado: `1c32e395959837bca5993f1179d04fbe63867dc8` (analyze 0, 285/285 según estado archivado).
- Web probado/revisado: `8bef7ac5d0ec7fe029003cd6a4f8e8ea493331dd` (build OK, 68 tests según estado archivado).
- Grep estático actual: negativo en fuentes Flutter y Web para `password_temporal`, `passwordTemporal`, `Clipboard.setData` y `password temporal`.
- Reintentos de red: Supabase con `--resolve 104.18.38.10`, 3 intentos, conexión rechazada; Pages, 3 intentos, DNS no resolvió. No se ejecutaron mutaciones ni casos que requieran backend/web vivo.

## Casos

| Caso | Resultado | Evidencia |
|---|---|---|
| IAM-D-001 Invitación nueva | NO EJECUTADO-dependencia externa | Requiere cuota de correo Supabase y flujo usuario-nuevo vivo; expresamente excluido por el bundle. |
| IAM-D-002 Invitación idempotente | PASS | Evidencia previa backend 2026-09-21: reintento sin duplicado, fósiles revertidos. |
| IAM-D-003 Invitación expirada | PASS | Evidencia previa: expiración inline rechazada sin depender del cron. |
| IAM-D-004 Invitación usada | PASS | Evidencia previa: aceptación y re-aceptación; segundo uso rechazado. |
| IAM-D-005 Invitación revocada | PASS | Evidencia previa: revoke + re-revoke, sin mutación colateral. |
| IAM-D-006 Email existente/misma membresía | PASS | Evidencia previa: invite existente e idempotencia, sin duplicar identidad/vínculo. |
| IAM-D-007 Email existente/otra membresía | NO EJECUTADO-dependencia externa | Requiere escenario multi-tenant vivo y cliente desplegado; red no disponible. |
| IAM-D-008 Email nuevo | NO EJECUTADO-dependencia externa | Es flujo de usuario nuevo; requiere cuota de correo Supabase. |
| IAM-D-009 Rol no permitido | NO EJECUTADO-dependencia externa | Requiere invocación viva desde EF/RPC y auditoría; Supabase no conectó. |
| IAM-D-010 Sucursal de otro tenant | PASS | Evidencia previa backend: intento cross-tenant rechazado y fósiles revertidos. |
| IAM-D-011 Atacante sin permisos | PASS | Evidencia previa backend: deny-by-default SELECT y rutas protegidas; sin cambios persistentes. |
| IAM-D-012 Respuestas sin password | PASS | Grep negativo actual en Flutter/Web y EF v9 sin campo secreto; evidencia previa de responses sin secretos. |
| IAM-D-013 Dos roles iguales en dos comercios | NO EJECUTADO-dependencia externa | Requiere dos membresías y ejecución viva de módulos; clientes/backend inaccesibles por red. |
| IAM-D-014 Dos roles distintos en dos comercios | NO EJECUTADO-dependencia externa | Requiere sesión multi-tenant viva y RLS; no se inventa resultado. |
| IAM-D-015 Cambio repetido de comercio | NO EJECUTADO-dependencia externa | Requiere app/web desplegados y datos fósiles vivos. |
| IAM-D-016 Revocación del comercio seleccionado | NO EJECUTADO-dependencia externa | Requiere sesión persistente y revocación viva. |
| IAM-D-017 Reinicio de aplicación | NO EJECUTADO-dependencia externa | Requiere ejecución Flutter/dispositivo con backend disponible. |
| IAM-D-018 Revocación unilateral A/B | NO EJECUTADO-dependencia externa | Requiere membresías A/B y RPC viva. |
| IAM-D-019 Recovery de cuenta privilegiada | NO EJECUTADO-dependencia externa | Requiere login superadmin vivo; explícitamente fuera de alcance/dependencia del bundle. |
| IAM-D-020 `fn_editar_usuario` | NO EJECUTADO-dependencia externa | Requiere RPC viva y auditoría consultable; sin conexión Supabase. |
| IAM-D-021 `fn_gestionar_vinculo` | NO EJECUTADO-dependencia externa | Requiere RPC viva y fixtures A/B; sin conexión Supabase. |
| REG-D-001 Pedidos y reservas | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-002 Pagos y comprobantes | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-003 Inventario y variantes | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-004 Créditos | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-005 Logística | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-006 Sesión sobre módulos operativos | NO EJECUTADO-dependencia externa | Requiere ejecución Flutter/Web y backend vivos; no se pudo conectar. |

## Veredicto IAM-1

**BLOQUEADO.** Hay evidencia suficiente para los casos backend/regresión indicados y grep negativo de secretos en los clientes actuales, pero no se cumple el DoD de 100% ejecutado. Quedan pendientes IAM-D-001, IAM-D-007 a IAM-D-009, IAM-D-013 a IAM-D-021 y REG-D-006 por dependencias externas o flujo vivo no disponible. No se declara verde ningún caso no ejecutado.

No se actualizó `ESTADO-EJECUCION.md` porque el bundle autoriza escribir únicamente este reporte.

## Addendum orquestador (2026-09-22, red propia con fósiles, todo revertido)

Casos que el agente QA no pudo ejecutar por sandbox sin red, ejecutados en vivo:

| Caso | Resultado | Evidencia |
|---|---|---|
| Rol fuera de alcance (id_rol 7) | PASS | `{"ok":false,"error":"Rol fuera de alcance"}` |
| Sucursal ajena al comercio | PASS | `{"ok":false,"error":"Sucursal ajena al comercio"}` |
| Atacante sin permiso (cajero invita rol 5) | PASS | 403 `El invocador no tiene permiso para este rol` |
| Sin sesión | PASS | `UNAUTHORIZED_NO_AUTH_HEADER` (verify_jwt) |
| Cero secretos en todas las responses | PASS | assert `password_temporal` ausente en cada respuesta |

Quedan NO EJECUTADOS-dependencia externa (ChatGPT los exige así): usuario-nuevo vivo (cuota mail) y PATH SUPERADMIN vivo (login superadmin).
