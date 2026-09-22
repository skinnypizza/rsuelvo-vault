-- 95_auto_alta_firma_canonical.sql
-- IAM-8 parche: firma canonica sin p_email + reclamo de fila huerfana.
-- Elimina overload anterior (PostgREST ambiguo si conviven).

drop function if exists rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text, text);

create or replace function rsuelvo.fn_auto_alta_comercio(
  p_request_id uuid,
  p_nombre_comercio text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono_comercio text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email_auth text;
  v_email_ok boolean;
  v_codigo text := upper(trim(p_codigo_tienda));
  v_existente uuid;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_admins integer;
  v_owner uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    -- reclamo de fila huerfana por email (reparo EF retry)
    select email into v_email_auth from auth.users where id = v_auth;
    if v_email_auth is not null then
      update tbl_usuarios set auth_user_id = v_auth, updated_at = now()
      where lower(email) = lower(v_email_auth) and auth_user_id is null
      returning id_usuario into v_usuario;
    end if;
  end if;
  if v_usuario is null then
    insert into tbl_usuarios (auth_user_id, email, nombre, activo)
    select v_auth, au.email,
           coalesce(nullif(trim(au.raw_user_meta_data->>'nombre'), ''), 'Comerciante'),
           true
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

  select (email_confirmed_at is not null) into v_email_ok
  from auth.users where id = v_auth;
  if coalesce(v_email_ok, false) = false then
    return jsonb_build_object('ok', false, 'codigo', 'email_no_verificado');
  end if;

  select id_comercio into v_existente from tbl_auto_alta_requests
  where id_usuario = v_usuario and id_request = p_request_id;
  if v_existente is not null then
    return jsonb_build_object('ok', true, 'id_comercio', v_existente, 'repetido', true);
  end if;

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
  if nullif(trim(coalesce(p_nombre_comercio, '')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'nombre_invalido');
  end if;

  insert into tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, trim(p_nombre_comercio),
          nullif(trim(coalesce(p_telefono_comercio, '')), ''),
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
revoke execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text) from public;
grant execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text) to authenticated, service_role;
