# Reporte QA IAM-1

**Fecha:** 2026-09-22  
**Alcance:** IAM-D + REG-D, solo fósiles de prueba. No se modificaron código, BD, cloud ni producción.  
**Resultado global:** **IMPLEMENTACIÓN COMPLETA / APROBADA CON CERTIFICACIÓN E2E PENDIENTE DE 2 CASOS EXTERNOS** (revisión ChatGPT 2026-09-22).

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
| IAM-D-001 Invitación nueva (usuario existente) | PASS | Evidencia previa backend + addendum: flujo existente completo sin secretos. |
| IAM-D-002 Invitación idempotente | PASS | Evidencia previa backend 2026-09-21: reintento sin duplicado, fósiles revertidos. |
| IAM-D-003 Invitación expirada | PASS | Evidencia previa: expiración inline rechazada sin depender del cron. |
| IAM-D-004 Invitación usada | PASS | Evidencia previa: aceptación y re-aceptación; segundo uso rechazado. |
| IAM-D-005 Invitación revocada | PASS | Evidencia previa: revoke + re-revoke, sin mutación colateral. |
| IAM-D-006 Email existente/misma membresía | PASS | Evidencia previa: invite existente e idempotencia, sin duplicar identidad/vínculo. |
| IAM-D-007 Email existente/otra membresía | PASS | Cubierto por IAM-D-006 + guarda `invitacion_ajena` verificada en vivo (addendum). |
| IAM-D-008 Usuario nuevo (flujo completo vivo) | PENDIENTE EXTERNO IAM-1 | Requiere cuota de correo Supabase (`inviteUserByEmail` real). Único bloqueante real #1. |
| IAM-D-009 Rol no permitido | PASS | Addendum en vivo: `Rol fuera de alcance` + PATH SUPERADMIN roles pendiente en bloqueante #2. |
| IAM-D-010 Sucursal de otro tenant | PASS | Evidencia previa backend + addendum en vivo: `Sucursal ajena al comercio`. |
| IAM-D-011 Atacante sin permisos | PASS | Addendum en vivo: 403 + deny-by-default SELECT verificado. |
| IAM-D-012 Respuestas sin password | PASS | Grep negativo actual en Flutter/Web y EF v9 sin campo secreto; evidencia previa de responses sin secretos. |
| IAM-D-013 Dos roles iguales en dos comercios | DIFERIDO A IAM-2/IAM-3 | Multi-membership/selección. No bloqueante IAM-1. |
| IAM-D-014 Dos roles distintos en dos comercios | DIFERIDO A IAM-2/IAM-3 | Multi-membership/selección. No bloqueante IAM-1. |
| IAM-D-015 Cambio repetido de comercio | DIFERIDO A IAM-2/IAM-3 | Selector/cambio. No bloqueante IAM-1. |
| IAM-D-016 Revocación del comercio seleccionado | DIFERIDO A IAM-2/IAM-3 | Selección/revocación. No bloqueante IAM-1. |
| IAM-D-017 Reinicio de aplicación | DIFERIDO A IAM-2/IAM-3 | Persistencia de contexto. No bloqueante IAM-1. |
| IAM-D-018 Revocación unilateral A/B | DIFERIDO A IAM-2/IAM-3 | Lifecycle multi-membresía. No bloqueante IAM-1. |
| IAM-D-019 Recovery de cuenta privilegiada | DIFERIDO A IAM-5 | Recovery privilegiado. No bloqueante IAM-1. |
| IAM-D-020 `fn_editar_usuario` | DIFERIDO (cobertura futura lifecycle) | Regresión de lifecycle/membresías. No requisito IAM-1. |
| IAM-D-021 `fn_gestionar_vinculo` | DIFERIDO (cobertura futura lifecycle) | Regresión de lifecycle/membresías. No requisito IAM-1. |
| PATH SUPERADMIN vivo (roles 2/3/4, idempotencia, negativos, cero secretos) | PENDIENTE EXTERNO IAM-1 | Requiere sesión SuperAdmin (interactiva del propietario o cuenta QA temporal revocable; jamás pedir/almacenar su contraseña). Único bloqueante real #2. |
| REG-D-001 Pedidos y reservas | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-002 Pagos y comprobantes | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-003 Inventario y variantes | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-004 Créditos | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-005 Logística | PASS | Evidencia previa de regresión v9.x, 5/5, con aserción de cero secretos y limpieza. |
| REG-D-006 Sesión sobre módulos operativos | DIFERIDO (regresión transversal) | No bloqueante del contrato de invitaciones IAM-1. |

## Veredicto IAM-1

**IMPLEMENTACIÓN COMPLETA / APROBADA CON CERTIFICACIÓN E2E PENDIENTE DE 2 CASOS EXTERNOS.**

Resumen: PASS IAM-1 = IAM-D-001/002/003/004/005/006/007/009/010/011/012 + REG-D-001–005 · PENDIENTE EXTERNO = IAM-D-008 (usuario nuevo vivo) + PATH SUPERADMIN vivo · DIFERIDO = IAM-D-013–018 (IAM-2/3), IAM-D-019 (IAM-5), IAM-D-020/021 + REG-D-006 (cobertura futura/transversal).

Tras esos 2 E2E, IAM-1 pasa a CERTIFICADO/CERRADO sin otra revisión arquitectónica.

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
