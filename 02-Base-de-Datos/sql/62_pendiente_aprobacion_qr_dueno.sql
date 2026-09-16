-- 62_pendiente_aprobacion_qr_dueno.sql
-- D17 + roles expandidos: alta con estado (staff->pendiente), cuarentena de no-ACTIVO,
-- QR del dueño (tenant). HU-105/106, F8-slice.
-- NOTA: el `alter type ... add value` va en llamada SEPARADA (no corre en bloque txn).

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

-- ── Cuarentena D17: identificar exige comercio ACTIVO ────────────────────────
create or replace function rsuelvo.fn_identificar_comercio_por_whatsapp(p_numero text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  with m as (
    select c.id_comercio, c.id_sucursal, c.provider::text as provider
    from tbl_canal_whatsapp c
    join tbl_comercios co on co.id_comercio = c.id_comercio
    where c.numero = p_numero and c.activo and co.estado = 'ACTIVO'
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
    join tbl_comercios co on co.id_comercio = c.id_comercio
    where c.provider_phone_number_id = p_pnid and c.activo and co.estado = 'ACTIVO'
  )
  select * from m where (select count(*) from m) = 1;
$fn$;

-- ── Cuarentena D17: resolver SKU exige comercio ACTIVO ───────────────────────
create or replace function rsuelvo.fn_resolver_sku_universal(p_sku text)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $function$
declare
  v_sku text := replace(upper(trim(coalesce(p_sku,''))), 'O', '0');
  v_comercio uuid;
  v_com_estado text;
  v_var record;
  v_n integer;
  v_cand record;
  v_ef_nom text;
  v_ef_pre numeric;
  v_ef_act boolean;
begin
  if v_sku !~ '^[A-Z0-9]{6}$' then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','FORMATO_INVALIDO');
  end if;

  select c.id_comercio, c.estado into v_comercio, v_com_estado
  from tbl_comercios c
  where c.codigo_tienda = substr(v_sku,1,3);
  if not found then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','TIENDA_DESCONOCIDA');
  end if;

  if v_com_estado is distinct from 'ACTIVO' then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','COMERCIO_NO_ACTIVO',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado);
  end if;

  select v.id_variante, v.id_producto, v.sku into v_var
  from tbl_variantes v
  join tbl_productos p on p.id_producto = v.id_producto
  where v.id_comercio = v_comercio
    and v.sku = v_sku
    and v.activo and p.activo;
  if not found then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','SKU_INEXISTENTE',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado);
  end if;

  select count(*) into v_n
  from tbl_inventario
  where id_variante = v_var.id_variante;
  if v_n = 0 then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','SIN_INVENTARIO',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado,
      'id_variante', v_var.id_variante);
  end if;

  select i.id_sucursal, (i.stock_actual - i.stock_reservado) as disp into v_cand
  from tbl_inventario i
  where i.id_variante = v_var.id_variante
  order by (i.stock_actual - i.stock_reservado) > 0 desc,
           (i.stock_actual - i.stock_reservado) desc,
           i.id_sucursal
  limit 1;

  select e.nombre, e.precio, e.activo into v_ef_nom, v_ef_pre, v_ef_act
  from fn_variante_efectiva(v_var.id_variante, v_cand.id_sucursal) e;
  if coalesce(v_ef_act, true) = false then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','VARIANTE_INACTIVA',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado,
      'id_variante', v_var.id_variante);
  end if;

  return jsonb_build_object(
    'resultado','RESUELTO',
    'id_comercio', v_comercio,
    'comercio_estado', v_com_estado,
    'id_sucursal', v_cand.id_sucursal,
    'id_variante', v_var.id_variante,
    'id_producto', v_var.id_producto,
    'sku', v_var.sku,
    'nombre', v_ef_nom,
    'precio', v_ef_pre,
    'origen', case when v_n = 1 then 'SKU_UNICO' else 'SKU_COMPARTIDO' end
  );
end;
$function$;

