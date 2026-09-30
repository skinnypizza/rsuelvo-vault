# QA Onboarding Flutter por ADB — 2026-09-30

**Decisión explícita del usuario:** retirar MFA obligatorio del login Flutter y de la habilitación V0→V1. Se implementó en Flutter y en `fn_solicitar_habilitacion_v1`, conservando owner, requisitos, atomicidad y auditoría. `fn_tiene_aal2` y otras operaciones sensibles permanecen. Web no cambia su política de login.

**LIVE / producción / Samsung A55:** cuenta QA → login AAL1 → auto-alta V0 → tres aceptaciones legales QA → perfil → dirección sucursal → QR privado → botón Habilitar comercio → ACTIVO/dashboard → persistencia tras reinicio → visualización de QR. Una aprobación y una auditoría; retry `ya_activo`. Anónimo denegado; no-owner `solo_owner`; faltantes no habilitan.

**Registro:** formulario Flutter con email QA existente devuelve respuesta neutral. La cuenta Auth fue preparada como fixture confirmada; entrega y confirmación de correo nuevo siguen **NO PROBADAS**. Este QA no certifica el E2E integral IAM-1..9.

**Código:** suite Flutter completa 379/379, analyze sin problemas, APK debug correcta. Corrección adicional del bucle de rutas de seguridad/staff de SuperAdmin, con cuatro regresiones de router.

**Migración:** `BACKEND RSUELVO/supabase/migrations/20260930153503_optional_mfa_commerce_enablement.sql`, aplicada en producción y staging. Guards sanos en producción. Cuenta/comercio QA de producción `Q9A` conservados; fixture staging eliminada.

Reporte y capturas: [qa-onboarding-adb-2026-09-30.md](/home/nico/StudioProjects/rsuelvo/docs/qa-onboarding-adb-2026-09-30.md). El requisito histórico owner+AAL2 de habilitación queda superseded por esta decisión; el cierre del 23/09 se conserva como evidencia histórica.

**Recuperación de red (ADB):** APK actualizada instalada con sesión original SuperAdmin. Arranque con Wi-Fi/datos desactivados muestra mensaje comprensible y «Reintentar cargar mi cuenta»; al restaurar ambas conexiones y pulsar reintentar vuelve al dashboard de Ivan sin credenciales ni reinicio. La sesión Auth se conserva y los permisos derivados se vuelven a comprobar. Capturas y pruebas de regresión en el reporte enlazado.

**Validación final:** 381/381 pruebas Flutter aprobadas, analyze sin problemas, APK debug compilada e instalada.
