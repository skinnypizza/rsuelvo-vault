-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 53 (2026-09-12)
-- R5: último comprobante también con contexto activo
-- ============================================================
-- Mismo bug que m52 pero en la otra rama: un VALIDO de otra compra vieja
-- disparaba "pago confirmado" sin pago. Ahora solo cuenta el comprobante del
-- pedido esperando o de la reserva. Validado: buyer2 → null + pedido correcto.

-- == FUNCIONES ==
-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_estado_pago_cliente(p_id_comercio uuid, p_id_cliente uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_res record;
  v_ped record;
  v_ver record;
  v_comp text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;
  select id_reserva, estado, id_pedido, fecha_expiracion,
         extract(epoch from (fecha_expiracion - now()))/60 as expira_min
  into v_res
  from tbl_reservas
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  order by created_at desc
  limit 1;
  select id_pedido, estado, subtotal
  into v_ped
  from tbl_pedidos
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado='ESPERANDO_PAGO'
  order by created_at desc
  limit 1;
  select v.id_verificacion, v.estado
  into v_ver
  from tbl_verificaciones v
  join tbl_comprobantes_pago c on c.id_comprobante = v.id_comprobante
  where v.id_comercio=p_id_comercio
    and c.id_cliente=p_id_cliente
    and v.estado in ('PENDIENTE','PROCESANDO')
    and (c.id_pedido = v_ped.id_pedido or c.id_pedido = v_res.id_pedido)
  order by v.created_at desc
  limit 1;
  select c.estado into v_comp
  from tbl_comprobantes_pago c
  where c.id_comercio=p_id_comercio
    and c.id_cliente=p_id_cliente
    and (c.id_pedido = v_ped.id_pedido or c.id_pedido = v_res.id_pedido)
  order by c.created_at desc
  limit 1;
  return jsonb_build_object(
    'tiene_reserva_activa', (v_res.id_reserva is not null),
    'reserva_estado', v_res.estado,
    'reserva_expira_min', case when v_res.expira_min is null then null
      when v_res.expira_min < 0 then 0 else floor(v_res.expira_min)::integer end,
    'pedido_esperando_pago', case when v_ped.id_pedido is null then null else jsonb_build_object(
      'id_pedido', v_ped.id_pedido, 'estado', v_ped.estado, 'total', v_ped.subtotal) end,
    'verificacion_en_curso', case when v_ver.id_verificacion is null then null else jsonb_build_object(
      'id_verificacion', v_ver.id_verificacion, 'estado', v_ver.estado) end,
    'ultimo_comprobante_estado', v_comp
  );
end;
$function$;
