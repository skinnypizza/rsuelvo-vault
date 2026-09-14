# Edge Function `meta-ingress` (P3)

> Receptor Meta delante de n8n. Desplegada v2 (v1 murió por `URL` sombreado).
> `verify_jwt=false` (Meta no usa JWT). Probada: GET 403 sin secreto, status→drop+auditoría,
> mensaje replay→forward+dedup en n8n sin efectos.

## Comportamiento
- **GET** `?hub.mode=subscribe&hub.verify_token&hub.challenge`: responde challenge en
  texto plano solo si coincide `META_VERIFY_TOKEN`; si no, 403.
- **POST**: HMAC `x-hub-signature-256` contra `META_APP_SECRET` (si existe; si no,
  pasa sin verificar y lo marca). Descarta SOLO status puros sin `failed`
  (delivered/read/sent) con log `meta_ingress/descartado_status` → 200. Todo lo demás
  (mensajes, failed, mixtos, desconocidos) se reenvía íntegro a n8n; si el reenvío
  falla → 502 (Meta reintenta). Fail-open a entrega, fail-closed a extraños.

## Secretos (dashboard Supabase → Edge Functions → Secrets; NUNCA en repo/vault)
- `META_VERIFY_TOKEN` (del panel n8n Variables o Meta dashboard).
- `META_APP_SECRET` (Meta dashboard → App Settings).
- `N8N_META_WEBHOOK_URL` (opcional; default al webhook `rsuelvotest` actual).

## Cutover (dueño, cuando apruebe)
1. Pegar los 2 secretos. 2. En Meta dashboard, cambiar la URL del webhook a
   `https://iwfaktlxebxtocmswdvv.supabase.co/functions/v1/meta-ingress` (verificación
   con challenge en vivo). 3. Comparar raíces/24h antes/después. Rollback: volver a la
   URL n8n (nada interno cambió; el filtro interno de status sigue).
