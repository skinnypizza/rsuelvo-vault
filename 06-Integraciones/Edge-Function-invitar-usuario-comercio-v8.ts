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

function tempPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#-";
  const buf = new Uint8Array(16);
  crypto.getRandomValues(buf);
  return Array.from(buf, (b) => chars[b % chars.length]).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "Metodo no permitido" }, 405);

  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { db: { schema: "rsuelvo" } },
  );

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ ok: false, error: "Sin sesion" }, 401);
  const { data: { user }, error: uerr } = await supa.auth.getUser(token);
  if (uerr || !user) return json({ ok: false, error: "Token invalido" }, 401);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { return json({ ok: false, error: "Cuerpo invalido" }, 400); }

  const email = String(body.email ?? "").trim().toLowerCase();
  const nombre = String(body.nombre ?? "").trim();
  const apellido = String(body.apellido ?? "").trim();
  const telefono = String(body.telefono ?? "").trim();
  const idRol = Number(body.id_rol);
  const idSucursal = body.id_sucursal ? String(body.id_sucursal) : null;
  const idComercioReq = body.id_comercio ? String(body.id_comercio) : null;

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ ok: false, error: "Email invalido" }, 400);
  }

  // Invocador: usuario + vinculos activos
  const { data: invocador } = await supa.from("tbl_usuarios")
    .select("id_usuario").eq("auth_user_id", user.id).eq("activo", true).maybeSingle();
  if (!invocador) return json({ ok: false, error: "Sin acceso" }, 403);
  const { data: vinc } = await supa.from("tbl_usuario_comercio")
    .select("id_comercio, id_rol, tbl_roles!inner(codigo)")
    .eq("id_usuario", (invocador as { id_usuario: string }).id_usuario).eq("activo", true);
  const roles: string[] = (vinc ?? []).map((v: { tbl_roles: { codigo: string } }) => v.tbl_roles.codigo);
  const esSuper = roles.includes("ROLE_SUPERADMIN");
  const adminVinc = (vinc ?? []).find((v: { tbl_roles: { codigo: string } }) => v.tbl_roles.codigo === "ROLE_TENANT_ADMIN");

  // ── PATH B: SUPERADMIN invita dueño (rol 4), comercio explicito ──
  if (esSuper && (idRol === 2 || idRol === 3 || idRol === 4)) {
    if (!idComercioReq) return json({ ok: false, error: "Falta id_comercio" }, 400);
    const { data: com } = await supa.from("tbl_comercios")
      .select("id_comercio").eq("id_comercio", idComercioReq).maybeSingle();
    if (!com) return json({ ok: false, error: "Comercio inexistente" }, 400);
    if (idSucursal) {
      const { data: suc } = await supa.from("tbl_sucursales").select("id_sucursal")
        .eq("id_sucursal", idSucursal).eq("id_comercio", idComercioReq).eq("activo", true).maybeSingle();
      if (!suc) return json({ ok: false, error: "Sucursal ajena al comercio" }, 400);
    }
    return await crearInvitado(supa, {
      email, nombre: nombre || (idRol === 4 ? "Dueño invitado" : "Staff invitado"), apellido, telefono,
      idRol, idComercio: idComercioReq, idSucursal,
    });
  }

  // ── PATH A (v1 intacto): ADMIN invita roles 5/6 con sucursal ──
  if (adminVinc && (idRol === 5 || idRol === 6)) {
    const idComercio = (adminVinc as { id_comercio: string }).id_comercio;
    if (!idSucursal) return json({ ok: false, error: "Falta sucursal" }, 400);
    const { data: suc } = await supa.from("tbl_sucursales").select("id_sucursal")
      .eq("id_sucursal", idSucursal).eq("id_comercio", idComercio).eq("activo", true).maybeSingle();
    if (!suc) return json({ ok: false, error: "Sucursal ajena al comercio" }, 400);
    return await crearInvitado(supa, {
      email, nombre: nombre || "Usuario invitado", apellido,
      telefono, idRol, idComercio, idSucursal,
    });
  }

  if (![2, 3, 4, 5, 6].includes(idRol)) {
    return json({ ok: false, error: "Rol fuera de alcance" }, 400);
  }
  return json({ ok: false, error: "El invocador no tiene permiso para este rol" }, 403);
});

async function crearInvitado(
  supa: ReturnType<typeof createClient>,
  p: { email: string; nombre: string; apellido: string; telefono: string; idRol: number; idComercio: string; idSucursal: string | null },
): Promise<Response> {
  // Idempotencia: mismo email + mismo vinculo -> 200 sin duplicar
  const { data: existing } = await supa.auth.admin.listUsers();
  const yaAuth = (existing?.users ?? []).find((u: { email?: string }) => u.email?.toLowerCase() === p.email);
  if (yaAuth) {
    const { data: urow } = await supa.from("tbl_usuarios").select("id_usuario")
      .eq("auth_user_id", (yaAuth as { id: string }).id).maybeSingle();
    if (urow) {
      const { data: vrow } = await supa.from("tbl_usuario_comercio").select("id_rol")
        .eq("id_usuario", (urow as { id_usuario: string }).id_usuario)
        .eq("id_comercio", p.idComercio).eq("id_rol", await rolId(supa, p.idRol)).maybeSingle();
      if (vrow) {
        return json({ ok: true, email: p.email, id_usuario: (urow as { id_usuario: string }).id_usuario, ya_existente: true });
      }
    }
    return json({ ok: false, error: "Ese email ya tiene cuenta" }, 409);
  }

  const pass = tempPassword();
  const { data: created, error: cerr } = await supa.auth.admin.createUser({
    email: p.email, password: pass, email_confirm: true,
    user_metadata: { nombre: p.nombre },
  });
  if (cerr || !created?.user) return json({ ok: false, error: "No se pudo crear la cuenta" }, 500);
  const authId = created.user.id;

  try {
    const { data: urow, error: uerr } = await supa.from("tbl_usuarios").insert({
      auth_user_id: authId, email: p.email, nombre: p.nombre,
      apellido: p.apellido || null,
      telefono: p.telefono || null, activo: true,
    }).select("id_usuario").single();
    if (uerr || !urow) throw new Error("usuarios");
    const idUsuario = (urow as { id_usuario: string }).id_usuario;

    const { error: verr } = await supa.from("tbl_usuario_comercio").insert({
      id_usuario: idUsuario, id_comercio: p.idComercio,
      id_rol: await rolId(supa, p.idRol), id_sucursal: p.idSucursal, activo: true,
    });
    if (verr) {
      await supa.from("tbl_usuarios").delete().eq("id_usuario", idUsuario);
      throw new Error("vinculo");
    }
    return json({
      ok: true, email: p.email, id_usuario: idUsuario,
      password_temporal: pass,
      mensaje: "Compartila por un canal seguro; se cambia en el primer ingreso.",
    }, 201);
  } catch {
    await supa.auth.admin.deleteUser(authId).catch(() => {});
    return json({ ok: false, error: "Error interno" }, 500);
  }
}

async function rolId(supa: ReturnType<typeof createClient>, idRol: number): Promise<number> {
  // v1 usa ids numericos directos; se conservan tal cual
  return idRol;
}
