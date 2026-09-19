-- 77_alta_metodo_default.sql
-- Alta crea metodo QR por defecto (fn_generar_cobro lo exige).

create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100,
  p_estado rsuelvo.estado_comercio default 'ACTIVO',
  p_id_solicitud uuid default null
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
  v_sol record;
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
$fn$;






drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio);
-- backfill pnid universal donde falta
-- (UNIQUE provider_phone_number_id es anti-D16 como el de numero en mig 60: fuera)
alter table rsuelvo.tbl_canal_whatsapp drop constraint if exists tbl_canal_whatsapp_provider_phone_number_id_key;
update rsuelvo.tbl_canal_whatsapp set provider_phone_number_id = '1275143265687773' where provider_phone_number_id is null;

drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio);
