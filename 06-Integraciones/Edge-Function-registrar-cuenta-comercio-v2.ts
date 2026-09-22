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

  if (String(body.empresa ?? "").trim() !== "") return json(NEUTRAL);

  const email = String(body.email ?? "").trim().toLowerCase();
  const nombre = String(body.nombre ?? "").trim().slice(0, 80);
  const apellido = String(body.apellido ?? "").trim().slice(0, 80);
  const telefono = String(body.telefono ?? "").trim().slice(0, 32);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !nombre) {
    return json({ ok: false, error: "Datos inválidos" }, 400);
  }
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim().slice(0, 64) || null;

  const { count } = await supa.from("tbl_registro_intentos")
    .select("id", { count: "exact", head: true })
    .eq("email", email)
    .gt("created_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
  await supa.from("tbl_registro_intentos").insert({ email, ip });
  if ((count ?? 0) >= 5) return json(NEUTRAL);

  // Solo metadata segura de perfil. Jamás rol/comercio/owner/membership.
  const metadata = {
    nombre,
    ...(apellido ? { apellido } : {}),
    ...(telefono ? { telefono } : {}),
  };
  const { data: invited, error: invErr } = await supa.auth.admin.inviteUserByEmail(email, {
    data: metadata,
  });

  // Perfil idempotente (opción A): con Auth id directo, o por email si ya existía.
  const authId = invited?.user?.id ?? null;
  if (authId) {
    await supa.from("tbl_usuarios").upsert(
      { auth_user_id: authId, email, nombre, apellido: apellido || null, telefono: telefono || null, activo: true },
      { onConflict: "auth_user_id" },
    );
  } else {
    // Auth ya existía (respuesta neutral). El perfil se repara solo en el
    // primer llamado autenticado (fn_auto_alta_comercio), que deriva todo
    // del JWT + metadata del invite. Aquí no se toca nada más.
  }
  void invErr;
  return json(NEUTRAL);
});
