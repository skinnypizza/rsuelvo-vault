-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 43 (2026-09-11)
-- SIN_STOCK avisa si la lista está LLENA (OBS-006, base del atajo en WF-10)
-- ============================================================
-- OBS del dueño: con lista llena, el comprador nuevo recibe directo
-- "Lo sentimos, el producto que busca no tiene stock y la lista de espera está llena"
-- sin la pregunta SI/NO de Momento 1.
-- Se agrega a AMBOS retornos SIN_STOCK (solo cuando NO está en lista):
-- lista_llena (boolean), activos (integer|null), maximo (integer|null).
-- Conteo con el mismo conjunto vigente de m41/m42 (ESPERANDO/NOTIFICADO/ACEPTADO);
-- el máximo se reusa de v_cfg (ya cargado); COALESCE contra config nula → nunca llena
-- (degrada a la pregunta; v2 impone el límite real al aceptar).
-- Validado con cupo temporal 1: buyer1/FERC01 → lista_llena true (1/1);
-- buyer2/FERC01 → ya_en_lista true (conteo omitido). Cupo restaurado a 5.

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
  v_ya boolean;
  v_llena boolean;
  v_activos integer;
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
    v_ya := found;
    v_llena := false;
    v_activos := null;
    if not v_ya then
      select count(*) into v_activos
      from tbl_lista_espera
      where id_sucursal=p_id_sucursal
        and id_variante=p_id_variante
        and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');
      v_llena := v_activos >= coalesce(v_cfg.max_lista_espera_por_producto, 2147483647);
    end if;
    return jsonb_build_object(
      'resultado','SIN_STOCK',
      'motivo','NO_EXISTE_INVENTARIO',
      'ya_en_lista', v_ya,
      'posicion', v_lista_pos,
      'id_lista_espera', v_lista_id,
      'lista_llena', v_llena,
      'activos', v_activos,
      'maximo', v_cfg.max_lista_espera_por_producto
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
  v_ya := found;
  v_llena := false;
  v_activos := null;
  if not v_ya then
    select count(*) into v_activos
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');
    v_llena := v_activos >= coalesce(v_cfg.max_lista_espera_por_producto, 2147483647);
  end if;
  return jsonb_build_object(
    'resultado','SIN_STOCK',
    'motivo','PRODUCTO_RESERVADO_O_AGOTADO',
    'ya_en_lista', v_ya,
    'posicion', v_lista_pos,
    'id_lista_espera', v_lista_id,
    'lista_llena', v_llena,
    'activos', v_activos,
    'maximo', v_cfg.max_lista_espera_por_producto
  );
end;
$function$;
