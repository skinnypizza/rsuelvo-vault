-- ============================================================
-- RSUELVO v2 :: 7. TRIGGERS
-- ============================================================

set search_path = rsuelvo, public;

-- Asignación usuario/comercio
drop trigger if exists trg_validar_asignacion_usuario_comercio on tbl_usuario_comercio;
create trigger trg_validar_asignacion_usuario_comercio
before insert or update on tbl_usuario_comercio
for each row execute function fn_validar_asignacion_usuario_comercio();

-- Resolver tenant+SKU de variantes
drop trigger if exists trg_resolver_variante_tenant_sku on tbl_variantes;
create trigger trg_resolver_variante_tenant_sku
before insert or update on tbl_variantes
for each row execute function fn_resolver_variante_tenant_sku();


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

-- Auditoría ACTIVA en tablas críticas (A12/HU-127..131)
do $$
declare t text;
begin
  foreach t in array array[
    'tbl_usuario_comercio','tbl_comercio_config','tbl_variantes','tbl_inventario',
    'tbl_reservas','tbl_pedidos','tbl_comprobantes_pago','tbl_verificaciones',
    'tbl_movimientos_creditos','tbl_envios',
    'tbl_canal_whatsapp','tbl_contact_preferences'
  ] loop
    execute format('drop trigger if exists trg_audit_%s on %I',t,t);
    execute format(
      'create trigger trg_audit_%s after insert or update or delete on %I for each row execute function fn_auditar_cambio()',t,t);
  end loop;
end $$;


-- ========== (Migración 30) Triggers event-driven de entrega ==========
-- Funciones fn_notifica_pedido_pagado / fn_notifica_envio_estado definidas en 06_functions.sql
-- (copiar los cuerpos desde 30_logistica_entrega_eventos.sql). Triggers:

-- CREATE TRIGGER trg_pedido_pagado_notifica
-- AFTER UPDATE OF estado ON rsuelvo.tbl_pedidos
-- FOR EACH ROW
-- WHEN (NEW.estado = 'PAGADO' AND OLD.estado IS DISTINCT FROM 'PAGADO')
-- EXECUTE FUNCTION rsuelvo.fn_notifica_pedido_pagado();

-- CREATE TRIGGER trg_envio_estado_notifica
-- AFTER UPDATE OF estado ON rsuelvo.tbl_envios
-- FOR EACH ROW
-- WHEN (NEW.estado IS DISTINCT FROM OLD.estado)
-- EXECUTE FUNCTION rsuelvo.fn_notifica_envio_estado();

-- -- 34_entrega_captura_destino.sql [TRIGGERS]
CREATE TRIGGER trg_entrega_captura_updated_at BEFORE UPDATE ON rsuelvo.tbl_entrega_captura
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_entrega_captura AFTER INSERT OR UPDATE OR DELETE ON rsuelvo.tbl_entrega_captura
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();

-- -- 35_lista_pendiente_momento1.sql [TRIGGERS]
CREATE TRIGGER trg_lista_pendiente_updated_at BEFORE UPDATE ON rsuelvo.tbl_lista_pendiente
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_lista_pendiente AFTER INSERT OR UPDATE OR DELETE ON rsuelvo.tbl_lista_pendiente
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();
