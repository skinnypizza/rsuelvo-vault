-- Preserve the explicit product decision: a commerce owner may complete V0→V1
-- enablement at AAL1. Step-up MFA remains in place for the other protected
-- operations and in the restrictive RLS policies introduced by email MFA.
-- This forward migration removes the two guards reintroduced by
-- 20260930212303/email_second_factor. Owner, checks, row lock, transaction,
-- verification record and audit behavior are unchanged.
create or replace function rsuelvo.fn_solicitar_habilitacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog', 'rsuelvo', 'public', 'pg_temp'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
  v_res jsonb;
  v_faltantes text[];
  v_vid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
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
