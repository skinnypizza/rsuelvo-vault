-- ============================================================
-- RSUELVO v2 :: 6. FUNCIONES
-- ============================================================

set search_path = rsuelvo, public;

-- Validación de asignación usuario/comercio (cajero = 1 sucursal)
-- (fix 17_hardening_search_path_restante) SECURITY INVOKER + SET search_path
-- = rsuelvo, public y objetos calificados para no depender del search_path de
-- sesión (mismo patrón que 16_fix_search_path_sku).
create or replace function fn_validar_asignacion_usuario_comercio()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_codigo rsuelvo.rol_codigo;
  v_sucursal uuid;
begin
  select codigo into v_codigo from rsuelvo.tbl_roles where id_rol=new.id_rol;

  if v_codigo in ('ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT')
     and new.id_sucursal is null then
    raise exception 'El rol % requiere una sucursal',v_codigo;
  end if;

  if v_codigo='ROLE_TENANT_CASHIER' then
    if exists (
      select 1
      from rsuelvo.tbl_usuario_comercio uc
      join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
      where uc.id_usuario=new.id_usuario
        and uc.activo
        and r.codigo='ROLE_TENANT_CASHIER'
        and uc.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
    ) then
      raise exception 'Un cashier solo puede tener una asignación activa';
    end if;
  end if;

  return new;
end;
$$;


-- (v2/A1) Resuelve tenant de la variante, genera SKU de 6 caracteres
-- [3 tienda][3 producto] en base36 si viene nulo, valida formato y duplicados.
-- (fix 16_fix_search_path_sku) SECURITY INVOKER + SET search_path = rsuelvo, public
-- y tablas calificadas para no depender del search_path de sesión.
-- Helper base36 → int (m39: el trigger calculaba el máximo como HEX y fallaba con G-Z)
create or replace function fn_base36_a_int(p_texto text)
returns integer
language plpgsql
immutable
set search_path = rsuelvo, public
as $$
declare
  v text := upper(coalesce(p_texto,''));
  i int;
  c text;
  v_valor int := 0;
begin
  if v = '' then return null; end if;
  for i in 1..length(v) loop
    c := substr(v, i, 1);
    if c ~ '[0-9]' then
      v_valor := v_valor * 36 + (ascii(c) - 48);
    elsif c ~ '[A-Z]' then
      v_valor := v_valor * 36 + (ascii(c) - 55);
    else
      return null;
    end if;
  end loop;
  return v_valor;
end;
$$;

create or replace function fn_resolver_variante_tenant_sku()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_comercio uuid;
  v_codigo char(3);
  v_max int;
  v_sufijo text;
  v_sku text;
begin
  -- 1) Resolver id_comercio desde el producto (siempre).
  if new.id_producto is not null then
    select p.id_comercio into v_comercio
    from rsuelvo.tbl_productos p
    where p.id_producto=new.id_producto;
  end if;

  if v_comercio is null then
    raise exception 'Producto inexistente';
  end if;

  new.id_comercio := v_comercio;

  select codigo_tienda into v_codigo
  from rsuelvo.tbl_comercios
  where id_comercio=v_comercio;

  if v_codigo is null then
    raise exception 'El comercio % no tiene codigo_tienda asignado',v_comercio;
  end if;

  -- 2) Generar SKU si no viene (o venir vacío).
  if coalesce(new.sku,'')='' then
    -- serializar por comercio: bloquea la fila del comercio.
    select 1 into v_max from rsuelvo.tbl_comercios
    where id_comercio=v_comercio for update;

    select coalesce(max(
      rsuelvo.fn_base36_a_int(substr(v.sku,4,3))
    ),0) into v_max
    from rsuelvo.tbl_variantes v
    where v.id_comercio=v_comercio
      and v.sku ~ '^[A-Z0-9]{6}$'
      and substr(v.sku,1,3)=v_codigo::text;

    v_max := v_max+1;
    if v_max > 46655 then
      raise exception 'Se agotaron los SKUs disponibles para la tienda %',v_codigo;
    end if;

    declare
      n int := v_max;
      chars text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      out text := '';
    begin
      while n>0 loop
        out := substr(chars,(n%36)+1,1)||out;
        n := n/36;
      end loop;
      v_sufijo := lpad(coalesce(nullif(out,''),'0'),3,'0');
    end;

    new.sku := upper(v_codigo::text||v_sufijo);
  else
    new.sku := upper(new.sku);
  end if;

  -- 3) Validar formato 6 caracteres tienda+producto.
  if new.sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido %. Formato requerido: 6 caracteres [3 tienda][3 producto], ej. FERA01',new.sku;
  end if;

  if substr(new.sku,1,3) <> v_codigo::text then
    raise exception 'El prefijo del SKU (%) debe ser el código de la tienda (%)',substr(new.sku,1,3),v_codigo;
  end if;

  -- 4) Duplicado amigable (el UNIQUE físico es la garantía real).
  if exists (
    select 1 from rsuelvo.tbl_variantes v
    where v.id_comercio=v_comercio
      and v.sku=new.sku
      and v.id_variante<>coalesce(new.id_variante,'00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    raise exception 'SKU duplicado dentro del comercio: %',new.sku;
  end if;

  return new;
end;
$$;


-- (fix 17_hardening_search_path_restante) SECURITY INVOKER + SET search_path
-- = rsuelvo, public y objetos calificados para no depender del search_path de
-- sesión (mismo patrón que 16_fix_search_path_sku).
create or replace function fn_validar_consistencia_tenant()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_comercio uuid;
begin
  -- Sucursal pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_lista_espera','tbl_pedidos','tbl_envios') then
    select id_comercio into v_comercio
    from rsuelvo.tbl_sucursales
    where id_sucursal=new.id_sucursal;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'La sucursal no pertenece al comercio';
    end if;
  end if;

  -- Cliente pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_pedidos','tbl_comprobantes_pago') then
    select id_comercio into v_comercio
    from rsuelvo.tbl_clientes
    where id_cliente=new.id_cliente;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'El cliente no pertenece al comercio';
    end if;
  end if;

  return new;
end;
$$;


-- updated_at automático
create or replace function fn_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- (v2) ¿La llamada proviene de service_role (n8n/backend)?
create or replace function fn_es_service_role()
returns boolean
language sql
stable
as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),'service_role')
     = 'service_role';
$$;


-- (fix A15) Resolver auth.uid() -> tbl_usuarios.id_usuario.
-- Devuelve NULL para sesiones sin usuario de app (service_role/cron);
-- consumida por fn_solicitar_reserva, fn_crear_envio, fn_actualizar_estado_envio,
-- fn_movimiento_inventario y fn_auditar_cambio.
create or replace function fn_current_usuario_id()
returns uuid
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select id_usuario from tbl_usuarios where auth_user_id = auth.uid();
$$;


-- Helpers de tenancy (v2: con escape para service_role en accesos)

create or replace function fn_tiene_rol(p_rol rol_codigo)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select exists (
    select 1
    from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol=uc.id_rol
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    where u.auth_user_id=auth.uid()
      and u.activo
      and uc.activo
      and r.codigo=p_rol
  );
$$;


create or replace function fn_es_superadmin()
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_tiene_rol('ROLE_SUPERADMIN');
$$;


create or replace function fn_tiene_acceso_comercio(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        where u.auth_user_id=auth.uid()
          and u.activo
          and uc.activo
          and uc.id_comercio=p_id_comercio
      );
$$;

create or replace function fn_tiene_acceso_sucursal(p_id_comercio uuid,p_id_sucursal uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        where u.auth_user_id=auth.uid()
          and u.activo
          and uc.activo
          and uc.id_comercio=p_id_comercio
          and (
            uc.id_sucursal is null
            or uc.id_sucursal=p_id_sucursal
            or exists (
              select 1
              from tbl_roles r
              where r.id_rol=uc.id_rol
                and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPPORT','ROLE_SUPERADMIN')
            )
          )
      );
$$;

create or replace function fn_es_admin_comercio(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
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
          and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPPORT')
      );
$$;

-- (v2/A10) Rol específico dentro de un comercio
create or replace function fn_tiene_rol_comercio(p_id_comercio uuid,p_rol rol_codigo)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_service_role() or exists (
    select 1
    from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid()
      and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and r.codigo=p_rol
  );
$$;

