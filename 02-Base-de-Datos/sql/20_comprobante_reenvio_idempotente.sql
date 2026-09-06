-- Migración 20 (2026-08-29): idempotencia de reenvío de comprobantes (D5, Reglas 2/7)
-- Caso: comprador reenvía la MISMA imagen de comprobante (mismo numero_operacion).
-- Antes: el INSERT chocaba con uq_comprobante_operacion_comercio → flujo moría en WF-21.
-- Ahora (mismo contrato/firma, WF-21 sin cambios):
--   * mismo (id_comercio, numero_operacion) + mismo pedido  → UPDATE datos y reutiliza comprobante
--   * mismo (id_comercio, numero_operacion) + OTRO pedido   → excepción COMPROBANTE_DUPLICADO (anti-fraude)
-- El índice uq_comprobante_operacion_comercio (05_indexes) sigue vigente como garantía física.

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
        update tbl_comprobantes_pago
           set tipo_archivo     = p_tipo_archivo,
               archivo_url      = p_archivo_url,
               monto_detectado  = coalesce(p_monto_detectado, monto_detectado),
               fecha_detectada  = coalesce(p_fecha_detectada, fecha_detectada),
               nombre_pagador   = coalesce(p_nombre_pagador, nombre_pagador),
               estado           = p_estado
         where id_comprobante = v_existente;
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
