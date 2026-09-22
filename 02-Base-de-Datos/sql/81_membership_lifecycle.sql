-- 81_membership_lifecycle.sql
-- IAM-2B backend. Implementa D-IAM-MEMBERSHIP.md rev2 + CAMBIAR atomico.
-- Depende de IAM-2A Flutter verificado (1160232). NO reescribe migs 68/79/80.

-- ── 1. anti-duplicado no-terminal (preflight limpio 2026-09-22) ──
create unique index if not exists uc_tupla_vigente_unica
  on rsuelvo.tbl_usuario_comercio
    (id_usuario, id_comercio, id_rol, coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000'))
  where estado in ('ACTIVE', 'SUSPENDED');

-- ── 2. trigger canonico activo = (estado = 'ACTIVE') ──
create or replace function rsuelvo.fn_uc_sincronizar_activo()
returns trigger
language plpgsql
set search_path to 'rsuelvo', 'public'
as $fn$
begin
  new.activo := (new.estado = 'ACTIVE');
  new.updated_at := now();
  return new;
end;
$fn$;
drop trigger if exists trg_uc_sincronizar_activo on rsuelvo.tbl_usuario_comercio;
create trigger trg_uc_sincronizar_activo
  before insert or update on rsuelvo.tbl_usuario_comercio
  for each row execute function rsuelvo.fn_uc_sincronizar_activo();

-- ── 3. fn_gestionar_vinculo: N-4 por comercio + SUSPENDER/REVOCAR/CAMBIAR ──
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
  v_nuevo_rol smallint;
  v_nueva_suc uuid;
  v_nuevo_codigo text;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if v_acc = 'CAMBIAR' then
    -- ── reemplazo atomico: (p_id_rol,p_id_sucursal)=viejo, (p_rol_nuevo,p_sucursal_nueva)=nuevo ──
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
    -- N-4 por comercio (solo si el destino es cajero y no lo era ya en este comercio)
    if v_nuevo_codigo = 'ROLE_TENANT_CASHIER' and p_rol_nuevo != v_row.id_rol then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER';
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;

    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;

    -- reutiliza semantica CREAR sobre el destino (misma transaccion)
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_rol_nuevo
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED'
    for update;
    if v_row.id is not null then
      update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
    else
      begin
        insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
        values (p_id_usuario, p_id_comercio, p_rol_nuevo, p_sucursal_nueva, 'ACTIVE');
      exception when unique_violation then
        update tbl_usuario_comercio set estado = 'ACTIVE'
        where id_usuario = p_id_usuario and id_comercio = p_id_comercio
          and id_rol = p_rol_nuevo
          and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
            = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
          and estado = 'SUSPENDED';
      end;
    end if;

    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
  end if;

  -- ── acciones simples ──
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

  -- N-4 por comercio + vigentes (rev2)
  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
      and uc.estado in ('ACTIVE','SUSPENDED')
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      -- idempotente si es la misma tupla vigente
      select id into v_row from tbl_usuario_comercio
      where id_usuario = p_id_usuario and id_comercio = p_id_comercio
        and id_rol = p_id_rol
        and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
          = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
        and estado in ('ACTIVE','SUSPENDED');
      if v_row.id is not null then
        update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
        return jsonb_build_object('ok', true, 'reactivado', true);
      end if;
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  -- semantica CREAR: ACTIVE→idempotente; SUSPENDED→misma fila; solo-REVOKED→nueva
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

revoke execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text, smallint, uuid) from public;
grant execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text, smallint, uuid) to authenticated, service_role;

-- ── 4. fn_aceptar_invitacion: SOLO N-4 por comercio + vigentes (resto IAM-1 intacto) ──
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
  -- N-4 por comercio + vigentes (rev2; resto intacto)
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

  select id into v_vinculo from tbl_usuario_comercio
  where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
    and id_rol = v_inv.id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED');
  if v_vinculo is null then
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
  else
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_vinculo;
  end if;

  update tbl_invitaciones set estado = 'ACEPTADA', accepted_at = now() where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_aceptada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true, 'id_comercio', v_inv.id_comercio);
end;
$fn$;
revoke execute on function rsuelvo.fn_aceptar_invitacion(uuid) from public;
grant execute on function rsuelvo.fn_aceptar_invitacion(uuid) to authenticated, service_role;

-- ── 5. fn_editar_usuario: cascada a SUSPENDED, sin auto-restaurar ──
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

  update tbl_usuarios
  set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
      apellido = coalesce(nullif(trim(p_apellido), ''), apellido),
      telefono = coalesce(nullif(trim(p_telefono), ''), telefono),
      activo = coalesce(p_activo, activo),
      updated_at = now()
  where id_usuario = p_id_usuario;

  if coalesce(p_activo, true) = false then
    -- rev2: SUSPENDED, no REVOKED; reactivar usuario NO restaura memberships
    update tbl_usuario_comercio set estado = 'SUSPENDED'
    where id_usuario = p_id_usuario and estado = 'ACTIVE';
  end if;

  return jsonb_build_object('ok', true, 'id_usuario', p_id_usuario);
end;
$fn$;

revoke execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) from public;
grant execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) to authenticated, service_role;

-- ── 6. backfill divergencia historica (ejecutado 2026-09-22: 1 fila fosil) ──
update rsuelvo.tbl_usuario_comercio set estado = 'SUSPENDED'
where estado = 'ACTIVE' and activo = false;

-- ── 7. N-4 tercer path: trigger de asignacion por comercio + vigentes (rev2) ──
create or replace function rsuelvo.fn_validar_asignacion_usuario_comercio()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_codigo rsuelvo.rol_codigo;
begin
  select codigo into v_codigo from rsuelvo.tbl_roles where id_rol=new.id_rol;

  if v_codigo in ('ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT')
     and new.id_sucursal is null then
    raise exception 'El rol % requiere una sucursal',v_codigo;
  end if;

  if v_codigo='ROLE_TENANT_CASHIER' then
    if exists (
      select 1
      from rsuelvo.tbl_usuario_comercio uc
      join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
      where uc.id_usuario=new.id_usuario
        and uc.id_comercio=new.id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo='ROLE_TENANT_CASHIER'
        and uc.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
    ) then
      raise exception 'Un cashier solo puede tener una asignación activa por comercio';
    end if;
  end if;

  return new;
end;
$$;
