-- ============================================================
-- RSUELVO v2 :: 19. IDEMPOTENCIA PEDIDO Y COBRO (cierra hallazgo H-1 de QA)
-- ============================================================
-- Aplicada en cloud (proyecto iwfaktlxebxtocmswdvv / RSUELVO us-west-2).
-- Reescribe rsuelvo.fn_crear_pedido_desde_reserva y rsuelvo.fn_generar_cobro
-- manteniendo firma, SECURITY DEFINER y SET search_path = rsuelvo, public.
-- ÚNICO cambio: se añaden guardas de idempotencia para reintentos de la
-- MISMA reserva/pedido (devuelve el registro existente en vez de duplicar).

create or replace function rsuelvo.fn_crear_pedido_desde_reserva(p_id_reserva uuid)
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

create or replace function rsuelvo.fn_generar_cobro(
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
