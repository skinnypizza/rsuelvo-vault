# Reporte QA IAM-9

**Fecha:** 2026-09-22 · **Resultado:** IMPLEMENTACIÓN COMPLETA / APROBADA / CERRADA (con deudas documentadas).

---

## 1. Contrato canónico
`01-Arquitectura/D-IAM-VERIFICACION.md` rev3 determinista (`f8d355d`).

- V0: `PENDIENTE_VERIFICACION`
- V1: `ACTIVO` = **PERFIL COMERCIAL DECLARATIVO COMPLETO** (no "empresa verificada")
- NIT sintáctico: `^[0-9]{5,20}$`, modo `syntactic_only`, repetible
- 3 documentos v1 obligatorios: TERMINOS, PRIVACIDAD, TRATAMIENTO_DATOS
- `content_sha256` hex-64 + `obligatorio=true` en v1
- Inmutabilidad: trigger impide editar campos si hay aceptaciones
- `fn_es_owner` + AAL2 como guard backend
- Transiciones cerradas: V0→V1→(revocación→V0)

## 2. Backend (migraciones IAM-9: 96–100 sobre baseline IAM-1..8)

| Migración | Propósito |
|---|---|
| 96 | Evidencia IAM-9, checks V1, lectura/solicitud/revocación y guards owner+AAL2/SuperAdmin |
| 97 | QR privado de setup y ajustes de autorización/transición |
| 98 | Ajustes de autorización y flujo de habilitación |
| 99 | Retiro del flujo de publicación anterior y entrega QR state-driven |
| 100 | Solicitud owner+AAL2 transaccional V0→ACTIVO, bucket canónico privado y retiro de finalize/EF |

**Atribución:** IAM-9 backend = migraciones 96–100 sobre baseline IAM-1..8. Las migraciones 92–95 son baseline/dependencias anteriores, no migraciones IAM-9.

### 2.1 Checks V1 exactos (fuente→condición→modo)
| Check | Fuente | Condición | Modo |
|---|---|---|---|
| nit | `tbl_comercios.nit` | presente + `^[0-9]{5,20}$` | syntactic_only |
| razon_social | campo | no vacío ≤200 | — |
| telefono | `tbl_comercios.telefono` | `^[0-9+\s]{7,20}$` | present_unverified |
| email_owner | `auth.users.email_confirmed_at` del owner | confirmado | auth_confirmed |
| sucursal | `tbl_sucursales` | ≥1 activa + dirección no vacía | — |
| qr | `storage.objects` bucket `qr-pagos-setup`, path `<id_comercio>/...` | existe | — |
| config | `tbl_comercio_config` | fila existe + `tiempo_reserva_minutos` 1..1440 | — |

Modos: `syntactic_only`, `present_unverified`, `auth_confirmed`.

### 2.1 RPCs
- `fn_estado_verificacion_comercio(p_id_comercio)` → checks + faltantes
- `fn_solicitar_habilitacion_v1(p_id_comercio)` → owner+AAL2, lock, `ya_activo`, evidence APROBADA_AUTOMATICA, V0→ACTIVO atómico, 1 AuditLog
- `fn_finalizar_habilitacion_v1` → **DROP** (mig 100)
- `fn_revocar_verificacion_v1` (SuperAdmin, lock, `ya_v0`, motivo obligatorio)

### 2.2 Helpers
- `fn_es_service_role` / `fn_tiene_aal2` → JWT-only
- `fn_tiene_acceso_comercio` / `fn_es_admin_comercio` / `fn_tiene_rol` / `fn_es_owner` / `fn_comercio_habilitado` → JWT-only
- `fn_es_superadmin` / `fn_es_service_role` → JWT-only

### 2.3 Tablas nuevas
- `tbl_verificaciones_comercio` (append-only; campos: id, comercio, nivel='V1', estado, origen, verificador, checks_snapshot, motivo, timestamps y revocación). No contiene unicidad `usuario+doc`; esa semántica pertenece a aceptación legal IAM-7.
- `tbl_auto_alta_requests` (idempotencia por request_id, rate-limit 1/24h)
- Trigger `trg_doc_inmutable` (inmutable si aceptaciones > 0)
- Trigger `trg_uc_auto_owner` (auto-owner en primera membresía TENANT_ADMIN)

## 2.4 E2E IAM-9 — 37 puntos y clasificación

