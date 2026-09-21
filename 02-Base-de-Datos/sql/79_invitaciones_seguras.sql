-- 79_invitaciones_seguras.sql
-- IAM-1 backend. Implementa 01-Arquitectura/D-IAM-INVITACIONES.md.
-- Supabase es el unico secreto; tbl_invitaciones = contexto/estado (sin tokens).
-- N-4 (cajero_multiplo) NO se toca: va a IAM-2.

-- ── 1. lifecycle minimo en tbl_usuario_comercio (aditivo) ──
alter table rsuelvo.tbl_usuario_comercio
  add column if not exists estado text not null default 'ACTIVE',
  add column if not exists invited_by uuid null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  add column if not exists accepted_at timestamptz null;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'uc_estado_chk') then
    alter table rsuelvo.tbl_usuario_comercio
      add constraint uc_estado_chk check (estado in ('ACTIVE','SUSPENDED','REVOKED'));
  end if;
end $$;

-- ── 2. tbl_invitaciones (contexto/estado, JAMAS secretos) ──
create table if not exists rsuelvo.tbl_invitaciones (
  id uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete cascade,
  id_rol smallint not null references rsuelvo.tbl_roles(id_rol),
  id_sucursal uuid null references rsuelvo.tbl_sucursales(id_sucursal) on delete set null,
  email text not null,
  invited_by uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  estado text not null default 'PENDIENTE',
  expira_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint invit_estado_chk check (estado in ('PENDIENTE','ACEPTADA','VENCIDA','REVOCADA'))
);
-- Idempotencia sobre PENDIENTE (C-02): el historial se conserva siempre
create unique index if not exists invit_pendiente_unica
  on rsuelvo.tbl_invitaciones (lower(email), id_comercio) where estado = 'PENDIENTE';

-- deny-by-default: sin policies -> solo service_role + SECURITY DEFINER
alter table rsuelvo.tbl_invitaciones enable row level security;
grant all on rsuelvo.tbl_invitaciones to service_role;

-- ── 3. fn_mis_invitaciones_pendientes (descubrimiento server-side) ──
create or replace function rsuelvo.fn_mis_invitaciones_pendientes()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_email text;
begin
  select lower(email) into v_email from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_email is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  return jsonb_build_object('ok', true, 'invitaciones', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_invitacion', i.id, 'id_comercio', i.id_comercio,
      'comercio', c.nombre_comercial, 'id_rol', i.id_rol,
      'rol', r.codigo, 'id_sucursal', i.id_sucursal,
      'sucursal', s.nombre, 'estado', i.estado, 'expira_at', i.expira_at
    ))
    from tbl_invitaciones i
    join tbl_comercios c on c.id_comercio = i.id_comercio
    join tbl_roles r on r.id_rol = i.id_rol
    left join tbl_sucursales s on s.id_sucursal = i.id_sucursal
    where lower(i.email) = v_email and i.estado = 'PENDIENTE' and i.expira_at > now()
  ), '[]'::jsonb));
end;
$fn$;
revoke execute on function rsuelvo.fn_mis_invitaciones_pendientes() from public;
grant execute on function rsuelvo.fn_mis_invitaciones_pendientes() to authenticated, service_role;

-- ── 4. fn_aceptar_invitacion (identidad SOLO del JWT) ──
create or replace function rsuelvo.fn_aceptar_invitacion(p_id_invitacion uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email text;
  v_inv record;
  v_estado_comercio text;
  v_codigo_rol text;
  v_vinculo uuid;
  v_cajeros integer;
begin
  select id_usuario, lower(email) into v_usuario, v_email from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;

  select * into v_inv from tbl_invitaciones where id = p_id_invitacion for update;
  if v_inv.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_existe');
  end if;
  if lower(v_inv.email) != v_email then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_ajena');
  end if;
  if v_inv.estado != 'PENDIENTE' or v_inv.expira_at <= now() then
    if v_inv.estado = 'PENDIENTE' then
      update tbl_invitaciones set estado = 'VENCIDA' where id = p_id_invitacion;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_vencida');
  end if;

  select estado into v_estado_comercio from tbl_comercios where id_comercio = v_inv.id_comercio;
  if v_estado_comercio is null or v_estado_comercio not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible');
  end if;

  select codigo into v_codigo_rol from tbl_roles where id_rol = v_inv.id_rol;
  if v_codigo_rol is null or v_codigo_rol = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;
  if v_inv.id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = v_inv.id_sucursal
                       and id_comercio = v_inv.id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;
  if v_codigo_rol = 'ROLE_LOGISTICS_AGENT' and v_inv.id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;
  -- N-4 intacto hasta IAM-2: regla global vigente
  if v_codigo_rol = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.activo and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  -- Idempotencia: vinculo equivalente ya activo -> aceptar sin duplicar
  select id into v_vinculo from tbl_usuario_comercio
  where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
    and id_rol = v_inv.id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
    and activo;
  if v_vinculo is null then
    insert into tbl_usuario_comercio
      (id_usuario, id_comercio, id_rol, id_sucursal, activo, estado, invited_by, accepted_at)
    values
      (v_usuario, v_inv.id_comercio, v_inv.id_rol, v_inv.id_sucursal, true, 'ACTIVE', v_inv.invited_by, now());
  end if;

  update tbl_invitaciones set estado = 'ACEPTADA', accepted_at = now() where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_aceptada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true, 'id_comercio', v_inv.id_comercio);
end;
$fn$;
revoke execute on function rsuelvo.fn_aceptar_invitacion(uuid) from public;
grant execute on function rsuelvo.fn_aceptar_invitacion(uuid) to authenticated, service_role;

-- ── 5. fn_revocar_invitacion (invitador / admin comercio / superadmin) ──
create or replace function rsuelvo.fn_revocar_invitacion(p_id_invitacion uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_inv record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;

  select * into v_inv from tbl_invitaciones where id = p_id_invitacion for update;
  if v_inv.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_existe');
  end if;
  if v_inv.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_pendiente');
  end if;
  if v_inv.invited_by != v_usuario
     and not fn_es_admin_comercio(v_inv.id_comercio)
     and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'sin_permiso');
  end if;

  update tbl_invitaciones set estado = 'REVOCADA' where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_revocada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_revocar_invitacion(uuid) from public;
grant execute on function rsuelvo.fn_revocar_invitacion(uuid) to authenticated, service_role;
