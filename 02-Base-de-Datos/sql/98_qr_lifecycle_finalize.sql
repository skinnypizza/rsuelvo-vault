-- 98_qr_lifecycle_finalize.sql
-- IAM-9 parche revision ChatGPT. NO reescribe migs 96/97.
-- 1) service_role fuera de solicitar (solo humanos owner+AAL2).
-- 2) staging->operativo via EF + finalize (sin fingir atomicidad DB+Storage).

-- ── 1. grants ──
revoke execute on function rsuelvo.fn_solicitar_habilitacion_v1(uuid) from service_role;

-- ── 2. solicitar: QR solo-staging no transiciona ──
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
  v_qr_operativo boolean;
  v_vid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;

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

  -- QR solo en staging: no transiciona; la EF publica y finaliza
  select exists (
    select 1 from storage.objects
    where bucket_id = 'qr-pagos' and name like p_id_comercio::text || '/%'
  ) into v_qr_operativo;
  if not v_qr_operativo then
    return jsonb_build_object('ok', false, 'codigo', 'qr_por_publicar');
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

-- ── 3. finalize (llamada solo por EF tras publicar; idempotente) ──
create or replace function rsuelvo.fn_finalizar_habilitacion_v1(p_id_comercio uuid)
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
  v_qr_operativo boolean;
  v_vid uuid;
begin
  -- Solo service_role (EF) o owner+AAL2 humano
  if coalesce(auth.jwt()->>'role', '') = 'service_role' then
    select propietario_id into v_usuario from tbl_comercios
    where id_comercio = p_id_comercio;
  else
    select id_usuario into v_usuario from tbl_usuarios
    where auth_user_id = v_auth and activo;
    if v_usuario is null then
      return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
    end if;
    if not fn_tiene_aal2() then
      return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
    end if;
    if not fn_es_owner(p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
    end if;
  end if;

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
    return jsonb_build_object('ok', false, 'codigo', 'requisitos_faltantes',
      'faltantes', v_faltantes);
  end if;

  -- exige QR operativo confirmado (la EF ya lo publico)
  select exists (
    select 1 from storage.objects
    where bucket_id = 'qr-pagos' and name like p_id_comercio::text || '/%'
  ) into v_qr_operativo;
  if not v_qr_operativo then
    return jsonb_build_object('ok', false, 'codigo', 'qr_por_publicar');
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
revoke execute on function rsuelvo.fn_finalizar_habilitacion_v1(uuid) from public;
grant execute on function rsuelvo.fn_finalizar_habilitacion_v1(uuid) to authenticated, service_role;