Clasificación de cierre: **25 LIVE + 10 CÓDIGO + 2 PENDIENTE EXTERNO = 37**. No se cuenta ninguna prueba unitaria como LIVE. El reporte fuente de cierre no conservó la descripción individual de los puntos 13–27; por eso no se atribuyen resultados caso por caso que no tengan evidencia documentada aquí. Los grupos verificables del expediente son:

| Grupo | Cantidad | Clasificación | Evidencia resumida |
|---|---:|---|---|
| Checks V1, guards, autorización, transición, evidencia, QR privado/entrega y restore | 25 | LIVE | E2E backend documentado en bitácora; incluye casos de migraciones 96–100 y restore. |
| Casos cubiertos por implementación/tests y verificaciones estáticas sin ejecución LIVE | 10 | CÓDIGO | No son pruebas LIVE. El expediente no conserva desglose individual de los 10 casos. |
| Certificación SuperAdmin: revocación LIVE y denegación a no-owner/cajero con AAL2 LIVE | 2 | PENDIENTE EXTERNO | No consta ejecución real; no se declaran aprobados. |

**Regresión IAM-7 (fuera de los 37 puntos IAM-9):** aceptación de documentos obligatorios, retry/idempotencia, versionado/obsolescencia, documentos opcionales y estados de acceso/recovery. Su reporte fuente es [Reporte-IAM7.md](Reporte-IAM7.md). Esas pruebas no son núcleo E2E de IAM-9.

### 2.1 Deuda IAM-9
| ID | Descripción |
|---|---|
| IAM9-D1 | 2 objetos huérfanos QA en `qr-pagos` público (borrado bloqueado por API) |
| IAM9-D2 | bucket legacy `qr-pagos` público accesible fuera de `qr-entrega` para objetos históricos |

**Certificación SuperAdmin pendiente:** revocar live + no-owner/cashier AAL2 live.

## 3. Flutter (`b3ebaa9`, 375/375, analyze 0)

### 3.1 Flujo
- V0 checklist: NIT, razón, teléfono, correo, sucursal, QR (sube a `qr-pagos-setup/<id>/...`), config
- Botón **Habilitar comercio** solo owner → MFA AAL2 → `fn_solicitar_habilitacion_v1` → `recargarPerfil()` → dashboard
- `legalAcceptanceRequired` / `legalStatusUnavailable` / `mfaVerificationUnavailable` gates en router
- `qr-entrega` signed URL bajo demanda, NO persiste URL firmada
- V0: `qr-pagos-setup/<id>/...` (privado), JAMÁS `qr-pagos`
- V1: entrega por `qr-entrega` (signed URL temporal), NO persistir URL
- `mfaEnrollmentRequired` → `/mfa-setup`; `mfaChallengeRequired` → `/mfa-challenge`; `mfaVerificationUnavailable` → `/mfa-unavailable`
- `legalAcceptanceRequired` → `/legal`; `legalStatusUnavailable` → `/legal-unavailable`
- Selector IAM-3 intacto: nunca `selected.first` silencioso
- `mfaEnrollmentRequired` + `mfaChallengeRequired` + `legalAcceptanceRequired` → gates en orden correcto

### 3.1 Tests Flutter (375/375, analyze 0)
- 7 tests IAM-9 (`mfa_policy_test.dart`) + 23 tests específicos (`verification_screens_test.dart`, etc.)
- Cobertura: owner/no-owner, AAL1/2, obsoleta, retry, V0/V1, opcional no bloquea, selector no loop, gateway fail-closed, recovery/MFA accesible, lenguaje honesto (grep 0 prohibidos)

### 3.2 Flutter archivos nuevos/principales
- `lib/features/onboarding/onboarding_screens.dart` (checklist V0)
- `lib/features/onboarding/commerce_phase.dart` (state machine)
- `lib/features/legal/legal_screens.dart` (aceptación IAM-7)
- `lib/features/auth/mfa_screens.dart` (enroll/challenge)
- `lib/features/auth/auth_controller.dart` (MFA + phase)
- `lib/features/onboarding/commerce_phase.dart` (`v0AllowsPath`)
- `lib/core/router.dart` (gate centralizado, `securityExemptRoutes`)
- `lib/features/qr_comercio/qr_comercio_repository.dart` (staging bucket)
- `lib/core/capabilities.dart` (catálogo + `can()`)

## 4. Web (`2c4eb51`, build OK, 95 unit + 9 browser; deploy 200)

### 4.1 Alcance
**IAM-9 onboarding tenant = N/A** (D-IAM-WEB-SCOPE: `/app` = backoffice global staff; onboarding tenant solo-Flutter)

