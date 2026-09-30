# Correo transaccional, onboarding y MFA — 2026-09-30

> **Estado actualizado:** dominio verificado en Zoho Mail y CPaaS; DKIM activo, rebotes configurados y noreply autorizado. Falta validación del cliente Zoho y SMTP/entrega Supabase. Las secciones anteriores documentan la revisión previa.

## Instrucción del usuario

Usar `noreply@rsuelvo.com` como remitente del onboarding. El usuario confirmó que “M2A” se refería a MFA/2FA mediante código recibido por correo. Solicitó investigar uso de Zoho; no se activó un plan ni se reimpuso MFA obligatorio.

## Verificación actual

- DNS MX de rsuelvo.com: mx.zoho.com (10), mx2.zoho.com (20), mx3.zoho.com (50).
- TXT: verificación Zoho y SPF `v=spf1 include:zohomail.com ~all`.
- No se obtuvo un TXT DMARC en `_dmarc.rsuelvo.com` durante la consulta. DKIM no se certificó: falta identificar el selector/configuración del servicio de envío.
- Chromium mantiene Zoho Mail autenticado con `contacto@rsuelvo.com`, ajustes SMTP visibles. No se vio noreply en la vista actual; eso no demuestra que no exista como alias/buzón.
- Zoho Accounts todavía presenta comprobación de identidad. El vault registra un rechazo previo RA102 al generar contraseña de aplicación; no se volvió a generar credencial.
- No se certificó configuración SMTP actual de Supabase ni entrega real. Tener MX/SPF/buzón no demuestra que Auth tenga envío transaccional conectado.
- La EF `registrar-cuenta-comercio` llama `supa.auth.admin.inviteUserByEmail`; la entrega depende del proveedor de Supabase Auth, no de una integración SMTP local en el frontend.

## Compatibilidad y límites

**Zoho Mail:** su política vigente excluye correo automatizado y transaccional, incluyendo OTP/activaciones, y dirige ese uso a ZeptoMail. Fuente oficial: https://www.zoho.com/mail/help/usage-policy.html

**Zoho CPaaS (antes ZeptoMail):** producto transaccional actual de Zoho, compatible con envío SMTP/API. La documentación SMTP actual indica `smtp.zeptomail.com`, 465 SSL/587 TLS, credenciales del agente; confirmar los datos del datacenter/cuenta antes de configurar. Fuentes: https://www.zoho.com/cpaas/ y https://www.zoho.com/cpaas/help/smtp-home.html

**Onboarding:** Supabase Auth admite SMTP externo, incluye ZeptoMail entre proveedores y permite remitente propio. Configurar allí `RSUELVO <noreply@rsuelvo.com>` resolvería envíos de invitación, confirmación y recuperación para web/Flutter. Primero verificar dominio/remitente, credenciales, límites y entrega. Fuente: https://supabase.com/docs/guides/auth/auth-smtp

**MFA por correo:** Zoho CPaaS puede transportar el código, pero no implementa su validación en RSUELVO. Supabase MFA nativo documenta TOTP y teléfono; el OTP de correo es un mecanismo Auth de primer factor y no eleva por sí solo una sesión a AAL2. No sustituir `fn_tiene_aal2` por una comprobación visual. Fuente: https://supabase.com/docs/guides/auth/auth-mfa

Para un segundo paso por email se requiere decisión de arquitectura y backend propio: challenge vinculado a usuario/sesión/operación, código aleatorio almacenado como hash, expiración, uso único, límites de reenvío/intentos y autorización comprobada en servidor. No se implementó ni se presenta como equivalente al MFA nativo.

## Próximos pasos concretos

1. Confirmar cuenta/agente Zoho CPaaS existente o habilitarlo según plan elegido por el usuario; no asumir que Zoho Mail lo incluye.
2. Verificar rsuelvo.com y autorizar remitente noreply en ese servicio; configurar SPF/DKIM y revisar DMARC sin reemplazar el SPF Zoho Mail con un segundo registro SPF.
3. Conectar SMTP a Supabase Auth, revisar sender/site URL/redirects y plantillas.
4. Probar registro nuevo, entrega con remitente real noreply, enlace/confirmación y continuidad Flutter; probar también recuperación desde web.
5. Definir por separado si implementar segundo paso por correo y cómo se relaciona con operaciones backend que exigen AAL2. MFA obligatorio de login permanece retirado por la decisión anterior del usuario.

