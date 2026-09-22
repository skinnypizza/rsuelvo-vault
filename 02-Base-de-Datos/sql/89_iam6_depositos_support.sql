-- 89_iam6_depositos_support.sql
-- IAM-6 DB (paso 1, para revision antes de clientes).
-- N-6 DB+Storage (credits.deposit.read congelado: SUPERADMIN + OWNER mismo
-- comercio; SYSADMIN/SUPPORT DENY) + SUPPORT fuera de writes. Helpers
-- compartidos INTACTOS (dependency audit: 46 policies los usan; ventas/n8n
-- a salvo). Export server-side: no existe RPC frontera -> best-effort
-- documentado, sin cambio DB.

-- ── 1. N-6 tabla ──
drop policy if exists compras_select on rsuelvo.tbl_compras_creditos;
create policy compras_select on rsuelvo.tbl_compras_creditos
  for select to authenticated
  using (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_es_owner(id_comercio));

drop policy if exists credit_purchases_select on rsuelvo.tbl_compras_creditos;
create policy credit_purchases_select on rsuelvo.tbl_compras_creditos
  for select to authenticated
  using (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_es_owner(id_comercio));

-- ── 2. N-6 storage ──
drop policy if exists depositos_staff_select on storage.objects;
create policy depositos_staff_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
     and rsuelvo.fn_es_superadmin());

drop policy if exists depositos_dueno_select on storage.objects;
create policy depositos_dueno_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
     and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
     and rsuelvo.fn_es_owner((split_part(name, '/', 1))::uuid));
-- parche IAM-6 aplicado sobre cuerpo vivo 66
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_compra_creditos(p_id_compra uuid, p_decision text, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN');
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
    if not (rsuelvo.fn_es_superadmin() or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')) then
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
$function$
;
-- parche IAM-6: SUPPORT fuera de alta (cuerpo vivo)
CREATE OR REPLACE FUNCTION rsuelvo.fn_alta_comercio(p_nombre text, p_codigo_tienda text, p_sucursal text DEFAULT 'Sucursal Principal'::text, p_telefono text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_reserva_min integer DEFAULT 10, p_verificacion_automatica boolean DEFAULT false, p_bonus integer DEFAULT 100, p_estado rsuelvo.estado_comercio DEFAULT 'ACTIVO'::rsuelvo.estado_comercio, p_id_solicitud uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_sol record;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') then
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

  if p_id_solicitud is not null then
    select id_solicitud, codigo_sugerido, estado into v_sol
    from rsuelvo.tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
    if not found then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
    end if;
    if v_sol.estado != 'APROBADA' then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_aprobada');
    end if;
    if v_sol.codigo_sugerido is null then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_sin_codigo');
    end if;
    if exists (select 1 from rsuelvo.tbl_comercios where id_solicitud = p_id_solicitud) then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_consumida');
    end if;
    if upper(trim(p_codigo_tienda)) != v_sol.codigo_sugerido then
      return jsonb_build_object('ok', false, 'codigo', 'codigo_mismatch');
    end if;
    v_codigo := v_sol.codigo_sugerido;
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;



  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado, id_solicitud)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final, p_id_solicitud)
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

  -- D16: numero universal; pnid universal por defecto (por comercio a futuro)
  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, provider_phone_number_id, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', '1275143265687773', 'DESCONECTADO', true);

  -- metodo de pago por defecto (fn_generar_cobro lo exige)
  insert into rsuelvo.tbl_metodos_pago (id_comercio, nombre, tipo, activo)
  values (v_comercio, 'QR Estático', 'QR', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus,
    'id_solicitud', p_id_solicitud
  );
end;
$function$
;
