# MIG-PY-01 — Retiro progresivo de n8n y migración a Python/VPS

**Estado:** DECISIÓN VINCULANTE / MIGRACIÓN NO INICIADA  
**Fecha de registro:** 2026-09-23  
**Ámbito de este documento:** registrar la decisión, el alcance de la deuda y sus gates. No define ni implementa la arquitectura Python.

## Decisión

RSUELVO abandona n8n Cloud y retirará n8n como componente operativo. Los workflows actuales quedan como **LEGACY SOURCE** para inventariar y reconstruir reglas, SQL, APIs, dependencias y comportamiento. La arquitectura objetivo mantiene Supabase como servicio administrado y migra los workflows a un backend Python desplegado en VPS:

`Flutter/Web → Supabase + Backend Python/VPS`

No se debe diseñar una funcionalidad nueva para n8n, crear nuevos workflows productivos, reactivar/pagar n8n Cloud para certificar A6, ni invertir en hardening n8n salvo necesidad transitoria indispensable para una migración autorizada.

Esta decisión no equivale a una declaración de que todos los workflows ya estén retirados. Su uso remanente es fuente de comportamiento mientras se migra según un proceso independiente.

## MIG-PY-01 — deuda de migración

La migración deberá inventariar y cubrir, por workflow/dominio:

- workflows, triggers y agrupación funcional;
- dependencias entre workflows/subworkflows;
- SQL PostgreSQL directo, RPCs y contratos de Supabase;
- WhatsApp/Meta y demás APIs externas;
- webhooks y scheduling;
- inputs, outputs y paridad observable;
- transacciones, retries, idempotencia, errores y concurrencia;
- side effects y orden de operaciones;
- observabilidad y logging;
- gestión de secrets;
- deployment, process manager, reverse proxy y HTTPS;
- backups, health checks y monitoring;
- pruebas de integración y regresión;
- rollback por dominio y retiro controlado de cada workflow legacy.

La traducción no será nodo-a-nodo sin arquitectura. La definición de arquitectura Python objetivo y el plan de ejecución pertenecen al hilo/proceso independiente de migración y quedan fuera del cierre IAM/Onboarding.

## Gate IAM10-A6-PYTHON

**Estado: PENDIENTE / GATE PRE-GO-LIVE DEL BACKEND PYTHON.** No forma parte de la tarea actual y no fue ejecutado ni diseñado aquí.

Después de completar la migración, antes de habilitar el go-live, deberá certificarse la frontera Python/VPS → Supabase/PostgreSQL: conectividad con identidad técnica aprobada; comportamiento IAM-5 y guards; compatibilidad con RPCs permitidos; emisión correcta de SecurityEvents; ausencia de acceso indebido a `rsuelvo_private`; gestión segura de secrets; idempotencia y regresión server-to-server. Debe ejecutarse contra un entorno seguro y comprobar la paridad funcional de los workflows migrados con evidencia de input/output, retries, errores, transacciones, concurrencia y side effects.

La lista anterior establece el gate, no un diseño de arquitectura ni una implementación de pruebas.

## Reclasificación A6-n8n

**A6-n8n = SUPERSEDED / NO PASS / NO APLICA A LA ARQUITECTURA OBJETIVO.** El smoke aislado `QA-IAM10-DIRECT-PG-SMOKE` (workflow `6XoIAD3JIOt1KlaN`) se preparó con Manual Trigger y una consulta SELECT, pero n8n Cloud rechazó el intento al terminar el trial. No se creó execution ID, el SQL no se ejecutó y no hubo side effects. No se reintentará, no se pagará/reactivará n8n Cloud y el artefacto permanece inactivo/obsoleto sin evidencia PASS.

Esta reclasificación retira A6-n8n como blocker de cierre IAM-10. No modifica los estados A1–A5 ni convierte la prueba no ejecutada en PASS.

## Control de cambios

- Los workflows existentes se consultan como material legacy de inventario y paridad.
- No alterar workflows comerciales como parte de IAM/Onboarding.
- La migración Python/VPS es una deuda independiente y requiere su propio alcance, contrato, revisión y QA.
- IAM10-A6-PYTHON es un gate de go-live: debe permanecer visible hasta que exista evidencia LIVE de la arquitectura objetivo.
