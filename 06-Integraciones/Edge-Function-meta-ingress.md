# Edge Function `meta-ingress` — Meta → n8n Community

Fuente de la versión desplegada: [Edge-Function-meta-ingress-v13.ts](Edge-Function-meta-ingress-v13.ts).

Estado: desplegada y activa en Supabase producción, versión 13. El endpoint público de Meta es `https://iwfaktlxebxtocmswdvv.supabase.co/functions/v1/meta-ingress`. `verify_jwt=false` porque Meta no presenta JWT; el receptor verifica la firma HMAC de Meta y añade autenticación propia al reenviar a n8n.

## Comportamiento vigente

- **GET de verificación:** acepta `hub.mode=subscribe` solo si `hub.verify_token` coincide con `META_VERIFY_TOKEN`; devuelve `hub.challenge` como texto plano. Otros casos devuelven 403.
- **POST:** requiere `N8N_META_INGRESS_SECRET` y `META_APP_SECRET`; si falta alguno, falla cerrado con 503. Verifica `X-Hub-Signature-256` sobre el cuerpo crudo; firma inválida o ausente devuelve 401 y no reenvía.
- **Estados:** descarta callbacks que solo contienen estados normales (`sent`, `delivered`, `read`) y los audita. Los estados `failed`, los mensajes y los lotes mixtos se reenvían sin modificar a `https://n8n.rsuelvo.com/webhook/webhooks/whatsapp/meta` por defecto. El secreto de ingreso a n8n se envía solo en `X-RSUELVO-META-INGRESS`.
- **Resultado del reenvío:** la versión 13 audita el resultado en `rsuelvo.tbl_logs_auditoria` como `reenviado`, `reenvio_fallido` o `reenvio_excepcion`, con código HTTP y conteos. No registra el cuerpo, teléfono, IDs de mensaje ni medios. Ante no-2xx o excepción, responde 502 para permitir los reintentos de Meta.
- Las escrituras de auditoría son best effort; errores de inserción producen `meta_ingress_audit_failed` con el código de error, sin datos del mensaje.

## Secretos

Los valores residen solo en Supabase Edge Function Secrets; no copiarlos al vault ni al repositorio:

- `META_VERIFY_TOKEN`
- `META_APP_SECRET`
- `N8N_META_INGRESS_SECRET`
- `N8N_META_WEBHOOK_URL` es opcional; si no se configura usa el endpoint de n8n Community descrito arriba.

## Evidencia y pendientes

- A 2026-10-01 18:55 UTC, la función estaba `ACTIVE`, versión 13, `verify_jwt=false`. `deno check` pasó antes del despliegue.
- Tras el despliegue, una petición sintética con firma inválida devolvió HTTP 401 y produjo solo una auditoría `rechazado_firma`; no se insertó evento WhatsApp. Esto verifica que el endpoint responde y mantiene la protección HMAC.
- El último evento real de WhatsApp seguía siendo la imagen de las 16:01:53 UTC; el último `meta_ingress` real anterior, a las 16:02 UTC. No hay prueba aún de un POST válido de Meta después de WF-04 v`9920b9cc-278b-4042-af75-c7c25193ae64` y Edge Function v13.
- La configuración actual de suscripción/estado de la app en Meta Developers no pudo comprobarse desde esta sesión. Un GET con token incorrecto devuelve 403 por diseño; eso no verifica el token válido ni la suscripción de `messages`.

Al validar el camino real, enviar primero un SKU de prueba y comprobar en orden `reenviado` → ejecución WF-02/03/04 → evento procesado en Supabase. No enviar otro comprobante hasta que el SKU entre y se procese correctamente.
