# D-IAM-OWNER — Decisión ownership + operaciones críticas (rev2, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REV2 con ajustes ChatGPT (requiere aprobación antes de código).

## Auditoría real (2026-09-22)

- **No existe owner en BD:** `tbl_comercios` sin columna propietario; owner = quien tenga `ROLE_TENANT_ADMIN`, sin límite (múltiples admins posibles, sin primacía).
- **Vías críticas hoy:** `fn_gestionar_vinculo` y `fn_cambiar_estado_comercio` superadmin-only; EF PATH A (admin) solo invita 5/6; PATH B (super) 2/3/4. Tenant-admin NO puede crear otros admins ni cerrar comercios (bueno, pero tampoco hay transferencia ni baja propia).
- **Sin reauth/step-up/MFA** en ningún flujo (solo sesión Supabase); sin `SecurityEvent` (solo AuditLog negocio); exportación masiva = CSV web (`ReportsPage`) + reportes Flutter, con N-6 pendiente (IAM-6).
- **Sin transferencia de propiedad** (no hay qué transferir formalmente).

## Decisión rev2: owner explícito + invariantes (Opción A)

- Mig aditiva: `tbl_comercios.propietario_id → tbl_usuarios` (nullable).
- **Backfill sin inferencia:** exactamente 1 admin ACTIVE → owner automático; 0 o >1 → NULL + excepción (preflight/reporte de ambiguos; adjudicación explícita SuperAdmin). Jamás antigüedad.
- **Invariante owner+membership** (helper canónico `fn_es_owner(p_id_comercio)` desde `auth.uid()`, jamás id de cliente): owner del mismo comercio + membership TENANT_ADMIN + no REVOKED; operación owner exige ACTIVE; prohibido revocar/suspender/degradar la membership del owner sin transferencia/resolución previa.
- **Transferencia con lifecycle propio** `tbl_transferencias_propiedad` (id, comercio, origen, destino, estado PENDIENTE/ACEPTADA/RECHAZADA/CANCELADA/VENCIDA, expira_at, accepted_at, initiated_by): owner ACTIVE inicia hacia admin válido mismo comercio → PENDIENTE (única por comercio) → destinatario acepta/rechaza con `FOR UPDATE` + revalidación total → cambio `propietario_id` atómico + ACEPTADA + AuditLog. Sin tokens propios. CANCELAR por origen/SuperAdmin.
- **CIERRE vs SUSPENSIÓN:** CERRAR voluntario = owner ACTIVE + confirmación + auditoría (no borra datos/memberships; define estado resultante y bloqueos); SUSPENDER/BLOQUEAR = SuperAdmin (puede forzar cierre excepcional).
- **Admins:** crear/promover admin sigue SuperAdmin; owner puede pedir/ejecutar baja de otro admin solo si backend lo permite y sin tocar su propia membership; no-owner jamás degrada al owner; SuperAdmin conserva autoridad. Sin permission engine.
- **Reauth:** IAM-4 = sesión + confirmación explícita + auditoría + ownership backend. Reauth fuerte/MFA = IAM-5 (documentar mecanismo Supabase antes de usarlo).
- **Export:** IAM-4 solo la identifica como sensible (+AuditLog opcional sin cambiar permisos). Policy completa = IAM-6.

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