## Verificación autenticada en Chromium (posterior)

El usuario autorizó usar su sesión del navegador. Se accedió mediante CDP a Chromium ya autenticado, sin copiar contraseñas/cookies ni generar credenciales.

- Zoho Mail Admin: organización `rsuelvo`, plan **Mail Free**, dos usuarios. `contacto@rsuelvo.com` es superadministrador.
- **`noreply@rsuelvo.com` sí existe como usuario/buzón**, con nombre Ethan Cardenas. Esto reemplaza la incertidumbre de la revisión previa de ajustes; no hay que crearlo de nuevo.
- Dashboard: MX 1/1, SPF 1/1, DKIM 0/1. Dominios confirma «Configuración de DKIM pendiente» para rsuelvo.com.
- Zoho Mail → Transactional Emails: describe ZeptoMail para OTP/confirmaciones/recuperación; indica que la integración solo está disponible en planes de pago. No se hizo upgrade.
- `https://cpaas.zoho.com/` reconoce al usuario pero presenta **alta inicial**, con Organization name, términos y Get Started; no muestra organización/agente existente. No se completó esa alta ni aceptaron términos.
- No se modificaron usuarios, factores, contraseñas, DNS, suscripción ni configuración SMTP; no se envió correo. SMTP actual de Supabase sigue sin comprobarse.

El camino concreto es habilitar/verificar el servicio transaccional CPaaS por separado, verificar dominio/remitente, completar autenticación DKIM y conectar Supabase Auth. La limitación del botón integrado de Mail Free no demuestra que sea necesario contratar Zoho Mail para usar CPaaS independiente; son configuraciones/planes distintos que deben verificarse antes de contratar.

Evidencias: `rsuelvo-web/evidence/mail/2026-09-30/noreply-exists.png`, `domain-dkim-pending.png`, `cpaas-not-onboarded.png`.

## Dominio habilitado con Cloudflare — actualización posterior

El usuario autorizó habilitar el dominio con su acceso Cloudflare. Se utilizó la zona existente `rsuelvo.com` de la cuenta que aloja `rsuelvo-web`, sin modificar el destino web. El apex ya estaba asociado a `rsuelvo-web.pages.dev`.

**Resultado: verificación de dominio COMPLETA. Envío transaccional/SMTP aún NO certificado.**

Acciones realizadas:

1. Zoho Mail: creado selector DKIM `rsuelvo202609` con clave RSA de 2048 bits, publicada como TXT `rsuelvo202609._domainkey.rsuelvo.com`. Zoho verificó el selector y DKIM figura activo.
2. Zoho CPaaS: completada alta inicial de organización RSUELVO, identificador `941351485`; agente predeterminado `agent_1` (`c641888da14c8da`). No se compraron créditos ni se eligió un plan de pago.
3. Dominio `rsuelvo.com` agregado a CPaaS (`1c7a829fb42ce`) y asociado a ese agente.
4. Publicado TXT de DKIM transaccional `30134428._domainkey.rsuelvo.com`, con la clave pública generada por CPaaS.
5. Publicado CNAME `bounce-zem.rsuelvo.com` → `cluster89.zeptomail.com`, **DNS only**. CPaaS verifica DKIM y CNAME y marca el dominio **Verificado**.
6. Añadida dirección de remitente permitida `noreply@rsuelvo.com`, asociada a `agent_1`. La restricción de remitentes de CPaaS permite solo las direcciones registradas; no afecta los buzones de Zoho Mail.

Validaciones:

- Consulta a `erin.ns.cloudflare.com`: los tres registros publicados coinciden exactamente con los valores de Zoho (concatenando los fragmentos TXT del DNS).
- Zoho Mail: selector Verificado y `dkim-status-switch` checked=true.
- CPaaS: dominio, DKIM y CNAME Verificados; noreply visible en remitentes.
- MX permanecen mx/mx2/mx3.zoho.com; SPF del dominio permanece `v=spf1 include:zohomail.com ~all`, sin duplicar SPF.
- `https://rsuelvo.com` responde HTTP 200.
- No se enviaron correos ni se cambiaron ajustes Auth/Supabase durante esta habilitación.

