# Cierre global — Onboarding e IAM RSUELVO

**Fecha:** 2026-09-23  
**Resultado:** **ONBOARDING / IAM = CERRADO HASTA MIGRACIÓN PYTHON**  
**IAM-10 BACKEND:** **CERRADO CON CERTIFICACIONES DIFERIDAS DOCUMENTADAS**

Este cierre congela el alcance IAM/Onboarding ejecutado hasta IAM-10. Los estados de certificación pendientes se conservan explícitamente y no se convierten en PASS. La arquitectura futura de backend Python/VPS y su migración se gestionan en un proceso independiente; aquí solo se registra `MIG-PY-01` y el gate `IAM10-A6-PYTHON`.

## Estado canónico

| Fase | Estado | Alcance/certificaciones que permanecen |
|---|---|---|
| IAM-0 | CERRADO | Auditoría inicial multi-repo y hallazgos registrados. |
| IAM-1 | CERRADO | Invitaciones seguras; quedan compensación Auth invite→DB, unicidad de invitaciones pendientes expiradas y E2E de usuario nuevo/SuperAdmin documentados. |
| IAM-2 | CERRADO | Lifecycle de membership; queda deuda histórica de concurrencia Cashier N-4 si sigue aplicando al flujo. |
| IAM-3 | CERRADO | Multi-comercio y selección scoped; conserva dependencias/certificaciones externas documentadas. |
| IAM-4 | CERRADO | Ownership/transferencias; quedan certificaciones externas SuperAdmin y concurrencia donde consten en QA. |
| IAM-5 | CERRADO CON CERTIFICACIONES/DEUDAS DOCUMENTADAS | Sin reabrir helpers. A2/A3/A4 externos; guard estructural pendiente de mejora futura; fallback direct-PG permanece solo durante la transición desde n8n a Python. |
| IAM-6 | CERRADO | RBAC/capabilities backend; la matriz REV3.2 de IAM10-B1 usa estos códigos/capabilities. |
| IAM-7 | CERRADO | Consentimiento legal queda separado de SecurityEvents; validación jurídica de documentos borrador se conserva como pendiente preproducción. |
| IAM-8 | CERRADO | Self onboarding; quedan deudas de rate-limit/IP/privacy, `tbl_registro_intentos`, atomicidad/race, trusted proxy y una identidad QA fósil. |
| IAM-9 | CERRADO CANÓNICAMENTE | V0→V1 declarativo; deudas IAM9-D1/D2, URLs firmadas residuales, grandfathering ACTIVO y certificación externa SuperAdmin se mantienen. |
| IAM-10 | BACKEND CERRADO CON CERTIFICACIONES DIFERIDAS DOCUMENTADAS | Event store V1 y ocho producers aprobados, migraciones 101/102. IAM10-B1 cerrado. A2/A3/A4, E2E integral IAM-1..9 y restore quedan externos. A6-n8n superseded; `IAM10-A6-PYTHON` gate pre-go-live. |

## SHAs canónicos

| Entregable | SHA / referencia |
|---|---|
| IAM-9 contrato | `f8d355d31caea11b95e0bfea84a154a8c88a8689` |
| IAM-9 backend (migraciones 96–100) | `8cf0206891a79d692356b780ced4248f601e9c2f` |
| IAM-9 Flutter | `b3ebaa95c8e4c950a98637835094bea573c0b2bf` |
| IAM-9 Web | `2c4eb51bf440072dafc276488156559ddb975e1a` |
| IAM-9 prompts | `e78a3b40f80d0ef3c963aa5bd0f5f3221ef89f48` |
| Cierre documental IAM-9 | `728d06f3576de6aaaba76559143a9e47523b0ab1` |
| IAM-10 contrato | REV3.2 vigente en [D-IAM-SECURITY-EVENTS.md](../01-Arquitectura/D-IAM-SECURITY-EVENTS.md) |
| IAM-10 backend base (migración 101) | `4d5d86199e8f3c9e2ac7a7bf8c879c2c8453794e` |
| IAM10-B1 / migración 102 / alineación REV3.2 | `87f079777481e65e411736287e35bfd7c8d79af6` |
| IAM-10 QA backend | [Reporte-IAM10-Backend.md](Reporte-IAM10-Backend.md) |

IAM-9 continúa siendo 37 puntos: **25 LIVE / 10 CÓDIGO / 2 PENDIENTE EXTERNO**, con regresión IAM-7 separada. Flutter IAM-9: 375/375 tests, analyze 0. Web IAM-9: 95 unit, 9 browser, build OK, deploy HTTP 200.

## IAM-10: evidencia y límites

**LIVE:** migraciones 101 y 102 aplicadas; schema privado no expuesto; acceso directo de roles API revocado; `fn_verificar_guards_sanos()` green; cron purge/watchdog activos y exitosos en las últimas observaciones. A1 anon/PostgREST = LIVE PASS. A5 direct-PG en contexto confiable = LIVE PASS (`DIRECT_PG_TRUSTED_CONTEXT`).

