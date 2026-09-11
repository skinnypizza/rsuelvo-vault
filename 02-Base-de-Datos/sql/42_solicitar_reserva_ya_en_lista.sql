-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 42 (2026-09-11)
-- SIN_STOCK avisa si ya está en lista (base del atajo UX en WF-10)
-- ============================================================
-- Decisión del dueño: quien ya está en lista y reenvía el SKU recibe directo
-- "Ya estás en la lista #N" sin la pregunta SI/NO de Momento 1.
-- Se agregan a AMBOS retornos SIN_STOCK: ya_en_lista (boolean),
-- posicion (integer|null), id_lista_espera (uuid|null). Lookup por
-- (sucursal, variante, cliente) con estado en (ESPERANDO, NOTIFICADO, ACEPTADO).
-- Sin regresiones: RESERVA_CREADA/YA_EXISTENTE intactos; el NO de Momento 1 solo
-- borraba el pendiente, así que saltar la pregunta no quita vías de salida.
-- Validado: buyer2/FERC01 → ya_en_lista true pos 1; buyer1/FERC01 → false/nulls.

-- == FUNCIONES ==
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