### 4.1 Implementado (read-only SuperAdmin)
- `app/src/auth/mfa.ts` — helpers `fn_estado_verificacion_comercio`, `fn_solicitar_habilitacion_v1`, `fn_estado_verificacion_comercio`
- `app/src/App.tsx` — `StaffGate` + `legalStatus` gate (`loading` → `unavailable` → `needSelector` → `legalAcceptanceRequired`)
- `app/src/features/MfaSetupPage.tsx` / `MfaChallengePage.tsx` — enroll/verify TOTP
- `app/src/features/LegalAcceptancePage.tsx` — aceptar Términos/Privacidad/Tratamiento
- `app/src/auth/AuthContext.tsx` — `legalStatus`, `mfaStatus`, `refreshMfa`
- `app/src/features/CommercesPage.tsx` — read-only checks
- `app/src/auth/permissions.ts` — `mfaStatusFor`, `privilegedRequiresMfa`
- `app/src/auth/permissions.test.ts` — 4 tests nuevos
- `app/src/auth/mfa.test.ts` — 4 tests
- `qr-entrega` → signed URL bucket privado; no persiste URL

### 4.1 Pruebas
- 95 unit tests; 9 browser tests.
- Build OK; deploy HTTP 200.

## 5. Regresión IAM-7 (fuera del E2E IAM-9)

Las pruebas de aceptación de documentos, idempotencia (`ya_aceptado`), versionado/obsolescencia, opcionales y gates legales corresponden a IAM-7. Se conservan como regresión y su evidencia está en [Reporte-IAM7.md](Reporte-IAM7.md); no se incluyen entre los 37 puntos E2E IAM-9.

### 5.1 Deuda pendiente (preexistente)
| ID | Descripción |
|---|---|
| IAM9-D1 | 2 objetos huérfanos QA en `qr-pagos` público (borrado bloqueado API) |
| IAM9-D2 | bucket legacy `qr-pagos` público accesible fuera de `qr-entrega` para objetos históricos |

**Certificación SuperAdmin pendiente** (revocar live + no-owner/cashier AAL2 live) → `PENDIENTE EXTERNO`

## 6. Restore (post-E2E)
- 0 comercios V0 residuales
- cajero 1 vínculo FER
- e2eF Auth fósil sin perfil (sin JWT, inofensivo) → **deuda IAM8-D1 separada**
- `guards_sanos` verde

## 6. Veredicto final

### Estado por componente
| Componente | Estado |
|---|---|
| Backend (mig 96–100 sobre baseline IAM-1..8) | ✅ APROBADO |
| Flutter | ✅ APROBADO |
| Web | ✅ APROBADO |
| E2E IAM-9 | ✅ (37 puntos: 25 LIVE / 10 CÓDIGO / 2 PENDIENTE EXTERNO) |
| Docs / Prompts | ✅ |

### Deudas pendientes (preexistentes, no bloqueantes)
- **IAM9-D1**: 2 objetos QA huérfanos en `qr-pagos` público (borrado bloqueado por API)
- **IAM9-D2**: bucket legacy `qr-pagos` público accesible fuera de `qr-entrega` para objetos históricos
- **Certificación SuperAdmin** pendiente (revocar live + no-owner/cashier AAL2 live)

### Restore
- Cero residuos nuevos del E2E
- Deudas preexistentes (IAM9-D1, D2) no cuentan como restore nuevo
- `guards_sanos` verde

---

## Veredicto final

**IAM-9 = IMPLEMENTACIÓN COMPLETA / APROBADA / CERRADA**

> **Certificación SuperAdmin revocar live + no-owner/cashier AAL2 live:** pendiente (`PENDIENTE EXTERNO`). No bloquea cierre IAM-9.

> **Deudas preexistentes IAM9-D1, IAM9-D2** documentadas, no bloquean cierre.

> **Restore:** funcional completo; deudas preexistentes (IAM9-D1/D2) separadas de E2E.

---

> **IAM-9 = IMPLEMENTACIÓN COMPLETA / APROBADA / CERRADA** ✅

---

**IAM-10 — Security Events:** no iniciado. Requiere auditoría y propuesta de contrato antes de implementación.

---

*Generado: 2026-09-22 · Vault: `c89cf1e` (IAM-8 cerrado) / `f8d355d` (IAM-9 rev2) / `e78a3b4` (prompts) / `6e46cd4` (E2E IAM-7) / `b1c5249` (IAM-7 E2E) / `5fe07bf` / `2c4eb51` (Flutter/Web IAM-9).*