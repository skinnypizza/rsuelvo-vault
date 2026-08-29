-- ============================================================
-- RSUELVO v2 :: 13. FUNCIÓN DE RESOLUCIÓN SKU
-- Migración: rsuelvo_v2_13_fn_resolver_variante_por_sku
-- WF-10 / HU-037..041 / D1 / D3 / D5
-- ============================================================

set search_path = rsuelvo, pg_catalog;

create or replace function fn_resolver_variante_por_sku(
  p_id_comercio uuid,
  p_sku text
)
returns table(
  id_variante uuid,
  nombre text,
  precio numeric(14,2),
  id_producto uuid
)
language plpgsql
stable
security invoker
set search_path = rsuelvo, pg_catalog
as $$
begin
  if p_sku is null or p_sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido. Formato requerido: exactamente 6 caracteres [A-Z0-9]'
      using errcode = '22023';
  end if;

  return query
  select v.id_variante, v.nombre, v.precio, v.id_producto
  from tbl_variantes v
  where v.id_comercio = p_id_comercio
    and v.sku = p_sku
    and v.activo;
end;
$$;

revoke execute on function fn_resolver_variante_por_sku(uuid, text) from public;
grant execute on function fn_resolver_variante_por_sku(uuid, text) to authenticated, service_role;

comment on function fn_resolver_variante_por_sku(uuid, text) is
'Resuelve un SKU v2 exacto dentro de un comercio y devuelve las columnas mínimas consumidas por WF-10.';
