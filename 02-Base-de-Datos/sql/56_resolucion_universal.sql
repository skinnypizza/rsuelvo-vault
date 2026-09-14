-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 56 (2026-09-15)
-- Resolución universal M1 (SKU) + M2 (contexto por teléfono)
-- ============================================================
-- Base del ruteo con número único (D16 en diseño): el SKU identifica comercio
-- (tienda global única) y sucursal (única fila de inventario, o la de mayor
-- disponible en legacy compartidos); el contexto cubre mensajes sin SKU.
-- Solo lectura (STABLE), sin tocar nada existente. Validadas en datos reales:
-- FERC01→SKU_UNICO, FERK02→SKU_COMPARTIDO, O tolerada, ZZZ999/FERZZZ→motivos,
-- buyer1/2→PEDIDO, desconocido→DESCONOCIDO.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_sku_universal(p_sku text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION rsuelvo.fn_contexto_por_telefono(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
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
    select id_sucursal, id_variante into v_pen
    from tbl_lista_pendiente
    where id_cliente = v_cli.id_cliente;
    if found then
      return jsonb_build_object('origen','PENDIENTE', 'id_comercio', v_cli.id_comercio,
        'id_sucursal', v_pen.id_sucursal, 'id_variante', v_pen.id_variante);
    end if;
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
  select id_comercio into v_last
  from tbl_clientes
  where coalesce(telefono_whatsapp, telefono) = v_tel
  order by updated_at desc
  limit 1;
  if found then
    return jsonb_build_object('origen','ULTIMO_COMERCIO', 'id_comercio', v_last);
  end if;
  return jsonb_build_object('origen','DESCONOCIDO');
end;
$function$;
