-- 94_auto_alta_v0.sql
-- IAM-8 backend. D-IAM-ONBOARDING.md rev3.
-- Estado, helper, idempotencia, auto-alta atomica, guards V0.

-- ── 1. estado ──
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'estado_comercio' and e.enumlabel = 'PENDIENTE_VERIFICACION') then
    alter type rsuelvo.estado_comercio add value 'PENDIENTE_VERIFICACION';
  end if;
end $$;

-- ── 2. helper NUEVO (pertenencia != habilitacion) ──
create or replace function rsuelvo.fn_comercio_habilitado(p_id_comercio uuid)
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select exists (select 1 from tbl_comercios
                 where id_comercio = p_id_comercio and estado = 'ACTIVO');
$fn$;
revoke execute on function rsuelvo.fn_comercio_habilitado(uuid) from public;
grant execute on function rsuelvo.fn_comercio_habilitado(uuid) to authenticated, service_role;

-- ── 3. idempotencia + intentos registro ──
create table if not exists rsuelvo.tbl_auto_alta_requests (
  id_usuario uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete cascade,
  id_request uuid not null,
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete cascade,
  created_at timestamptz not null default now(),
  constraint auto_alta_req_uniq unique (id_usuario, id_request)
);
alter table rsuelvo.tbl_auto_alta_requests enable row level security;
grant all on rsuelvo.tbl_auto_alta_requests to service_role;

create table if not exists rsuelvo.tbl_registro_intentos (
  id bigint generated always as identity primary key,
  email text not null,
  ip text null,
  created_at timestamptz not null default now()
);
create index if not exists reg_intentos_email_fecha
  on rsuelvo.tbl_registro_intentos (lower(email), created_at);
alter table rsuelvo.tbl_registro_intentos enable row level security;
grant all on rsuelvo.tbl_registro_intentos to service_role;

-- ── 4. fn_auto_alta_comercio ──
create or replace function rsuelvo.fn_auto_alta_comercio(
  p_request_id uuid,
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email_ok boolean;
  v_codigo text := upper(trim(p_codigo_tienda));
  v_existente uuid;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_admins integer;
  v_owner uuid;
begin
  -- identidad: JWT + tbl_usuarios activo (jamás params cliente)
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    -- auto-reparo de perfil (retry tras EF registro)
    insert into tbl_usuarios (auth_user_id, email, nombre, activo)
    select v_auth, au.email, coalesce(au.raw_user_meta_data->>'nombre', 'Comerciante'), true
    from auth.users au where au.id = v_auth
    on conflict (auth_user_id) do nothing
    returning id_usuario into v_usuario;
    if v_usuario is null then
      select id_usuario into v_usuario from tbl_usuarios where auth_user_id = v_auth and activo;
    end if;
    if v_usuario is null then
      return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
    end if;
  end if;

  -- email verificado: fuente server-side auth.users (jamás cliente)
  select (email_confirmed_at is not null) into v_email_ok
  from auth.users where id = v_auth;
  if coalesce(v_email_ok, false) = false then
    return jsonb_build_object('ok', false, 'codigo', 'email_no_verificado');
  end if;

  -- idempotencia: mismo user+request -> mismo comercio
  select id_comercio into v_existente from tbl_auto_alta_requests
  where id_usuario = v_usuario and id_request = p_request_id;
  if v_existente is not null then
    return jsonb_build_object('ok', true, 'id_comercio', v_existente, 'repetido', true);
  end if;

  -- rate-limit: 1 nuevo comercio / 24h (antiabuso, no vitalicio)
  if exists (select 1 from tbl_auto_alta_requests
             where id_usuario = v_usuario and created_at > now() - interval '24 hours') then
    return jsonb_build_object('ok', false, 'codigo', 'rate_limit');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;
  if exists (select 1 from tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;
  if nullif(trim(coalesce(p_nombre, '')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'nombre_invalido');
  end if;

  -- creacion atomica
  insert into tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, trim(p_nombre), nullif(trim(coalesce(p_telefono, '')), ''),
          (select email from tbl_usuarios where id_usuario = v_usuario), 'PENDIENTE_VERIFICACION')
  returning id_comercio into v_comercio;

  insert into tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, 10, false);

  insert into tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, coalesce(nullif(trim(p_sucursal), ''), 'Sucursal Principal'), true)
  returning id_sucursal into v_sucursal;

  insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
  values (v_usuario, v_comercio,
          (select id_rol from tbl_roles where codigo = 'ROLE_TENANT_ADMIN'),
          v_sucursal, 'ACTIVE');

  update tbl_comercios set propietario_id = v_usuario where id_comercio = v_comercio;

  insert into tbl_auto_alta_requests (id_usuario, id_request, id_comercio)
  values (v_usuario, p_request_id, v_comercio);

  -- postcondiciones
  select count(*) into v_admins
  from tbl_usuario_comercio uc join tbl_roles r on r.id_rol = uc.id_rol
  where uc.id_comercio = v_comercio and uc.estado = 'ACTIVE'
    and r.codigo = 'ROLE_TENANT_ADMIN';
  select propietario_id into v_owner from tbl_comercios where id_comercio = v_comercio;
  if v_admins != 1 or v_owner is distinct from v_usuario then
    raise exception 'postcondicion owner invalida';
  end if;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_comercio, v_usuario, 'auto_alta', 'tbl_comercios', v_comercio);

  return jsonb_build_object('ok', true, 'id_comercio', v_comercio,
    'codigo_tienda', v_codigo, 'estado', 'PENDIENTE_VERIFICACION',
    'id_sucursal', v_sucursal, 'repetido', false);
