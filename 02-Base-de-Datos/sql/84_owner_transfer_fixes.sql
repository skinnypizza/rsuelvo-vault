-- 84_owner_transfer_fixes.sql
-- IAM-4 hardening revision ChatGPT. NO reescribe mig 83.

-- ── 1. cancelar: solo origen o superadmin ──
create or replace function rsuelvo.fn_cancelar_transferencia(p_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_t record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_t from tbl_transferencias_propiedad where id = p_id for update;
  if v_t.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_existe');
  end if;
  if v_t.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_pendiente');
  end if;
  if v_t.propietario_origen != v_usuario and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'sin_permiso');
  end if;
  update tbl_transferencias_propiedad set estado = 'CANCELADA' where id = p_id;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_t.id_comercio, v_usuario, 'transferencia_cancelada', 'tbl_transferencias_propiedad', p_id);
  return jsonb_build_object('ok', true);
end;
$fn$;

-- ── 2+3. iniciar: sweep expiracion + unique_violation determinista ──
create or replace function rsuelvo.fn_iniciar_transferencia(p_id_comercio uuid, p_destino uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_tid uuid;
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
$fn$;

-- ── 4. auto-owner: solo si queda exactamente 1 admin ACTIVE ──
create or replace function rsuelvo.fn_uc_auto_owner()
returns trigger
language plpgsql security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text;
  v_prop uuid;
  v_admins integer;
begin
  if new.estado != 'ACTIVE' then return new; end if;
  select codigo into v_codigo from tbl_roles where id_rol = new.id_rol;
  if v_codigo != 'ROLE_TENANT_ADMIN' then return new; end if;
  select propietario_id into v_prop from tbl_comercios where id_comercio = new.id_comercio;
  if v_prop is not null then return new; end if;
  select count(*) into v_admins
  from tbl_usuario_comercio uc
  join tbl_roles r on r.id_rol = uc.id_rol
  where uc.id_comercio = new.id_comercio and uc.estado = 'ACTIVE'
    and r.codigo = 'ROLE_TENANT_ADMIN';
  if v_admins = 1 then
    update tbl_comercios set propietario_id = new.id_usuario, updated_at = now()
    where id_comercio = new.id_comercio;
  end if;
  return new;
end;
$fn$;

-- ── 5. responder: revalidar origen admin ACTIVE ──
create or replace function rsuelvo.fn_responder_transferencia(p_id uuid, p_acepta boolean)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_t record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_t from tbl_transferencias_propiedad where id = p_id for update;
  if v_t.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_existe');
  end if;
  if v_t.propietario_destino != v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_ajena');
  end if;
  if v_t.estado != 'PENDIENTE' or v_t.expira_at <= now() then
    if v_t.estado = 'PENDIENTE' then
      update tbl_transferencias_propiedad set estado = 'VENCIDA' where id = p_id;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_vencida');
  end if;
  if not p_acepta then
    update tbl_transferencias_propiedad set estado = 'RECHAZADA' where id = p_id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (v_t.id_comercio, v_usuario, 'transferencia_rechazada', 'tbl_transferencias_propiedad', p_id);
    return jsonb_build_object('ok', true, 'estado', 'RECHAZADA');
  end if;
  if not exists (select 1 from tbl_comercios
                 where id_comercio = v_t.id_comercio and propietario_id = v_t.propietario_origen) then
    return jsonb_build_object('ok', false, 'codigo', 'origen_ya_no_owner');
  end if;
  -- FIX84-5: origen debe seguir admin ACTIVE
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_t.propietario_origen and uc.id_comercio = v_t.id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'origen_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.id_comercio = v_t.id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  update tbl_comercios set propietario_id = v_usuario, updated_at = now()
  where id_comercio = v_t.id_comercio;
  update tbl_transferencias_propiedad set estado = 'ACEPTADA', accepted_at = now() where id = p_id;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_t.id_comercio, v_usuario, 'transferencia_aceptada', 'tbl_transferencias_propiedad', p_id);
  return jsonb_build_object('ok', true, 'estado', 'ACEPTADA');
end;
$fn$;
