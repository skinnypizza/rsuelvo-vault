-- ============================================================
-- RSUELVO :: CONSTRAINTS E ÍNDICES ÚNICOS PARCIALES
-- Archivo 04/12 del schema separado
-- Ejecutar en orden. Idempotente. Esquema: rsuelvo
-- ============================================================

set search_path = rsuelvo, public;

-- Cliente único por WhatsApp dentro del comercio
create unique index if not exists uq_cliente_whatsapp_comercio
on tbl_clientes(id_comercio,telefono_whatsapp)
where telefono_whatsapp is not null;

-- Una sola reserva activa por variante+sucursal (incluye PAGO_VALIDANDO)
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

-- Comprobante único por número de operación
create unique index if not exists uq_comprobante_operacion_comercio
on tbl_comprobantes_pago(id_comercio,numero_operacion)
where numero_operacion is not null;
