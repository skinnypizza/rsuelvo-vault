import { createClient } from "jsr:@supabase/supabase-js@2";

const ORIGINS = [
  "https://rsuelvo-web.pages.dev",
  "https://rsuelvo.com",
  "https://www.rsuelvo.com",
  "http://localhost:4321",
  "http://localhost:5173",
];

function cors(req: Request) {
  const o = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : ORIGINS[0],
    "Access-Control-Allow-Headers": "content-type, idempotency-key",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(req), "Content-Type": "application/json" },
  });
}

const normTel = (t: string) => t.replace(/[\s.\-()]/g, "");

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Método no permitido" }, 405);

  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { db: { schema: "rsuelvo" } },
  );

  let body: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > 8192) return json(req, { error: "Cuerpo excesivo" }, 413);
    body = JSON.parse(raw);
  } catch { return json(req, { error: "Cuerpo inválido" }, 400); }

  const allowed = ["nombre", "telefono", "tienda", "mensaje", "plan", "origen", "sitio_web", "codigo", "email"];
  for (const k of Object.keys(body)) {
    if (!allowed.includes(k)) return json(req, { error: "Campo inesperado" }, 400);
  }
  if (String(body.sitio_web ?? "") !== "") return json(req, { error: "Solicitud inválida" }, 400);

  const nombre = String(body.nombre ?? "").trim();
  const tienda = String(body.tienda ?? "").trim();
  const telefono = normTel(String(body.telefono ?? ""));
  const mensaje = String(body.mensaje ?? "").trim();
  const plan = body.plan == null ? null : String(body.plan);
  const key = req.headers.get("Idempotency-Key") ?? "";

  if (nombre.length < 2 || nombre.length > 100) return json(req, { error: "Nombre inválido" }, 422);
  if (tienda.length < 2 || tienda.length > 150) return json(req, { error: "Tienda inválida" }, 422);
  if (!/^\+?\d{8,15}$/.test(telefono)) return json(req, { error: "Teléfono inválido" }, 422);
  if (mensaje.length < 1 || mensaje.length > 1500) return json(req, { error: "Mensaje inválido" }, 422);
  if (plan !== null && !["Básico", "Basico", "Pro", "Empresa"].includes(plan)) {
    return json(req, { error: "Plan inválido" }, 422);
  }
  const codigoRaw = body.codigo == null ? null : String(body.codigo).trim().toUpperCase();
  const emailRaw = body.email == null ? null : String(body.email).trim().toLowerCase();
  if (emailRaw !== null && (emailRaw.length > 150 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailRaw))) {
    return json(req, { error: "Email inválido" }, 422);
  }
  if (codigoRaw !== null && (codigoRaw.length !== 3 || /O/.test(codigoRaw) || /[^A-Z0-9]/.test(codigoRaw))) {
    return json(req, { error: "Código inválido (3 caracteres A-Z0-9 sin O)" }, 422);
  }
  if (!/^[0-9a-f-]{36}$/i.test(key)) return json(req, { error: "Falta clave de idempotencia" }, 400);

  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim().slice(0, 64);
  const hace1h = new Date(Date.now() - 3600_000).toISOString();
  const { count: porTel } = await supa.from("tbl_solicitudes_alta")
    .select("id_solicitud", { count: "exact", head: true })
    .eq("telefono", telefono).gte("created_at", hace1h);
  if ((porTel ?? 0) >= 3) return json(req, { error: "Demasiados intentos. Probá en una hora." }, 429);
  if (ip) {
    const { count: porIp } = await supa.from("tbl_solicitudes_alta")
      .select("id_solicitud", { count: "exact", head: true })
      .eq("ip_origen", ip).gte("created_at", hace1h);
    if ((porIp ?? 0) >= 10) return json(req, { error: "Demasiados intentos. Probá en una hora." }, 429);
  }

  const payload = JSON.stringify({ nombre, telefono, tienda, mensaje, plan });
  const hashBuf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(payload));
  const hash = Array.from(new Uint8Array(hashBuf)).map((b) => b.toString(16).padStart(2, "0")).join("");

  // Idempotencia atómica: la clave es UNIQUE
  if (codigoRaw !== null) {
    const { data: libre } = await supa.rpc("fn_sugerir_codigo", { p_base: codigoRaw });
    const lista: string[] = (libre as { sugerencias?: string[] })?.sugerencias ?? [];
    if (!lista.includes(codigoRaw)) {
      return json(req, { error: "Código en uso", sugerencias: lista }, 409);
    }
  }
  const { data: ins, error: ierr } = await supa.from("tbl_solicitudes_alta").insert({
    nombre, telefono, tienda, mensaje, plan,
    origen: "landing", estado: "PENDIENTE",
    idempotency_key: key, payload_hash: hash, ip_origen: ip || null,
    codigo_sugerido: codigoRaw,
    email: emailRaw,
  }).select("id_solicitud, estado, payload_hash").single();

  if (ierr) {
    if (ierr.code === "23505") {
      const { data: prev } = await supa.from("tbl_solicitudes_alta")
        .select("id_solicitud, estado, payload_hash").eq("idempotency_key", key).single();
      if (prev && (prev as { payload_hash: string }).payload_hash === hash) {
        return json(req, {
          solicitud_id: (prev as { id_solicitud: string }).id_solicitud,
          estado: (prev as { estado: string }).estado,
        }, 200);
      }
      return json(req, { error: "Solicitud duplicada con otros datos" }, 409);
    }
    return json(req, { error: "Fallo temporal. Reintentá." }, 500);
  }

  return json(req, {
    solicitud_id: (ins as { id_solicitud: string }).id_solicitud,
    estado: "PENDIENTE",
  }, 201);
});
