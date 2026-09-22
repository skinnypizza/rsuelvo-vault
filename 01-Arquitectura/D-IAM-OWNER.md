# D-IAM-OWNER — Decisión ownership + operaciones críticas (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT.

## Auditoría real (2026-09-22)

- **No existe owner en BD:** `tbl_comercios` sin columna propietario; owner = quien tenga `ROLE_TENANT_ADMIN`, sin límite (múltiples admins posibles, sin primacía).
- **Vías críticas hoy:** `fn_gestionar_vinculo` y `fn_cambiar_estado_comercio` superadmin-only; EF PATH A (admin) solo invita 5/6; PATH B (super) 2/3/4. Tenant-admin NO puede crear otros admins ni cerrar comercios (bueno, pero tampoco hay transferencia ni baja propia).
- **Sin reauth/step-up/MFA** en ningún flujo (solo sesión Supabase); sin `SecurityEvent` (solo AuditLog negocio); exportación masiva = CSV web (`ReportsPage`) + reportes Flutter, con N-6 pendiente (IAM-6).
- **Sin transferencia de propiedad** (no hay qué transferir formalmente).

## Decisión propuesta: owner explícito (Opción A recomendada)

- Mig aditiva: `tbl_comercios.propietario_id → tbl_usuarios` (seteado en alta: creador/dueño invitado aceptado; backfill: admin activo más antiguo por comercio).
- Solo owner (o superadmin): transferir propiedad (doble confirmación + auditoría + notificación), cerrar comercio, cambiar email/teléfono principal.
- Solo superadmin (ya es así): suspender/bloquear, crear admins.
- Admin no-owner: operar (invitar 5/6, gestión diaria) pero NO: quitar a otro admin, cambiar rol privilegiado, desactivar al owner.
- Opción B descartada en propuesta (antigüedad implícita = ambigua ante empates/reingresos).

## Matriz de operaciones críticas (resumen; detalle en prompts)

| Operación | Hoy | Propuesto |
|---|---|---|
| Agregar admin | superadmin (PATH B/gestionar) | igual + notificar a owner/admins |
| Quitar admin / cambiar rol privilegiado | superadmin | + reauth admin que ejecuta si es tenant + AuditLog + notificación |
| Desactivar owner | posible vía editar (superadmin) | prohibido si es último owner; transferencia primero |
| Email/teléfono comercio | sin control dedicado | owner + confirmación |
| Transferencia propiedad | imposible | owner→otro admin, doble confirmación, auditoría |
| Exportación masiva | CSV sin control extra | capability + auditoría (coordina N-6/IAM-6) |
| Cierre/suspensión | superadmin | igual + confirmación explícita + notificación |
| Reauth/MFA/step-up | inexistente | reauth para críticas tenant; MFA privilegiados en IAM-5 |

## Fuera
MFA/SecurityEvent completos (IAM-5/IAM-10); permission engine (IAM-6); KYC (IAM-9).
