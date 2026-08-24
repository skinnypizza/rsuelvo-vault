-- ============================================================
-- RSUELVO v2 :: 9. VISTAS OPERATIVAS
-- ============================================================

set search_path = rsuelvo, public;

create or replace view vw_inventario_disponible as
select
  i.id_inventario,
  s.id_comercio,
  i.id_sucursal,
  i.id_variante,
  v.sku,
  v.nombre as variante,
  p.nombre as producto,
  i.stock_actual,
  i.stock_reservado,
  (i.stock_actual-i.stock_reservado) as stock_disponible
from tbl_inventario i
join tbl_sucursales s on s.id_sucursal=i.id_sucursal
join tbl_variantes v on v.id_variante=i.id_variante
join tbl_productos p on p.id_producto=v.id_producto;

create or replace view vw_lista_espera_activa as
select
  le.id_lista_espera,
  le.id_comercio,
  le.id_sucursal,
  le.id_variante,
  v.sku,
  p.nombre as producto,
  le.id_cliente,
  c.nombre as cliente,
  c.telefono_whatsapp,
  le.posicion,
  le.estado,
  le.fecha_notificacion,
  le.fecha_expiracion
from tbl_lista_espera le
join tbl_variantes v on v.id_variante=le.id_variante
join tbl_productos p on p.id_producto=v.id_producto
join tbl_clientes c on c.id_cliente=le.id_cliente
where le.estado in ('ESPERANDO','NOTIFICADO');

grant select on vw_inventario_disponible to authenticated;
grant select on vw_lista_espera_activa to authenticated;
