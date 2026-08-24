-- ============================================================
-- RSUELVO v2 :: 6. FUNCIONES
-- ============================================================

set search_path = rsuelvo, public;

-- Validación de asignación usuario/comercio (cajero = 1 sucursal)
create or replace function fn_validar_asignacion_usuario_comercio()
returns trigger
language plpgsql
as $$
declare
  v_codigo rol_codigo;
  v_sucursal uuid;
begin
  select codigo into v_codigo from tbl_roles where id_rol=new.id_rol;

  if v_codigo in ('ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT')
     and new.id_sucursal is null then
    raise exception 'El rol % requiere una sucursal',v_codigo;
  end if;

  if v_codigo='ROLE_TENANT_CASHIER' then
    if exists (
      select 1
      from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol=uc.id_rol
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
create or replace function fn_resolver_variante_tenant_sku()
returns trigger
language plpgsql
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
    from tbl_productos p
    where p.id_producto=new.id_producto;
  end if;

  if v_comercio is null then
    raise exception 'Producto inexistente';
  end if;

  new.id_comercio := v_comercio;

  select codigo_tienda into v_codigo
  from tbl_comercios
  where id_comercio=v_comercio;

  if v_codigo is null then
    raise exception 'El comercio % no tiene codigo_tienda asignado',v_comercio;
  end if;

  -- 2) Generar SKU si no viene (o venir vacío).
  if coalesce(new.sku,'')='' then
    -- serializar por comercio: bloquea la fila del comercio.
    select 1 into v_max from tbl_comercios
    where id_comercio=v_comercio for update;

    select coalesce(max(
      ('x'||substr(v.sku,4,3))::bit(12)::int
    ),0) into v_max
    from tbl_variantes v
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
    select 1 from tbl_variantes v
    where v.id_comercio=v_comercio
      and v.sku=new.sku
      and v.id_variante<>coalesce(new.id_variante,'00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    raise exception 'SKU duplicado dentro del comercio: %',new.sku;
  end if;

  return new;
end;
$$;


-- Consistencia multi-tenant
create or replace function fn_validar_consistencia_tenant()
returns trigger
language plpgsql
as $$
declare
  v_comercio uuid;
begin
  -- Sucursal pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_lista_espera','tbl_pedidos','tbl_envios') then
    select id_comercio into v_comercio
    from tbl_sucursales
    where id_sucursal=new.id_sucursal;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'La sucursal no pertenece al comercio';
    end if;
  end if;

  -- Cliente pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_pedidos','tbl_comprobantes_pago') then
    select id_comercio into v_comercio
    from tbl_clientes
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

-- Guard: rechazar si NO es service_role
create or replace function fn_assert_service_role()
returns void
language plpgsql
as $$
begin
  if not fn_es_service_role() then
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


-- Reserva atómica
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

  -- Bloqueo pesimista: solo una transacción modifica esta fila.
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


-- Notificar siguiente de la lista
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
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado='ESPERANDO'
  order by posicion
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

  select * into v_res
  from tbl_reservas
  where id_pedido=v_ver.id_pedido
  for update;

  if not found then
    raise exception 'No existe reserva asociada al pedido';
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
create or replace function fn_actualizar_estado_envio(
  p_id_envio uuid,
  p_nuevo_estado estado_envio,
  p_observacion text default null,
  p_latitud numeric(9,6) default null,
  p_longitud numeric(9,6) default null
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_env tbl_envios%rowtype;
begin
  select * into v_env from tbl_envios
  where id_envio=p_id_envio for update;

  if not found then
    raise exception 'Envío inexistente';
  end if;

  if not (
    (v_env.estado='PENDIENTE'   and p_nuevo_estado in ('PREPARANDO','CANCELADO'))
 or (v_env.estado='PREPARANDO' and p_nuevo_estado in ('ASIGNADO','CANCELADO'))
 or (v_env.estado='ASIGNADO'   and p_nuevo_estado in ('EN_RUTA','CANCELADO'))
 or (v_env.estado='EN_RUTA'    and p_nuevo_estado in ('ENTREGADO','NO_ENTREGADO'))
 or (v_env.estado='NO_ENTREGADO' and p_nuevo_estado in ('EN_RUTA'))
  ) then
    raise exception 'Transición inválida: % -> %',v_env.estado,p_nuevo_estado;
  end if;

  if p_nuevo_estado='NO_ENTREGADO' and coalesce(p_observacion,'')='' then
    raise exception 'NO_ENTREGADO requiere observación';
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