-- ── Cuarentena D17: contexto M2 (parche programatico abajo) ─────────────────
CREATE OR REPLACE FUNCTION rsuelvo.fn_contexto_por_telefono(p_telefono text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_tel text := nullif(trim(coalesce(p_telefono,'')), '');
  v_cli record;
  v_cap record;
  v_pen record;
  v_op record;
  v_res record;
  v_ped record;
  v_last uuid;
begin
  if v_tel is null then
    return jsonb_build_object('origen','DESCONOCIDO');
  end if;

  for v_cli in
    select id_cliente, id_comercio
    from tbl_clientes
    where coalesce(telefono_whatsapp, telefono) = v_tel
    order by updated_at desc
  loop
    -- cuarentena D17: ignora comercios no ACTIVO
    if (select c.estado from tbl_comercios c where c.id_comercio = v_cli.id_comercio) is distinct from 'ACTIVO' then
      continue;
    end if;
    -- 1. captura de destino en curso
    select p.id_pedido, p.id_sucursal into v_cap
    from tbl_pedidos p
    where p.id_cliente = v_cli.id_cliente
      and p.estado = 'PAGADO'
      and not exists (select 1 from tbl_envios e where e.id_pedido = p.id_pedido)
      and exists (select 1 from tbl_entrega_captura c where c.id_pedido = p.id_pedido)
    order by p.created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','CAPTURA', 'id_comercio', v_cli.id_comercio,
        'id_pedido', v_cap.id_pedido, 'id_sucursal', v_cap.id_sucursal);
    end if;

    -- 2. pendiente Momento 1 (PK por cliente: una fila como máximo)
    select id_sucursal, id_variante into v_pen
    from tbl_lista_pendiente
    where id_cliente = v_cli.id_cliente;
    if found then
      return jsonb_build_object('origen','PENDIENTE', 'id_comercio', v_cli.id_comercio,
        'id_sucursal', v_pen.id_sucursal, 'id_variante', v_pen.id_variante);
    end if;

    -- 3. oportunidad NOTIFICADO vigente
    select id_lista_espera, id_sucursal, id_variante into v_op
    from tbl_lista_espera
    where id_cliente = v_cli.id_cliente
      and estado = 'NOTIFICADO'
      and fecha_expiracion > now()
    order by fecha_notificacion desc
    limit 1;
    if found then
      return jsonb_build_object('origen','OPORTUNIDAD', 'id_comercio', v_cli.id_comercio,
        'id_lista_espera', v_op.id_lista_espera,
        'id_sucursal', v_op.id_sucursal, 'id_variante', v_op.id_variante);
    end if;

    -- 4. reserva viva
    select id_reserva, id_sucursal, id_variante into v_res
    from tbl_reservas
    where id_cliente = v_cli.id_cliente
      and estado in ('ACTIVA','PAGO_VALIDANDO')
    order by created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','RESERVA', 'id_comercio', v_cli.id_comercio,
        'id_reserva', v_res.id_reserva,
        'id_sucursal', v_res.id_sucursal, 'id_variante', v_res.id_variante);
    end if;

    -- 5. pedido esperando pago
    select id_pedido, id_sucursal into v_ped
    from tbl_pedidos
    where id_cliente = v_cli.id_cliente
      and estado = 'ESPERANDO_PAGO'
    order by created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','PEDIDO', 'id_comercio', v_cli.id_comercio,
        'id_pedido', v_ped.id_pedido, 'id_sucursal', v_ped.id_sucursal);
    end if;
  end loop;

  -- 6. último comercio activo del teléfono (sin sucursal)
  select cl.id_comercio into v_last
  from tbl_clientes cl
  join tbl_comercios c on c.id_comercio = cl.id_comercio
  where coalesce(cl.telefono_whatsapp, cl.telefono) = v_tel
    and c.estado = 'ACTIVO'
  order by cl.updated_at desc
  limit 1;
  if found then
    return jsonb_build_object('origen','ULTIMO_COMERCIO', 'id_comercio', v_last);
  end if;

  return jsonb_build_object('origen','DESCONOCIDO');
end;
$function$


-- ── QR del dueño: policies tenant sobre qr-pagos (el path manda) ────────────
drop policy if exists qr_pagos_dueno_select on storage.objects;
drop policy if exists qr_pagos_dueno_insert on storage.objects;
drop policy if exists qr_pagos_dueno_update on storage.objects;

create policy qr_pagos_dueno_select on storage.objects
  for select to authenticated
  using (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));

create policy qr_pagos_dueno_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));

create policy qr_pagos_dueno_update on storage.objects
  for update to authenticated
  using (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid))
  with check (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));
