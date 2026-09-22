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

const NEUTRAL = { ok: true, mensaje: "Si el correo es válido, recibirás instrucciones." };

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

  // Honeypot antiabuso (campo invisible que solo llenan bots)
  if (String(body.empresa ?? "").trim() !== "") return json(NEUTRAL);

  const email = String(body.email ?? "").trim().toLowerCase();
  const nombre = String(body.nombre ?? "").trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !nombre) {
    return json({ ok: false, error: "Datos inválidos" }, 400);
  }
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim().slice(0, 64) || null;

  // Rate-limit: max 5 intentos / 24h por email (antiabuso; plataforma limita envío a 2/h)
  const { count } = await supa.from("tbl_registro_intentos")
    .select("id", { count: "exact", head: true })
    .eq("email", email)
    .gt("created_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
  await supa.from("tbl_registro_intentos").insert({ email, ip });
  if ((count ?? 0) >= 5) return json(NEUTRAL);

  // Anti-enumeración: el mismo camino exista o no; jamás revela pertenencia.
  // inviteUserByEmail falla neutral si Auth ya existe (sin reenviar).
  await supa.auth.admin.inviteUserByEmail(email);
  return json(NEUTRAL);
});
