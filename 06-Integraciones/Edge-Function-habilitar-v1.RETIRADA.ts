import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function jwtAal(token: string): string | null {
  try {
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return (payload as { aal?: string }).aal ?? null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "Metodo no permitido" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ ok: false, error: "Sin sesion" }, 401);
  // AAL2 real del JWT (server-side, jamás parámetro cliente)
  if (jwtAal(token) !== "aal2") {
    return json({ ok: false, codigo: "mfa_requerido" }, 403);
  }

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { return json({ ok: false, error: "Cuerpo invalido" }, 400); }
  const idComercio = String(body.id_comercio ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(idComercio)) {
    return json({ ok: false, error: "Comercio inválido" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Cliente con JWT del usuario: owner se valida server-side (fn_es_owner)
  const userClient = createClient(url, anon, {
    db: { schema: "rsuelvo" },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const admin = createClient(url, serviceKey, { db: { schema: "rsuelvo" } });

  const { data: esOwner, error: ownerErr } = await userClient.rpc("fn_es_owner", {
    p_id_comercio: idComercio,
  });
  if (ownerErr || esOwner !== true) {
    return json({ ok: false, codigo: "solo_owner" }, 403);
  }

  // Copia idempotente staging -> operativo (sobrescribe si ya existe)
  const { data: staged, error: listErr } = await admin.storage
    .from("qr-pagos-setup")
    .list(idComercio, { limit: 10 });
  if (listErr || !staged || staged.length === 0) {
    return json({ ok: false, codigo: "qr_staging_vacio" }, 409);
  }
  const src = staged.find((f) => !f.name.startsWith(".")) ?? staged[0];
  const { data: blob, error: dlErr } = await admin.storage
    .from("qr-pagos-setup")
    .download(`${idComercio}/${src.name}`);
  if (dlErr || !blob) {
    return json({ ok: false, codigo: "qr_descarga_fallo" }, 502);
  }
  const { error: upErr } = await admin.storage
    .from("qr-pagos")
    .upload(`${idComercio}/${src.name}`, blob, { upsert: true, contentType: "image/png" });
  if (upErr) {
    return json({ ok: false, codigo: "qr_publicacion_fallo" }, 502);
  }

  // Finalización atómica (idempotente: ya_activo si otro ganó la carrera)
  const { data, error: finErr } = await admin.rpc("fn_finalizar_habilitacion_v1", {
    p_id_comercio: idComercio,
  });
  if (finErr) return json({ ok: false, error: "Finalización fallida" }, 500);
  return json(data);
});
