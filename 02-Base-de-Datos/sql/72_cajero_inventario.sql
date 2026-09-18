-- 72_cajero_inventario.sql
-- Cajero ajusta inventario de SU sucursal via RPC (trazado). Directo sigue
-- denegado (mig 67). HU roles (cajero operativo).

create or replace function rsuelvo.fn_registrar_movimiento_inventario(
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_tipo text,
  p_cantidad integer,
  p_referencia_tipo text default null,
  p_referencia_id uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_tipo text := upper(trim(coalesce(p_tipo,'')));
  v_comercio uuid;
  v_var_comercio uuid;
  v_inv record;
  v_nuevo integer;
  v_uid uuid;
  v_cajero_ok boolean := false;
begin
  select id_comercio into v_comercio
  from tbl_sucursales where id_sucursal = p_id_sucursal and activo;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  -- cajero: solo su sucursal asignada
  select exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario = uc.id_usuario
    join tbl_roles r on r.id_rol = uc.id_rol
    where u.auth_user_id = auth.uid()
      and u.activo and uc.activo
      and uc.id_comercio = v_comercio
      and uc.id_sucursal = p_id_sucursal
      and r.codigo = 'ROLE_TENANT_CASHIER'
  ) into v_cajero_ok;

  if not (fn_es_service_role() or fn_es_superadmin()
          or fn_es_admin_comercio(v_comercio) or v_cajero_ok) then
    raise exception 'sin permiso de inventario';
  end if;

  if v_tipo not in ('ENTRADA','SALIDA','AJUSTE','DEVOLUCION') then
    return jsonb_build_object('ok', false, 'codigo', 'tipo_invalido');
  end if;

  if (v_tipo = 'AJUSTE' and coalesce(p_cantidad, 0) = 0)
     or (v_tipo != 'AJUSTE' and coalesce(p_cantidad, 0) <= 0) then
    return jsonb_build_object('ok', false, 'codigo', 'cantidad_invalida');
  end if;

  select id_comercio into v_var_comercio
  from tbl_variantes where id_variante = p_id_variante;
  if not found or v_var_comercio is distinct from v_comercio then
    return jsonb_build_object('ok', false, 'codigo', 'variante_invalida');
  end if;

  select * into v_inv from tbl_inventario
  where id_sucursal = p_id_sucursal and id_variante = p_id_variante
  for update;

  if not found then
    if v_tipo != 'ENTRADA' then
      return jsonb_build_object('ok', false, 'codigo', 'sin_inventario');
    end if;
    insert into tbl_inventario (id_sucursal, id_variante, stock_actual, stock_reservado)
    values (p_id_sucursal, p_id_variante, p_cantidad, 0)
    returning * into v_inv;
    v_nuevo := p_cantidad;
  else
    v_nuevo := v_inv.stock_actual +
      case when v_tipo in ('ENTRADA','DEVOLUCION','AJUSTE') then p_cantidad else -p_cantidad end;
    if v_nuevo < 0 then
      return jsonb_build_object('ok', false, 'codigo', 'stock_insuficiente',
        'stock', v_inv.stock_actual);
    end if;
    update tbl_inventario set stock_actual = v_nuevo, updated_at = now()
    where id_inventario = v_inv.id_inventario;
  end if;

  select id_usuario into v_uid from tbl_usuarios where auth_user_id = auth.uid();

  insert into tbl_inventario_movimientos
    (id_comercio, id_sucursal, id_variante, tipo, cantidad, referencia_tipo, referencia_id, usuario_id)
  values
    (v_comercio, p_id_sucursal, p_id_variante, v_tipo::rsuelvo.tipo_movimiento_inventario,
     p_cantidad, p_referencia_tipo, p_referencia_id, v_uid);

  return jsonb_build_object('ok', true, 'stock_actual', v_nuevo, 'tipo', v_tipo);
end;
$fn$;

-- CHECK cantidad: de >0 a <>0 (AJUSTE con signo; flujos del sistema insertan >=1)
alter table rsuelvo.tbl_inventario_movimientos
  drop constraint if exists tbl_inventario_movimientos_cantidad_check;
alter table rsuelvo.tbl_inventario_movimientos
  add constraint tbl_inventario_movimientos_cantidad_check check (cantidad <> 0);
