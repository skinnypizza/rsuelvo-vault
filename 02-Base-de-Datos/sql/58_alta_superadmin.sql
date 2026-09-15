-- 58_alta_superadmin.sql
-- F8-slice backend: alta de comercios + cambio de estado + fix identificacion universal.
-- HU-105/106 (suspender/bloquear/reactivar) · D4 (alta self-service) · D13 (verif manual por defecto)
-- D15 (lanzamiento solo-manual) · D16 (numero universal: identificar no desambigua compartidos).
-- PostgREST: fns en schema rsuelvo (expuesto) -> RPC automatico; RETURNS jsonb;
--   errores de negocio como {ok:false} (patron casa), RAISE solo si no es superadmin.

-- ── fn_alta_comercio ─────────────────────────────────────────────────────────
create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
begin
  if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;

  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, p_nombre, p_telefono, p_email, 'ACTIVO')
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
    'id_sucursal', v_sucursal,
    'bonus', p_bonus
  );
end;
$fn$;

-- ── fn_cambiar_estado_comercio (HU-105/106) ───────────────────────────────────
create or replace function rsuelvo.fn_cambiar_estado_comercio(
  p_id_comercio uuid,
  p_estado rsuelvo.estado_comercio
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_anterior rsuelvo.estado_comercio;
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

  update rsuelvo.tbl_comercios
  set estado = p_estado, updated_at = now()
  where id_comercio = p_id_comercio;

  return jsonb_build_object('ok', true, 'anterior', v_anterior, 'nuevo', p_estado);
end;
$fn$;

-- ── Fix identificacion: numero/pnid compartido (universal) no desambigua ─────
-- Un solo canal activo -> lo devuelve (comportamiento actual intacto).
-- Varios (numero universal D16) -> vacio para que el llamador caiga a M1/M2.
create or replace function rsuelvo.fn_identificar_comercio_por_whatsapp(p_numero text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  with m as (
    select c.id_comercio, c.id_sucursal, c.provider::text as provider
    from tbl_canal_whatsapp c
    where c.numero = p_numero and c.activo
  )
  select * from m where (select count(*) from m) = 1;
$fn$;

create or replace function rsuelvo.fn_identificar_comercio_por_phone_number_id(p_pnid text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  with m as (
    select c.id_comercio, c.id_sucursal, c.provider::text as provider
    from tbl_canal_whatsapp c
    where c.provider_phone_number_id = p_pnid and c.activo
  )
  select * from m where (select count(*) from m) = 1;
$fn$;
