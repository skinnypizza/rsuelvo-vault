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
  const idRol = Number(body.id_rol);
  const idSucursal = body.id_sucursal ? String(body.id_sucursal) : null;
  const idComercioReq = body.id_comercio ? String(body.id_comercio) : null;

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ ok: false, error: "Email invalido" }, 400);
  }
  if (![2, 3, 4, 5, 6].includes(idRol)) {
    return json({ ok: false, error: "Rol fuera de alcance" }, 400);
  }

  // Invocador: usuario + vinculos activos
  const { data: invocador } = await supa.from("tbl_usuarios")
    .select("id_usuario").eq("auth_user_id", user.id).eq("activo", true).maybeSingle();
  if (!invocador) return json({ ok: false, error: "Sin acceso" }, 403);
  const idInvocador = (invocador as { id_usuario: string }).id_usuario;
  const { data: vinc } = await supa.from("tbl_usuario_comercio")
    .select("id_comercio, id_rol, tbl_roles!inner(codigo)")
    .eq("id_usuario", idInvocador).eq("activo", true);
  const roles: string[] = (vinc ?? []).map((v: { tbl_roles: { codigo: string } }) => v.tbl_roles.codigo);
  const esSuper = roles.includes("ROLE_SUPERADMIN");
  const adminVinc = (vinc ?? []).find((v: { tbl_roles: { codigo: string } }) => v.tbl_roles.codigo === "ROLE_TENANT_ADMIN");

  // Resolver comercio objetivo segun path
  let idComercio: string | null = null;
  if (esSuper && (idRol === 2 || idRol === 3 || idRol === 4)) {
    if (!idComercioReq) return json({ ok: false, error: "Falta id_comercio" }, 400);
    const { data: com } = await supa.from("tbl_comercios")
      .select("id_comercio").eq("id_comercio", idComercioReq).maybeSingle();
    if (!com) return json({ ok: false, error: "Comercio inexistente" }, 400);
    idComercio = idComercioReq;
  } else if (adminVinc && (idRol === 5 || idRol === 6)) {
    idComercio = (adminVinc as { id_comercio: string }).id_comercio;
    if (!idSucursal) return json({ ok: false, error: "Falta sucursal" }, 400);
  } else {
    return json({ ok: false, error: "El invocador no tiene permiso para este rol" }, 403);
  }

  if (idSucursal) {
    const { data: suc } = await supa.from("tbl_sucursales").select("id_sucursal")
      .eq("id_sucursal", idSucursal).eq("id_comercio", idComercio).eq("activo", true).maybeSingle();
    if (!suc) return json({ ok: false, error: "Sucursal ajena al comercio" }, 400);
  }

  // Idempotencia 1: vinculo equivalente ya activo -> 200 sin nada
  const { data: urow } = await supa.from("tbl_usuarios").select("id_usuario")
    .eq("email", email).maybeSingle();
  if (urow) {
    const { data: vrow } = await supa.from("tbl_usuario_comercio").select("id")
      .eq("id_usuario", (urow as { id_usuario: string }).id_usuario)
      .eq("id_comercio", idComercio).eq("id_rol", idRol).eq("activo", true).maybeSingle();
    if (vrow) {
      return json({ ok: true, email, ya_existente: true, mensaje: "La persona ya tiene acceso." });
    }
  }

  // Idempotencia 2: invitacion PENDIENTE vigente -> 200 reenvio logico
  const { data: pend } = await supa.from("tbl_invitaciones").select("id")
    .eq("email", email).eq("id_comercio", idComercio)
    .eq("estado", "PENDIENTE").gt("expira_at", new Date().toISOString()).maybeSingle();
  if (pend) {
    return json({ ok: true, email, pendiente: true, mensaje: "Invitación pendiente reenviada. La persona debe aceptarla desde su cuenta." });
  }

  // Crear invitacion PENDIENTE primero (orden seguro: si el email falla, el reintento la reutiliza)
  const { data: inv, error: ierr } = await supa.from("tbl_invitaciones").insert({
    id_comercio: idComercio, id_rol: idRol, id_sucursal: idSucursal,
    email, invited_by: idInvocador,
  }).select("id").single();
  if (ierr || !inv) return json({ ok: false, error: "No se pudo crear la invitación" }, 500);

  // Usuario nuevo (sin auth user): invitar via Supabase (unico secreto, fuera de RSUELVO)
  const { data: existing } = await supa.auth.admin.listUsers();
  const yaAuth = (existing?.users ?? []).find((u: { email?: string }) => u.email?.toLowerCase() === email);
  if (!yaAuth) {
    const { error: invErr } = await supa.auth.admin.inviteUserByEmail(email);
    if (invErr) {
      await supa.from("tbl_invitaciones").delete().eq("id", (inv as { id: string }).id);
      return json({ ok: false, error: "No se pudo enviar la invitación" }, 500);
    }
    // Fila espejo minima para el auth user recien creado (acepta luego por JWT)
    const { data: created } = await supa.auth.admin.listUsers();
    const nu = (created?.users ?? []).find((u: { email?: string }) => u.email?.toLowerCase() === email);
    if (nu) {
      await supa.from("tbl_usuarios").upsert(
        { auth_user_id: (nu as { id: string }).id, email, nombre: "Invitado", activo: true },
        { onConflict: "auth_user_id" },
      );
    }
    return json({ ok: true, email, pendiente: true, mensaje: "Invitación enviada. La persona deberá aceptar el acceso desde su propio correo verificado." }, 201);
  }

  // Usuario existente: sin token; acepta autenticado via fn_mis_invitaciones_pendientes/fn_aceptar_invitacion
  if (!urow) {
    const { data: vinculada } = await supa.from("tbl_usuarios").update({
      auth_user_id: (yaAuth as { id: string }).id,
    }).eq("email", email).is("auth_user_id", null).select("id_usuario").maybeSingle();
    if (!vinculada) {
      await supa.from("tbl_usuarios").insert({
        auth_user_id: (yaAuth as { id: string }).id, email, nombre: "Invitado", activo: true,
      });
    }
  }
  return json({ ok: true, email, pendiente: true, mensaje: "Invitación enviada. La persona deberá aceptar el acceso desde su cuenta." }, 201);
});
