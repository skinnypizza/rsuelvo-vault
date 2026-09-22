# IAM-7/WEB — Aceptación legal (implementación Codex)

## OBJETIVO
Implementar D-IAM-CONSENTIMIENTO.md rev3 en web contra el backend IAM-7 desplegado (mig 92+93, APROBADO).

## ALCANCE EXACTO
Solo consentimiento en `app/`. Prohibido: backend/schema, KYC, SecurityEvent, tocar `permissions.ts`, selector tenant, MFA/capabilities existentes.

## REPOSITORIO
`skinnypizza/rsuelvo-web`, rama `main` (`app/`).

## CONTRATOS REALES (NO inventar campos)
`fn_documentos_pendientes()` → `{ok:true, documentos:[{id_documento, tipo, version, titulo, url_texto, content_sha256, obligatorio, vigente_desde}]}`; error `{ok:false,codigo:'sin_acceso'}`. Lista filtrada server-side; sin semver local.
`fn_aceptar_documento(p_id_documento, p_canal='WEB')` → `{ok:true,codigo:'aceptado'|'ya_aceptado'}` (ambos éxito); errores `canal_invalido|sin_acceso|documento_no_existe|documento_no_vigente|version_obsoleta`. Ante obsoleta/no-vigente: refrescar, NO reintentar.

## ARCHIVOS A REVISAR
`app/src/auth/AuthContext.tsx` (integrar estado sin romper MFA gates), `app/src/App.tsx` (StaffGate + ruta dedicada), `app/src/data/api.ts` (RPCs), `app/src/auth/permissions.ts` (solo leer/usar, jamás modificar), `01-Arquitectura/D-IAM-CONSENTIMIENTO.md`.

## DEPENDENCIAS
Backend desplegado. No crear agentes persistentes.

## REGLAS CLIENTE OBLIGATORIAS
- `legalAcceptanceRequired` con obligatorios pendientes; recovery SIEMPRE fuera del gate; MFA setup/challenge, flujo legal, ayuda, logout accesibles.
- Aceptación explícita por documento + enlace; anti-doble-submit; refresh tras éxito; liberar solo sin obligatorios; `ya_aceptado` = éxito.
- Nueva versión en sesión → gate + banner; sin gracia; SUPPORT/SYSADMIN/SuperAdmin sujetos igual.
- Futuro `obligatorio=false`: no bloquea; no STOP/marketing; no nueva RPC.
- BORRADOR: indicar `Contenido legal pendiente de validación final`.
- Fail-closed: error técnico (autenticado) → `legalStatusUnavailable`; bloquea operación; retry/logout; recovery intacto.

## CAMBIOS PERMITIDOS
RPCs + estados + pantalla/ruta + banner + tests.

## CAMBIOS PROHIBIDOS
Backend/schema · service_role · KYC · SecurityEvent · modificar permissions.ts · selector tenant · autoaceptar · autoridad local · modificar contrato.

## PRUEBAS REQUERIDAS
`tsc`+build verdes; tests (pendientes, aceptar/`ya_aceptado`, obsoleta refresca, nueva versión, opcional no bloquea, error→unavailable+retry, recovery fuera del gate); cero secretos en responses/UI/logs.

## ENTREGABLES
Commit en `main` + deploy Pages HTTP 200 + SHAs (commit + deploy) + resumen.

## DEFINITION OF DONE
Contrato campo por campo; build/tests verdes; alcance respetado.
