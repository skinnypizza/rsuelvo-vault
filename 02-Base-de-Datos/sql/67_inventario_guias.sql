-- 67_inventario_guias.sql
-- Auditoria P0 (hallazgos 2,4): inventario sin escritura directa no-admin;
-- guias-envios aislado por path de comercio. HU roles/logistica.

-- ═══ A. Inventario: SELECT amplio, escritura solo admin-tenant (RPC proximo paso)
drop policy if exists inventory_all on rsuelvo.tbl_inventario;

create policy inventory_select on rsuelvo.tbl_inventario
  for select to authenticated
  using (EXISTS (
    SELECT 1 FROM rsuelvo.tbl_sucursales s
    WHERE s.id_sucursal = tbl_inventario.id_sucursal
      AND rsuelvo.fn_tiene_acceso_sucursal(s.id_comercio, s.id_sucursal)));

create policy inventory_write_admin on rsuelvo.tbl_inventario
  for all to authenticated
  using (EXISTS (
    SELECT 1 FROM rsuelvo.tbl_sucursales s
    WHERE s.id_sucursal = tbl_inventario.id_sucursal
      AND rsuelvo.fn_es_admin_comercio(s.id_comercio)))
  with check (EXISTS (
    SELECT 1 FROM rsuelvo.tbl_sucursales s
    WHERE s.id_sucursal = tbl_inventario.id_sucursal
      AND rsuelvo.fn_es_admin_comercio(s.id_comercio)));

-- ═══ B. fn_registrar_movimiento_inventario (ajustes manuales auditados) ══════
-- Tipos manuales: ENTRADA/SALIDA/AJUSTE/DEVOLUCION (RESERVA/VENTA/LIBERACION son del sistema).
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
begin
  select id_comercio into v_comercio
  from tbl_sucursales where id_sucursal = p_id_sucursal and activo;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  if not (fn_es_service_role() or fn_es_superadmin() or fn_es_admin_comercio(v_comercio)) then
    raise exception 'solo admin del comercio';
  end if;

  if v_tipo not in ('ENTRADA','SALIDA','AJUSTE','DEVOLUCION') then
    return jsonb_build_object('ok', false, 'codigo', 'tipo_invalido');
  end if;

  -- AJUSTE acepta cantidad con signo (direccion); resto exige positiva
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

revoke execute on function rsuelvo.fn_registrar_movimiento_inventario(uuid, uuid, text, integer, text, uuid) from public;
grant execute on function rsuelvo.fn_registrar_movimiento_inventario(uuid, uuid, text, integer, text, uuid) to authenticated, service_role;

-- ═══ C. guias-envios aislado por comercio ═══════════════════════════════════
-- Paths reales: <id_comercio>/<archivo> (sin subcarpetas; no hay legacy que migrar).
drop policy if exists guias_envios_insert on storage.objects;
drop policy if exists guias_envios_select on storage.objects;
drop policy if exists guias_envios_update on storage.objects;

create policy guias_tenant_select on storage.objects
  for select to authenticated
  using (bucket_id = 'guias-envios'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid));

create policy guias_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'guias-envios'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and (rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid)
      or (rsuelvo.fn_tiene_rol('ROLE_LOGISTICS_AGENT')
        and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid))));

create policy guias_update on storage.objects
  for update to authenticated
  using (bucket_id = 'guias-envios'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and (rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid)
      or (rsuelvo.fn_tiene_rol('ROLE_LOGISTICS_AGENT')
        and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid))))
  with check (bucket_id = 'guias-envios'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and (rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid)
      or (rsuelvo.fn_tiene_rol('ROLE_LOGISTICS_AGENT')
        and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid))));
