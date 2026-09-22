-- 96_verificacion_v1.sql
-- IAM-9 backend. D-IAM-VERIFICACION.md rev2 + GO ChatGPT.
-- V1 = PERFIL COMERCIAL DECLARATIVO COMPLETO (nunca "empresa verificada").

-- ── 1. evidencia append-only ──
create table if not exists rsuelvo.tbl_verificaciones_comercio (
  id_verificacion uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete cascade,
  nivel text not null default 'V1',
  estado text not null,
  origen text not null,
  id_verificador uuid null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  checks_snapshot jsonb not null,
  motivo text null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  revoked_at timestamptz null,
  revoked_by uuid null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  motivo_revocacion text null,
  constraint verif_estado_chk check (estado in ('APROBADA_AUTOMATICA','APROBADA_MANUAL','RECHAZADA','REVOCADA')),
  constraint verif_origen_chk check (origen in ('SYSTEM','SUPERADMIN')),
  constraint verif_nivel_chk check (nivel = 'V1')
);
alter table rsuelvo.tbl_verificaciones_comercio enable row level security;
grant all on rsuelvo.tbl_verificaciones_comercio to service_role;

-- ── 2. builder de checks (server-side, nombres exactos) ──
create or replace function rsuelvo.fn_checks_verificacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_c record;
  v_owner uuid;
  v_email_ok boolean;
  v_suc_ok boolean;
  v_qr_ok boolean;
  v_cfg_ok boolean;
  v_nit text;
  v_razon text;
  v_tel text;
begin
  select * into v_c from tbl_comercios where id_comercio = p_id_comercio;
  if v_c.id_comercio is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  v_owner := v_c.propietario_id;
  v_nit := upper(trim(coalesce(v_c.nit, '')));
  v_razon := trim(coalesce(v_c.razon_social, ''));
  v_tel := trim(coalesce(v_c.telefono, ''));

  if v_owner is not null then
    select (email_confirmed_at is not null) into v_email_ok
    from auth.users au join tbl_usuarios u on u.auth_user_id = au.id
    where u.id_usuario = v_owner;
  end if;

  select exists (
    select 1 from tbl_sucursales
    where id_comercio = p_id_comercio and activo
      and nullif(trim(coalesce(direccion, '')), '') is not null
  ) into v_suc_ok;

  select exists (
    select 1 from storage.objects
    where bucket_id = 'qr-pagos' and name like p_id_comercio::text || '/%'
  ) into v_qr_ok;

  select exists (
    select 1 from tbl_comercio_config
    where id_comercio = p_id_comercio
      and tiempo_reserva_minutos between 1 and 1440
  ) into v_cfg_ok;

  return jsonb_build_object(
    'ok', true,
    'checks', jsonb_build_object(
      'nit', jsonb_build_object('pass', v_nit ~ '^[0-9]{5,20}$', 'mode', 'syntactic_only'),
      'razon_social', jsonb_build_object('pass', v_razon <> '' and length(v_razon) <= 200),
      'telefono', jsonb_build_object('pass', v_tel ~ '^[0-9+\s]{7,20}$', 'mode', 'present_unverified'),
      'email_owner', jsonb_build_object('pass', coalesce(v_email_ok, false), 'mode', 'auth_confirmed'),
      'sucursal', jsonb_build_object('pass', v_suc_ok),
      'qr', jsonb_build_object('pass', v_qr_ok),
      'config', jsonb_build_object('pass', v_cfg_ok)
    )
  );
end;
$fn$;
revoke execute on function rsuelvo.fn_checks_verificacion_v1(uuid) from public;
grant execute on function rsuelvo.fn_checks_verificacion_v1(uuid) to authenticated, service_role;

-- ── 3. consulta (sin mutar) ──
create or replace function rsuelvo.fn_estado_verificacion_comercio(p_id_comercio uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_res jsonb;
  v_faltantes text[];
  v_k text;
begin
  if not (fn_es_service_role() or fn_es_superadmin()
          or fn_es_admin_comercio(p_id_comercio)) then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  v_res := fn_checks_verificacion_v1(p_id_comercio);
  if (v_res ->> 'ok')::boolean = false then return v_res; end if;
  select array_agg(k) into v_faltantes
  from jsonb_object_keys(v_res -> 'checks') k
  where ((v_res -> 'checks' -> k ->> 'pass')::boolean) = false;
  return jsonb_build_object('ok', true, 'checks', v_res -> 'checks',
    'faltantes', coalesce(v_faltantes, '{}'));
end;
$fn$;
revoke execute on function rsuelvo.fn_estado_verificacion_comercio(uuid) from public;
grant execute on function rsuelvo.fn_estado_verificacion_comercio(uuid) to authenticated, service_role;

-- ── 4. habilitacion (owner + AAL2, atomica, idempotente) ──
create or replace function rsuelvo.fn_solicitar_habilitacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
  v_res jsonb;
  v_faltantes text[];
  v_k text;
  v_vid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) and not fn_es_service_role() then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;

  -- lock + recheck (concurrencia: una sola transicion efectiva)
  select estado into v_estado from tbl_comercios
  where id_comercio = p_id_comercio for update;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'ACTIVO' then
    return jsonb_build_object('ok', true, 'codigo', 'ya_activo');
  end if;
  if v_estado != 'PENDIENTE_VERIFICACION' then
    return jsonb_build_object('ok', false, 'codigo', 'estado_incompatible');
  end if;

  v_res := fn_checks_verificacion_v1(p_id_comercio);
  select array_agg(k) into v_faltantes
  from jsonb_object_keys(v_res -> 'checks') k
  where ((v_res -> 'checks' -> k ->> 'pass')::boolean) = false;

  if v_faltantes is not null then
    insert into tbl_verificaciones_comercio
      (id_comercio, estado, origen, id_verificador, checks_snapshot, motivo, resolved_at)
    values (p_id_comercio, 'RECHAZADA', 'SYSTEM', v_usuario,
            v_res -> 'checks', 'faltantes: ' || array_to_string(v_faltantes, ','), now());
    return jsonb_build_object('ok', false, 'codigo', 'requisitos_faltantes',
      'faltantes', v_faltantes);
  end if;

  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot, resolved_at)
  values (p_id_comercio, 'APROBADA_AUTOMATICA', 'SYSTEM', v_usuario,
          v_res -> 'checks', now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'ACTIVO', updated_at = now()
  where id_comercio = p_id_comercio;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_aprobada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true, 'codigo', 'habilitado');
end;
$fn$;
revoke execute on function rsuelvo.fn_solicitar_habilitacion_v1(uuid) from public;
grant execute on function rsuelvo.fn_solicitar_habilitacion_v1(uuid) to authenticated, service_role;

-- ── 5. revocacion SuperAdmin (V1->V0 + REVOCADA; fraude = flujo aparte) ──
create or replace function rsuelvo.fn_revocar_verificacion_v1(
  p_id_comercio uuid, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_vid uuid;
  v_checks jsonb;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  v_checks := (fn_checks_verificacion_v1(p_id_comercio) -> 'checks');
  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot,
     motivo_revocacion, revoked_at, revoked_by, resolved_at)
  values (p_id_comercio, 'REVOCADA', 'SUPERADMIN', v_usuario, v_checks,
          nullif(trim(coalesce(p_motivo, ' ')), ''), now(), v_usuario, now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'PENDIENTE_VERIFICACION', updated_at = now()
  where id_comercio = p_id_comercio and estado = 'ACTIVO';

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_revocada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_revocar_verificacion_v1(uuid, text) from public;
grant execute on function rsuelvo.fn_revocar_verificacion_v1(uuid, text) to authenticated, service_role;
