-- ============================================================
-- RSUELVO v2 :: 18. RESERVAS POR CLIENTE (decisión H-2 = B)
-- ============================================================
-- Migración: 18_reservas_por_cliente
-- Proyecto cloud: iwfaktlxebxtocmswdvv (RSUELVO, us-west-2)
-- IDs: WF-10 (TSC1otHnDCr0ADiW) / WF-80 (ISxev9AssaAvQa8z) /
--      HU-037..041 / HU-041 / D3 / Regla de Oro 2
-- Autoriza: usuario (opción B confirmada explícitamente)
--
-- Propósito: permitir reservas activas del MISMO SKU/variante+sucursal para
-- clientes DISTINTOS mientras haya stock (opción B), conservando la idempotencia
-- por cliente+variante+sucursal. Cambios:
--   (1) Índice único parcial uq_reserva_activa_variante_sucursal:
--       (id_sucursal,id_variante) -> (id_sucursal,id_variante,id_cliente)
--       Mismo nombre y mismo predicate de estados canónicos
--       ('ACTIVA','PAGO_VALIDANDO').
--   (2) fn_solicitar_reserva: misma firma y lógica; ambas detecciones de reserva
--       existente ahora filtran id_cliente=p_id_cliente. RESERVA_YA_EXISTENTE
--       solo para el MISMO cliente+variante+sucursal; cliente distinto continúa a
--       reservar si hay stock. Se conservan FOR UPDATE/lock de inventario,
--       atomicidad, security definer, search_path, auditoría y movimientos.
-- No se modifican enums ni tablas.
-- Verificación en cloud: índice real = (sucursal,variante,cliente); prueba
-- mismo cliente -> RESERVA_YA_EXISTENTE (idempotente, sin stock extra); cliente
-- distinto -> RESERVA_CREADA (no bloqueado). Rollback de prueba limpio.
-- ============================================================

set search_path = rsuelvo, public;

-- (1) ÍNDICE: (id_sucursal,id_variante) -> (id_sucursal,id_variante,id_cliente)
--     Mismo nombre y mismo predicate de estados canónicos ('ACTIVA','PAGO_VALIDANDO').
--     Sin conflictos: verificado que no existe par (sucursal,variante) con >1 reserva activa.
drop index if exists uq_reserva_activa_variante_sucursal;

create unique index uq_reserva_activa_variante_sucursal
  on tbl_reservas(id_sucursal, id_variante, id_cliente)
  where estado in ('ACTIVA','PAGO_VALIDANDO');


-- (2) FUNCIÓN fn_solicitar_reserva: misma firma y lógica, detección POR CLIENTE.
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

  -- Bloqueo pesimista de inventario: solo una transacción modifica esta fila.
  -- Serializa la carrera primera-reserva/reintento para la misma variante+sucursal.
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

comment on function fn_solicitar_reserva(uuid,uuid,uuid,uuid,integer) is
  'Reserva atómica de una variante en una sucursal (opción B: una reserva activa POR CLIENTE por sucursal+variante; clientes distintos pueden reservar en paralelo mientras haya stock). Retorna RESERVA_CREADA, SIN_STOCK, o RESERVA_YA_EXISTENTE (solo si el MISMO cliente ya tiene reserva activa, sin duplicar ni tocar inventario).';
