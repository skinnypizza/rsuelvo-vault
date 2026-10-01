# QA Onboarding Flutter por ADB — 2026-09-30

**Decisión explícita del usuario:** retirar MFA obligatorio del login Flutter y de la habilitación V0→V1. Se implementó en Flutter y en `fn_solicitar_habilitacion_v1`, conservando owner, requisitos, atomicidad y auditoría. `fn_tiene_aal2` y otras operaciones sensibles permanecen. Web no cambia su política de login.

**LIVE / producción / Samsung A55:** cuenta QA → login AAL1 → auto-alta V0 → tres aceptaciones legales QA → perfil → dirección sucursal → QR privado → botón Habilitar comercio → ACTIVO/dashboard → persistencia tras reinicio → visualización de QR. Una aprobación y una auditoría; retry `ya_activo`. Anónimo denegado; no-owner `solo_owner`; faltantes no habilitan.

**Registro:** formulario Flutter con email QA existente devuelve respuesta neutral. La cuenta Auth fue preparada como fixture confirmada; entrega y confirmación de correo nuevo siguen **NO PROBADAS**. Este QA no certifica el E2E integral IAM-1..9.

**Código:** suite Flutter completa 379/379, analyze sin problemas, APK debug correcta. Corrección adicional del bucle de rutas de seguridad/staff de SuperAdmin, con cuatro regresiones de router.

**Migración:** `BACKEND RSUELVO/supabase/migrations/20260930153503_optional_mfa_commerce_enablement.sql`, aplicada en producción y staging. Guards sanos en producción. Cuenta/comercio QA de producción `Q9A` conservados; fixture staging eliminada.

Reporte y capturas: [qa-onboarding-adb-2026-09-30.md](/home/nico/StudioProjects/rsuelvo/docs/qa-onboarding-adb-2026-09-30.md). El requisito histórico owner+AAL2 de habilitación queda superseded por esta decisión; el cierre del 23/09 se conserva como evidencia histórica.

**Recuperación de red (ADB):** APK actualizada instalada con sesión original SuperAdmin. Arranque con Wi-Fi/datos desactivados muestra mensaje comprensible y «Reintentar cargar mi cuenta»; al restaurar ambas conexiones y pulsar reintentar vuelve al dashboard de Ivan sin credenciales ni reinicio. La sesión Auth se conserva y los permisos derivados se vuelven a comprobar. Capturas y pruebas de regresión en el reporte enlazado.

**Validación final:** 381/381 pruebas Flutter aprobadas, analyze sin problemas, APK debug compilada e instalada.

## Revisión posterior de step-up MFA — 2026-10-01

La migración de email MFA `20260930212303/email_second_factor` había vuelto a insertar dos checks de step-up en `fn_solicitar_habilitacion_v1`, aunque la decisión de producto y el recorrido QA anterior indicaban habilitación V0→V1 permitida en AAL1. Apliqué la migración forward-only `20261001052304_restore_user_decision_optional_mfa_commerce_enablement` para retirar únicamente esos dos checks. Se conservan owner, checklist comercial, bloqueo de fila, atomicidad, auditoría, grants y `search_path`; los requisitos MFA de otras operaciones y RLS permanecen.

Verificación PROD de solo retorno: la llamada de `authenticated` con claims sintéticos AAL1 de la cuenta QA propietaria sobre el comercio QA ya activo devolvió `ya_activo`, dentro de `BEGIN/ROLLBACK`. El catálogo confirma ambas llamadas MFA ausentes y ACL/search_path intactos. No se insertaron filas ni se activaron efectos externos.
