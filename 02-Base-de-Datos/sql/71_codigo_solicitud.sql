-- 71_codigo_solicitud.sql
-- Codigo de 3 caracteres elegible desde la solicitud: propuesta + reserva +
-- sugerencias + consumo en el alta + linaje. HU D17 extension.

-- ── Solicitud: codigo propuesto (reserva = UNIQUE parcial en PENDIENTE/APROBADA)
alter table rsuelvo.tbl_solicitudes_alta
  add column if not exists codigo_sugerido text;

create unique index if not exists uq_solicitud_codigo_reserva
  on rsuelvo.tbl_solicitudes_alta (codigo_sugerido)
  where codigo_sugerido is not null and estado in ('PENDIENTE','APROBADA');

-- ── Linaje comercio <- solicitud
alter table rsuelvo.tbl_comercios
  add column if not exists id_solicitud uuid references rsuelvo.tbl_solicitudes_alta(id_solicitud);

-- ── Normalizacion de codigo (mayus, sin O, 3 alnum). NULL si invalido.
create or replace function rsuelvo.fn_normalizar_codigo(p_codigo text)
returns text
language sql immutable
set search_path to 'rsuelvo', 'public'
as $fn$
  select case
    when upper(regexp_replace(coalesce(trim(p_codigo),''), '[^A-Z0-9]', '', 'gi')) ~ '^[A-Z0-9]{3}$'
     and position('O' in upper(regexp_replace(coalesce(trim(p_codigo),''), '[^A-Z0-9]', '', 'gi'))) = 0
    then upper(regexp_replace(coalesce(trim(p_codigo),''), '[^A-Z0-9]', '', 'gi'))
  end;
$fn$;

-- ── Sugerencias (anonimo: sin auth, solo lectura). Max 5.
create or replace function rsuelvo.fn_sugerir_codigo(p_base text)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_clean text := upper(regexp_replace(coalesce(trim(p_base),''), '[^A-Z0-9]', '', 'gi'));
  v_base text := '';
  v_out text[] := '{}';
  v_cand text;
  v_letras constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ123456789';
  i integer;
  j integer;
begin
  -- base: 3 exactos validos, o primeros 3 si vienen de mas (sin O); si no, ABC
  if v_clean ~ '^[A-Z0-9]{3}$' and position('O' in v_clean) = 0 then
    v_base := v_clean;
  elsif length(v_clean) >= 3
    and substr(v_clean, 1, 3) ~ '^[A-Z0-9]{3}$'
    and position('O' in substr(v_clean, 1, 3)) = 0 then
    v_base := substr(v_clean, 1, 3);
  else
    v_base := 'ABC';
  end if;

  -- 1. la base si esta libre (comercios + reservas vivas)
  if not exists (select 1 from tbl_comercios where codigo_tienda = v_base)
     and not exists (select 1 from tbl_solicitudes_alta
                     where codigo_sugerido = v_base and estado in ('PENDIENTE','APROBADA')) then
    v_out := v_out || v_base;
  end if;

  -- 2. variantes cambiando ultimo char
  for j in 1..length(v_letras) loop
    exit when array_length(v_out, 1) >= 5;
    v_cand := substr(v_base, 1, 2) || substr(v_letras, j, 1);
    if v_cand = v_base then continue; end if;
    if not exists (select 1 from tbl_comercios where codigo_tienda = v_cand)
       and not exists (select 1 from tbl_solicitudes_alta
                       where codigo_sugerido = v_cand and estado in ('PENDIENTE','APROBADA')) then
      v_out := v_out || v_cand;
    end if;
  end loop;

  -- 3. variantes cambiando segundo char (si faltan)
  for j in 1..length(v_letras) loop
    exit when array_length(v_out, 1) >= 5;
    v_cand := substr(v_base, 1, 1) || substr(v_letras, j, 1) || substr(v_base, 3, 1);
    if v_cand = any (v_out) then continue; end if;
    if not exists (select 1 from tbl_comercios where codigo_tienda = v_cand)
       and not exists (select 1 from tbl_solicitudes_alta
                       where codigo_sugerido = v_cand and estado in ('PENDIENTE','APROBADA')) then
      v_out := v_out || v_cand;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'base', v_base, 'sugerencias', to_jsonb(v_out));
end;
$fn$;

revoke execute on function rsuelvo.fn_sugerir_codigo(text) from public;
grant execute on function rsuelvo.fn_sugerir_codigo(text) to anon, authenticated, service_role;

-- ── Alta consume reserva (p_id_solicitud opcional) ───────────────────────────
-- NOTA: re-aplica fn completa identica a mig 66 + bloque solicitud (parche abajo).
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

  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', 'DESCONECTADO', true);

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
