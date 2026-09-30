# MFA por correo — implementación y QA, 2026-09-30

## Resultado

Segundo paso por correo desde noreply@rsuelvo.com implementado y obligatorio para SUPERADMIN, SYSADMIN y TENANT_ADMIN. Un rol administrativo en cualquiera de las membresías activas obliga al segundo paso, aunque el cliente móvil seleccione otra membresía. TOTP existente sigue disponible. SUPPORT/cajero/repartidor sin membresía administrativa conservan su política anterior.

Correo es step-up propio de RSUELVO: no modifica ni falsifica el claim nativo `aal2`. `fn_tiene_aal2()` conserva su contrato; las operaciones protegidas usan `fn_segundo_factor_verificado()` para admitir TOTP/AAL2 nativo o la verificación de correo ligada a sesión.

## Implementación

- Edge Function `email-mfa`, JWT obligatorio y validación adicional mediante Auth getUser. Destinatario obtenido del usuario validado, nunca del formulario. Requiere correo confirmado y método password en AMR: recovery/magic link solo no reemplazan la contraseña.
- SMTP Zoho/CPaaS: smtp.zeptomail.com:587, STARTTLS obligatorio, usuario emailapikey. Contraseña solo en secret de Edge `RSUELVO_SMTP_PASSWORD`, sin incluirla en los clientes/repositorios.
- Código aleatorio de seis dígitos, hash SHA-256 ligado al session_id, vencimiento 10 minutos, cinco intentos, consumo atómico con bloqueo de fila. Reenvío invalida código anterior. Bloqueo por usuario: 60 segundos entre envíos y tres solicitudes cada 15 minutos, incluyendo diferentes sesiones y envíos fallidos.
- Verificación dura hasta ocho horas en esa sesión; no se transfiere a otras sesiones. Comprueba email actual, sesión existente y `not_after`; FK a auth.sessions elimina la verificación al cerrar/revocar sesión.
- Tabla privada `rsuelvo_private.email_mfa`, RLS activo, sin permisos para anon/authenticated. RPCs reservar/validar solo service_role; clientes solo pueden consultar su estado.
- RLS restrictivo en tablas operativas y Storage. Bootstrap de lectura (perfil, roles, membresías, comercios) conserva los permisos originales. Guard adicional en entradas RPC PL/pgSQL operativas SECURITY DEFINER y lector SQL de catálogo; legal/bootstrap siguen disponibles. Se restaura segundo factor para habilitación V1.
- Flutter y React muestran envío, reenvío, código, errores y alternativa TOTP. Web comprueba estado al recuperar sesión, al enfocar y cada minuto; móvil al restaurar/recargar perfil y renovar token. Rutas MFA conservan la corrección del redirect loop.

Migraciones aplicadas a producción y staging:

- 20260930211527_email_second_factor.sql
- 20260930213620_enforce_email_mfa_rpc_and_storage.sql
- 20260930214149_email_mfa_catalog_guard.sql

Web publicada: https://1ca58134.rsuelvo-web.pages.dev y rsuelvo.com/app/.

## Evidencia real

Cuenta QA ya confirmada del test SMTP: ethannic2+qa20260930smtp@gmail.com, Auth 4ba435a8-d9c8-411a-897a-07bd0d9e9924. Contraseña QA guardada fuera del repositorio con permisos 0600; no se modificó la cuenta original del usuario.

1. Inicio password real de QA y solicitud de código: HTTP 200.
2. Zoho registra entrega de «Tu código de acceso a RSUELVO», desde noreply al alias QA.
3. Código tomado de la vista previa del proveedor para esa cuenta QA, sin reproducirlo en registros. Verificación real HTTP 200; RPC de estado devuelve true.
4. Reutilización del mismo código: HTTP 400.
5. Cerrar todas las sesiones QA: Auth 204. Consultar con el antiguo access token devuelve verificación false. Sesiones temporales cerradas y tokens removidos del archivo QA.
6. Chromium real en producción: cuenta QA sin acceso al panel staff, pantalla de código accesible, alternativa TOTP y respuesta 429 de cuota mostrada en interfaz. Captura `evidence/mail/2026-09-30/email-mfa-production-qa.png`.

La lectura inicial de configuración SMTP desde Management API no devolvía la contraseña SMTP utilizable y causó EAUTH en Edge. Se resolvió copiando la contraseña directamente del agente Zoho a secrets, esperando a que terminara la copia asíncrona. Auth/Supabase mantuvo el SMTP que ya enviaba confirmaciones. No se guardaron claves SMTP/API en archivos del proyecto.

## Pruebas

- SQL transaccional `BACKEND RSUELVO/tests/sql/email_mfa.sql`: sin verificar, sesión ajena, cooldown entre sesiones, cinco errores, código anterior tras reenvío, correcto, replay, vencimiento de código/confianza, cuota por usuario, privilegios de RPC/tabla y borrado con sesión. Pasó en staging y producción, con rollback.
- SQL `tests/sql/email_mfa_access.sql`: fixture de administrador en transacción; RPC y UPDATE bloqueados antes de MFA, bootstrap legible, UPDATE permitido tras MFA. Pasó en producción, con rollback. Staging no tiene los mismos grants de tablas que producción y el caso de bootstrap allí falla por permiso de SELECT preexistente; no se alteraron esos grants para fingir equivalencia.
- Web: 95 tests unitarios, typecheck/build y 20 tests Chromium. Nuevo escenario verifica SuperAdmin sin TOTP: bloqueo, reload, fallo de envío/reintento, código incorrecto, cooldown, código válido y dashboard tras recargar. El transporte de ese escenario es simulado y no acredita login real de SuperAdmin.
- Flutter: análisis sin incidencias y 381 tests completos pasaron en la implementación inicial. Tras ajuste de membresías/renovación: 14 pruebas específicas (MFA/router/recuperación de perfil) pasaron, análisis sin incidencias y APK debug recompilado.
- Advisors: tabla MFA privada sin políticas produce aviso informativo intencional de deny-by-default; permisos revocados. RPCs de consulta autorizadas SECURITY DEFINER producen avisos de revisión por diseño. Avisos previos de pg_net público, fn_sugerir_codigo anon y protección de passwords permanecen fuera de este cambio.

## Pendientes solicitados por el usuario

- Usuario pidió pausar pruebas del teléfono porque debe salir con él. Primera APK con MFA instalada y app abierta; modificaciones finales de membresías/renovación están en APK recompilada y se instalarán antes del E2E a su vuelta. No se continuó usando ADB tras la pausa.
- Login completo real de SuperAdmin en ambos clientes requiere que el usuario inicie su sesión; no se obtuvo su contraseña ni se generó sesión administrativa para saltarse el primer factor. Web tiene QA de navegador y protocolo real descritos arriba.
- Zoho sigue mostrando revisión pendiente. Entrega real comprobada no acredita aprobación de capacidad a escala.
