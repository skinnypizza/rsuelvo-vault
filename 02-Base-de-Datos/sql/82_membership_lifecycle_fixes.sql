-- 82_membership_lifecycle_fixes.sql
-- IAM-2B parche revision ChatGPT. NO reescribe mig 81.
-- 1) CAMBIAR mismo rol: UPDATE in-place (obligatorio CASHIER por N-4).
-- 2) accept/CREAR: tupla exacta primero, N-4 despues.
-- 3) CAMBIAR auditoria con id destino determinista.

-- ── fn_gestionar_vinculo rev2 ──
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

-- ── fn_aceptar_invitacion rev2: tupla exacta primero, N-4 despues ──
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
  v_vinc_estado text;
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

  -- FIX82-2 (accept): tupla exacta primero
  select id, estado into v_vinculo, v_vinc_estado from tbl_usuario_comercio
  where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
    and id_rol = v_inv.id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED')
  for update;
  if v_vinculo is not null then
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_vinculo;
  else
    if v_codigo_rol = 'ROLE_TENANT_CASHIER' then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = v_usuario and uc.id_comercio = v_inv.id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER';
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;
    begin
      insert into tbl_usuario_comercio
        (id_usuario, id_comercio, id_rol, id_sucursal, activo, estado, invited_by, accepted_at)
      values
        (v_usuario, v_inv.id_comercio, v_inv.id_rol, v_inv.id_sucursal, true, 'ACTIVE', v_inv.invited_by, now());
    exception when unique_violation then
      update tbl_usuario_comercio set estado = 'ACTIVE'
      where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
        and id_rol = v_inv.id_rol
        and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
          = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
        and estado = 'SUSPENDED';
    end;
  end if;

  update tbl_invitaciones set estado = 'ACEPTADA', accepted_at = now() where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_aceptada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true, 'id_comercio', v_inv.id_comercio);
end;
$fn$;
