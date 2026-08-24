-- ============================================================
-- RSUELVO v2 :: 8. ROW LEVEL SECURITY Y GRANTS
-- ============================================================

set search_path = rsuelvo, public;

do $$
declare
  t text;
begin
  foreach t in array array[
    'tbl_comercios','tbl_comercio_config','tbl_sucursales',
    'tbl_usuarios','tbl_usuario_comercio','tbl_categorias',
    'tbl_productos','tbl_variantes','tbl_inventario',
    'tbl_inventario_movimientos','tbl_clientes','tbl_reservas',
    'tbl_lista_espera','tbl_pedidos','tbl_pedido_detalles',
    'tbl_metodos_pago','tbl_qr_cobros','tbl_comprobantes_pago',
    'tbl_verificaciones','tbl_cuentas_creditos','tbl_movimientos_creditos',
    'tbl_compras_creditos','tbl_pagos_creditos','tbl_envios',
    'tbl_env_seguimiento_estados','tbl_logs_auditoria'
  ] loop
    execute format('alter table %I enable row level security',t);
  end loop;
end $$;

-- Roles y servicios globales
alter table tbl_roles enable row level security;
alter table tbl_servicios_creditos enable row level security;
alter table tbl_paquetes_creditos enable row level security;
alter table tbl_canal_whatsapp enable row level security;
alter table tbl_whatsapp_eventos enable row level security;
alter table tbl_contact_preferences enable row level security;
alter table tbl_whatsapp_eventos force row level security; -- sin políticas => denegado a clientes; backend vía service_role

-- COMERCIOS
create policy commerce_select on tbl_comercios for select using (fn_tiene_acceso_comercio(id_comercio));
create policy commerce_insert on tbl_comercios for insert with check (fn_es_superadmin());
create policy commerce_update on tbl_comercios for update using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));
create policy commerce_delete on tbl_comercios for delete using (fn_es_superadmin());
create policy commerce_config_all on tbl_comercio_config for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));

-- SUCURSALES: lectura miembros / escritura admin (A10)
create policy branches_select on tbl_sucursales for select using (fn_tiene_acceso_comercio(id_comercio));
create policy branches_manage on tbl_sucursales for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));

-- USUARIOS
create policy users_select on tbl_usuarios for select using (
  auth_user_id=auth.uid()
  or exists (select 1 from tbl_usuario_comercio uc
             where uc.id_usuario=tbl_usuarios.id_usuario and uc.activo
               and fn_tiene_acceso_comercio(uc.id_comercio))
);
create policy users_update_self on tbl_usuarios for update using (auth_user_id=auth.uid()) with check (auth_user_id=auth.uid());
create policy user_commerce_select on tbl_usuario_comercio for select using (fn_tiene_acceso_comercio(id_comercio));
create policy user_commerce_manage on tbl_usuario_comercio for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));
create policy roles_select on tbl_roles for select using (true);

-- CATÁLOGO: lectura miembros / escritura admin (A10)
create policy categories_select on tbl_categorias for select using (fn_tiene_acceso_comercio(id_comercio));
create policy categories_manage on tbl_categorias for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));
create policy products_select on tbl_productos for select using (fn_tiene_acceso_comercio(id_comercio));
create policy products_manage on tbl_productos for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));
create policy variants_select on tbl_variantes for select using (fn_tiene_acceso_comercio(id_comercio));
create policy variants_manage on tbl_variantes for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));

-- INVENTARIO: movimientos manuales solo admin (matriz); funciones backend usan service_role
create policy inventory_all on tbl_inventario for all using (
  exists (select 1 from tbl_sucursales s where s.id_sucursal=tbl_inventario.id_sucursal
          and fn_tiene_acceso_sucursal(s.id_comercio,s.id_sucursal))
) with check (
  exists (select 1 from tbl_sucursales s where s.id_sucursal=tbl_inventario.id_sucursal
          and fn_tiene_acceso_sucursal(s.id_comercio,s.id_sucursal))
);
create policy inventory_movements_select on tbl_inventario_movimientos for select using (fn_tiene_acceso_comercio(id_comercio));
create policy inventory_movements_insert on tbl_inventario_movimientos for insert with check (fn_es_admin_comercio(id_comercio));

-- CLIENTES
create policy clients_all on tbl_clientes for all using (fn_tiene_acceso_comercio(id_comercio)) with check (fn_tiene_acceso_comercio(id_comercio));

