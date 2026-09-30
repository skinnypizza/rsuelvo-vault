# QA onboarding web — 2026-09-30

**LIVE producción aprobado hasta consulta V1 del mismo QA móvil.** Registro web con correo QA existente neutral; login merchant denegado para staff como corresponde. Onboarding del comerciante sigue en Flutter; backoffice consulta checks en lectura.

El usuario autorizó retirar MFA obligatorio del login web. Publicado en Cloudflare Pages `rsuelvo-web/main`, despliegue `c003e540`. SuperAdmin con sesión real AAL1 → dashboard → Comercios → ficha Q9A ACTIVO/V1 con siete checks completos, RPC HTTP 200 y recarga HTTP 200. No se inscribieron factores ni cambiaron estados de comercios. Backend sensible conserva sus reglas.

Defecto 404 de login/MFA corregido mediante entradas estáticas para las 15 rutas del panel. HTML de landing/registro/privacidad preservado byte por byte frente a producción antes del deploy.

**Validación:** 95 unit / 19 browser aprobadas, build/typecheck correctos. Diez casos nuevos: ocho entradas/recargas sin sesión, dos fichas V0/V1 simuladas con SuperAdmin AAL1 y recuperación ante fallo. Las simulaciones se distinguen de la ficha V1 real de producción.

**Pendiente compartido con Flutter:** entrega, enlace y confirmación de correo nuevo. No hay onboarding merchant editable V0→V1 en web; no se presenta la lectura staff como habilitación web.

[Reporte y capturas](/home/nico/StudioProjects/rsuelvo-web/docs/qa-onboarding-web-2026-09-30.md).
