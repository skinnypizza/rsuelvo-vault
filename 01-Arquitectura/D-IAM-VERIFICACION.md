# D-IAM-VERIFICACION — Contrato IAM-9 (propuesta, SIN implementar)

**Fecha:** 2026-09-22 · **Estado:** PROPUESTA para revisión ChatGPT.

## Auditoría real (2026-09-22)
- Datos disponibles por comercio: NIT, razón social, teléfono, email, sucursales, config, QR en `qr-pagos`, canal WhatsApp. FEE real: teléfono+email, sin NIT/razón. Cero infraestructura de verificación (sin niveles, evidencias, revisores).
- V0 vive en `PENDIENTE_VERIFICACION`; V1 = `ACTIVO` (vía verificación, no solo staff-alta).

## Decisiones
1. **Niveles (dimensión estado, no rol):** V0 `PENDIENTE_VERIFICACION` (email verificado + perfil mínimo) → V1 `ACTIVO` (identidad comercial verificable). Sin V2/V3 documentales en IAM-9 v1 (futuro).
2. **Requisitos V1 (declarativos, sin KYC personal):** NIT válido (formato + dígito/unicidad, sin validación tributaria en línea) + razón social + teléfono operativo + email + ≥1 sucursal con dirección + QR de cobro subido + config completa. Nada de CI, selfie, biometría, domicilio personal, documentos societarios (revisión normativa boliviana antes de pedir más).
3. **Quién verifica:** auto-declaración del owner + verificación mixta: completitud automática (fn) + spot-check SuperAdmin con muestreo; `EN_REVISION` opcional solo si hay cola manual — v1: directo a ACTIVO al cumplir (sin cuello SuperAdmin), con auditoría y reversión (SUSPENDER si fraude).
4. **Evidencia:** snapshot de campos verificados (tabla `tbl_verificaciones_comercio`: comercio, nivel, verificador (sistema/SuperAdmin), detalle jsonb de checks, timestamps) + AuditLog. Nunca documentos personales (no se piden).
5. **Rechazo/reintento/expiración:** `RECHAZADA` con motivo + reintento libre tras corregir; sin expiración de nivel en v1.
6. **Fuera:** V2/V3 KYC, biometría, burós externos, cambios a solicitud-staff, ventas/n8n.

## E2E
V0 incompleto → falta NIT/QR · completo → ACTIVO + evidencia · NIT duplicado/inválido DENY · owner no-owner DENY · reversión a SUSPENDIDO conserva evidencia · regresión IAM-1..8 + suites.