**Pendiente real:** CPaaS solicita “Validación del cliente” para verificar la cuenta y habilitar funcionalidad completa. El formulario tiene cuatro pasos y comienza pidiendo el sitio web; se inspeccionó, pero no se enviaron respuestas ni solicitudes de aprobación. La configuración del agente también ofrece IP permitidas para SMTP/API; debe revisarse al conectar el proveedor, sin inventar IPs ni habilitar rangos globales. No se generaron/copiaran tokens SMTP/API. Falta conectar SMTP a Supabase, revisar remitente/plantillas/redirects y probar entrega, enlace y confirmación de un correo nuevo. La verificación DNS no equivale a envío habilitado o entregado.

Evidencias en `rsuelvo-web/evidence/mail/2026-09-30/`: `cloudflare-mail-dns.png`, `zoho-mail-dkim-active.png`, `cpaas-domain-verified.png`, `cpaas-validation-pending.png`, `dns-mail-records.json` (solo nombres y claves públicas DNS).

## Avance alertas de errores n8n — 2026-09-30 21:02 UTC

El usuario confirmó que inició sesión en n8n. La integración MCP ya permite inspeccionar credenciales y workflows, aunque la pestaña Chromium que tenemos expuesta todavía redirige a `signin?sessionExpired=true`.

- No existe aún una credencial SMTP entre las 7 credenciales de n8n.
- El workflow compartido `RSUELVO — Alertas de errores` está armado con Error Trigger → saneamiento del contexto → envío de email a `ethannic2@gmail.com`, pero permanece inactivo, sin versión publicada y sin credencial en el nodo email.
- No se ha enviado ningún correo ni se ha conectado el handler a workflows de producción.
- CPaaS muestra host `smtp.zeptomail.com`, usuario `emailapikey`, puerto 587 TLS o 465 SSL. La contraseña/API key se mantienen enmascaradas; KYC sigue pendiente y el agente está cerrado.

**Pendiente:** titular completa KYC/habilitación del agente; guardar el SMTP en una credencial de n8n sin transcribir el secreto; hacer entrega de prueba; publicar el handler y asociarlo a los workflows; comprobar una alerta sintética recibida. Bitácora operativa: [[QA-n8n-produccion-2026-09-30]].

## Alertas compartidas de workflows — avance 2026-09-30 21:10 UTC

La auditoría actual de n8n encontró 16 workflows de negocio activos y ninguno enlazado al handler por `settings.errorWorkflow`. El MCP n8n responde; Chromium UI disponible todavía conserva una sesión expirada. La cuenta CPaaS está “en revisión” y `agent_1` continúa cerrado.

El borrador `RSUELVO — Alertas de errores` se preparó para enviar desde `noreply@rsuelvo.com` (remitente autorizado en CPaaS) a `ethannic2@gmail.com`. El nodo de contexto elimina Bearer/JWT/credenciales/valores sensibles de URL y emails/teléfonos del texto del error. Validé su configuración y casos sintéticos de sanitización. El workflow sigue inactivo, sin versión publicada y sin credencial SMTP; no hubo envío de correo.

Próximo paso después de la habilitación CPaaS: crear/guardar credencial SMTP solo en n8n, hacer entrega de prueba, publicar el handler, asignarlo a los 16 workflows y confirmar llegada de una alerta sintética. Detalles: [[QA-n8n-produccion-2026-09-30]].


## Prueba SMTP y confirmación real — 2026-09-30 21:11 UTC

El usuario completó el formulario de validación de Zoho y la configuración inicial en Supabase. Se corrigió el usuario SMTP guardado (contenía una credencial de API) a `emailapikey` y se copió directamente la contraseña SMTP del agente, sin guardar secretos en el repositorio. Se comprobó tras recargar que la configuración persistía. Host `smtp.zeptomail.com`, puerto 587, remitente `noreply@rsuelvo.com`, nombre RSUELVO, SMTP personalizado activo.

