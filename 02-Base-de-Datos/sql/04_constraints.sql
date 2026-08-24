-- ============================================================
-- RSUELVO v2 :: 4. CONSTRAINTS E ÍNDICES ÚNICOS PARCIALES
-- ============================================================

set search_path = rsuelvo, public;

-- Cliente único por WhatsApp dentro del comercio
create unique index if not exists uq_cliente_whatsapp_comercio
on tbl_clientes(id_comercio,telefono_whatsapp)
where telefono_whatsapp is not null;


-- Una sola reserva activa por variante+sucursal
create unique index if not exists uq_reserva_activa_variante_sucursal
on tbl_reservas(id_sucursal,id_variante)
where estado in ('ACTIVA','PAGO_VALIDANDO');


-- Posición única activa en lista de espera
create unique index if not exists uq_lista_posicion_activa
on tbl_lista_espera(id_sucursal,id_variante,posicion)
where estado in ('ESPERANDO','NOTIFICADO');

create unique index if not exists uq_cliente_lista_activa
on tbl_lista_espera(id_sucursal,id_variante,id_cliente)
where estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');


-- FK diferida reserva↔pedido
alter table tbl_reservas
  drop constraint if exists tbl_reservas_id_pedido_fkey;

alter table tbl_reservas
  add constraint tbl_reservas_id_pedido_fkey
  foreign key(id_pedido) references tbl_pedidos(id_pedido) on delete set null;


-- Comprobante único por operación dentro del comercio
create unique index if not exists uq_comprobante_operacion_comercio
on tbl_comprobantes_pago(id_comercio,numero_operacion)
where numero_operacion is not null;


-- SKU único FÍSICO por comercio (v2/A1: cierra la carrera del trigger)
alter table tbl_variantes
  add constraint uq_variante_sku_comercio
  unique (id_comercio, sku);

-- Formato SKU v2: 6 caracteres [3 tienda][3 producto] base36 mayúsculas
alter table tbl_variantes
  add constraint ck_variante_sku_formato
  check (sku ~ '^[A-Z0-9]{6}$');

-- Un número de WhatsApp no puede repetirse como canal activo
create unique index if not exists uq_canal_numero_activo
on tbl_canal_whatsapp(numero) where activo;