-- VENTAS
create policy reservations_all on tbl_reservas for all using (fn_tiene_acceso_sucursal(id_comercio,id_sucursal)) with check (fn_tiene_acceso_sucursal(id_comercio,id_sucursal));
create policy waitlist_all on tbl_lista_espera for all using (fn_tiene_acceso_sucursal(id_comercio,id_sucursal)) with check (fn_tiene_acceso_sucursal(id_comercio,id_sucursal));
create policy orders_all on tbl_pedidos for all using (fn_tiene_acceso_sucursal(id_comercio,id_sucursal)) with check (fn_tiene_acceso_sucursal(id_comercio,id_sucursal));
create policy order_details_all on tbl_pedido_detalles for all using (
  exists (select 1 from tbl_pedidos p where p.id_pedido=tbl_pedido_detalles.id_pedido
          and fn_tiene_acceso_sucursal(p.id_comercio,p.id_sucursal))
) with check (
  exists (select 1 from tbl_pedidos p where p.id_pedido=tbl_pedido_detalles.id_pedido
          and fn_tiene_acceso_sucursal(p.id_comercio,p.id_sucursal))
);

-- PAGOS
create policy payment_methods_select on tbl_metodos_pago for select using (fn_tiene_acceso_comercio(id_comercio));
create policy payment_methods_manage on tbl_metodos_pago for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));
create policy qr_all on tbl_qr_cobros for all using (fn_tiene_acceso_comercio(id_comercio)) with check (fn_tiene_acceso_comercio(id_comercio));
create policy receipts_all on tbl_comprobantes_pago for all using (fn_tiene_acceso_comercio(id_comercio)) with check (fn_tiene_acceso_comercio(id_comercio));

-- VERIFICACIONES: gestión admin o cajero (A10/HU-141)
create policy verification_select on tbl_verificaciones for select using (fn_tiene_acceso_comercio(id_comercio));
create policy verification_manage on tbl_verificaciones for all using (fn_puede_verificar(id_comercio)) with check (fn_puede_verificar(id_comercio));

-- CRÉDITOS (consulta admin; ledger de dinero IA)
create policy credit_accounts_select on tbl_cuentas_creditos for select using (fn_es_admin_comercio(id_comercio));
create policy credit_movements_select on tbl_movimientos_creditos for select using (fn_es_admin_comercio(id_comercio));
create policy credit_purchases_select on tbl_compras_creditos for select using (fn_es_admin_comercio(id_comercio));
create policy credit_payments_select on tbl_pagos_creditos for select using (
  exists (select 1 from tbl_compras_creditos c where c.id_compra=tbl_pagos_creditos.id_compra
          and fn_es_admin_comercio(c.id_comercio))
);
create policy credit_services_select on tbl_servicios_creditos for select using (true);
create policy credit_packages_select on tbl_paquetes_creditos for select using (true);

-- LOGÍSTICA: crear/asignar admin o cajero (A10/matriz)
create policy shipments_select on tbl_envios for select using (fn_tiene_acceso_sucursal(id_comercio,id_sucursal));
create policy shipments_manage on tbl_envios for all using (fn_puede_gestionar_envios(id_comercio)) with check (fn_puede_gestionar_envios(id_comercio));
create policy shipment_tracking_select on tbl_env_seguimiento_estados for select using (
  exists (select 1 from tbl_envios e where e.id_envio=tbl_env_seguimiento_estados.id_envio
          and fn_tiene_acceso_sucursal(e.id_comercio,e.id_sucursal))
);
create policy shipment_tracking_insert on tbl_env_seguimiento_estados for insert with check (
  exists (select 1 from tbl_envios e where e.id_envio=tbl_env_seguimiento_estados.id_envio
          and fn_tiene_acceso_sucursal(e.id_comercio,e.id_sucursal))
);

-- AUDITORÍA
create policy audit_select on tbl_logs_auditoria for select using (fn_es_superadmin() or fn_es_admin_comercio(id_comercio));
create policy audit_insert on tbl_logs_auditoria for insert with check (fn_es_superadmin() or fn_tiene_acceso_comercio(id_comercio));

-- CANALES WHATSAPP
create policy canal_select on tbl_canal_whatsapp for select using (fn_tiene_acceso_comercio(id_comercio));
create policy canal_manage on tbl_canal_whatsapp for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));

-- OPT-OUT
create policy contact_pref_all on tbl_contact_preferences for all using (fn_tiene_acceso_comercio(id_comercio)) with check (fn_tiene_acceso_comercio(id_comercio));


-- GRANTS
grant usage on schema rsuelvo to anon, authenticated, service_role;
grant select on tbl_roles to authenticated;
grant select on tbl_servicios_creditos to authenticated;
grant select on tbl_paquetes_creditos to authenticated;

-- No se otorga acceso directo al resto de tablas aquí:
-- Supabase/PostgREST + RLS se encargará del acceso autenticado.
grant select, insert, update, delete on all tables in schema rsuelvo to authenticated;

-- Las funciones RPC son el camino recomendado para operaciones críticas.
grant execute on all functions in schema rsuelvo to authenticated;

-- service_role mantiene bypass de RLS en Supabase.
