# D-IAM-VERIFICACION — Contrato IAM-9 (rev2 determinista, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** REV2 (requiere aprobación; backend solo después).

## 1. V1 = PERFIL COMERCIAL DECLARATIVO COMPLETO (no "verificable")
V1 = datos mínimos completos + email confirmado + sucursal declarada + config + QR configurado + declaración del owner. NO es: NIT-SIN, existencia jurídica, representante verificado, KYC, cumplimiento tributario. UI/AuditLog jamás "empresa verificada por RSUELVO". V2/V3 futuro.

## 2. NIT sintáctico
Sin dígito verificador (SIN asigna aleatorio 1-9). Checks: requerido, normalizado, `^[0-9]{5,20}$`, `nit_check="syntactic_only"`. Repetible entre comercios (sin UNIQUE; repetición = señal spot-check, no rechazo).

## 3. Estados separados
COMERCIO: PENDIENTE_VERIFICACION(V0)/ACTIVO(V1)/admin existentes. VERIFICACIÓN (por intento, append-only): PENDIENTE/APROBADA_AUTOMATICA/APROBADA_MANUAL/RECHAZADA/REVOCADA. RECHAZADA vive en verificación; comercio queda V0.

## 4. Reversión
A) Pierde requisito → ACTIVO→V0 con evidencia revocación. B) Fraude → SUSPENDIDO/BLOQUEADO administrativo. Sin suspensión automática por declarativo.

## 5. Checks exactos (fuente|condición|modo)
- nit: `tbl_comercios.nit` | presente+`^[0-9]{5,20}$` | auto, `syntactic_only`
- razon_social: campo | no vacío ≤200 | auto
- telefono: `tbl_comercios.telefono` (comercio; owner va por Auth) | formato `^[0-9+\s]{7,20}$` | auto, etiquetar `present_unverified` (NO "operativo")
- email_owner: `auth.users.email_confirmed_at` del owner | confirmado | auto, `auth_confirmed`
- sucursal: `tbl_sucursales` | ≥1 activa con `direccion` no vacía | auto
- qr: objeto en `qr-pagos/<uuid-comercio>/...` | existe | auto (sin contenido financiero)
- config: `tbl_comercio_config` | fila existe + `tiempo_reserva_minutos` 1..1440 | auto
Snapshot backend con esos nombres exactos.

## 6. RPCs
- `fn_estado_verificacion_comercio(p_id_comercio)` → checks sin mutar (owner/admin mismo comercio o staff).
- `fn_solicitar_habilitacion_v1(p_id_comercio)`: solo owner + AAL2 (V1 es crítica: SÍ exige AAL2) → evalúa → todo PASS: evidencia APROBADA_AUTOMATICA + V0→ACTIVO atómico + AuditLog. Todo server-side (sin user/owner/nivel/resultado/estado/reviewer del cliente). Evaluación sincrónica: cada llamada = un intento resuelto (sin solicitudes abiertas concurrentes por diseño).
- SuperAdmin: RPC administrativa separada (revisar/revocar). Spot-check no bloquea (sin EN_REVISION v1): confirma/observa/revoca-V0/suspende.

## 7. Evidencia append-only
`tbl_verificaciones_comercio(id, comercio, nivel='V1', estado, origen SYSTEM|SUPERADMIN, verificador?, checks_snapshot, motivo?, created_at, resolved_at, revoked_at?, revoked_by?, motivo_revocacion?)`. Sin secretos/personales; owner no edita.

## 8. IAM-7
Sin duplicar validación; V1 es operación normal bajo gates existentes (legales pendientes → cliente no llega).

## 9. E2E rev2
V0 incompleto→faltantes deterministas · NIT inválido DENY · NIT repetido OK · teléfono `present_unverified` · email PASS · sucursal sin dirección FAIL · QR FAIL · config FAIL · todos→ACTIVO · append-only · snapshot backend · owner PASS · no-owner/cashier/sin-AAL2 DENY · retry PASS · concurrencia 1 transición · ACTIVO→V0 por revocación · fraude→SUSPENDIDO separado · regresión IAM-1..8 + ventas/n8n + guards_sanos.