**CÓDIGO:** pruebas QA locales documentadas de catálogo/metadata, transiciones, ownership, membership (incluido `CAMBIAR` MIXED), retry/concurrencia, rollback, lectura, purge y watchdog. IAM10-B1 fue revisado independientemente y está cerrado. Estos resultados no se describen como ejecuciones LIVE.

| Certificación | Estado final |
|---|---|
| IAM10-H1 A1 anon/PostgREST | LIVE PASS |
| IAM10-H1 A2 authenticated AAL1 | PENDIENTE EXTERNO |
| IAM10-H1 A3 authenticated AAL2 | PENDIENTE EXTERNO |
| IAM10-H1 A4 service_role HTTP | PENDIENTE EXTERNO |
| IAM10-H1 A5 direct-PG | LIVE PASS · `DIRECT_PG_TRUSTED_CONTEXT` |
| A6-n8n direct-PG | SUPERSEDED / NO PASS / NO APLICA AL TARGET |
| IAM10-A6-PYTHON | PENDIENTE / GATE PRE-GO-LIVE |
| Regresión E2E integral IAM-1..9 con identidades QA | PENDIENTE EXTERNO |
| Restore integral IAM-10 / entorno representativo | PENDIENTE EXTERNO |

### A6-n8n: evidencia histórica

`QA-IAM10-DIRECT-PG-SMOKE`, workflow `6XoIAD3JIOt1KlaN`, fue preparado e inspeccionado como Manual Trigger → PostgreSQL read-only. n8n Cloud rechazó el intento porque terminó el trial: `executionId` nulo, cero ejecuciones y SQL nunca ejecutado. No hubo side effects. El artefacto está inactivo y obsoleto; **no tiene evidencia PASS y no se debe reintentar ni pagar/reactivar n8n**. La decisión de retirar n8n de la arquitectura objetivo supersede el gate A6-n8n.

### IAM10-A6-PYTHON

Gate obligatorio antes del go-live del backend Python/VPS, ejecutado después de completar la migración. Debe comprobar conectividad server-to-server con identidad técnica aprobada; IAM-5/guards; RPCs permitidas; emisión de SecurityEvents; falta de acceso directo indebido a `rsuelvo_private`; gestión segura de secrets; idempotencia y regresión server-to-server/paridad funcional. No se diseñó ni ejecutó aquí.

## Deudas que sobreviven al cierre

- **IAM-1:** compensación Auth invite→DB; uniqueness de invitaciones `PENDIENTE` expiradas; flujo de usuario nuevo y PATH SuperAdmin LIVE pendientes por dependencias de Auth/sesión.
- **IAM-2:** concurrencia histórica de Cashier N-4 si aplica.
- **IAM-4:** certificación SuperAdmin y concurrencia de transferencia donde sigan pendientes en el reporte fuente.
- **IAM-5:** A2/A3/A4; mejora estructural futura de `fn_verificar_guards_sanos()`; conservar el contexto direct-PG aprobado hasta sustituir sus consumidores por Python.
- **IAM-7:** revisión jurídica de los tres documentos legales borrador.
- **IAM-8:** rate limiting/IP/privacy; retención y purga de `tbl_registro_intentos`; atomicidad/race; trusted proxy; limpieza segura del Auth fósil `e2eF`.
- **IAM-9:** IAM9-D1 (dos objetos QA huérfanos en bucket legacy `qr-pagos`); IAM9-D2 (bucket legacy público para objetos históricos); signed URLs residuales; grandfathering de comercios `ACTIVO`; certificación SuperAdmin donde siga pendiente.
- **IAM-10:** feed del proveedor Auth no integrado y `auth.audit_log_entries` sin observabilidad confirmada; A2/A3/A4; E2E IAM-1..9; restore; `IAM10-A6-PYTHON`; revisar política de retención/AuditLog si cambia infraestructura.
- **MIG-PY-01:** inventario y migración progresiva de workflows n8n a Python/VPS, con dependencias, paridad, operaciones y rollback. Se detalla solo su deuda en [MIG-PY-01](../01-Arquitectura/MIG-PY-01-N8N-A-PYTHON-VPS.md); la ejecución se realiza fuera de este hilo.

Las certificaciones externas pendientes no se convierten en PASS y no bloquean el cierre de implementación IAM aprobado, salvo los gates pre-go-live expresamente establecidos.

## Regla de reapertura

Reabrir IAM/Onboarding solo si: la migración Python descubre incompatibilidad IAM; falla `IAM10-A6-PYTHON`; A2/A3/A4 muestran bypass; falla una regresión funcional IAM-1..10; aparece vulnerabilidad P0/P1; cambia roles, membership u ownership; cambia onboarding/V0/V1; o cambia Auth/Supabase. Los cambios ordinarios de frontend o negocio que no alteren IAM no reabren estas fases.

## Alcance excluido de este cierre

No se implementó Python ni se diseñó su arquitectura. No se reactivó n8n Cloud ni se modificaron workflows productivos. No se modificaron Flutter, Web, migraciones 101/102 ni guards IAM-5. No se ejecutó restore productivo.
