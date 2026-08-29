-- (v2/WF-21/HU-057..058) Registra un comprobante de pago y lo vincula al pedido
-- en espera de pago del cliente/comercio. SECURITY DEFINER para que n8n pueda
-- invocarla con la credencial anon (mismo patrón que fn_upsert_cliente), sin
-- requerir service_role en el app layer. Resuelve id_pedido si no se provee.
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
