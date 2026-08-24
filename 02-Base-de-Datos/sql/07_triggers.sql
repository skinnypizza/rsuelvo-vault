-- ============================================================
-- RSUELVO :: TRIGGERS
-- Archivo 07/12 del schema separado
-- Ejecutar en orden. Idempotente. Esquema: rsuelvo
-- ============================================================

set search_path = rsuelvo, public;

-- Asignación usuario/comercio
drop trigger if exists trg_validar_asignacion_usuario_comercio on tbl_usuario_comercio;
create trigger trg_validar_asignacion_usuario_comercio
before insert or update on tbl_usuario_comercio
for each row execute function fn_validar_asignacion_usuario_comercio();

-- SKU único por comercio
drop trigger if exists trg_validar_sku_variante_comercio on tbl_variantes;
create trigger trg_validar_sku_variante_comercio
before insert or update on tbl_variantes
for each row execute function fn_validar_sku_variante_comercio();

-- Consistencia multi-tenant
drop trigger if exists trg_reservas_tenant on tbl_reservas;
create trigger trg_reservas_tenant before insert or update on tbl_reservas
for each row execute function fn_validar_consistencia_tenant();

drop trigger if exists trg_lista_tenant on tbl_lista_espera;
create trigger trg_lista_tenant before insert or update on tbl_lista_espera
for each row execute function fn_validar_consistencia_tenant();

drop trigger if exists trg_pedidos_tenant on tbl_pedidos;
create trigger trg_pedidos_tenant before insert or update on tbl_pedidos
for each row execute function fn_validar_consistencia_tenant();

drop trigger if exists trg_envios_tenant on tbl_envios;
create trigger trg_envios_tenant before insert or update on tbl_envios
for each row execute function fn_validar_consistencia_tenant();

drop trigger if exists trg_comprobantes_tenant on tbl_comprobantes_pago;
create trigger trg_comprobantes_tenant before insert or update on tbl_comprobantes_pago
for each row execute function fn_validar_consistencia_tenant();

-- updated_at
do $$
declare
  t text;
begin
  foreach t in array array[
    'tbl_comercios','tbl_comercio_config','tbl_sucursales','tbl_usuarios',
    'tbl_usuario_comercio','tbl_categorias','tbl_productos','tbl_variantes',
    'tbl_inventario','tbl_clientes','tbl_reservas','tbl_lista_espera',
    'tbl_pedidos','tbl_metodos_pago','tbl_verificaciones','tbl_cuentas_creditos',
    'tbl_servicios_creditos','tbl_envios'
  ] loop
    execute format('drop trigger if exists trg_%s_updated_at on %I',t,t);
    execute format(
      'create trigger trg_%s_updated_at before update on %I for each row execute function fn_set_updated_at()',
      t,t
    );
  end loop;
end $$;

-- Auditoría genérica (fn_auditar_cambio existe pero SIN triggers adjuntos en el monolito).
-- Se recomienda activarla en tablas críticas una vez validado el volumen:
--
-- create trigger trg_audit_inventario after insert or update or delete
--   on tbl_inventario for each row execute function fn_auditar_cambio();
-- (repetir para: tbl_variantes, tbl_reservas, tbl_pedidos, tbl_verificaciones,
--  tbl_movimientos_creditos, tbl_envios)
