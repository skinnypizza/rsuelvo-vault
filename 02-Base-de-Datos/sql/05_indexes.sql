-- ============================================================
-- RSUELVO :: ÍNDICES DE RENDIMIENTO
-- Archivo 05/12 del schema separado
-- Ejecutar en orden. Idempotente. Esquema: rsuelvo
-- ============================================================

set search_path = rsuelvo, public;

create index if not exists idx_sucursales_comercio on tbl_sucursales(id_comercio);
create index if not exists idx_usuario_comercio_usuario on tbl_usuario_comercio(id_usuario);
create index if not exists idx_usuario_comercio_comercio on tbl_usuario_comercio(id_comercio);
create index if not exists idx_productos_comercio on tbl_productos(id_comercio);
create index if not exists idx_variantes_producto on tbl_variantes(id_producto);
create index if not exists idx_inventario_sucursal on tbl_inventario(id_sucursal);
create index if not exists idx_inventario_variante on tbl_inventario(id_variante);
create index if not exists idx_reservas_cliente on tbl_reservas(id_cliente);
create index if not exists idx_reservas_variante on tbl_reservas(id_variante);
create index if not exists idx_reservas_expiracion on tbl_reservas(fecha_expiracion)
where estado='ACTIVA';
create index if not exists idx_lista_variante on tbl_lista_espera(id_variante,posicion);
create index if not exists idx_pedidos_cliente on tbl_pedidos(id_cliente);
create index if not exists idx_pedidos_estado on tbl_pedidos(id_comercio,estado);
create index if not exists idx_comprobantes_pedido on tbl_comprobantes_pago(id_pedido);
create index if not exists idx_verificaciones_pedido on tbl_verificaciones(id_pedido);
create index if not exists idx_mov_creditos_comercio on tbl_movimientos_creditos(id_comercio,created_at);
create index if not exists idx_envios_estado on tbl_envios(id_comercio,estado);
create index if not exists idx_auditoria_comercio_fecha on tbl_logs_auditoria(id_comercio,created_at desc);