El correo indicado ya tenía cuenta; se utilizó el alias del mismo buzón `ethannic2+qa20260930smtp@gmail.com`. Registro público en producción HTTP 200; Auth creó la cuenta QA `4ba435a8-d9c8-411a-897a-07bd0d9e9924`. Supabase registró envío de invitación a las 21:10:49 UTC. El registro de Zoho muestra remitente noreply, destinatario QA, asunto `You've been invited` y estado **Entregado**. El usuario confirmó recepción y apertura del enlace. Auth registra `email_confirmed_at=2026-09-30 21:11:20.017825+00` y primer inicio de sesión inmediatamente después.

Resultado: registro web → envío SMTP → entrega Gmail → enlace → confirmación Auth comprobados. La cuenta original no se modificó. Zoho aún muestra revisión pendiente: esta entrega no acredita aprobación completa ni capacidad de producción a escala. La plantilla real de invitación todavía usa asunto en inglés; adaptar la plantilla Invite user también, además de Confirm signup. MFA/2FA por correo continúa sin implementar y esta prueba no acredita AAL2.

Una inspección previa mostró accidentalmente una credencial API en la salida de una herramienta; no se reproduce ni se guarda aquí. La corrección SMTP no equivale a rotación de esa credencial API.


## Reconciliación posterior de correo — 2026-09-30 21:37 UTC

Se contrastó el estado con Chromium y n8n MCP después de la prueba Auth documentada arriba. Supabase Auth sí completó la entrega de una invitación QA por el SMTP de CPaaS; el mensaje llegó, el enlace se confirmó y la cuenta pudo iniciar sesión. Esto no certifica el canal SMTP de n8n: n8n conserva siete credenciales y ninguna SMTP, el handler de error no está publicado ni activo y ninguno de los 16 workflows activos lo tiene asignado.

La consola CPaaS abierta muestra que `agent_1` sigue cerrado y que SMTP/API secrets están enmascarados. No se regeneró la contraseña porque el agente sirve al SMTP de Supabase. Para continuar sin impactar Auth, se debe provisionar una credencial adicional o recuperar de forma segura la credencial activa para n8n; después hacer envío de prueba al buzón aprobado y enlazar el handler. Bitácora detallada: [[QA-n8n-produccion-2026-09-30]].


## Actualización MFA por correo — 2026-09-30

Implementado y restaurado como obligatorio para administradores en Flutter/web, con comprobación de sesión en backend; TOTP sigue como alternativa. Envío, verificación real, rechazo de replay y revocación al cerrar sesión comprobados. No se presenta como AAL2 nativo. Ver QA-MFA-Correo-2026-09-30 (vault) / qa-email-mfa-2026-09-30.md (web). Prueba móvil pausada a petición del usuario; último APK preparado para instalar y probar al volver.


## Plantillas de Auth localizadas — 2026-09-30 21:45 UTC

Desde el dashboard de producción actualicé y recargué para confirmar persistencia las plantillas **Invite user** y **Confirm sign up**. Ambas usan asuntos y contenido en español, mantienen `{{ .ConfirmationURL }}` y el enlace CTA correspondiente. La plantilla de invitación dice “Te invitamos a unirte a RSUELVO”; la de confirmación “Confirma tu correo electrónico”. No cambié SMTP, límites ni redirecciones, y aún no envié un correo nuevo después del cambio; el E2E de entrega anterior sigue siendo la prueba del canal, con la plantilla anterior.


## Estado MFA posterior — 2026-09-30 21:48 UTC

La implementación de step-up por correo quedó documentada por el orquestador en [[QA-MFA-Correo-2026-09-30]]. La función y la experiencia web/móvil requieren código ligado a sesión para usuarios administrativos; conserva TOTP como alternativa y no afirma AAL2 de Supabase. QA de cuenta sintética comprobó envío real, validación, rechazo de replay y revocación. El login E2E real de SuperAdmin en sus dispositivos está pendiente de la sesión del titular.

El ledger de producción alcanzó 99 versiones. La rama candidata tiene 48 archivos de migración; los timestamps de los tres archivos locales MFA difieren de las versiones registradas remotamente, además del archivo de hardening. Se mantiene congelado `db push` hasta reconciliar semánticamente nombres, SQL y ledger.
