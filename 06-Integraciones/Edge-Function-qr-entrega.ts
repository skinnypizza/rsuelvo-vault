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

// Frontera pública de entrega de QR (IAM-9): la autorización depende del
// ESTADO del comercio en DB, nunca de la ubicación del archivo.
// V0 (o revocado) => DENY aunque el objeto exista almacenado.
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "Metodo no permitido" }, 405);

  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { db: { schema: "rsuelvo" } },
  );

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { return json({ ok: false, error: "Cuerpo invalido" }, 400); }
  const idComercio = String(body.id_comercio ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(idComercio)) {
    return json({ ok: false, error: "Comercio inválido" }, 400);
  }
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim().slice(0, 64) || null;

  // Rate-limit best-effort por IP (30/h)
  const { count } = await supa.from("tbl_registro_intentos")
    .select("id", { count: "exact", head: true })
    .eq("email", `qr:${idComercio}`)
    .eq("ip", ip ?? "-")
    .gt("created_at", new Date(Date.now() - 3600 * 1000).toISOString());
  await supa.from("tbl_registro_intentos").insert({ email: `qr:${idComercio}`, ip });
  if ((count ?? 0) >= 30) return json({ ok: false, error: "Límite excedido" }, 429);

  // Estado DB manda (service_role lee sin RLS; la decisión es explícita)
  const { data: com } = await supa.from("tbl_comercios")
    .select("estado")
    .eq("id_comercio", idComercio)
    .maybeSingle();
  if ((com as { estado?: string } | null)?.estado !== "ACTIVO") {
    return json({ ok: false, codigo: "comercio_no_habilitado" }, 403);
  }

  // Canonical privado primero (IAM-9+), legacy operativo después
  for (const bucket of ["qr-pagos-setup", "qr-pagos"]) {
    const { data: files } = await supa.storage.from(bucket).list(idComercio, { limit: 10 });
    const file = (files ?? []).find((f) => !f.name.startsWith(".")) ?? (files ?? [])[0];
    if (!file) continue;
    const { data: signed, error } = await supa.storage
      .from(bucket)
      .createSignedUrl(`${idComercio}/${file.name}`, 300);
    if (!signed || error) continue;
    return json({ ok: true, url: signed.signedUrl });
  }
  return json({ ok: false, codigo: "qr_no_configurado" }, 404);
});
