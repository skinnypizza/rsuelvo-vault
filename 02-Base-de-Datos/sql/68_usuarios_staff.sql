-- 68_usuarios_staff.sql
-- Auditoria: CRUD global usuarios (superadmin) + invariantes de vinculos.
-- HU roles expandidos. Protegidos: SUPERADMIN (no editar/asignar/desactivar),
-- ultimo superadmin implicito (solo existe 1: el dueño).

-- ── fn_editar_usuario ───────────────────────────────────────────────────────
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
    update tbl_usuario_comercio set activo = false
    where id_usuario = p_id_usuario and activo;
  end if;

  return jsonb_build_object('ok', true, 'id_usuario', p_id_usuario);
end;
$fn$;

-- ── fn_gestionar_vinculo ────────────────────────────────────────────────────
create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,
  p_id_comercio uuid,
  p_id_rol smallint,
  p_id_sucursal uuid default null,
  p_accion text default 'CREAR'
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_acc text := upper(trim(coalesce(p_accion,'CREAR')));
  v_codigo text;
  v_estado text;
  v_existente uuid;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  select codigo into v_codigo from tbl_roles where id_rol = p_id_rol;
  if v_codigo is null then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;
  if v_codigo = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'protegido');
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  if v_acc = 'DESACTIVAR' then
    select id into v_existente from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and activo;
    if v_existente is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set activo = false where id = v_existente;
    return jsonb_build_object('ok', true, 'nuevo', 'DESACTIVADO');
  end if;

  if v_acc != 'CREAR' then
    return jsonb_build_object('ok', false, 'codigo', 'accion_invalida');
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

  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.activo
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  select id into v_existente from tbl_usuario_comercio
  where id_usuario = p_id_usuario and id_comercio = p_id_comercio
    and id_rol = p_id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000');
  if v_existente is not null then
    update tbl_usuario_comercio set activo = true where id = v_existente;
    return jsonb_build_object('ok', true, 'reactivado', true);
  end if;

  insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, activo)
  values (p_id_usuario, p_id_comercio, p_id_rol, p_id_sucursal, true);

  return jsonb_build_object('ok', true, 'reactivado', false);
end;
$fn$;

revoke execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) from public;
grant execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) to authenticated, service_role;

revoke execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text) from public;
grant execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text) to authenticated, service_role;
