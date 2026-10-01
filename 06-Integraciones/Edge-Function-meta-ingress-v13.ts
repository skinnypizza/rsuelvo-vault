import { createClient } from 'npm:@supabase/supabase-js@2'

// Meta webhook ingress: challenge verification, fail-closed HMAC, status filtering,
// and forwarding to the currently configured n8n community endpoint.
const N8N_DEFAULT = 'https://n8n.rsuelvo.com/webhook/webhooks/whatsapp/meta'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json' },
})

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function hmacOk(secret: string, raw: string, sig: string | null): Promise<boolean> {
  if (!sig || !sig.startsWith('sha256=')) return false
  try {
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
    const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(raw))
    const want = `sha256=${hex(mac)}`
    if (want.length !== sig.length) return false
    let diff = 0
    for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ sig.charCodeAt(i)
    return diff === 0
  } catch {
    return false
  }
}

Deno.serve(async (req) => {
  const supaUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const verifyToken = Deno.env.get('META_VERIFY_TOKEN') ?? ''
  const appSecret = Deno.env.get('META_APP_SECRET') ?? ''
  const n8nIngressSecret = Deno.env.get('N8N_META_INGRESS_SECRET') ?? ''
  const n8nUrl = Deno.env.get('N8N_META_WEBHOOK_URL') || N8N_DEFAULT
  if (!supaUrl || !serviceKey) return json({ ok: false }, 503)

  const admin = createClient(supaUrl, serviceKey, { auth: { persistSession: false }, db: { schema: 'rsuelvo' } })
  const audit = async (datos: unknown) => {
    try {
      const { error } = await admin.from('tbl_logs_auditoria').insert({ id_comercio: null, accion: 'meta_ingress', tabla: 'tbl_whatsapp_eventos', datos_nuevos: datos })
      if (error) console.error('meta_ingress_audit_failed', error.code ?? 'db_error')
    } catch { /* best-effort audit */ }
  }

  const url = new URL(req.url)
  if (req.method === 'GET') {
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token') ?? ''
    const challenge = url.searchParams.get('hub.challenge') ?? ''
    if (mode === 'subscribe' && challenge && verifyToken && token === verifyToken) {
      return new Response(challenge, { status: 200, headers: { 'Content-Type': 'text/plain' } })
    }
    return new Response('Forbidden', { status: 403 })
  }

  if (req.method !== 'POST') return json({ ok: false }, 405)

  // The extra shared credential prevents bypassing this HMAC-verified ingress
  // by calling the public n8n webhook directly.
  if (!n8nIngressSecret) {
    await audit({ decision: 'rechazado_configuracion', reason: 'missing_n8n_ingress_secret' })
    return json({ ok: false, error: 'Webhook forwarding authentication unavailable' }, 503)
  }

  // Never accept unsigned events: empty/missing app secret is a configuration failure.
  if (!appSecret) {
    await audit({ decision: 'rechazado_configuracion', reason: 'missing_app_secret' })
    return json({ ok: false, error: 'Webhook authentication unavailable' }, 503)
  }
  const raw = await req.text()
  if (!await hmacOk(appSecret, raw, req.headers.get('x-hub-signature-256'))) {
    await audit({ decision: 'rechazado_firma', len: raw.length })
    return json({ ok: false, error: 'Firma inválida' }, 401)
  }

  let body: Record<string, unknown>
  try { body = JSON.parse(raw) } catch { return json({ ok: false, error: 'JSON inválido' }, 400) }

  let messageCount = 0
  let hasFailed = false
  let failedStatusCount = 0
  const statusKinds: string[] = []
  try {
    const entries = (body.entry ?? []) as Array<Record<string, unknown>>
    for (const entry of entries) {
      const changes = (entry.changes ?? []) as Array<Record<string, unknown>>
      for (const change of changes) {
        const value = (change.value ?? {}) as Record<string, unknown>
        const messages = (value.messages ?? []) as Array<Record<string, unknown>>
        const statuses = (value.statuses ?? []) as Array<Record<string, unknown>>
        messageCount += messages.length
        for (const status of statuses) {
          const kind = String(status.status ?? '')
          if (kind) statusKinds.push(kind)
          if (kind === 'failed') {
            hasFailed = true
            failedStatusCount++
          }
        }
      }
    }
  } catch { return json({ ok: false, error: 'Estructura ilegible' }, 400) }

  if (messageCount === 0 && !hasFailed) {
    await audit({ decision: 'descartado_status', status: statusKinds, n: statusKinds.length, verificado: true })
    return json({ ok: true, dropped: true, status: statusKinds })
  }

  try {
    const response = await fetch(n8nUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-RSUELVO-META-INGRESS': n8nIngressSecret,
      },
      body: raw,
      signal: AbortSignal.timeout(15000),
    })
    if (!response.ok) {
      await audit({ decision: 'reenvio_fallido', status: response.status, n_mensajes: messageCount, n_estados_fallidos: failedStatusCount })
      return json({ ok: false, error: `Reenvío falló: ${response.status}` }, 502)
    }
    await audit({ decision: 'reenviado', status: response.status, n_mensajes: messageCount, n_estados_fallidos: failedStatusCount })
    return json({ ok: true, forwarded: true })
  } catch (error) {
    await audit({ decision: 'reenvio_excepcion', reason: error instanceof Error ? error.name : 'UnknownError', n_mensajes: messageCount, n_estados_fallidos: failedStatusCount })
    return json({ ok: false, error: 'Reenvío falló: ' + (error as Error).message }, 502)
  }
})
