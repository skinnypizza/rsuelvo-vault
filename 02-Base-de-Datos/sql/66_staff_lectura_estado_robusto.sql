-- 66_staff_lectura_estado_robusto.sql
-- Auditoria P0 (hallazgos 1,3 + robustez): SUPPORT fuera de admin-tenant,
-- lecturas staff explicitas, EXECUTE restringido, maquina de estados,
-- bonus>=0, motivo de rechazo. HU roles expandidos, D17.

-- ── 1. fn_es_admin_comercio sin SUPPORT ─────────────────────────────────────
create or replace function rsuelvo.fn_es_admin_comercio(p_id_comercio uuid)
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        join tbl_roles r on r.id_rol=uc.id_rol
        where u.auth_user_id=auth.uid()
          and u.activo and uc.activo
          and uc.id_comercio=p_id_comercio
          and r.codigo = 'ROLE_TENANT_ADMIN'
      );
$fn$;

-- ── 2. Lectura staff (sysadmin/soporte, global, sin escritura) ──────────────
create or replace function rsuelvo.fn_lectura_staff()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select fn_es_service_role()
      or fn_es_superadmin()
      or fn_tiene_rol('ROLE_SYSADMIN')
      or fn_tiene_rol('ROLE_SUPPORT');
$fn$;

drop policy if exists staff_read on rsuelvo.tbl_comercios;
create policy staff_read on rsuelvo.tbl_comercios
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_comercio_config;
create policy staff_read on rsuelvo.tbl_comercio_config
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_cuentas_creditos;
create policy staff_read on rsuelvo.tbl_cuentas_creditos
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_movimientos_creditos;
create policy staff_read on rsuelvo.tbl_movimientos_creditos
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_sucursales;
create policy staff_read on rsuelvo.tbl_sucursales
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_canal_whatsapp;
create policy staff_read on rsuelvo.tbl_canal_whatsapp
  for select to authenticated using (rsuelvo.fn_lectura_staff());

-- Auditoria: sysadmin la conserva (matriz), support no (ya la pierde al salir de admin_fn)
drop policy if exists audit_sysadmin_select on rsuelvo.tbl_logs_auditoria;
create policy audit_sysadmin_select on rsuelvo.tbl_logs_auditoria
  for select to authenticated
  using (rsuelvo.fn_es_service_role()
    or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN'));

-- ── 3. EXECUTE: fuera PUBLIC, solo authenticated + service_role ─────────────
-- (incluye DROP del overload 8-params de fn_alta heredado de mig 58)
drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer);
revoke execute on function rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio) from public;
grant execute on function rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio) to authenticated, service_role;

revoke execute on function rsuelvo.fn_cambiar_estado_comercio(uuid, rsuelvo.estado_comercio) from public;
grant execute on function rsuelvo.fn_cambiar_estado_comercio(uuid, rsuelvo.estado_comercio) to authenticated, service_role;

revoke execute on function rsuelvo.fn_solicitar_creditos(uuid, text) from public;
grant execute on function rsuelvo.fn_solicitar_creditos(uuid, text) to authenticated, service_role;

revoke execute on function rsuelvo.fn_registrar_comprobante(uuid, uuid, text, text, numeric, timestamptz, text, text, rsuelvo.estado_comprobante, uuid, text) from public;
grant execute on function rsuelvo.fn_registrar_comprobante(uuid, uuid, text, text, numeric, timestamptz, text, text, rsuelvo.estado_comprobante, uuid, text) to authenticated, service_role;

-- ── 4. fn_alta: bonus>=0 (re-aplicada identica a mig 62 + guard) ───────
-- ── fn_alta_comercio: p_estado + coercion staff ──────────────────────────────
create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100,
  p_estado rsuelvo.estado_comercio default 'ACTIVO'
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT') then
    v_estado_final := 'PENDIENTE_APROBACION';
  else
    raise exception 'solo staff autorizado';
  end if;

  if v_estado_final not in ('ACTIVO', 'PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'estado_invalido');
  end if;

  if coalesce(p_bonus, 0) < 0 then
    return jsonb_build_object('ok', false, 'codigo', 'bonus_invalido');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;

  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final)
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', 'DESCONECTADO', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus
  );
end;
$fn$;



-- ── 5. fn_cambiar_estado: maquina de estados ─────────────────────────────────
create or replace function rsuelvo.fn_cambiar_estado_comercio(
  p_id_comercio uuid,
  p_estado rsuelvo.estado_comercio
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_anterior rsuelvo.estado_comercio;
  v_ok boolean := false;
begin
  if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  select estado into v_anterior
  from rsuelvo.tbl_comercios where id_comercio = p_id_comercio;

  if v_anterior is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;

  if v_anterior = p_estado then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cambio', 'estado', v_anterior);
  end if;

  v_ok := (v_anterior = 'PENDIENTE_APROBACION' and p_estado in ('ACTIVO','CANCELADO'))
       or (v_anterior = 'ACTIVO' and p_estado in ('SUSPENDIDO','BLOQUEADO','CANCELADO'))
       or (v_anterior = 'SUSPENDIDO' and p_estado in ('ACTIVO','BLOQUEADO','CANCELADO'))
       or (v_anterior = 'BLOQUEADO' and p_estado in ('ACTIVO','SUSPENDIDO'))
       or (v_anterior = 'CANCELADO' and p_estado = 'ACTIVO');

  if not v_ok then
    return jsonb_build_object('ok', false, 'codigo', 'transicion_invalida',
      'anterior', v_anterior, 'nuevo', p_estado);
  end if;

  update rsuelvo.tbl_comercios
  set estado = p_estado, updated_at = now()
  where id_comercio = p_id_comercio;

  return jsonb_build_object('ok', true, 'anterior', v_anterior, 'nuevo', p_estado);
end;
$fn$;

-- ── 6. fn_resolver_compra: p_motivo (nueva firma 3 params; DROP vieja abajo) ─
create or replace function rsuelvo.fn_resolver_compra_creditos(
  p_id_compra uuid,
  p_decision text,
  p_motivo text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT');
  v_c record;
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not rsuelvo.fn_es_admin_comercio(v_c.id_comercio) then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        motivo_rechazo = nullif(trim(coalesce(p_motivo,'')), ''),
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  if v_cuenta is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cuenta');
  end if;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$fn$;

drop function if exists rsuelvo.fn_resolver_compra_creditos(uuid, text);
