# Reporte QA IAM-4

**Fecha:** 2026-09-22 · **Estado:** IMPLEMENTACIÓN COMPLETA / APROBADA CON CERTIFICACIÓN EXTERNA PENDIENTE.

## Backend (mig 83/84/85, en vivo con fósiles, limpio)

| Caso | Resultado | Evidencia |
|---|---|---|
| Backfill 1-admin → owner; 0 → NULL; 0 ambiguos | PASS | FER→dueño, FEE→Ethan, ABC→fósil, resto NULL |
| `fn_es_owner` true/false por JWT | PASS | dueño true, cajero false |
| Transferencia ida/vuelta + privilegio inmediato | PASS | ACEPTADA, owner flip en ambas direcciones |
| Doble PENDIENTE | PASS | `transferencia_pendiente` |
| Cancel origen OK / no-owner `sin_permiso` | PASS | matriz completa |
| Expirada no bloquea (sweep → VENCIDA + nueva) | PASS | estados verificados |
| Auto-owner 1 admin / 2 admins → NULL | PASS | en vivo |
| Cierre owner OK / no-owner / repetido | PASS | CANCELADO + `solo_owner` + `sin_cambio` |
| Cero secretos | PASS | asserts en cada response |
| `owner_protegido` (gestionar/editar) | PENDIENTE EXTERNO | requiere sesión SuperAdmin |
| Concurrencia real doble inicio | PENDIENTE EXTERNO | requiere sesión SuperAdmin + simultaneidad |

## Flutter (`1e71b9e`, analyze 0, 307/307)

Ownership visible (badge propietario / transferir / cerrar con confirmación) · transferencias listar/aceptar/rechazar/cancelar/iniciar (destino admin) · errores backend como autoridad · sin reauth/MFA · sin IAM-6.

## Web (build OK, 68 tests, deploy 200)

Cerrar (owner/superadmin, confirm + `solo_owner`) · transferencias propias aceptar/rechazar/cancelar en Perfil · iniciar transferencias documentado como móvil (destino debe ser admin) · sin selector tenant · sin reauth/MFA · sin IAM-6.

## Veredicto
IAM-4 completo salvo certificación externa (superadmin vivo + concurrencia real).
