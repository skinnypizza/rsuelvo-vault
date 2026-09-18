-- 63_creditos_clientes.sql
-- A) Clientes: `nombre` guardaba el CONCATENADO (nombre+apellidos) y la app volvia
--    a concatenar -> "Juan Pérez García Pérez García". Fix: el escritor normaliza
--    (despoja apellidos de `nombre`) + limpieza de filas existentes. Display en app
--    (concat) queda intacto, sin cambios.
-- B) Creditos: extension `tbl_compras_creditos` + bucket `depositos-creditos` +
--    `fn_solicitar_creditos` (dueño) + `fn_resolver_compra_creditos` (staff).
--    HU-pendientes roles expandidos, D17-adjacente.

-- ═══ A1. Limpieza: despojar apellidos de `nombre` (solo si queda no-vacio) ═══
update rsuelvo.tbl_clientes
set nombre = trim(both ' ' from regexp_replace(
  regexp_replace(nombre,
    '(?i)\m' || regexp_replace(coalesce(apellido_paterno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'),
  '(?i)\m' || regexp_replace(coalesce(apellido_materno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'))
where apellido_paterno is not null
  and nullif(trim(both ' ' from regexp_replace(
    regexp_replace(nombre,
      '(?i)\m' || regexp_replace(coalesce(apellido_paterno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'),
    '(?i)\m' || regexp_replace(coalesce(apellido_materno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g')), '') is not null
  and (nombre ilike '%' || apellido_paterno || '%' or nombre ilike '%' || apellido_materno || '%');

-- ═══ A2. Escritor: fn_upsert_cliente normaliza (reescritura completa) ═══
create or replace function rsuelvo.fn_upsert_cliente(p_id_comercio uuid, p_nombre text, p_telefono text DEFAULT NULL::text, p_telefono_whatsapp text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_apellido_paterno text DEFAULT NULL::text, p_apellido_materno text DEFAULT NULL::text, p_origen_nombre text DEFAULT 'PERFIL'::text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'rsuelvo', 'public'
as $function$
declare
  v_id uuid;
  v_origen text;
  v_pat text := nullif(trim(coalesce(p_apellido_paterno,'')), '');
  v_mat text := nullif(trim(coalesce(p_apellido_materno,'')), '');
  v_nom_limpio text;
  v_cur_nom text;
  v_cur_pat text;
  v_cur_mat text;
  v_nuevo_nom text;
  v_nuevo_pat text;
  v_nuevo_mat text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;

  v_origen := upper(coalesce(nullif(trim(p_origen_nombre),''), 'PERFIL'));
  if v_origen not in ('CONFIRMADO','PERFIL') then
    raise exception 'origen de nombre inválido (CONFIRMADO|PERFIL)';
  end if;

  -- `nombre` guarda SOLO nombres: se despojan los apellidos que vengan pegados
  -- (p.ej. perfil WhatsApp "Juan Pérez García" + pat/Mat). Si quedara vacio,
  -- se conserva el original recortado (nunca NULL por normalizacion).
  v_nom_limpio := trim(both ' ' from regexp_replace(
    regexp_replace(coalesce(trim(p_nombre), ''),
      '(?i)\m' || regexp_replace(coalesce(v_pat,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'),
    '(?i)\m' || regexp_replace(coalesce(v_mat,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'));
  if v_nom_limpio = '' then
    v_nom_limpio := nullif(trim(coalesce(p_nombre,'')), '');
  end if;

  if p_telefono_whatsapp is not null then
    select id_cliente into v_id
    from tbl_clientes
    where id_comercio=p_id_comercio
      and telefono_whatsapp=p_telefono_whatsapp
    for update;

    if v_id is not null then
      -- Q8: el nombre confirmado (comprador/cajero) nunca se pisa con perfil/fallback.
      select nombre, apellido_paterno, apellido_materno
        into v_cur_nom, v_cur_pat, v_cur_mat
      from tbl_clientes
      where id_cliente = v_id;

      if v_origen = 'CONFIRMADO' then
        v_nuevo_nom := coalesce(v_nom_limpio, v_cur_nom);
        v_nuevo_pat := coalesce(v_pat, v_cur_pat);
        v_nuevo_mat := coalesce(v_mat, v_cur_mat);
      else
        if coalesce(trim(v_cur_nom),'') in ('', 'Cliente WhatsApp') then
          v_nuevo_nom := coalesce(v_nom_limpio, v_cur_nom);
        else
          v_nuevo_nom := v_cur_nom;
        end if;
        v_nuevo_pat := coalesce(nullif(trim(v_cur_pat),''), v_pat, v_cur_pat);
        v_nuevo_mat := coalesce(nullif(trim(v_cur_mat),''), v_mat, v_cur_mat);
      end if;

      update tbl_clientes
      set nombre = v_nuevo_nom,
          apellido_paterno = v_nuevo_pat,
          apellido_materno = v_nuevo_mat,
          telefono = coalesce(p_telefono, telefono),
          email = coalesce(p_email, email)
      where id_cliente = v_id;
      return v_id;
    end if;
  end if;

  insert into tbl_clientes(
    id_comercio, nombre, apellido_paterno, apellido_materno, telefono, telefono_whatsapp, email
  )
  values(
    p_id_comercio,
    v_nom_limpio,
    v_pat,
    v_mat,
    p_telefono, p_telefono_whatsapp, p_email
  )
  returning id_cliente into v_id;

  return v_id;
end;
$function$;

-- ═══ B1. Extension compras + bucket ═══
alter table rsuelvo.tbl_compras_creditos
  add column if not exists comprobante_deposito_url text,
  add column if not exists id_revisor uuid references rsuelvo.tbl_usuarios(id_usuario),
  add column if not exists fecha_revision timestamptz,
  add column if not exists motivo_rechazo text;

insert into storage.buckets (id, name, public)
values ('depositos-creditos', 'depositos-creditos', false)
on conflict (id) do nothing;

drop policy if exists depositos_dueno_select on storage.objects;
drop policy if exists depositos_dueno_insert on storage.objects;
drop policy if exists depositos_staff_select on storage.objects;

create policy depositos_dueno_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid));

create policy depositos_dueno_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'depositos-creditos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));

create policy depositos_staff_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
    and (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')
      or rsuelvo.fn_tiene_rol('ROLE_SUPPORT')));

-- ═══ B2. RLS compras: lectura dueño/staff, escritura solo via fns ═══
alter table rsuelvo.tbl_compras_creditos enable row level security;

drop policy if exists compras_select on rsuelvo.tbl_compras_creditos;
drop policy if exists compras_no_direct_write on rsuelvo.tbl_compras_creditos;

create policy compras_select on rsuelvo.tbl_compras_creditos
  for select to authenticated
  using (rsuelvo.fn_tiene_acceso_comercio(id_comercio)
    or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')
    or rsuelvo.fn_tiene_rol('ROLE_SUPPORT'));

create policy compras_no_direct_write on rsuelvo.tbl_compras_creditos
  for all to authenticated
  using (false) with check (false);

-- ═══ B3. fn_solicitar_creditos (dueño) ═══
create or replace function rsuelvo.fn_solicitar_creditos(
  p_id_paquete uuid,
  p_comprobante_url text
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_comercio uuid;
  v_n integer;
  v_paq record;
  v_compra uuid;
begin
  select uc.id_comercio into v_comercio
  from tbl_usuario_comercio uc
  join tbl_usuarios u on u.id_usuario = uc.id_usuario
  join tbl_roles r on r.id_rol = uc.id_rol
  where u.auth_user_id = auth.uid()
    and u.activo and uc.activo
    and r.codigo = 'ROLE_TENANT_ADMIN';

  select count(*) into v_n from (
    select uc.id_comercio
    from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario = uc.id_usuario
    join tbl_roles r on r.id_rol = uc.id_rol
    where u.auth_user_id = auth.uid()
      and u.activo and uc.activo
      and r.codigo = 'ROLE_TENANT_ADMIN'
  ) t;
  if v_comercio is null then
    return jsonb_build_object('ok', false, 'codigo', 'solo_dueno');
  end if;
  if v_n > 1 then
    return jsonb_build_object('ok', false, 'codigo', 'multi_comercio');
  end if;

  select id_paquete, creditos, precio into v_paq
  from tbl_paquetes_creditos
  where id_paquete = p_id_paquete and activo;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'paquete_invalido');
  end if;

  if nullif(trim(coalesce(p_comprobante_url,'')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'falta_comprobante');
  end if;

  insert into tbl_compras_creditos
    (id_comercio, id_paquete, creditos_comprados, monto, moneda, estado, comprobante_deposito_url)
  values
    (v_comercio, v_paq.id_paquete, v_paq.creditos, v_paq.precio, 'Bs', 'PENDIENTE', trim(p_comprobante_url))
  returning id_compra into v_compra;

  return jsonb_build_object('ok', true, 'id_compra', v_compra,
    'creditos', v_paq.creditos, 'monto', v_paq.precio);
end;
$fn$;

-- ═══ B4. fn_resolver_compra_creditos (staff aprueba/rechaza; dueño cancela) ═══
create or replace function rsuelvo.fn_resolver_compra_creditos(
  p_id_compra uuid,
  p_decision text
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_c record;
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT');
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not rsuelvo.fn_es_admin_comercio(v_c.id_comercio) then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$fn$;

-- 2026-09-18: dueño elimina sus depositos (reemplazo de comprobante)
drop policy if exists depositos_dueno_delete on storage.objects;
create policy depositos_dueno_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'depositos-creditos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));