-- (v2/A10) Puede verificar comprobantes: admin o cajero del comercio (HU-141)
create or replace function fn_puede_verificar(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_admin_comercio(p_id_comercio)
      or fn_tiene_rol_comercio(p_id_comercio,'ROLE_TENANT_CASHIER');
$$;

-- (v2/A10) Puede crear/asignar envíos: admin o cajero del comercio (matriz)
create or replace function fn_puede_gestionar_envios(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_puede_verificar(p_id_comercio);
$$;


-- Upsert de cliente
create or replace function fn_upsert_cliente(
  p_id_comercio uuid,
  p_nombre text,
  p_telefono text default null,
  p_telefono_whatsapp text default null,
  p_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_id uuid;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;

  if p_telefono_whatsapp is not null then
    select id_cliente into v_id
    from tbl_clientes
    where id_comercio=p_id_comercio
      and telefono_whatsapp=p_telefono_whatsapp
    for update;

    if v_id is not null then
      update tbl_clientes
      set nombre=coalesce(nullif(p_nombre,''),nombre),
          telefono=coalesce(p_telefono,telefono),
          email=coalesce(p_email,email)
      where id_cliente=v_id;
      return v_id;
    end if;
  end if;

  insert into tbl_clientes(
    id_comercio,nombre,telefono,telefono_whatsapp,email
  )
  values(
    p_id_comercio,p_nombre,p_telefono,p_telefono_whatsapp,p_email
  )
  returning id_cliente into v_id;

  return v_id;
end;
$$;


-- (v2/WF-10/HU-037..041) Resuelve SKU exacto dentro del comercio.
-- SECURITY INVOKER conserva RLS; n8n usa service_role para el flujo backend.
create or replace function fn_resolver_variante_por_sku(
  p_id_comercio uuid,
  p_sku text
)
returns table(
  id_variante uuid,
  nombre text,
  precio numeric(14,2),
  id_producto uuid
)
language plpgsql
stable
security invoker
set search_path = rsuelvo, pg_catalog
as $$
begin
  if p_sku is null or p_sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido. Formato requerido: exactamente 6 caracteres [A-Z0-9]'
      using errcode = '22023';
  end if;

  return query
  select v.id_variante, v.nombre, v.precio, v.id_producto
  from tbl_variantes v
  where v.id_comercio = p_id_comercio
    and v.sku = p_sku
    and v.activo;
end;
$$;

revoke execute on function fn_resolver_variante_por_sku(uuid, text) from public;
grant execute on function fn_resolver_variante_por_sku(uuid, text) to authenticated, service_role;


-- (v2/A2/HU-123) Identificar comercio+sucursal por número de WhatsApp destino.
-- Solo service_role (n8n): nunca expone el mapa completo al cliente.
create or replace function fn_identificar_comercio_por_whatsapp(p_numero text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select c.id_comercio, c.id_sucursal, c.provider::text
  from tbl_canal_whatsapp c
  where c.numero=p_numero
    and c.activo
  limit 1;
$$;

-- (fix 17_hardening_search_path_restante) SECURITY INVOKER + SET search_path
-- = rsuelvo, public y llamada calificada a rsuelvo.fn_es_service_role (mismo
-- patrón que 16_fix_search_path_sku).
create or replace function fn_assert_service_role()
returns void
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
begin
  if not rsuelvo.fn_es_service_role() then
    raise exception 'Operación reservada al backend (service_role)';
  end if;
end;
$$;

-- (v2/A6/HU-143 + Guía Meta §15-16) Registrar evento entrante con estado de
-- procesamiento y datos de correlación. Devuelve jsonb: nuevo=true => procesar.
create or replace function fn_registrar_evento_whatsapp(
  p_provider text,
  p_external_message_id text,
  p_tipo text default null,
  p_payload jsonb default null,
  p_phone_number_id text default null,
  p_customer_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_nuevo boolean := false;
begin
  perform fn_assert_service_role();

  insert into tbl_whatsapp_eventos(
    provider,external_message_id,tipo,payload,phone_number_id,customer_phone,processing_status
  )
  values(
    p_provider,p_external_message_id,p_tipo,p_payload,p_phone_number_id,p_customer_phone,'PROCESANDO'
  )
  on conflict (provider,external_message_id) do nothing;

  v_nuevo := found;

  if not v_nuevo then
    -- Reintento legítimo si el intento anterior quedó PROCESSING/ERROR.
    update tbl_whatsapp_eventos
    set processing_status='PROCESANDO', payload=coalesce(p_payload,payload)
    where provider=p_provider
      and external_message_id=p_external_message_id
      and processing_status in ('PROCESANDO','ERROR');
    v_nuevo := found;
  end if;

  return jsonb_build_object('nuevo',v_nuevo);
end;
$$;

-- Marcar resultado del procesamiento (éxito/error).
create or replace function fn_cerrar_evento_whatsapp(
  p_provider text,
  p_external_message_id text,
  p_exito boolean default true,
  p_error text default null
)
returns void
language sql
security definer
set search_path = rsuelvo, public
as $$
  update tbl_whatsapp_eventos
  set processing_status = case when p_exito then 'PROCESADO' else 'ERROR' end,
      procesado_at = now(),
      payload = coalesce(payload || jsonb_build_object('last_error',p_error), payload)
  where provider=p_provider and external_message_id=p_external_message_id;
$$;

-- (v2/Guía Meta §18/58) Identificación por Phone Number ID de Meta.
create or replace function fn_identificar_comercio_por_phone_number_id(p_pnid text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select c.id_comercio, c.id_sucursal, c.provider::text
  from tbl_canal_whatsapp c
  where c.provider_phone_number_id=p_pnid
    and c.activo
  limit 1;
$$;

-- (v2/HU-142) Registrar opt-out del comprador
create or replace function fn_registrar_opt_out(
  p_id_comercio uuid,
  p_telefono_whatsapp text,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
begin
  insert into tbl_contact_preferences(id_comercio,telefono_whatsapp,opted_out,opted_out_at,motivo)
  values(p_id_comercio,p_telefono_whatsapp,true,now(),coalesce(p_motivo,'STOP'))
  on conflict (id_comercio,telefono_whatsapp)
  do update set opted_out=true, opted_out_at=now(), motivo=coalesce(excluded.motivo,tbl_contact_preferences.motivo);
end;
$$;

-- (v2/HU-142) ¿Puede recibirse comunicación transaccional?
create or replace function fn_cliente_optado(p_id_comercio uuid,p_telefono_whatsapp text)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select coalesce((select opted_out from tbl_contact_preferences
    where id_comercio=p_id_comercio and telefono_whatsapp=p_telefono_whatsapp),false);
$$;


-- Reserva atómica (v2/18 RESERVA_YA_EXISTENTE por cliente; opción B: una activa POR CLIENTE por sucursal+variante)
create or replace function fn_solicitar_reserva(
  p_id_comercio uuid,
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_id_cliente uuid,
  p_cantidad integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_inv tbl_inventario%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_reserva uuid;
  v_pedido uuid;
  v_precio numeric(14,2);
  v_reserva_existente uuid;
  v_fecha_expiracion timestamptz;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0';
  end if;

  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;

  select * into v_cfg
  from tbl_comercio_config
  where id_comercio=p_id_comercio;

  if not found then
    raise exception 'El comercio no tiene configuración';
  end if;

  select v.precio into v_precio
  from tbl_variantes v
  join tbl_productos p on p.id_producto=v.id_producto
  where v.id_variante=p_id_variante
    and p.id_comercio=p_id_comercio
    and v.activo
    and p.activo;

  if v_precio is null then
    raise exception 'SKU/variante inválida para el comercio';
  end if;

  -- (18/RESERVA_YA_EXISTENTE por cliente) Detección temprana SIN tocar inventario:
  -- si el MISMO cliente ya tiene una reserva activa para (sucursal, variante) la
  -- devolvemos. El índice uq_reserva_activa_variante_sucursal ahora incluye
  -- id_cliente, por lo que clientes DISTINTOS NO colisionan y pueden reservar en
  -- paralelo mientras haya stock. FOR UPDATE serializa contra fn_expirar_reserva
  -- sobre la misma fila del cliente y evita doble retorno en reintentos.
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  for update;

  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;

  -- Bloqueo pesimista: solo una transacción modifica esta fila. Este lock serializa
  -- la carrera primera-reserva/reintento para la misma variante+sucursal.
  select * into v_inv
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;

  if not found then
    return jsonb_build_object(
      'resultado','SIN_STOCK',
      'motivo','NO_EXISTE_INVENTARIO'
    );
  end if;

  -- (18/RESERVA_YA_EXISTENTE por cliente) Re-verificación DENTRO del lock de
  -- inventario para cerrar la carrera primer-reserva/reintento del MISMO cliente.
  -- Una transacción concurrente del mismo cliente pudo crear la reserva mientras
  -- esta esperaba el lock. Cliente distinto no cuenta (puede reservar si hay stock).
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  limit 1;

  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;

  if (v_inv.stock_actual-v_inv.stock_reservado) >= p_cantidad then

    update tbl_inventario
    set stock_reservado=stock_reservado+p_cantidad
    where id_inventario=v_inv.id_inventario;

    insert into tbl_reservas(
      id_comercio,id_sucursal,id_variante,id_cliente,
      origen,estado,cantidad,fecha_inicio,fecha_expiracion
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,
      'DIRECTA','ACTIVA',p_cantidad,now(),
      now() + make_interval(mins=>v_cfg.tiempo_reserva_minutos)
    )
    returning id_reserva into v_reserva;

    insert into tbl_inventario_movimientos(
      id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,'RESERVA',
      p_cantidad,'RESERVA',v_reserva,fn_current_usuario_id()
    );

    return jsonb_build_object(
      'resultado','RESERVA_CREADA',
      'id_reserva',v_reserva,
      'fecha_expiracion',(
        select fecha_expiracion from tbl_reservas where id_reserva=v_reserva
      )
    );
  end if;

  return jsonb_build_object(
    'resultado','SIN_STOCK',
    'motivo','PRODUCTO_RESERVADO_O_AGOTADO'
  );
end;
$$;


-- Agregar a lista de espera
create or replace function fn_agregar_lista_espera(
  p_id_comercio uuid,
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_id_cliente uuid
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_max integer;
  v_pos integer;
  v_id uuid;
begin
  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;

  select max_lista_espera_por_producto into v_max
  from tbl_comercio_config
  where id_comercio=p_id_comercio;

  if v_max is null then
    raise exception 'Configuración de comercio inexistente';
  end if;

  perform 1
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;

  select count(*) into v_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');

  if v_pos >= v_max then
    raise exception 'LISTA_DE_ESPERA_LLENA';
  end if;

  select coalesce(max(posicion),0)+1 into v_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO');

  insert into tbl_lista_espera(
    id_comercio,id_sucursal,id_variante,id_cliente,posicion,estado
  )
  values(
    p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,v_pos,'ESPERANDO'
  )
  returning id_lista_espera into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'El cliente ya está en la lista de espera activa';
end;
$$;


-- Expirar reserva
create or replace function fn_expirar_reserva(p_id_reserva uuid)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_res tbl_reservas%rowtype;
begin
  select * into v_res
  from tbl_reservas
  where id_reserva=p_id_reserva
  for update;

  if not found then
    raise exception 'Reserva inexistente';
  end if;

  if v_res.estado <> 'ACTIVA' then
    return jsonb_build_object('resultado','SIN_CAMBIO','estado',v_res.estado);
  end if;

  if v_res.fecha_expiracion > now() then
    return jsonb_build_object(
      'resultado','AUN_ACTIVA',
      'fecha_expiracion',v_res.fecha_expiracion
    );
  end if;

  update tbl_reservas
  set estado='VENCIDA',
      fecha_finalizacion=now()
  where id_reserva=p_id_reserva;

  update tbl_inventario
  set stock_reservado=stock_reservado-v_res.cantidad
  where id_sucursal=v_res.id_sucursal
    and id_variante=v_res.id_variante
    and stock_reservado >= v_res.cantidad;

  if not found then
    raise exception 'Inconsistencia de inventario al liberar reserva %',p_id_reserva;
  end if;

  insert into tbl_inventario_movimientos(
    id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id
  )
  values(
    v_res.id_comercio,v_res.id_sucursal,v_res.id_variante,
    'LIBERACION_RESERVA',v_res.cantidad,'RESERVA',v_res.id_reserva
  );

  return jsonb_build_object(
    'resultado','RESERVA_LIBERADA',
    'id_reserva',p_id_reserva
  );
end;
$$;


-- Notificar siguiente de la lista (m32: salta clientes con oferta NOTIFICADO vigente en cualquier grupo — H-17)
create or replace function fn_notificar_siguiente_lista_espera(
  p_id_sucursal uuid,
  p_id_variante uuid
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_item tbl_lista_espera%rowtype;
  v_cfg tbl_comercio_config%rowtype;
begin
  select * into v_item
  from tbl_lista_espera cand
  where cand.id_sucursal=p_id_sucursal
    and cand.id_variante=p_id_variante
    and cand.estado='ESPERANDO'
    and not exists (
      select 1 from tbl_lista_espera act
      where act.id_cliente = cand.id_cliente
        and act.estado='NOTIFICADO'
        and act.fecha_expiracion > now()
    )
  order by cand.posicion
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object('resultado','LISTA_VACIA');
  end if;

  select * into v_cfg
  from tbl_comercio_config
  where id_comercio=v_item.id_comercio;

  update tbl_lista_espera
  set estado='NOTIFICADO',
      fecha_notificacion=now(),
      fecha_expiracion=now()+make_interval(
        mins=>v_cfg.tiempo_aceptacion_lista_espera_minutos
      )
  where id_lista_espera=v_item.id_lista_espera;

  return jsonb_build_object(
    'resultado','CLIENTE_NOTIFICADO',
    'id_lista_espera',v_item.id_lista_espera,
    'id_cliente',v_item.id_cliente,
    'fecha_expiracion',(
      select fecha_expiracion
      from tbl_lista_espera
      where id_lista_espera=v_item.id_lista_espera
    )
  );
end;
$$;


-- Aceptar oportunidad
create or replace function fn_aceptar_lista_espera(p_id_lista_espera uuid)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_item tbl_lista_espera%rowtype;
  v_result jsonb;
begin
  select * into v_item
  from tbl_lista_espera
  where id_lista_espera=p_id_lista_espera
  for update;

  if not found then
    raise exception 'Entrada de lista inexistente';
  end if;

  if v_item.estado <> 'NOTIFICADO' then
    raise exception 'La oportunidad ya no está disponible';
  end if;

  if v_item.fecha_expiracion < now() then
    update tbl_lista_espera
    set estado='VENCIDO'
    where id_lista_espera=p_id_lista_espera;

    return jsonb_build_object('resultado','OPORTUNIDAD_VENCIDA');
  end if;

  update tbl_lista_espera
  set estado='ACEPTADO',
      fecha_aceptacion=now()
  where id_lista_espera=p_id_lista_espera;

  v_result := fn_solicitar_reserva(
    v_item.id_comercio,
    v_item.id_sucursal,
    v_item.id_variante,
    v_item.id_cliente,
    1
  );

  if v_result->>'resultado' = 'RESERVA_CREADA' then
    update tbl_lista_espera
    set estado='CONVERTIDO_RESERVA',
        id_reserva_generada=(v_result->>'id_reserva')::uuid
    where id_lista_espera=p_id_lista_espera;
  else
    update tbl_lista_espera
    set estado='VENCIDO'
    where id_lista_espera=p_id_lista_espera;
  end if;

  return v_result;
end;
$$;


-- Crear pedido desde reserva
-- (migración 19 / H-1) Idempotencia: reintento de la MISMA reserva devuelve el pedido existente.
create or replace function fn_crear_pedido_desde_reserva(p_id_reserva uuid)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_res tbl_reservas%rowtype;
  v_var tbl_variantes%rowtype;
  v_prod tbl_productos%rowtype;
  v_pedido uuid;
  v_subtotal numeric(14,2);
begin
  select * into v_res
  from tbl_reservas
  where id_reserva=p_id_reserva
  for update;

  if not found then
    raise exception 'Reserva inexistente';
  end if;

  if v_res.estado not in ('ACTIVA','PAGO_VALIDANDO') then
    raise exception 'La reserva no puede generar pedido';
  end if;

  -- H-1 (migración 19): idempotencia por reserva
  if v_res.id_pedido is not null then
    return v_res.id_pedido;
  end if;

  select v.* into v_var
  from tbl_variantes v
  where v.id_variante=v_res.id_variante;

  select p.* into v_prod
  from tbl_productos p
  where p.id_producto=v_var.id_producto;

  v_subtotal := v_var.precio * v_res.cantidad;

  insert into tbl_pedidos(
    id_comercio,id_sucursal,id_cliente,estado,subtotal,descuento,id_reserva
  )
  values(
    v_res.id_comercio,v_res.id_sucursal,v_res.id_cliente,
    'ESPERANDO_PAGO',v_subtotal,0,p_id_reserva
  )
  returning id_pedido into v_pedido;

  insert into tbl_pedido_detalles(
    id_pedido,id_variante,sku_snapshot,nombre_snapshot,precio_unitario,cantidad
  )
  values(
    v_pedido,v_var.id_variante,v_var.sku,
    v_prod.nombre || ' - ' || v_var.nombre,
    v_var.precio,v_res.cantidad
  );

  update tbl_reservas
  set id_pedido=v_pedido
  where id_reserva=p_id_reserva;

  return v_pedido;
end;
$$;


-- Consumo atómico de créditos
create or replace function fn_consumir_creditos(
  p_id_comercio uuid,
  p_id_servicio uuid,
  p_referencia_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_cuenta tbl_cuentas_creditos%rowtype;
  v_serv tbl_servicios_creditos%rowtype;
  v_anterior bigint;
  v_nuevo bigint;
begin
  select * into v_serv
  from tbl_servicios_creditos
  where id_servicio=p_id_servicio
    and activo
  for share;

  if not found then
    raise exception 'Servicio de créditos inexistente o inactivo';
  end if;

  select * into v_cuenta
  from tbl_cuentas_creditos
  where id_comercio=p_id_comercio
  for update;

  if not found then
    insert into tbl_cuentas_creditos(id_comercio,saldo_actual)
    values(p_id_comercio,0)
    returning * into v_cuenta;
  end if;

  v_anterior := v_cuenta.saldo_actual;

  if v_anterior < v_serv.costo_creditos then
    raise exception 'SALDO_INSUFICIENTE';
  end if;

  v_nuevo := v_anterior-v_serv.costo_creditos;

  update tbl_cuentas_creditos
  set saldo_actual=v_nuevo
  where id_cuenta_creditos=v_cuenta.id_cuenta_creditos;

  insert into tbl_movimientos_creditos(
    id_comercio,id_cuenta_creditos,tipo,cantidad,
    saldo_anterior,saldo_posterior,concepto,referencia_tipo,referencia_id
  )
  values(
    p_id_comercio,v_cuenta.id_cuenta_creditos,
    'CONSUMO_VERIFICACION',-v_serv.costo_creditos,
    v_anterior,v_nuevo,
    'Consumo de servicio de verificación',
    'VERIFICACION',p_referencia_id
  );

  update tbl_verificaciones
  set creditos_consumidos=v_serv.costo_creditos
  where id_verificacion=p_referencia_id;

  return v_serv.costo_creditos;
end;
$$;


-- Acreditar créditos
create or replace function fn_acreditar_creditos(
  p_id_comercio uuid,
  p_cantidad bigint,
  p_tipo tipo_movimiento_credito,
  p_concepto text default null,
  p_referencia_tipo text default null,
  p_referencia_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_cuenta tbl_cuentas_creditos%rowtype;
  v_anterior bigint;
  v_nuevo bigint;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser positiva';
  end if;

  insert into tbl_cuentas_creditos(id_comercio,saldo_actual)
  values(p_id_comercio,0)
  on conflict(id_comercio) do nothing;

  select * into v_cuenta
  from tbl_cuentas_creditos
  where id_comercio=p_id_comercio
  for update;

  v_anterior := v_cuenta.saldo_actual;
  v_nuevo := v_anterior+p_cantidad;

  update tbl_cuentas_creditos
  set saldo_actual=v_nuevo
  where id_cuenta_creditos=v_cuenta.id_cuenta_creditos;

  insert into tbl_movimientos_creditos(
    id_comercio,id_cuenta_creditos,tipo,cantidad,
    saldo_anterior,saldo_posterior,concepto,referencia_tipo,referencia_id
  )
  values(
    p_id_comercio,v_cuenta.id_cuenta_creditos,p_tipo,p_cantidad,
    v_anterior,v_nuevo,p_concepto,p_referencia_tipo,p_referencia_id
  );

  return v_nuevo;
end;
$$;


-- Confirmar pago
create or replace function fn_confirmar_pago(
  p_id_verificacion uuid,
  p_resultado jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_ver tbl_verificaciones%rowtype;
  v_res tbl_reservas%rowtype;
begin
  select * into v_ver
  from tbl_verificaciones
  where id_verificacion=p_id_verificacion
  for update;

  if not found then
    raise exception 'Verificación inexistente';
  end if;

  -- H-01: guarda de idempotencia por verificación
  if v_ver.estado = 'COMPLETADA' then
    return jsonb_build_object(
      'resultado','YA_PROCESADO',
      'id_pedido', v_ver.id_pedido,
      'mensaje','Esta verificación ya fue confirmada previamente; no se repiten efectos de inventario.'
    );
  end if;

  select * into v_res
  from tbl_reservas
  where id_pedido=v_ver.id_pedido
  for update;

  if not found then
    raise exception 'No existe reserva asociada al pedido';
  end if;

  -- H-12: el pedido no debe confirmarse dos veces
  if exists (select 1 from tbl_pedidos where id_pedido=v_ver.id_pedido and estado='PAGADO') then
    return jsonb_build_object(
      'resultado','YA_PROCESADO',
      'id_pedido', v_ver.id_pedido,
      'mensaje','El pedido ya estaba pagado; no se repiten efectos de inventario.'
    );
  end if;

  -- H-12: la reserva debe seguir viva para poder convertirse en venta
  if v_res.estado not in ('ACTIVA','PAGO_VALIDANDO') or v_res.fecha_expiracion < now() then
    return jsonb_build_object(
      'resultado','RESERVA_VENCIDA',
      'id_pedido', v_ver.id_pedido,
      'mensaje','La reserva expiró. El comprador debe solicitar el SKU nuevamente.'
    );
  end if;

  update tbl_verificaciones
  set estado='COMPLETADA',
      resultado=p_resultado,
      fecha_fin=now()
  where id_verificacion=p_id_verificacion;

  update tbl_comprobantes_pago
  set estado='VALIDO'
  where id_comprobante=v_ver.id_comprobante;

  update tbl_pedidos
  set estado='PAGADO',
      fecha_confirmacion=now()
  where id_pedido=v_ver.id_pedido;

  update tbl_reservas
  set estado='CONFIRMADA',
      fecha_finalizacion=now()
  where id_reserva=v_res.id_reserva;

  update tbl_inventario
  set stock_reservado=stock_reservado-v_res.cantidad,
      stock_actual=stock_actual-v_res.cantidad
  where id_sucursal=v_res.id_sucursal
    and id_variante=v_res.id_variante
    and stock_reservado >= v_res.cantidad
    and stock_actual >= v_res.cantidad;

  if not found then
    raise exception 'Inconsistencia de inventario al confirmar venta';
  end if;

  insert into tbl_inventario_movimientos(
    id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id
  )
  values(
    v_res.id_comercio,v_res.id_sucursal,v_res.id_variante,
    'VENTA',v_res.cantidad,'PEDIDO',v_ver.id_pedido
  );

  -- D14 (migración 27): consume 1 crédito por venta confirmada en la misma transacción
  -- (SD-1: nunca bloquea la venta; SD-5: los rechazos no consumen; SD-6: aplica a toda venta)
  PERFORM fn_consumir_credito_venta(v_res.id_comercio, v_ver.id_pedido);

  return jsonb_build_object(
    'resultado','PAGO_CONFIRMADO',
    'id_pedido',v_ver.id_pedido,
    'id_reserva',v_res.id_reserva
  );
end;
$$;


-- (v2/A9/HU-065) Rechazo: comprobante INVALIDO pero el pedido vuelve a
-- ESPERANDO_PAGO para permitir reenvío. CANCELADO solo por decisión admin.
create or replace function fn_rechazar_verificacion(
  p_id_verificacion uuid,
  p_resultado jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_ver tbl_verificaciones%rowtype;
begin
  select * into v_ver
  from tbl_verificaciones
  where id_verificacion=p_id_verificacion
  for update;

  if not found then
    raise exception 'Verificación inexistente';
  end if;

  update tbl_verificaciones
  set estado='COMPLETADA',
      resultado=p_resultado,
      fecha_fin=now()
  where id_verificacion=p_id_verificacion;

  update tbl_comprobantes_pago
  set estado='INVALIDO'
  where id_comprobante=v_ver.id_comprobante;

  update tbl_pedidos
  set estado='ESPERANDO_PAGO'
  where id_pedido=v_ver.id_pedido
    and estado in ('ESPERANDO_PAGO','PAGO_RECIBIDO','PAGO_VALIDANDO');

  return jsonb_build_object(
    'resultado','PAGO_RECHAZADO',
    'id_pedido',v_ver.id_pedido,
    'pedido','ESPERANDO_PAGO',
    'puede_reenviar',true
  );
end;
$$;


-- Crear envío
create or replace function fn_crear_envio(
  p_id_pedido uuid,
  p_direccion text,
  p_referencia text,
  p_telefono_contacto text
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_pedido tbl_pedidos%rowtype;
  v_id uuid;
begin
  select * into v_pedido
  from tbl_pedidos
  where id_pedido=p_id_pedido
  for update;

  if not found then
    raise exception 'Pedido inexistente';
  end if;

  if v_pedido.estado <> 'PAGADO' then
    raise exception 'El pedido todavía no está pagado';
  end if;

  insert into tbl_envios(
    id_comercio,id_pedido,id_sucursal,direccion,referencia,telefono_contacto
  )
  values(
    v_pedido.id_comercio,p_id_pedido,v_pedido.id_sucursal,
    p_direccion,p_referencia,p_telefono_contacto
  )
  returning id_envio into v_id;

  insert into tbl_env_seguimiento_estados(
    id_envio,estado,observacion,usuario_id
  )
  values(
    v_id,'PENDIENTE','Envío creado',fn_current_usuario_id()
  );

  update tbl_pedidos
  set estado='PREPARANDO'
  where id_pedido=p_id_pedido;

  return v_id;
end;
$$;


-- (v2/A4/HU-056) Generar cobro QR del pedido (referencia única por comercio).
-- (migración 19 / H-1) Idempotencia: reintento del MISMO pedido devuelve el cobro GENERADO vigente.
create or replace function fn_generar_cobro(
  p_id_pedido uuid,
  p_qr_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_pedido tbl_pedidos%rowtype;
  v_metodo uuid;
  v_id uuid;
begin
  select * into v_pedido from tbl_pedidos
  where id_pedido=p_id_pedido for update;

  if not found then
    raise exception 'Pedido inexistente';
  end if;

  if v_pedido.estado not in ('CREADO','ESPERANDO_PAGO') then
    raise exception 'El pedido % no admite cobro en estado %',p_id_pedido,v_pedido.estado;
  end if;

  -- H-1 (migración 19): idempotencia por pedido (retorna cobro GENERADO vigente)
  select id_qr_cobro into v_id from tbl_qr_cobros
  where id_pedido=p_id_pedido and estado='GENERADO' limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select id_metodo_pago into v_metodo
  from tbl_metodos_pago
  where id_comercio=v_pedido.id_comercio and activo
  order by created_at
  limit 1;

  if v_metodo is null then
    raise exception 'El comercio no tiene métodos de pago configurados';
  end if;

  update tbl_pedidos set estado='ESPERANDO_PAGO' where id_pedido=p_id_pedido;

  insert into tbl_qr_cobros(
    id_comercio,id_pedido,id_metodo_pago,monto,referencia,qr_url,estado
  )
  values(
    v_pedido.id_comercio,p_id_pedido,v_metodo,v_pedido.total,
    'RS-'||lpad(v_pedido.numero_pedido::text,8,'0'),
    p_qr_url,'GENERADO'
  )
  returning id_qr_cobro into v_id;

  return v_id;
end;
$$;

-- (v2/A3/HU-141) Iniciar verificación ATÓMICA: crea verificación + consume créditos.
create or replace function fn_iniciar_verificacion(
  p_id_comprobante uuid,
  p_codigo_servicio text default 'VERIFICACION_COMPROBANTE',
  p_forzar boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_comp tbl_comprobantes_pago%rowtype;
  v_serv tbl_servicios_creditos%rowtype;
  v_ver uuid;
  v_costo bigint;
begin
  select * into v_comp from tbl_comprobantes_pago
  where id_comprobante=p_id_comprobante for update;

  if not found then
    raise exception 'Comprobante inexistente';
  end if;

  if v_comp.estado not in ('RECIBIDO') then
    return jsonb_build_object('resultado','ESTADO_NO_VERIFICABLE','estado',v_comp.estado);
  end if;

  select * into v_serv from tbl_servicios_creditos
  where codigo=p_codigo_servicio and activo for share;

  if not found then
    raise exception 'Servicio de créditos inexistente: %',p_codigo_servicio;
  end if;
  v_costo := v_serv.costo_creditos;

  insert into tbl_verificaciones(
    id_comercio,id_comprobante,id_pedido,tipo_verificacion,estado,fecha_inicio
  )
  values(
    v_comp.id_comercio,p_id_comprobante,v_comp.id_pedido,
    p_codigo_servicio,'PROCESANDO',now()
  )
  returning id_verificacion into v_ver;

  begin
    perform 1 from tbl_cuentas_creditos
    where id_comercio=v_comp.id_comercio for update;

    if (select coalesce(saldo_actual,0) from tbl_cuentas_creditos
        where id_comercio=v_comp.id_comercio) < v_costo then
      raise exception 'SALDO_INSUFICIENTE';
    end if;

    perform fn_consumir_creditos(v_comp.id_comercio,v_serv.id_servicio,v_ver);

  exception
    when others then
      if sqlerrm='SALDO_INSUFICIENTE' and not p_forzar then
        update tbl_verificaciones
        set estado='BLOQUEADA',
            resultado=jsonb_build_object('motivo','SIN_CREDITOS'),
            fecha_fin=now()
        where id_verificacion=v_ver;

        return jsonb_build_object(
          'resultado','SIN_CREDITOS',
          'id_verificacion',v_ver,
          'mensaje','Recibimos tu comprobante. El comercio no puede completar la verificación en este momento.'
        );
      else
        update tbl_verificaciones
        set estado='ERROR',
            resultado=jsonb_build_object('error',sqlerrm),
            fecha_fin=now()
        where id_verificacion=v_ver;
        raise;
      end if;
  end;

  update tbl_comprobantes_pago
  set estado='PROCESANDO'
  where id_comprobante=p_id_comprobante;

  return jsonb_build_object('resultado','VERIFICACION_INICIADA','id_verificacion',v_ver);
end;
$$;

-- (v2/A5/HU-092-094) Transición de estado logístico validada.
-- Máquina de estados v2 (m33): saltos hacia adelante permitidos (OBS-003 decisión 2)
create or replace function fn_actualizar_estado_envio(
  p_id_envio uuid,
  p_nuevo_estado rsuelvo.estado_envio,
  p_observacion text DEFAULT NULL,
  p_latitud numeric DEFAULT NULL,
  p_longitud numeric DEFAULT NULL
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_env tbl_envios%rowtype;
  v_rank_actual integer;
  v_rank_nuevo integer;
begin
  select * into v_env from tbl_envios
  where id_envio=p_id_envio for update;

  if not found then
    raise exception 'Envío inexistente';
  end if;

  v_rank_actual := case v_env.estado
    when 'PENDIENTE' then 1 when 'PREPARANDO' then 2 when 'ASIGNADO' then 3
    when 'EN_RUTA' then 4 when 'ENTREGADO' then 5 else null end;
  v_rank_nuevo := case p_nuevo_estado
    when 'PENDIENTE' then 1 when 'PREPARANDO' then 2 when 'ASIGNADO' then 3
    when 'EN_RUTA' then 4 when 'ENTREGADO' then 5 else null end;

  if p_nuevo_estado = 'CANCELADO' then
    if v_env.estado in ('ENTREGADO','CANCELADO') then
      raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
    end if;
  elsif p_nuevo_estado = 'NO_ENTREGADO' then
    if v_env.estado not in ('ASIGNADO','EN_RUTA') then
      raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
    end if;
    if coalesce(p_observacion,'') = '' then
      raise exception 'NO_ENTREGADO requiere observación';
    end if;
  elsif p_nuevo_estado = 'EN_RUTA' and v_env.estado = 'NO_ENTREGADO' then
    null; -- reintento tras no-entrega (patrón previo preservado)
  elsif v_rank_actual is null or v_rank_nuevo is null
     or v_rank_nuevo <= v_rank_actual then
    raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
  end if;

  update tbl_envios
  set estado=p_nuevo_estado,
      updated_at=now(),
      id_repartidor=case
        when p_nuevo_estado='EN_RUTA' and v_env.id_repartidor is null
        then fn_current_usuario_id()
        else v_env.id_repartidor end
  where id_envio=p_id_envio;

  insert into tbl_env_seguimiento_estados(
    id_envio,estado,observacion,latitud,longitud,usuario_id
  )
  values(
    p_id_envio,p_nuevo_estado,p_observacion,p_latitud,p_longitud,
    fn_current_usuario_id()
  );

  return jsonb_build_object(
    'resultado','ESTADO_ACTUALIZADO',
    'id_envio',p_id_envio,
    'estado',p_nuevo_estado
  );
end;
$$;

-- (v2/HU-032/033/034) Movimientos manuales de inventario (entradas/salidas/ajustes).
create or replace function fn_movimiento_inventario(
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_tipo tipo_movimiento_inventario,
  p_cantidad integer,
  p_referencia_tipo text default 'MANUAL',
  p_referencia_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_inv tbl_inventario%rowtype;
  v_delta int;
begin
  if p_tipo not in ('ENTRADA','SALIDA','AJUSTE','DEVOLUCION') then
    raise exception 'Tipo manual inválido: use ENTRADA/SALIDA/AJUSTE/DEVOLUCION';
  end if;
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser positiva';
  end if;
  if not fn_tiene_acceso_sucursal(
    (select s.id_comercio from tbl_sucursales s where s.id_sucursal=p_id_sucursal),
    p_id_sucursal) then
    raise exception 'Sin acceso a la sucursal';
  end if;

  select * into v_inv from tbl_inventario
  where id_sucursal=p_id_sucursal and id_variante=p_id_variante
  for update;

  if not found then
    if p_tipo<>'ENTRADA' then
      raise exception 'No existe inventario para esa variante en la sucursal';
    end if;
    insert into tbl_inventario(id_sucursal,id_variante,stock_actual,stock_reservado)
    values(p_id_sucursal,p_id_variante,0,0)
    returning * into v_inv;
  end if;

  v_delta := case p_tipo when 'SALIDA' then -p_cantidad else p_cantidad end;

  update tbl_inventario
  set stock_actual=stock_actual+v_delta
  where id_inventario=v_inv.id_inventario;

  if (select stock_actual from tbl_inventario where id_inventario=v_inv.id_inventario)<0 then
    raise exception 'Stock insuficiente para SALIDA de %',p_cantidad;
  end if;

  insert into tbl_inventario_movimientos(
    id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
  )
  values(
    (select id_comercio from tbl_sucursales where id_sucursal=p_id_sucursal),
    p_id_sucursal,p_id_variante,p_tipo,p_cantidad,
    p_referencia_tipo,p_referencia_id,fn_current_usuario_id()
  );

  return jsonb_build_object('resultado','MOVIMIENTO_OK','delta',v_delta);
end;
$$;


-- Auditoría genérica
create or replace function fn_auditar_cambio()
returns trigger
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_id_comercio uuid;
  v_registro_id uuid;
begin
  begin
    v_registro_id := coalesce((to_jsonb(new)->>'id')::uuid,(to_jsonb(old)->>'id')::uuid);
  exception when others then
    v_registro_id := null;
  end;

  begin
    v_id_comercio := coalesce(
      (to_jsonb(new)->>'id_comercio')::uuid,
      (to_jsonb(old)->>'id_comercio')::uuid
    );
  exception when others then
    v_id_comercio := null;
  end;

  insert into tbl_logs_auditoria(
    id_comercio,id_usuario,accion,tabla,registro_id,
    datos_anteriores,datos_nuevos
  )
  values(
    v_id_comercio,fn_current_usuario_id(),tg_op,tg_table_name,
    v_registro_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );

  return coalesce(new,old);
end;
$$;


-- (v2/A12) Auditoría ACTIVA en tablas críticas (HU-127..131).
do $$
declare t text;
begin
  foreach t in array array[
    'tbl_usuario_comercio','tbl_comercio_config','tbl_variantes','tbl_inventario',
    'tbl_reservas','tbl_pedidos','tbl_comprobantes_pago','tbl_verificaciones',
    'tbl_movimientos_creditos','tbl_envios'
  ] loop
    execute format('drop trigger if exists trg_audit_%s on %I',t,t);
    execute format(
      'create trigger trg_audit_%s after insert or update or delete on %I for each row execute function fn_auditar_cambio()',t,t);
  end loop;
end $$;


-- Procesar reservas vencidas (cron / WF-30)
create or replace function fn_procesar_reservas_vencidas(p_limite integer default 100)
returns integer
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_count integer := 0;
  r record;
begin
  for r in
    select id_reserva
    from tbl_reservas
    where estado='ACTIVA'
      and fecha_expiracion <= now()
    order by fecha_expiracion
    limit p_limite
    for update skip locked
  loop
    begin
      perform fn_expirar_reserva(r.id_reserva);
      v_count := v_count+1;
    exception when others then
      raise warning 'No se pudo expirar reserva %: %',r.id_reserva,sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;

-- (v2/WF-21/HU-057..058) Registra un comprobante de pago y lo vincula al pedido
-- en espera de pago del cliente/comercio. SECURITY DEFINER para que n8n pueda
-- invocarla con la credencial anon (mismo patrón que fn_upsert_cliente), sin
-- requerir service_role en el app layer. Resuelve id_pedido si no se provee.
-- Migración 20: idempotencia de reenvío (D5). Mismo (id_comercio, numero_operacion):
--   * mismo pedido  → refresca datos y reutiliza el comprobante (el flujo continúa a verificación)
--   * otro pedido   → excepción COMPROBANTE_DUPLICADO (anti-fraude)
create or replace function fn_registrar_comprobante(
  p_id_comercio uuid,
  p_id_cliente uuid,
  p_tipo_archivo text,
  p_archivo_url text,
  p_monto_detectado numeric default null,
  p_fecha_detectada timestamptz default null,
  p_numero_operacion text default null,
  p_nombre_pagador text default null,
  p_estado rsuelvo.estado_comprobante default 'RECIBIDO',
  p_id_pedido uuid default null
)
returns table(id_comprobante uuid, id_pedido uuid)
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_id_comprobante uuid := gen_random_uuid();
  v_id_pedido uuid := p_id_pedido;
  v_existente uuid;
  v_pedido_existente uuid;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;

  if v_id_pedido is null then
    select p.id_pedido into v_id_pedido
    from tbl_pedidos p
    where p.id_comercio = p_id_comercio
      and p.id_cliente = p_id_cliente
      and p.estado = 'ESPERANDO_PAGO'
    order by p.created_at desc
    limit 1;
  end if;

  if v_id_pedido is null then
    raise exception 'No se encontro pedido en espera de pago para vincular el comprobante';
  end if;

  -- Idempotencia de reenvío: mismo numero de operacion en el mismo comercio
  if p_numero_operacion is not null then
    select c.id_comprobante, c.id_pedido
      into v_existente, v_pedido_existente
      from tbl_comprobantes_pago c
      where c.id_comercio = p_id_comercio
        and c.numero_operacion = p_numero_operacion
      limit 1;

    if v_existente is not null then
      if v_pedido_existente = v_id_pedido then
        update tbl_comprobantes_pago as c
           set tipo_archivo     = p_tipo_archivo,
               archivo_url      = p_archivo_url,
               monto_detectado  = coalesce(p_monto_detectado, c.monto_detectado),
               fecha_detectada  = coalesce(p_fecha_detectada, c.fecha_detectada),
               nombre_pagador   = coalesce(p_nombre_pagador, c.nombre_pagador),
               estado           = p_estado
         where c.id_comprobante = v_existente;
        return query select v_existente, v_id_pedido;
        return;
      else
        raise exception 'COMPROBANTE_DUPLICADO: el numero de operacion % ya fue registrado para otro pedido', p_numero_operacion;
      end if;
    end if;
  end if;

  insert into tbl_comprobantes_pago (
    id_comprobante, id_comercio, id_pedido, id_cliente,
    tipo_archivo, archivo_url, monto_detectado, fecha_detectada,
    numero_operacion, nombre_pagador, estado
  ) values (
    v_id_comprobante, p_id_comercio, v_id_pedido, p_id_cliente,
    p_tipo_archivo, p_archivo_url, p_monto_detectado, p_fecha_detectada,
    p_numero_operacion, p_nombre_pagador, p_estado
  );

  return query select v_id_comprobante, v_id_pedido;
end;
$$;

grant execute on function fn_registrar_comprobante(
  uuid, uuid, text, text, numeric, timestamptz, text, text, rsuelvo.estado_comprobante, uuid
) to anon, authenticated, service_role;


-- (D14/migración 27) Consume 1 crédito por venta confirmada — SD-1: saldo puede quedar
-- negativo (la venta NUNCA se bloquea); atribuye usuario_id del cajero vía JWT (D13).
create or replace function fn_consumir_credito_venta(
  p_id_comercio uuid,
  p_id_pedido uuid
)
returns bigint
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_cuenta tbl_cuentas_creditos%rowtype;
  v_anterior bigint;
  v_nuevo bigint;
begin
  select * into v_cuenta
  from tbl_cuentas_creditos
  where id_comercio=p_id_comercio
  for update;

  if not found then
    insert into tbl_cuentas_creditos(id_comercio,saldo_actual)
    values(p_id_comercio,0)
    returning * into v_cuenta;
  end if;

  v_anterior := v_cuenta.saldo_actual;
  v_nuevo := v_anterior - 1;

  update tbl_cuentas_creditos
  set saldo_actual=v_nuevo
  where id_cuenta_creditos=v_cuenta.id_cuenta_creditos;

  insert into tbl_movimientos_creditos(
    id_comercio,id_cuenta_creditos,tipo,cantidad,
    saldo_anterior,saldo_posterior,concepto,referencia_tipo,referencia_id,usuario_id
  )
  values(
    p_id_comercio,v_cuenta.id_cuenta_creditos,
    'CONSUMO_VENTA',-1,
    v_anterior,v_nuevo,
    'Consumo de crédito por venta confirmada (D14)',
    'PEDIDO',p_id_pedido,
    fn_current_usuario_id()
  );

  return 1;
end;
$$;


-- ========== (Migración 30) F5 — Logística de entrega ==========
-- fn_registrar_entrega: valida PAGADO, actualiza nombre del cliente, crea envío
-- vía fn_crear_envio (pedido -> PREPARANDO). Ver cuerpo completo en
-- 30_logistica_entrega_eventos.sql (idéntico en cloud).
-- fn_notifica_pedido_pagado / fn_notifica_envio_estado: triggers pg_net (07_triggers.sql).

-- Catálogo de puntos de entrega para selección guiada (m33 / OBS-003)
create or replace function fn_listar_puntos_entrega(p_id_sucursal uuid)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_opciones jsonb := '[]'::jsonb;
  r RECORD;
  v_n integer := 0;
begin
  for r in
    select p.*, t.nombre as transportadora
    from tbl_puntos_entrega p
    left join tbl_transportadoras t on t.id_transportadora = p.id_transportadora
    where p.id_sucursal = p_id_sucursal and p.activo
    order by p.orden, p.nombre
  loop
    v_n := v_n + 1;
    v_opciones := v_opciones || jsonb_build_object(
      'opcion', v_n,
      'id_punto_entrega', r.id_punto_entrega,
      'tipo', r.tipo,
      'nombre', r.nombre,
      'ciudad', r.ciudad,
      'direccion', r.direccion,
      'referencia', r.referencia,
      'transportadora', r.transportadora
    );
  end loop;
  return jsonb_build_object('puntos', v_opciones);
end;
$$;

-- Registro de entrega v2 (m33 / OBS-003): selección guiada por punto; elimina dirección libre
create or replace function fn_registrar_entrega(p_id_pedido uuid, p_datos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
DECLARE
  v_pedido tbl_pedidos%rowtype;
  v_punto tbl_puntos_entrega%rowtype;
  v_nombre text;
  v_telefono text;
  v_id_envio uuid;
BEGIN
  SELECT * INTO v_pedido
  FROM tbl_pedidos
  WHERE id_pedido=p_id_pedido
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido inexistente';
  END IF;

  IF v_pedido.estado <> 'PAGADO' THEN
    RAISE EXCEPTION 'El pedido % no está PAGADO (estado: %)', p_id_pedido, v_pedido.estado;
  END IF;

  IF EXISTS (SELECT 1 FROM tbl_envios WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'El pedido ya tiene envío registrado';
  END IF;

  v_telefono := NULLIF(trim(COALESCE(p_datos->>'telefono','')), '');
  IF v_telefono IS NULL THEN
    RAISE EXCEPTION 'Faltan datos de entrega obligatorios (telefono)';
  END IF;

  SELECT * INTO v_punto
  FROM tbl_puntos_entrega
  WHERE id_punto_entrega = (p_datos->>'id_punto_entrega')::uuid
    AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Punto de entrega inexistente o inactivo';
  END IF;
  IF v_punto.id_sucursal <> v_pedido.id_sucursal THEN
    RAISE EXCEPTION 'El punto no pertenece a la sucursal del pedido';
  END IF;

  -- El nombre actualiza el perfil del cliente (tbl_clientes.nombre)
  v_nombre := NULLIF(trim(COALESCE(p_datos->>'nombre','')), '');
  IF v_nombre IS NOT NULL THEN
    UPDATE tbl_clientes SET nombre=v_nombre WHERE id_cliente=v_pedido.id_cliente;
  END IF;

  -- Denormalización para la hoja de ruta del repartidor
  v_id_envio := fn_crear_envio(
    p_id_pedido,
    v_punto.nombre || ' - ' || v_punto.ciudad || '. ' || v_punto.direccion,
    v_punto.referencia,
    v_telefono
  );
  UPDATE tbl_envios SET id_punto_entrega=v_punto.id_punto_entrega WHERE id_envio=v_id_envio;

  RETURN jsonb_build_object(
    'resultado','ENTREGA_REGISTRADA',
    'id_envio',v_id_envio,
    'id_pedido',p_id_pedido,
    'id_punto_entrega',v_punto.id_punto_entrega,
    'tipo_punto',v_punto.tipo,
    'estado_envio','PENDIENTE'
  );
END;
$$;

-- Helper del estado conversacional de entrega (m33b / OBS-003):
-- el pedido PAGADO sin envío ES la pregunta pendiente — la BD decide, n8n orquesta (Regla 3)
create or replace function fn_pedido_entrega_pendiente(p_telefono text)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
DECLARE
  v_pedido RECORD;
BEGIN
  SELECT p.id_pedido, p.numero_pedido, p.id_sucursal
  INTO v_pedido
  FROM tbl_pedidos p
  JOIN tbl_clientes c ON c.id_cliente = p.id_cliente
  WHERE COALESCE(c.telefono_whatsapp, c.telefono) = p_telefono
    AND p.estado = 'PAGADO'
    AND NOT EXISTS (SELECT 1 FROM tbl_envios e WHERE e.id_pedido = p.id_pedido)
  ORDER BY p.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('pendiente', false);
  END IF;

  RETURN jsonb_build_object(
    'pendiente', true,
    'id_pedido', v_pedido.id_pedido,
    'numero_pedido', v_pedido.numero_pedido,
    'id_sucursal', v_pedido.id_sucursal
  );
END;
$$;

comment on function fn_pedido_entrega_pendiente(text) is 'Resuelve si el comprador tiene un pedido PAGADO sin envío (pregunta de entrega pendiente — OBS-003). Retorna pendiente/id_pedido/numero_pedido/id_sucursal.';

-- ==== MIGRACIÓN 40 (2026-09-10): catálogo por sucursal ====
CREATE OR REPLACE FUNCTION rsuelvo.fn_es_admin_o_cajero_comercio(p_id_comercio uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select fn_es_service_role() or fn_es_superadmin() or exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid() and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_TENANT_CASHIER')
  );
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_puede_gestionar_catalogo(p_id_comercio uuid, p_id_sucursal uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select fn_es_service_role() or fn_es_superadmin() or exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid() and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and (r.codigo='ROLE_TENANT_ADMIN' or (r.codigo='ROLE_TENANT_CASHIER' and uc.id_sucursal=p_id_sucursal))
  );
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_variante_efectiva(p_id_variante uuid, p_id_sucursal uuid)
RETURNS TABLE(nombre text, precio numeric, activo boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select coalesce(vs.nombre, v.nombre), coalesce(vs.precio, v.precio), coalesce(vs.activo, v.activo)
  from tbl_variantes v
  left join tbl_variante_sucursal vs on vs.id_variante=v.id_variante and vs.id_sucursal=p_id_sucursal
  where v.id_variante=p_id_variante;
$function$;

-- fn_resolver_variante_por_sku v2 (con sucursal; se elimina la firma vieja de 2 args)
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_variante_por_sku(p_id_comercio uuid, p_sku text, p_id_sucursal uuid DEFAULT NULL)
RETURNS TABLE(id_variante uuid, nombre text, precio numeric, id_producto uuid)
LANGUAGE plpgsql STABLE SET search_path TO 'rsuelvo', 'pg_catalog'
AS $function$
begin
  if p_sku is null or p_sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido. Formato requerido: exactamente 6 caracteres [A-Z0-9]' using errcode = '22023';
  end if;
  return query
  select v.id_variante, e.nombre, e.precio, v.id_producto
  from tbl_variantes v
  cross join lateral fn_variante_efectiva(v.id_variante, p_id_sucursal) e
  where v.id_comercio=p_id_comercio and v.sku=p_sku and e.activo;
end;
$function$;
DROP FUNCTION IF EXISTS rsuelvo.fn_resolver_variante_por_sku(uuid, text);

-- Listado por sucursal (efectivo + override flag + stock)
CREATE OR REPLACE FUNCTION rsuelvo.fn_listar_variantes_sucursal(p_id_sucursal uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_comercio uuid;
  v_out jsonb;
BEGIN
  SELECT s.id_comercio INTO v_comercio FROM tbl_sucursales s WHERE s.id_sucursal=p_id_sucursal;
  IF v_comercio IS NULL THEN RAISE EXCEPTION 'Sucursal inexistente'; END IF;
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'sku'),'[]'::jsonb) INTO v_out FROM (
    SELECT jsonb_build_object(
      'id_variante',v.id_variante,'sku',v.sku,'id_producto',v.id_producto,
      'nombre_global',v.nombre,'precio_global',v.precio,'activo_global',v.activo,
      'nombre',e.nombre,'precio',e.precio,'activo',e.activo,
      'tiene_override',(vs.id_variante IS NOT NULL),
      'stock_actual',coalesce(i.stock_actual,0),'stock_reservado',coalesce(i.stock_reservado,0)
    ) AS x
    FROM tbl_variantes v
    CROSS JOIN LATERAL fn_variante_efectiva(v.id_variante,p_id_sucursal) e
    LEFT JOIN tbl_variante_sucursal vs ON vs.id_variante=v.id_variante AND vs.id_sucursal=p_id_sucursal
    LEFT JOIN tbl_inventario i ON i.id_variante=v.id_variante AND i.id_sucursal=p_id_sucursal
    WHERE v.id_comercio=v_comercio
  ) t;
  RETURN jsonb_build_object('variantes',v_out);
END;
$function$;

-- m40: snapshot de venta con precio EFECTIVO de la sucursal
create or replace function fn_crear_pedido_desde_reserva(p_id_reserva uuid)
returns uuid language plpgsql security definer set search_path = rsuelvo, public
as $$
declare
  v_res tbl_reservas%rowtype; v_var tbl_variantes%rowtype; v_prod tbl_productos%rowtype;
  v_pedido uuid; v_subtotal numeric(14,2); v_ef_nombre text; v_ef_precio numeric(14,2);
begin
  select * into v_res from tbl_reservas where id_reserva=p_id_reserva for update;
  if not found then raise exception 'Reserva inexistente'; end if;
  if v_res.estado not in ('ACTIVA','PAGO_VALIDANDO') then raise exception 'La reserva no puede generar pedido'; end if;
  if v_res.id_pedido is not null then return v_res.id_pedido; end if;

  select v.* into v_var from tbl_variantes v where v.id_variante=v_res.id_variante;
  select p.* into v_prod from tbl_productos p where p.id_producto=v_var.id_producto;

  select e.nombre, e.precio into v_ef_nombre, v_ef_precio
  from fn_variante_efectiva(v_res.id_variante, v_res.id_sucursal) e;
  v_ef_nombre := coalesce(v_ef_nombre, v_var.nombre);
  v_ef_precio := coalesce(v_ef_precio, v_var.precio);
  v_subtotal := v_ef_precio * v_res.cantidad;

  insert into tbl_pedidos(id_comercio,id_sucursal,id_cliente,estado,subtotal,descuento,id_reserva)
  values(v_res.id_comercio,v_res.id_sucursal,v_res.id_cliente,'ESPERANDO_PAGO',v_subtotal,0,p_id_reserva)
  returning id_pedido into v_pedido;

  insert into tbl_pedido_detalles(id_pedido,id_variante,sku_snapshot,nombre_snapshot,precio_unitario,cantidad)
  values(v_pedido,v_var.id_variante,v_var.sku,v_prod.nombre || ' - ' || v_ef_nombre,v_ef_precio,v_res.cantidad);

  update tbl_reservas set id_pedido=v_pedido where id_reserva=p_id_reserva;
  return v_pedido;
end;
$$;

-- -- 34_entrega_captura_destino.sql [FUNCIONES]
CREATE OR REPLACE FUNCTION rsuelvo.fn_iniciar_captura_destino(p_id_pedido uuid, p_id_punto_entrega uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_pedido tbl_pedidos%rowtype;
  v_punto tbl_puntos_entrega%rowtype;
  v_transportadora text;
BEGIN
  SELECT * INTO v_pedido FROM tbl_pedidos WHERE id_pedido=p_id_pedido FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido inexistente'; END IF;
  IF v_pedido.estado <> 'PAGADO' THEN
    RAISE EXCEPTION 'El pedido % no está PAGADO (estado: %)', p_id_pedido, v_pedido.estado;
  END IF;
  IF EXISTS (SELECT 1 FROM tbl_envios WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'El pedido ya tiene envío registrado';
  END IF;
  IF EXISTS (SELECT 1 FROM tbl_entrega_captura WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'Ya existe una captura de destino en curso para este pedido';
  END IF;
  SELECT * INTO v_punto FROM tbl_puntos_entrega WHERE id_punto_entrega=p_id_punto_entrega AND activo;
  IF NOT FOUND THEN RAISE EXCEPTION 'Punto de entrega inexistente o inactivo'; END IF;
  IF v_punto.tipo <> 'ENVIO_TRANSPORTE' THEN
    RAISE EXCEPTION 'La captura de destino aplica solo a ENVIO_TRANSPORTE';
  END IF;
  IF v_punto.id_sucursal <> v_pedido.id_sucursal THEN
    RAISE EXCEPTION 'El punto no pertenece a la sucursal del pedido';
  END IF;
  SELECT t.nombre INTO v_transportadora FROM tbl_transportadoras t WHERE t.id_transportadora=v_punto.id_transportadora;
  INSERT INTO tbl_entrega_captura (id_pedido, id_comercio, id_punto_entrega)
  VALUES (p_id_pedido, v_pedido.id_comercio, p_id_punto_entrega);
  RETURN jsonb_build_object(
    'resultado','CAPTURA_INICIADA',
    'id_pedido',p_id_pedido,
    'id_punto_entrega',p_id_punto_entrega,
    'transportadora',v_transportadora
  );
END;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_entrega_captura_estado(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_row RECORD;
BEGIN
  SELECT c.id_pedido, c.destino_ciudad, c.destino_zona, pe.nombre AS punto, t.nombre AS transportadora
  INTO v_row
  FROM tbl_entrega_captura c
  JOIN tbl_pedidos p ON p.id_pedido = c.id_pedido
  JOIN tbl_clientes cl ON cl.id_cliente = p.id_cliente
  JOIN tbl_puntos_entrega pe ON pe.id_punto_entrega = c.id_punto_entrega
  LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
  WHERE COALESCE(cl.telefono_whatsapp, cl.telefono) = p_telefono
    AND p.estado = 'PAGADO'
    AND NOT EXISTS (SELECT 1 FROM tbl_envios e WHERE e.id_pedido = c.id_pedido)
    AND c.id_pedido = (SELECT p2.id_pedido FROM tbl_pedidos p2
                       WHERE p2.id_cliente = p.id_cliente
                         AND p2.estado = 'PAGADO'
                         AND NOT EXISTS (SELECT 1 FROM tbl_envios e2 WHERE e2.id_pedido = p2.id_pedido)
                       ORDER BY p2.created_at DESC LIMIT 1)
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('captura', false);
  END IF;
  RETURN jsonb_build_object(
    'captura', true,
    'paso', 'DESTINO',
    'id_pedido', v_row.id_pedido,
    'punto', v_row.punto,
    'transportadora', v_row.transportadora
  );
END;
$function$;

-- Cuerpo final vigente (incluye refinamientos 37/38: dígito = re-selección,
-- texto = solo ciudad, zona eliminada del flujo).
CREATE OR REPLACE FUNCTION rsuelvo.fn_procesar_captura_destino(p_telefono text, p_texto text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_punto RECORD;
  v_texto text;
  v_result jsonb;
BEGIN
  v_texto := NULLIF(trim(COALESCE(p_texto,'')), '');
  IF v_texto IS NULL THEN
    RAISE EXCEPTION 'Texto vacío';
  END IF;
  SELECT c.id_pedido, c.id_comercio, c.id_punto_entrega, c.destino_ciudad, c.destino_zona
  INTO v_row
  FROM tbl_entrega_captura c
  JOIN tbl_pedidos p ON p.id_pedido = c.id_pedido
  JOIN tbl_clientes cl ON cl.id_cliente = p.id_cliente
  WHERE COALESCE(cl.telefono_whatsapp, cl.telefono) = p_telefono
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('resultado','SIN_CAPTURA');
  END IF;
  -- Si responde un NÚMERO: es re-selección del punto de la lista (no una ciudad)
  IF v_texto ~ '^[0-9]+$' THEN
    SELECT pe.id_punto_entrega, pe.nombre, pe.tipo, pe.ciudad, pe.dias_atencion,
           pe.referencia, pe.horario_inicio, pe.horario_fin, t.nombre AS transportadora
    INTO v_punto
    FROM (
      SELECT pe2.*, row_number() OVER (ORDER BY pe2.orden, pe2.nombre) AS opcion
      FROM tbl_puntos_entrega pe2
      WHERE pe2.id_sucursal = (SELECT p3.id_sucursal FROM tbl_pedidos p3 WHERE p3.id_pedido = v_row.id_pedido)
        AND pe2.activo
    ) pe
    LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
    WHERE pe.opcion = v_texto::integer;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('resultado','OPCION_INVALIDA');
    END IF;
    IF v_punto.tipo = 'ENVIO_TRANSPORTE' THEN
      UPDATE tbl_entrega_captura
      SET id_punto_entrega = v_punto.id_punto_entrega,
          destino_ciudad = NULL,
          destino_zona = NULL
      WHERE id_pedido = v_row.id_pedido;
      RETURN jsonb_build_object(
        'resultado','CAPTURA_REINICIADA',
        'transportadora', v_punto.transportadora
      );
    END IF;
    -- Re-selección a punto no-transporte: registra la entrega directo
    v_result := fn_registrar_entrega(
      v_row.id_pedido,
      jsonb_build_object(
        'id_punto_entrega', v_punto.id_punto_entrega,
        'telefono', p_telefono
      )
    );
    DELETE FROM tbl_entrega_captura WHERE id_pedido = v_row.id_pedido;
    RETURN v_result;
  END IF;
  -- Texto normal = la ciudad
  v_texto := left(v_texto, 120);
  UPDATE tbl_entrega_captura
  SET destino_ciudad = v_texto, destino_zona = NULL
  WHERE id_pedido = v_row.id_pedido;
  v_result := fn_registrar_entrega(
    v_row.id_pedido,
    jsonb_build_object(
      'id_punto_entrega', v_row.id_punto_entrega,
      'telefono', p_telefono,
      'destino_ciudad', v_texto
    )
  );
  DELETE FROM tbl_entrega_captura WHERE id_pedido = v_row.id_pedido;
  RETURN v_result;
END;
$function$;

-- -- 35_lista_pendiente_momento1.sql [FUNCIONES]
CREATE OR REPLACE FUNCTION rsuelvo.fn_pendiente_lista(p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
BEGIN
  INSERT INTO tbl_lista_pendiente (id_cliente, id_comercio, id_sucursal, id_variante)
  VALUES (p_id_cliente, p_id_comercio, p_id_sucursal, p_id_variante)
  ON CONFLICT (id_cliente) DO UPDATE
    SET id_comercio = EXCLUDED.id_comercio,
        id_sucursal = EXCLUDED.id_sucursal,
        id_variante = EXCLUDED.id_variante;
  RETURN jsonb_build_object('resultado','PENDIENTE_LISTA');
END;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_aceptar_pendiente_lista(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_pend RECORD;
  v_sku text;
  v_nombre text;
  v_precio numeric;
  v_pos_existente integer;
BEGIN
  SELECT * INTO v_pend
  FROM tbl_lista_pendiente
  WHERE id_cliente = (SELECT id_cliente FROM tbl_clientes WHERE COALESCE(telefono_whatsapp, telefono) = p_telefono LIMIT 1)
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('resultado','SIN_PENDIENTE');
  END IF;
  -- Guarda: si ya está en la lista para esta variante, no duplicar
  SELECT posicion INTO v_pos_existente
  FROM tbl_lista_espera
  WHERE id_cliente = v_pend.id_cliente
    AND id_variante = v_pend.id_variante
    AND estado IN ('ESPERANDO','NOTIFICADO')
  LIMIT 1;
  DELETE FROM tbl_lista_pendiente WHERE id_cliente = v_pend.id_cliente;
  SELECT sku, nombre, precio INTO v_sku, v_nombre, v_precio
  FROM tbl_variantes WHERE id_variante = v_pend.id_variante;
  IF v_pos_existente IS NOT NULL THEN
    RETURN jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'posicion', v_pos_existente,
      'id_comercio', v_pend.id_comercio,
      'sku', v_sku,
      'nombre', v_nombre,
      'precio', v_precio
    );
  END IF;
  RETURN jsonb_build_object(
    'resultado','PENDIENTE_OK',
    'id_comercio', v_pend.id_comercio,
    'id_sucursal', v_pend.id_sucursal,
    'id_variante', v_pend.id_variante,
    'id_cliente', v_pend.id_cliente,
    'sku', v_sku,
    'nombre', v_nombre,
    'precio', v_precio
  );
END;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_rechazar_pendiente_lista(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  DELETE FROM tbl_lista_pendiente
  WHERE id_cliente = (SELECT id_cliente FROM tbl_clientes WHERE COALESCE(telefono_whatsapp, telefono) = p_telefono LIMIT 1);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RETURN jsonb_build_object('resultado','SIN_PENDIENTE');
  END IF;
  RETURN jsonb_build_object('resultado','LISTA_RECHAZADA');
END;
$function$;

-- -- 36_guia_foto.sql [FUNCIONES]
CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_guia(p_id_envio uuid, p_numero_guia text DEFAULT NULL, p_guia_foto_url text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_env tbl_envios%rowtype;
  v_tipo text;
  v_transportadora text;
  v_phone text;
  v_nuevo_num text;
  v_nueva_foto text;
BEGIN
  SELECT * INTO v_env FROM tbl_envios WHERE id_envio=p_id_envio FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Envío inexistente'; END IF;
  SELECT pe.tipo, t.nombre INTO v_tipo, v_transportadora
  FROM tbl_puntos_entrega pe
  LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
  WHERE pe.id_punto_entrega = v_env.id_punto_entrega;
  IF v_tipo IS NULL OR v_tipo NOT IN ('ENVIO_TRANSPORTE','PUNTO_LOCAL') THEN
    RAISE EXCEPTION 'La guía/código aplica solo a ENVIO_TRANSPORTE o PUNTO_LOCAL';
  END IF;
  IF v_env.estado NOT IN ('PREPARANDO','ASIGNADO','EN_RUTA') THEN
    RAISE EXCEPTION 'El envío debe estar PREPARANDO, ASIGNADO o EN_RUTA (estado: %)', v_env.estado;
  END IF;
  v_nuevo_num  := NULLIF(trim(COALESCE(p_numero_guia,'')), '');
  v_nueva_foto := NULLIF(trim(COALESCE(p_guia_foto_url,'')), '');
  IF v_nuevo_num IS NULL AND v_nueva_foto IS NULL THEN
    RAISE EXCEPTION 'Debe proporcionar numero_guia y/o guia_foto_url';
  END IF;
  UPDATE tbl_envios
  SET numero_guia   = COALESCE(v_nuevo_num, numero_guia),
      guia_foto_url = COALESCE(v_nueva_foto, guia_foto_url)
  WHERE id_envio = p_id_envio
  RETURNING numero_guia, guia_foto_url INTO v_nuevo_num, v_nueva_foto;
  SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
  FROM tbl_clientes
  WHERE id_cliente = (SELECT id_cliente FROM tbl_pedidos WHERE id_pedido = v_env.id_pedido);
  PERFORM net.http_post(
    url    => 'https://rsuelvotest.app.n8n.cloud/webhook/entrega/estado',
    body   => jsonb_build_object(
      'token', 'RSU_entrega_notif_7Qk2mXwP',
      'motivo', 'guia_registrada',
      'id_envio', v_env.id_envio,
      'id_pedido', v_env.id_pedido,
      'id_comercio', v_env.id_comercio,
      'phone', v_phone,
      'numero_guia', v_nuevo_num,
      'guia_foto_url', v_nueva_foto,
      'transportadora', v_transportadora,
      'destino_ciudad', v_env.destino_ciudad,
      'destino_zona', v_env.destino_zona
    ),
    headers => jsonb_build_object('Content-Type', 'application/json')
  );
  RETURN jsonb_build_object(
    'resultado','GUIA_REGISTRADA',
    'id_envio', p_id_envio,
    'numero_guia', v_nuevo_num,
    'guia_foto_url', v_nueva_foto,
    'tipo_punto', v_tipo
  );
END;
$function$;

-- -- m31 fn_rechazar_lista_espera (espejo)
CREATE OR REPLACE FUNCTION rsuelvo.fn_rechazar_lista_espera(p_id_lista_espera uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_item tbl_lista_espera%rowtype;
  v_nuevo_estado estado_lista_espera;
BEGIN
  SELECT * INTO v_item FROM tbl_lista_espera WHERE id_lista_espera = p_id_lista_espera FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrada de lista inexistente'; END IF;
  IF v_item.estado = 'NOTIFICADO' THEN
    v_nuevo_estado := 'RECHAZADO';
  ELSIF v_item.estado = 'ESPERANDO' THEN
    v_nuevo_estado := 'CANCELADO';
  ELSE
    RAISE EXCEPTION 'Solo se pueden rechazar entradas NOTIFICADO o cancelar ESPERANDO (estado actual: %)', v_item.estado;
  END IF;
  UPDATE tbl_lista_espera SET estado = v_nuevo_estado, updated_at = now() WHERE id_lista_espera = p_id_lista_espera;
  RETURN jsonb_build_object(
    'resultado', 'OPORTUNIDAD_RECHAZADA',
    'estado_anterior', v_item.estado,
    'estado_nuevo', v_nuevo_estado,
    'id_lista_espera', p_id_lista_espera,
    'id_sucursal', v_item.id_sucursal,
    'id_variante', v_item.id_variante
  );
END;
$function$;

-- -- m40 fn_notificar_siguiente_lista_espera (cuerpo exacto cloud)
CREATE OR REPLACE FUNCTION rsuelvo.fn_notificar_siguiente_lista_espera(p_id_sucursal uuid, p_id_variante uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_item tbl_lista_espera%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_ef_nombre text;
  v_ef_precio numeric(14,2);
begin
  select * into v_item
  from tbl_lista_espera cand
  where cand.id_sucursal=p_id_sucursal
    and cand.id_variante=p_id_variante
    and cand.estado='ESPERANDO'
    and not exists (
      select 1 from tbl_lista_espera act
      where act.id_cliente = cand.id_cliente
        and act.estado='NOTIFICADO'
        and act.fecha_expiracion > now()
    )
  order by cand.posicion
  limit 1
  for update skip locked;
  if not found then
    return jsonb_build_object('resultado','LISTA_VACIA');
  end if;
  select * into v_cfg from tbl_comercio_config where id_comercio=v_item.id_comercio;
  update tbl_lista_espera
  set estado='NOTIFICADO',
      fecha_notificacion=now(),
      fecha_expiracion=now()+make_interval(mins=>v_cfg.tiempo_aceptacion_lista_espera_minutos)
  where id_lista_espera=v_item.id_lista_espera;
  -- m40: valores efectivos de la sucursal del grupo (para el mensaje de oportunidad)
  select e.nombre, e.precio into v_ef_nombre, v_ef_precio
  from fn_variante_efectiva(v_item.id_variante, v_item.id_sucursal) e;
  return jsonb_build_object(
    'resultado','CLIENTE_NOTIFICADO',
    'id_lista_espera',v_item.id_lista_espera,
    'id_cliente',v_item.id_cliente,
    'fecha_expiracion',(select fecha_expiracion from tbl_lista_espera where id_lista_espera=v_item.id_lista_espera),
    'nombre', v_ef_nombre,
    'precio', v_ef_precio,
    'tiempo_aceptacion_minutos', v_cfg.tiempo_aceptacion_lista_espera_minutos
  );
end;
$function$;


-- -- 41_lista_espera_agregar_v2.sql [FUNCIONES]
CREATE OR REPLACE FUNCTION rsuelvo.fn_agregar_lista_espera_v2(
  p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_max integer;
  v_activos integer;
  v_pos integer;
  v_id uuid;
  v_existente record;
begin
  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;
  select max_lista_espera_por_producto into v_max
  from tbl_comercio_config
  where id_comercio=p_id_comercio;
  if v_max is null then
    raise exception 'Configuración de comercio inexistente';
  end if;
  perform 1
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;
  select id_lista_espera, posicion into v_existente
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
  limit 1;
  if found then
    return jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera', v_existente.id_lista_espera,
      'posicion', v_existente.posicion
    );
  end if;
  select count(*) into v_activos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');
  if v_activos >= v_max then
    return jsonb_build_object(
      'resultado','LISTA_LLENA',
      'activos', v_activos,
      'maximo', v_max
    );
  end if;
  select coalesce(max(posicion),0)+1 into v_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO');
  insert into tbl_lista_espera(
    id_comercio,id_sucursal,id_variante,id_cliente,posicion,estado
  )
  values(
    p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,v_pos,'ESPERANDO'
  )
  returning id_lista_espera into v_id;
  return jsonb_build_object(
    'resultado','AGREGADO',
    'id_lista_espera', v_id,
    'posicion', v_pos
  );
exception
  when unique_violation then
    select id_lista_espera, posicion into v_existente
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
      and id_variante=p_id_variante
      and id_cliente=p_id_cliente
      and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
    limit 1;
    return jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera', v_existente.id_lista_espera,
      'posicion', v_existente.posicion
    );
end;
$function$;


-- -- 42_solicitar_reserva_ya_en_lista.sql [FUNCIONES]
CREATE OR REPLACE FUNCTION rsuelvo.fn_solicitar_reserva(p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid, p_cantidad integer DEFAULT 1)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_inv tbl_inventario%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_reserva uuid;
  v_pedido uuid;
  v_precio numeric(14,2);
  v_reserva_existente uuid;
  v_fecha_expiracion timestamptz;
  v_lista_id uuid;
  v_lista_pos integer;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0';
  end if;
  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;
  select * into v_cfg from tbl_comercio_config where id_comercio=p_id_comercio;
  if not found then
    raise exception 'El comercio no tiene configuración';
  end if;
  select v.precio into v_precio
  from tbl_variantes v
  join tbl_productos p on p.id_producto=v.id_producto
  where v.id_variante=p_id_variante
    and p.id_comercio=p_id_comercio
    and v.activo
    and p.activo;
  if v_precio is null then
    raise exception 'SKU/variante inválida para el comercio';
  end if;
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  for update;
  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;
  select * into v_inv
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;
  if not found then
    -- m42: avisar si ya está en lista (misma sucursal×variante, vigente)
    select id_lista_espera, posicion into v_lista_id, v_lista_pos
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
      and id_variante=p_id_variante
      and id_cliente=p_id_cliente
      and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
    limit 1;
    return jsonb_build_object(
      'resultado','SIN_STOCK',
      'motivo','NO_EXISTE_INVENTARIO',
      'ya_en_lista', found,
      'posicion', v_lista_pos,
      'id_lista_espera', v_lista_id
    );
  end if;
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  limit 1;
  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;
  if (v_inv.stock_actual-v_inv.stock_reservado) >= p_cantidad then
    update tbl_inventario
    set stock_reservado=stock_reservado+p_cantidad
    where id_inventario=v_inv.id_inventario;
    insert into tbl_reservas(
      id_comercio,id_sucursal,id_variante,id_cliente,
      origen,estado,cantidad,fecha_inicio,fecha_expiracion
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,
      'DIRECTA','ACTIVA',p_cantidad,now(),
      now() + make_interval(mins=>v_cfg.tiempo_reserva_minutos)
    )
    returning id_reserva into v_reserva;
    insert into tbl_inventario_movimientos(
      id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,'RESERVA',
      p_cantidad,'RESERVA',v_reserva,fn_current_usuario_id()
    );
    return jsonb_build_object(
      'resultado','RESERVA_CREADA',
      'id_reserva',v_reserva,
      'fecha_expiracion',(
        select fecha_expiracion from tbl_reservas where id_reserva=v_reserva
      )
    );
  end if;
  -- m42: avisar si ya está en lista (misma sucursal×variante, vigente)
  select id_lista_espera, posicion into v_lista_id, v_lista_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
  limit 1;
  return jsonb_build_object(
    'resultado','SIN_STOCK',
    'motivo','PRODUCTO_RESERVADO_O_AGOTADO',
    'ya_en_lista', found,
    'posicion', v_lista_pos,
    'id_lista_espera', v_lista_id
  );
end;
$function$;
