-- 86_mfa_aal2_guards.sql
-- IAM-5 backend. Helper canonico + guards en operaciones criticas.
-- service_role conserva paths (passthrough primero).

-- ── 1. helper ──
create or replace function rsuelvo.fn_tiene_aal2()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select case
    when coalesce(auth.jwt()->>'role', '') = 'service_role' then true
    else coalesce(auth.jwt()->>'aal', '') = 'aal2'
  end;
$fn$;
revoke execute on function rsuelvo.fn_tiene_aal2() from public;
grant execute on function rsuelvo.fn_tiene_aal2() to authenticated, service_role;

-- ── 2. guards: transferencia iniciar/responder/cerrar/gestionar/editar-off ──
-- Patron por funcion: tras resolver identidad humana (no service_role),
-- exigir fn_tiene_aal2() o devolver {ok:false,codigo:'mfa_requerido'}.
-- Se aplica con CREATE OR REPLACE minimos que preservan cada cuerpo.

-- ── iniciar transferencia (guard tras identidad) ──
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
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
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
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'transferencia_iniciada', 'tbl_transferencias_propiedad', v_tid);
  return jsonb_build_object('ok', true, 'id_transferencia', v_tid);
end;
$fn$;

-- ── responder transferencia (guard tras identidad) ──
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
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
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

-- ── cerrar comercio (guard tras identidad) ──
create or replace function rsuelvo.fn_cerrar_comercio(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'CANCELADO' then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cambio');
  end if;
  update tbl_comercios set estado = 'CANCELADO', updated_at = now()
  where id_comercio = p_id_comercio;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'comercio_cerrado', 'tbl_comercios', p_id_comercio);
  return jsonb_build_object('ok', true, 'anterior', v_estado, 'nuevo', 'CANCELADO');
end;
$fn$;

-- ── editar rev3: guard solo en rama desactivacion ──
create or replace function rsuelvo.fn_editar_usuario(
  p_id_usuario uuid,
  p_nombre text default null,
  p_apellido text default null,
  p_telefono text default null,
  p_activo boolean default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_tiene_super boolean;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.activo
      and r.codigo = 'ROLE_SUPERADMIN'
  ) into v_tiene_super;

  if v_tiene_super then
    return jsonb_build_object('ok', false, 'codigo', 'protegido');
  end if;

  if coalesce(p_activo, true) = false then
    if not fn_es_service_role() and not fn_tiene_aal2() then
      return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
    end if;
    if exists (select 1 from tbl_comercios c
               join tbl_usuario_comercio uc on uc.id_usuario = c.propietario_id
                 and uc.id_comercio = c.id_comercio
               join tbl_roles r on r.id_rol = uc.id_rol
               where c.propietario_id = p_id_usuario
                 and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
  end if;

  update tbl_usuarios
  set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
      apellido = coalesce(nullif(trim(p_apellido), ''), apellido),
      telefono = coalesce(nullif(trim(p_telefono), ''), telefono),
      activo = coalesce(p_activo, activo),
      updated_at = now()
  where id_usuario = p_id_usuario;

  if coalesce(p_activo, true) = false then
    update tbl_usuario_comercio set estado = 'SUSPENDED'
    where id_usuario = p_id_usuario and estado = 'ACTIVE';
  end if;

  return jsonb_build_object('ok', true, 'id_usuario', p_id_usuario);
end;
$fn$;

-- ── gestionar rev4: AAL guard + anti-degradar owner (ensamblado de 82+83) ──
create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,
  p_id_comercio uuid,
  p_id_rol smallint,
  p_id_sucursal uuid default null,
  p_accion text default 'CREAR',
  p_rol_nuevo smallint default null,
  p_sucursal_nueva uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_acc text := upper(trim(coalesce(p_accion,'CREAR')));
  v_codigo text;
  v_estado text;
  v_row record;
  v_dest_id uuid;
  v_nuevo_codigo text;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;

  if v_acc = 'CAMBIAR' then
    if p_rol_nuevo is null then
      return jsonb_build_object('ok', false, 'codigo', 'falta_rol_nuevo');
    end if;
    select * into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    -- owner: solo in-place mismo rol; cualquier cambio de tupla requiere transferencia previa
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) and p_rol_nuevo != v_row.id_rol then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;

    select codigo into v_nuevo_codigo from tbl_roles where id_rol = p_rol_nuevo;
    if v_nuevo_codigo is null or v_nuevo_codigo = 'ROLE_SUPERADMIN' then
      return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
    end if;
    if p_sucursal_nueva is not null
       and not exists (select 1 from tbl_sucursales
                       where id_sucursal = p_sucursal_nueva
                         and id_comercio = p_id_comercio and activo) then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
    end if;
    if v_nuevo_codigo = 'ROLE_LOGISTICS_AGENT' and p_sucursal_nueva is null then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
    end if;

    -- FIX82-1: mismo rol -> UPDATE in-place (sin segunda fila; N-4 no aplica)
    if p_rol_nuevo = v_row.id_rol then
      update tbl_usuario_comercio
      set id_sucursal = p_sucursal_nueva, estado = 'ACTIVE'
      where id = v_row.id;
      insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
      values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_row.id);
      return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
    end if;

    -- N-4 por comercio (cambio de rol a cajero)
    if v_nuevo_codigo = 'ROLE_TENANT_CASHIER' then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER'
        and uc.id <> v_row.id;
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;

    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;

    select id into v_dest_id from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_rol_nuevo
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED'
    for update;
    if v_dest_id is not null then
      update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_dest_id;
    else
      begin
        insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
        values (p_id_usuario, p_id_comercio, p_rol_nuevo, p_sucursal_nueva, 'ACTIVE')
        returning id into v_dest_id;
      exception when unique_violation then
        update tbl_usuario_comercio set estado = 'ACTIVE'
        where id_usuario = p_id_usuario and id_comercio = p_id_comercio
          and id_rol = p_rol_nuevo
          and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
            = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
          and estado = 'SUSPENDED'
        returning id into v_dest_id;
      end;
    end if;

    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_dest_id);
    return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
  end if;

  if v_acc in ('DESACTIVAR','SUSPENDER') then
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'ACTIVE'
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_suspendido', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'SUSPENDIDO');
  end if;

  if v_acc = 'REVOCAR' then
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'REVOKED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_revocado', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'REVOCADO');
  end if;

  if v_acc != 'CREAR' then
    return jsonb_build_object('ok', false, 'codigo', 'accion_invalida');
  end if;

  select codigo into v_codigo from tbl_roles where id_rol = p_id_rol;
  if v_codigo is null or v_codigo = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible', 'estado', v_estado);
  end if;

  if p_id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = p_id_sucursal
                       and id_comercio = p_id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  if v_codigo = 'ROLE_LOGISTICS_AGENT' and p_id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;

  -- FIX82-2 (gestionar): tupla exacta primero; N-4 solo si no existe
  select id, estado into v_row from tbl_usuario_comercio
  where id_usuario = p_id_usuario and id_comercio = p_id_comercio
    and id_rol = p_id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED')
  for update;
  if v_row.id is not null then
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
    return jsonb_build_object('ok', true, 'reactivado', v_row.estado = 'SUSPENDED');
  end if;

  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
      and uc.estado in ('ACTIVE','SUSPENDED')
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  begin
    insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
    values (p_id_usuario, p_id_comercio, p_id_rol, p_id_sucursal, 'ACTIVE');
  exception when unique_violation then
    update tbl_usuario_comercio set estado = 'ACTIVE'
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED';
  end;
  return jsonb_build_object('ok', true, 'reactivado', false);
end;
$fn$;