end;
$fn$;
revoke execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text, text) from public;
grant execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text, text) to authenticated, service_role;

-- ── 5. V0: solicitar requiere habilitado (cuerpo vivo 63) ──
CREATE OR REPLACE FUNCTION rsuelvo.fn_solicitar_creditos(p_id_paquete uuid, p_comprobante_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
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
  if not rsuelvo.fn_comercio_habilitado(v_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_habilitado');
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
$function$
;

-- ── 6. V0: transferir requiere ACTIVO ──
create or replace function rsuelvo.fn_iniciar_transferencia(p_id_comercio uuid, p_destino uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_tid uuid;
  v_estado_tmp rsuelvo.estado_comercio;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  if p_destino = v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_destino and uc.id_comercio = p_id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  -- FIX84-2: expiradas no bloquean (sweep antes de comprobar)
  select estado into v_estado_tmp from tbl_comercios where id_comercio = p_id_comercio;
  if coalesce(v_estado_tmp::text, '') <> 'ACTIVO' then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_habilitado');
  end if;
  update tbl_transferencias_propiedad set estado = 'VENCIDA'
  where id_comercio = p_id_comercio and estado = 'PENDIENTE' and expira_at <= now();
  if exists (select 1 from tbl_transferencias_propiedad
             where id_comercio = p_id_comercio and estado = 'PENDIENTE') then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end if;
  begin
    insert into tbl_transferencias_propiedad
      (id_comercio, propietario_origen, propietario_destino, initiated_by)
    values (p_id_comercio, v_usuario, p_destino, v_usuario)
    returning id into v_tid;
  exception when unique_violation then
    -- FIX84-3: carrera -> determinista, sin excepcion SQL
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'transferencia_iniciada', 'tbl_transferencias_propiedad', v_tid);
  return jsonb_build_object('ok', true, 'id_transferencia', v_tid);
end;
$fn$;;

-- ── 7. V0: QR solo habilitado (lectura publica de pago intacta) ──
drop policy if exists qr_pagos_dueno_insert on storage.objects;
create policy qr_pagos_dueno_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'qr-pagos'
    and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
    and rsuelvo.fn_es_admin_comercio((split_part(name, '/', 1))::uuid)
    and rsuelvo.fn_comercio_habilitado((split_part(name, '/', 1))::uuid));

drop policy if exists qr_pagos_dueno_update on storage.objects;
create policy qr_pagos_dueno_update on storage.objects
  for update to authenticated
  using (bucket_id = 'qr-pagos'
    and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
    and rsuelvo.fn_es_admin_comercio((split_part(name, '/', 1))::uuid)
    and rsuelvo.fn_comercio_habilitado((split_part(name, '/', 1))::uuid))
  with check (bucket_id = 'qr-pagos'
    and rsuelvo.fn_comercio_habilitado((split_part(name, '/', 1))::uuid));
