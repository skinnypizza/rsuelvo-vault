-- ============================================================
-- RSUELVO - SUPABASE / POSTGRESQL BACKEND
-- schema v2 (refinado contra 148 HU + auditorías 2026-08-24)
-- ============================================================
-- CAMBIOS v1 -> v2 (trazabilidad: Auditoria-SQL-vs-ERD.md A1-A12 / Auditoría I3):
--   SKU: 6 caracteres = 3 código tienda + 3 código producto/variante (base36).
--        codigo_tienda en tbl_comercios; generación automática; UNIQUE físico (A1).
--   tbl_variantes.id_comercio denormalizado (RLS y unicidad directas) (A1).
--   NUEVAS TABLAS: tbl_canal_whatsapp (A2), tbl_whatsapp_eventos (A6/HU-143),
--        tbl_contact_preferences opt-out (HU-142/G1).
--   NUEVAS FN: fn_es_service_role (escape para n8n/service_role),
--        fn_identificar_comercio_por_whatsapp (A2/WF-04),
--        fn_registrar_evento_whatsapp (idempotencia, HU-143),
--        fn_registrar_opt_out (HU-142), fn_movimiento_inventario (HU-032/033),
--        fn_generar_cobro (A4/HU-056), fn_iniciar_verificacion atómica (A3/HU-141),
--        fn_actualizar_estado_envio con máquina de estados (A5/HU-092-094),
--        fn_rechazar_verificacion v2: pedido vuelve a ESPERANDO_PAGO (A9/HU-065),
--        fn_tiene_rol_comercio/fn_puede_verificar/fn_puede_gestionar_envios (A10).
--   RLS alineado a matriz: escritura catálogo/sucursales/métodos = admin;
--        envíos crear = admin o cajero; verificar = admin o cajero (A10).
--   Triggers de auditoría ACTIVOS en tablas críticas (A12/HU-127..131).
--   Seed: paquetes Básico/Pro/Empresa activos (wireframe 15 / HU-072).
--   Storage: buckets qr-pagos + comprobantes-pago creados (A7). Cron programado (A8).
-- Convención I3: funciones reales = fn_*; rpc_* del doc workflows son alias conceptuales.
--
-- Ejecutar 01..12 en orden (o este monolito completo) en Supabase SQL Editor.
-- ============================================================
-- RSUELVO v2 :: 1. EXTENSIONES Y ESQUEMA
-- ============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

create schema if not exists rsuelvo;

set search_path = rsuelvo, public;

-- ============================================================
-- RSUELVO v2 :: 2. ENUMS
-- ============================================================

set search_path = rsuelvo, public;

do $$ begin
  create type estado_comercio as enum ('ACTIVO','SUSPENDIDO','BLOQUEADO','CANCELADO');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_pedido as enum (
    'CREADO','ESPERANDO_PAGO','PAGO_RECIBIDO','PAGO_VALIDANDO',
    'PAGADO','PREPARANDO','DESPACHADO','ENTREGADO','CANCELADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_reserva as enum (
    'ACTIVA','PAGO_VALIDANDO','CONFIRMADA','VENCIDA','CANCELADA','LIBERADA'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type origen_reserva as enum ('DIRECTA','LISTA_ESPERA');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_lista_espera as enum (
    'ESPERANDO','NOTIFICADO','ACEPTADO','CONVERTIDO_RESERVA',
    'RECHAZADO','VENCIDO','CANCELADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_comprobante as enum (
    'RECIBIDO','PROCESANDO','VALIDO','INVALIDO','RECHAZADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_verificacion as enum (
    'PENDIENTE','PROCESANDO','COMPLETADA','BLOQUEADA','ERROR'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_movimiento_inventario as enum (
    'ENTRADA','SALIDA','RESERVA','LIBERACION_RESERVA','VENTA','AJUSTE','DEVOLUCION'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_movimiento_credito as enum (
    'COMPRA','BONIFICACION','AJUSTE','CONSUMO_VERIFICACION','CONSUMO_VENTA','DEVOLUCION','EXPIRACION'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_compra_creditos as enum (
    'PENDIENTE','PAGADA','RECHAZADA','CANCELADA'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_pago_creditos as enum (
    'PENDIENTE','CONFIRMADO','RECHAZADO','CANCELADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_qr as enum (
    'GENERADO','PAGADO','EXPIRADO','CANCELADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_envio as enum (
    'PENDIENTE','PREPARANDO','ASIGNADO','EN_RUTA',
    'ENTREGADO','NO_ENTREGADO','CANCELADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type rol_codigo as enum (
    'ROLE_SUPERADMIN',
    'ROLE_SYSADMIN',
    'ROLE_SUPPORT',
    'ROLE_TENANT_ADMIN',
    'ROLE_TENANT_CASHIER',
    'ROLE_LOGISTICS_AGENT'
  );
exception when duplicate_object then null; end $$;

-- ============================================================
-- RSUELVO v2 :: 3. TABLAS
-- ============================================================

set search_path = rsuelvo, public;

-- ROLES
create table if not exists tbl_roles (
  id_rol smallserial primary key,
  codigo rol_codigo not null unique,
  nombre text not null,
  nivel integer not null default 0 check (nivel >= 0),
  created_at timestamptz not null default now()
);


-- COMERCIOS (v2: codigo_tienda para SKU de 6 caracteres)
create table if not exists tbl_comercios (
  id_comercio uuid primary key default gen_random_uuid(),
  codigo_tienda char(3)
    not null unique
    check (codigo_tienda ~ '^[A-Z0-9]{3}$'),
  nombre_comercial text not null,
  razon_social text,
  nit text,
  telefono text,
  email text,
  estado estado_comercio not null default 'ACTIVO',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- CONFIGURACIÓN DEL COMERCIO
create table if not exists tbl_comercio_config (
  id_comercio uuid primary key references tbl_comercios(id_comercio) on delete cascade,
  tiempo_reserva_minutos integer not null default 10 check (tiempo_reserva_minutos > 0),
  tiempo_aceptacion_lista_espera_minutos integer not null default 2 check (tiempo_aceptacion_lista_espera_minutos > 0),
  max_lista_espera_por_producto integer not null default 5 check (max_lista_espera_por_producto > 0),
  verificacion_automatica boolean not null default true,
  rate_limit_whatsapp_por_minuto integer not null default 20 check (rate_limit_whatsapp_por_minuto > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- SUCURSALES
create table if not exists tbl_sucursales (
  id_sucursal uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  nombre text not null,
  direccion text,
  referencia text,
  latitud numeric(9,6),
  longitud numeric(9,6),
  telefono text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id_comercio,id_sucursal)
);


-- USUARIOS
create table if not exists tbl_usuarios (
  id_usuario uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  nombre text not null,
  apellido text,
  telefono text,
  email text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ASIGNACIÓN USUARIO/COMERCIO/ROL
create table if not exists tbl_usuario_comercio (
  id uuid primary key default gen_random_uuid(),
  id_usuario uuid not null references tbl_usuarios(id_usuario) on delete cascade,
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  id_rol smallint not null references tbl_roles(id_rol),
  id_sucursal uuid,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id_usuario,id_comercio,id_rol),
  foreign key(id_comercio,id_sucursal)
    references tbl_sucursales(id_comercio,id_sucursal)
    deferrable initially immediate
);


-- CATEGORÍAS
create table if not exists tbl_categorias (
  id_categoria uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  nombre text not null,
  descripcion text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id_comercio,nombre)
);


-- PRODUCTOS
create table if not exists tbl_productos (
  id_producto uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  id_categoria uuid references tbl_categorias(id_categoria) on delete set null,
  nombre text not null,
  descripcion text,
  imagen_url text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- VARIANTES (v2: id_comercio denormalizado + SKU único físico por comercio)
create table if not exists tbl_variantes (
  id_variante uuid primary key default gen_random_uuid(),
  id_producto uuid not null references tbl_productos(id_producto) on delete cascade,
  id_comercio uuid,
  sku text,
  nombre text not null,
  precio numeric(14,2) not null check (precio >= 0),
  sku_anterior text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id_producto,sku)
);


-- INVENTARIO
create table if not exists tbl_inventario (
  id_inventario uuid primary key default gen_random_uuid(),
  id_sucursal uuid not null references tbl_sucursales(id_sucursal) on delete cascade,
  id_variante uuid not null references tbl_variantes(id_variante) on delete cascade,
  stock_actual integer not null default 0 check (stock_actual >= 0),
  stock_reservado integer not null default 0 check (stock_reservado >= 0),
  updated_at timestamptz not null default now(),
  unique(id_sucursal,id_variante),
  check(stock_reservado <= stock_actual)
);

create table if not exists tbl_inventario_movimientos (
  id_movimiento uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  id_sucursal uuid not null references tbl_sucursales(id_sucursal) on delete restrict,
  id_variante uuid not null references tbl_variantes(id_variante) on delete restrict,
  tipo tipo_movimiento_inventario not null,
  cantidad integer not null check (cantidad > 0),
  referencia_tipo text,
  referencia_id uuid,
  usuario_id uuid references tbl_usuarios(id_usuario) on delete set null,
  created_at timestamptz not null default now()
);


-- CLIENTES
create table if not exists tbl_clientes (
  id_cliente uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  nombre text not null,
  telefono text,
  telefono_whatsapp text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- RESERVAS
create table if not exists tbl_reservas (
  id_reserva uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_sucursal uuid not null references tbl_sucursales(id_sucursal) on delete restrict,
  id_variante uuid not null references tbl_variantes(id_variante) on delete restrict,
  id_cliente uuid not null references tbl_clientes(id_cliente) on delete restrict,
  id_pedido uuid,
  origen origen_reserva not null,
  estado estado_reserva not null default 'ACTIVA',
  cantidad integer not null default 1 check (cantidad > 0),
  fecha_inicio timestamptz not null default now(),
  fecha_expiracion timestamptz not null,
  fecha_finalizacion timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- LISTA DE ESPERA
create table if not exists tbl_lista_espera (
  id_lista_espera uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  id_sucursal uuid not null references tbl_sucursales(id_sucursal) on delete cascade,
  id_variante uuid not null references tbl_variantes(id_variante) on delete cascade,
  id_cliente uuid not null references tbl_clientes(id_cliente) on delete cascade,
  posicion integer not null check (posicion > 0),
  estado estado_lista_espera not null default 'ESPERANDO',
  fecha_ingreso timestamptz not null default now(),
  fecha_notificacion timestamptz,
  fecha_aceptacion timestamptz,
  fecha_expiracion timestamptz,
  id_reserva_generada uuid references tbl_reservas(id_reserva) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- PEDIDOS
create table if not exists tbl_pedidos (
  id_pedido uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_sucursal uuid not null references tbl_sucursales(id_sucursal) on delete restrict,
  id_cliente uuid not null references tbl_clientes(id_cliente) on delete restrict,
  numero_pedido bigint generated always as identity,
  estado estado_pedido not null default 'CREADO',
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  descuento numeric(14,2) not null default 0 check (descuento >= 0),
  total numeric(14,2) generated always as (subtotal - descuento) stored,
  id_reserva uuid references tbl_reservas(id_reserva) on delete set null,
  fecha_creacion timestamptz not null default now(),
  fecha_confirmacion timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(descuento <= subtotal)
);


-- DETALLES DE PEDIDO (snapshots)
create table if not exists tbl_pedido_detalles (
  id_detalle uuid primary key default gen_random_uuid(),
  id_pedido uuid not null references tbl_pedidos(id_pedido) on delete cascade,
  id_variante uuid not null references tbl_variantes(id_variante) on delete restrict,
  sku_snapshot text not null,
  nombre_snapshot text not null,
  precio_unitario numeric(14,2) not null check (precio_unitario >= 0),
  cantidad integer not null default 1 check (cantidad > 0),
  subtotal numeric(14,2) generated always as (precio_unitario * cantidad) stored
);


-- MÉTODOS DE PAGO
create table if not exists tbl_metodos_pago (
  id_metodo_pago uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  nombre text not null,
  tipo text not null,
  proveedor text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id_comercio,nombre)
);


-- COBROS QR
create table if not exists tbl_qr_cobros (
  id_qr_cobro uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_pedido uuid not null references tbl_pedidos(id_pedido) on delete restrict,
  id_metodo_pago uuid not null references tbl_metodos_pago(id_metodo_pago) on delete restrict,
  monto numeric(14,2) not null check (monto > 0),
  referencia text not null,
  qr_url text,
  estado estado_qr not null default 'GENERADO',
  created_at timestamptz not null default now(),
  unique(id_comercio,referencia)
);


-- COMPROBANTES DE PAGO
create table if not exists tbl_comprobantes_pago (
  id_comprobante uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_pedido uuid not null references tbl_pedidos(id_pedido) on delete restrict,
  id_cliente uuid not null references tbl_clientes(id_cliente) on delete restrict,
  tipo_archivo text not null,
  archivo_url text not null,
  monto_detectado numeric(14,2),
  fecha_detectada timestamptz,
  numero_operacion text,
  nombre_pagador text,
  estado estado_comprobante not null default 'RECIBIDO',
  created_at timestamptz not null default now()
);


-- VERIFICACIONES IA
create table if not exists tbl_verificaciones (
  id_verificacion uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_comprobante uuid not null references tbl_comprobantes_pago(id_comprobante) on delete restrict,
  id_pedido uuid not null references tbl_pedidos(id_pedido) on delete restrict,
  tipo_verificacion text not null,
  estado estado_verificacion not null default 'PENDIENTE',
  resultado jsonb,
  confianza numeric(5,4) check (confianza between 0 and 1),
  creditos_consumidos integer not null default 0 check (creditos_consumidos >= 0),
  fecha_inicio timestamptz,
  fecha_fin timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- CRÉDITOS (cuenta + ledger + servicios + paquetes + compras + pagos)
create table if not exists tbl_cuentas_creditos (
  id_cuenta_creditos uuid primary key default gen_random_uuid(),
  id_comercio uuid not null unique references tbl_comercios(id_comercio) on delete cascade,
  saldo_actual bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists tbl_movimientos_creditos (
  id_movimiento uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_cuenta_creditos uuid not null references tbl_cuentas_creditos(id_cuenta_creditos) on delete restrict,
  tipo tipo_movimiento_credito not null,
  cantidad bigint not null check (cantidad <> 0),
  saldo_anterior bigint not null,
  saldo_posterior bigint not null,
  concepto text,
  referencia_tipo text,
  referencia_id uuid,
  usuario_id uuid references tbl_usuarios(id_usuario) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists tbl_servicios_creditos (
  id_servicio uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  descripcion text,
  costo_creditos bigint not null check (costo_creditos >= 0),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists tbl_paquetes_creditos (
  id_paquete uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  creditos bigint not null check (creditos > 0),
  precio numeric(14,2) not null check (precio >= 0),
  moneda char(3) not null default 'BOB',
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists tbl_compras_creditos (
  id_compra uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_paquete uuid not null references tbl_paquetes_creditos(id_paquete) on delete restrict,
  creditos_comprados bigint not null check (creditos_comprados > 0),
  monto numeric(14,2) not null check (monto >= 0),
  moneda char(3) not null default 'BOB',
  estado estado_compra_creditos not null default 'PENDIENTE',
  fecha_creacion timestamptz not null default now(),
  fecha_pago timestamptz
);

create table if not exists tbl_pagos_creditos (
  id_pago uuid primary key default gen_random_uuid(),
  id_compra uuid not null references tbl_compras_creditos(id_compra) on delete restrict,
  metodo_pago text not null,
  referencia_externa text,
  monto numeric(14,2) not null check (monto >= 0),
  estado estado_pago_creditos not null default 'PENDIENTE',
  fecha_pago timestamptz
);


-- LOGÍSTICA
create table if not exists tbl_envios (
  id_envio uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_pedido uuid not null unique references tbl_pedidos(id_pedido) on delete restrict,
  id_sucursal uuid not null references tbl_sucursales(id_sucursal) on delete restrict,
  direccion text not null,
  referencia text,
  telefono_contacto text not null,
  id_repartidor uuid references tbl_usuarios(id_usuario) on delete set null,
  estado estado_envio not null default 'PENDIENTE',
  numero_guia text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists tbl_env_seguimiento_estados (
  id_seguimiento uuid primary key default gen_random_uuid(),
  id_envio uuid not null references tbl_envios(id_envio) on delete cascade,
  estado estado_envio not null,
  observacion text,
  latitud numeric(9,6),
  longitud numeric(9,6),
  created_at timestamptz not null default now(),
  usuario_id uuid references tbl_usuarios(id_usuario) on delete set null
);


-- AUDITORÍA
create table if not exists tbl_logs_auditoria (
  id_log uuid primary key default gen_random_uuid(),
  id_comercio uuid references tbl_comercios(id_comercio) on delete set null,
  id_usuario uuid references tbl_usuarios(id_usuario) on delete set null,
  accion text not null,
  tabla text not null,
  registro_id uuid,
  datos_anteriores jsonb,
  datos_nuevos jsonb,
  ip inet,
  user_agent text,
  created_at timestamptz not null default now()
);


-- CANALES WHATSAPP (v2/A2: 1 WhatsApp = 1 tienda; soporta OpenWA y Meta)
create table if not exists tbl_canal_whatsapp (
  id_canal uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  id_sucursal uuid references tbl_sucursales(id_sucursal) on delete set null,
  numero text not null unique,
  provider text not null default 'OPENWA' check (provider in ('OPENWA','META')),
  provider_phone_number_id text unique,
  instance_id text,
  status text not null default 'DESCONECTADO',
  activo boolean not null default true, -- fix A13: referenciado por 04/06 (uq_canal_numero_activo, fn_identificar_*)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- EVENTOS WHATSAPP (v2/A6/HU-143: idempotencia de webhooks)
create table if not exists tbl_whatsapp_eventos (
  id_evento uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('OPENWA','META')),
  external_message_id text not null,
  phone_number_id text,
  customer_phone text,
  tipo text,
  processing_status text not null default 'RECIBIDO'
    check (processing_status in ('RECIBIDO','PROCESANDO','PROCESADO','ERROR')),
  payload jsonb,
  recibido timestamptz not null default now(),
  procesado_at timestamptz,
  unique(provider, external_message_id)
);

create index if not exists idx_eventos_status on tbl_whatsapp_eventos(processing_status)
where processing_status <> 'PROCESADO';

-- Catálogo de plantillas Meta (guía §37-38 / HU-124 / WF-80)
create table if not exists tbl_plantillas_whatsapp (
  template_code text primary key,
  template_name text not null,
  language text not null default 'es',
  parametros jsonb,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

-- PREFERENCIAS DE CONTACTO / OPT-OUT (v2/HU-142, política §16)
create table if not exists tbl_contact_preferences (
  id_contact_pref uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete cascade,
  telefono_whatsapp text not null,
  opted_out boolean not null default false,
  opted_out_at timestamptz,
  motivo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id_comercio, telefono_whatsapp)
);

-- ============================================================
-- RSUELVO v2 :: 4. CONSTRAINTS E ÍNDICES ÚNICOS PARCIALES
-- ============================================================

set search_path = rsuelvo, public;

-- Cliente único por WhatsApp dentro del comercio
create unique index if not exists uq_cliente_whatsapp_comercio
on tbl_clientes(id_comercio,telefono_whatsapp)
where telefono_whatsapp is not null;


-- Una sola reserva activa POR CLIENTE por variante+sucursal (opción B: clientes
-- distintos pueden reservar el mismo SKU en paralelo mientras haya stock).
create unique index if not exists uq_reserva_activa_variante_sucursal
on tbl_reservas(id_sucursal,id_variante,id_cliente)
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

-- ============================================================
-- RSUELVO v2 :: 5. ÍNDICES DE RENDIMIENTO
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

create index if not exists idx_variantes_comercio on tbl_variantes(id_comercio);
create index if not exists idx_reservas_expiracion_v2 on tbl_reservas(fecha_expiracion)
where estado in ('ACTIVA','PAGO_VALIDANDO');
-- fix A14: idx_eventos_pendientes eliminado (referenciaba columna procesado inexistente;
-- residuo pre-v2.1 — idx_eventos_status ya cubre eventos pendientes)
create index if not exists idx_envios_repartidor on tbl_envios(id_repartidor,estado);
create index if not exists idx_seguimiento_envio on tbl_env_seguimiento_estados(id_envio,created_at desc);

-- ============================================================
-- RSUELVO v2 :: 6. FUNCIONES
-- ============================================================

set search_path = rsuelvo, public;

-- Validación de asignación usuario/comercio (cajero = 1 sucursal)
-- (fix 17_hardening_search_path_restante) SECURITY INVOKER + SET search_path
-- = rsuelvo, public y objetos calificados.
create or replace function fn_validar_asignacion_usuario_comercio()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_codigo rsuelvo.rol_codigo;
  v_sucursal uuid;
begin
  select codigo into v_codigo from rsuelvo.tbl_roles where id_rol=new.id_rol;

  if v_codigo in ('ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT')
     and new.id_sucursal is null then
    raise exception 'El rol % requiere una sucursal',v_codigo;
  end if;

  if v_codigo='ROLE_TENANT_CASHIER' then
    if exists (
      select 1
      from rsuelvo.tbl_usuario_comercio uc
      join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
      where uc.id_usuario=new.id_usuario
        and uc.activo
        and r.codigo='ROLE_TENANT_CASHIER'
        and uc.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
    ) then
      raise exception 'Un cashier solo puede tener una asignación activa';
    end if;
  end if;

  return new;
end;
$$;


-- (v2/A1) Resuelve tenant de la variante, genera SKU de 6 caracteres
-- [3 tienda][3 producto] en base36 si viene nulo, valida formato y duplicados.
-- (fix 16_fix_search_path_sku) SECURITY INVOKER + SET search_path = rsuelvo, public
-- y tablas calificadas para no depender del search_path de sesión.
-- Helper base36 → int (m39: el trigger calculaba el máximo como HEX y fallaba con G-Z)
create or replace function fn_base36_a_int(p_texto text)
returns integer
language plpgsql
immutable
set search_path = rsuelvo, public
as $$
declare
  v text := upper(coalesce(p_texto,''));
  i int;
  c text;
  v_valor int := 0;
begin
  if v = '' then return null; end if;
  for i in 1..length(v) loop
    c := substr(v, i, 1);
    if c ~ '[0-9]' then
      v_valor := v_valor * 36 + (ascii(c) - 48);
    elsif c ~ '[A-Z]' then
      v_valor := v_valor * 36 + (ascii(c) - 55);
    else
      return null;
    end if;
  end loop;
  return v_valor;
end;
$$;

create or replace function fn_resolver_variante_tenant_sku()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_comercio uuid;
  v_codigo char(3);
  v_max int;
  v_sufijo text;
  v_sku text;
begin
  -- 1) Resolver id_comercio desde el producto (siempre).
  if new.id_producto is not null then
    select p.id_comercio into v_comercio
    from rsuelvo.tbl_productos p
    where p.id_producto=new.id_producto;
  end if;

  if v_comercio is null then
    raise exception 'Producto inexistente';
  end if;

  new.id_comercio := v_comercio;

  select codigo_tienda into v_codigo
  from rsuelvo.tbl_comercios
  where id_comercio=v_comercio;

  if v_codigo is null then
    raise exception 'El comercio % no tiene codigo_tienda asignado',v_comercio;
  end if;

  -- 2) Generar SKU si no viene (o venir vacío).
  if coalesce(new.sku,'')='' then
    -- serializar por comercio: bloquea la fila del comercio.
    select 1 into v_max from rsuelvo.tbl_comercios
    where id_comercio=v_comercio for update;

    select coalesce(max(
      rsuelvo.fn_base36_a_int(substr(v.sku,4,3))
    ),0) into v_max
    from rsuelvo.tbl_variantes v
    where v.id_comercio=v_comercio
      and v.sku ~ '^[A-Z0-9]{6}$'
      and substr(v.sku,1,3)=v_codigo::text;

    v_max := v_max+1;
    if v_max > 46655 then
      raise exception 'Se agotaron los SKUs disponibles para la tienda %',v_codigo;
    end if;

    declare
      n int := v_max;
      chars text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      out text := '';
    begin
      while n>0 loop
        out := substr(chars,(n%36)+1,1)||out;
        n := n/36;
      end loop;
      v_sufijo := lpad(coalesce(nullif(out,''),'0'),3,'0');
    end;

    new.sku := upper(v_codigo::text||v_sufijo);
  else
    new.sku := upper(new.sku);
  end if;

  -- 3) Validar formato 6 caracteres tienda+producto.
  if new.sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido %. Formato requerido: 6 caracteres [3 tienda][3 producto], ej. FERA01',new.sku;
  end if;

  if substr(new.sku,1,3) <> v_codigo::text then
    raise exception 'El prefijo del SKU (%) debe ser el código de la tienda (%)',substr(new.sku,1,3),v_codigo;
  end if;

  -- 4) Duplicado amigable (el UNIQUE físico es la garantía real).
  if exists (
    select 1 from rsuelvo.tbl_variantes v
    where v.id_comercio=v_comercio
      and v.sku=new.sku
      and v.id_variante<>coalesce(new.id_variante,'00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    raise exception 'SKU duplicado dentro del comercio: %',new.sku;
  end if;

  return new;
end;
$$;


-- Consistencia multi-tenant
-- (fix 17_hardening_search_path_restante) SECURITY INVOKER + SET search_path
-- = rsuelvo, public y objetos calificados.
create or replace function fn_validar_consistencia_tenant()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_comercio uuid;
begin
  -- Sucursal pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_lista_espera','tbl_pedidos','tbl_envios') then
    select id_comercio into v_comercio
    from rsuelvo.tbl_sucursales
    where id_sucursal=new.id_sucursal;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'La sucursal no pertenece al comercio';
    end if;
  end if;

  -- Cliente pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_pedidos','tbl_comprobantes_pago') then
    select id_comercio into v_comercio
    from rsuelvo.tbl_clientes
    where id_cliente=new.id_cliente;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'El cliente no pertenece al comercio';
    end if;
  end if;

  return new;
end;
$$;


-- updated_at automático
create or replace function fn_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- (v2) ¿La llamada proviene de service_role (n8n/backend)?
create or replace function fn_es_service_role()
returns boolean
language sql
stable
as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),'service_role')
     = 'service_role';
$$;


-- (fix A15) Resolver auth.uid() -> tbl_usuarios.id_usuario.
-- Devuelve NULL para sesiones sin usuario de app (service_role/cron);
-- consumida por fn_solicitar_reserva, fn_crear_envio, fn_actualizar_estado_envio,
-- fn_movimiento_inventario y fn_auditar_cambio.
create or replace function fn_current_usuario_id()
returns uuid
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select id_usuario from tbl_usuarios where auth_user_id = auth.uid();
$$;


-- Helpers de tenancy (v2: con escape para service_role en accesos)

create or replace function fn_tiene_rol(p_rol rol_codigo)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select exists (
    select 1
    from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol=uc.id_rol
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    where u.auth_user_id=auth.uid()
      and u.activo
      and uc.activo
      and r.codigo=p_rol
  );
$$;


create or replace function fn_es_superadmin()
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_tiene_rol('ROLE_SUPERADMIN');
$$;


create or replace function fn_tiene_acceso_comercio(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        where u.auth_user_id=auth.uid()
          and u.activo
          and uc.activo
          and uc.id_comercio=p_id_comercio
      );
$$;

create or replace function fn_tiene_acceso_sucursal(p_id_comercio uuid,p_id_sucursal uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        where u.auth_user_id=auth.uid()
          and u.activo
          and uc.activo
          and uc.id_comercio=p_id_comercio
          and (
            uc.id_sucursal is null
            or uc.id_sucursal=p_id_sucursal
            or exists (
              select 1
              from tbl_roles r
              where r.id_rol=uc.id_rol
                and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPPORT','ROLE_SUPERADMIN')
            )
          )
      );
$$;

create or replace function fn_es_admin_comercio(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        join tbl_roles r on r.id_rol=uc.id_rol
        where u.auth_user_id=auth.uid()
          and u.activo and uc.activo
          and uc.id_comercio=p_id_comercio
          and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPPORT')
      );
$$;

-- (v2/A10) Rol específico dentro de un comercio
create or replace function fn_tiene_rol_comercio(p_id_comercio uuid,p_rol rol_codigo)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_service_role() or exists (
    select 1
    from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid()
      and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and r.codigo=p_rol
  );
$$;

-- (v2/A10) Puede verificar comprobantes: admin o cajero del comercio (HU-141)
create or replace function fn_puede_verificar(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_es_admin_comercio(p_id_comercio)
      or fn_tiene_rol_comercio(p_id_comercio,'ROLE_TENANT_CASHIER');
$$;

-- (v2/A10) Puede crear/asignar envíos: admin o cajero del comercio (matriz)
create or replace function fn_puede_gestionar_envios(p_id_comercio uuid)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select fn_puede_verificar(p_id_comercio);
$$;


-- Upsert de cliente
create or replace function fn_upsert_cliente(
  p_id_comercio uuid,
  p_nombre text,
  p_telefono text default null,
  p_telefono_whatsapp text default null,
  p_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_id uuid;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;

  if p_telefono_whatsapp is not null then
    select id_cliente into v_id
    from tbl_clientes
    where id_comercio=p_id_comercio
      and telefono_whatsapp=p_telefono_whatsapp
    for update;

    if v_id is not null then
      update tbl_clientes
      set nombre=coalesce(nullif(p_nombre,''),nombre),
          telefono=coalesce(p_telefono,telefono),
          email=coalesce(p_email,email)
      where id_cliente=v_id;
      return v_id;
    end if;
  end if;

  insert into tbl_clientes(
    id_comercio,nombre,telefono,telefono_whatsapp,email
  )
  values(
    p_id_comercio,p_nombre,p_telefono,p_telefono_whatsapp,p_email
  )
  returning id_cliente into v_id;

  return v_id;
end;
$$;


-- (v2/WF-10/HU-037..041) Resuelve SKU exacto dentro del comercio.
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


-- (v2/A2/HU-123) Identificar comercio+sucursal por número de WhatsApp destino.
-- Solo service_role (n8n): nunca expone el mapa completo al cliente.
create or replace function fn_identificar_comercio_por_whatsapp(p_numero text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select c.id_comercio, c.id_sucursal, c.provider::text
  from tbl_canal_whatsapp c
  where c.numero=p_numero
    and c.activo
  limit 1;
$$;

-- Guard: rechazar si NO es service_role
-- (fix 17_hardening_search_path_restante) SECURITY INVOKER + SET search_path
-- = rsuelvo, public y llamada calificada a rsuelvo.fn_es_service_role.
create or replace function fn_assert_service_role()
returns void
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
begin
  if not rsuelvo.fn_es_service_role() then
    raise exception 'Operación reservada al backend (service_role)';
  end if;
end;
$$;

-- (v2/A6/HU-143 + Guía Meta §15-16) Registrar evento entrante con estado de
-- procesamiento y datos de correlación. Devuelve jsonb: nuevo=true => procesar.
create or replace function fn_registrar_evento_whatsapp(
  p_provider text,
  p_external_message_id text,
  p_tipo text default null,
  p_payload jsonb default null,
  p_phone_number_id text default null,
  p_customer_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_nuevo boolean := false;
begin
  perform fn_assert_service_role();

  insert into tbl_whatsapp_eventos(
    provider,external_message_id,tipo,payload,phone_number_id,customer_phone,processing_status
  )
  values(
    p_provider,p_external_message_id,p_tipo,p_payload,p_phone_number_id,p_customer_phone,'PROCESANDO'
  )
  on conflict (provider,external_message_id) do nothing;

  v_nuevo := found;

  if not v_nuevo then
    -- Reintento legítimo si el intento anterior quedó PROCESSING/ERROR.
    update tbl_whatsapp_eventos
    set processing_status='PROCESANDO', payload=coalesce(p_payload,payload)
    where provider=p_provider
      and external_message_id=p_external_message_id
      and processing_status in ('PROCESANDO','ERROR');
    v_nuevo := found;
  end if;

  return jsonb_build_object('nuevo',v_nuevo);
end;
$$;

-- Marcar resultado del procesamiento (éxito/error).
create or replace function fn_cerrar_evento_whatsapp(
  p_provider text,
  p_external_message_id text,
  p_exito boolean default true,
  p_error text default null
)
returns void
language sql
security definer
set search_path = rsuelvo, public
as $$
  update tbl_whatsapp_eventos
  set processing_status = case when p_exito then 'PROCESADO' else 'ERROR' end,
      procesado_at = now(),
      payload = coalesce(payload || jsonb_build_object('last_error',p_error), payload)
  where provider=p_provider and external_message_id=p_external_message_id;
$$;

-- (v2/Guía Meta §18/58) Identificación por Phone Number ID de Meta.
create or replace function fn_identificar_comercio_por_phone_number_id(p_pnid text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select c.id_comercio, c.id_sucursal, c.provider::text
  from tbl_canal_whatsapp c
  where c.provider_phone_number_id=p_pnid
    and c.activo
  limit 1;
$$;

-- (v2/HU-142) Registrar opt-out del comprador
create or replace function fn_registrar_opt_out(
  p_id_comercio uuid,
  p_telefono_whatsapp text,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
begin
  insert into tbl_contact_preferences(id_comercio,telefono_whatsapp,opted_out,opted_out_at,motivo)
  values(p_id_comercio,p_telefono_whatsapp,true,now(),coalesce(p_motivo,'STOP'))
  on conflict (id_comercio,telefono_whatsapp)
  do update set opted_out=true, opted_out_at=now(), motivo=coalesce(excluded.motivo,tbl_contact_preferences.motivo);
end;
$$;

-- (v2/HU-142) ¿Puede recibirse comunicación transaccional?
create or replace function fn_cliente_optado(p_id_comercio uuid,p_telefono_whatsapp text)
returns boolean
language sql
stable
security definer
set search_path = rsuelvo, public
as $$
  select coalesce((select opted_out from tbl_contact_preferences
    where id_comercio=p_id_comercio and telefono_whatsapp=p_telefono_whatsapp),false);
$$;


-- Reserva atómica (v2/18 RESERVA_YA_EXISTENTE por cliente; opción B)
create or replace function fn_solicitar_reserva(
  p_id_comercio uuid,
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_id_cliente uuid,
  p_cantidad integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_inv tbl_inventario%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_reserva uuid;
  v_pedido uuid;
  v_precio numeric(14,2);
  v_reserva_existente uuid;
  v_fecha_expiracion timestamptz;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0';
  end if;

  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;

  select * into v_cfg
  from tbl_comercio_config
  where id_comercio=p_id_comercio;

  if not found then
    raise exception 'El comercio no tiene configuración';
  end if;

  select v.precio into v_precio
  from tbl_variantes v
  join tbl_productos p on p.id_producto=v.id_producto
  where v.id_variante=p_id_variante
    and p.id_comercio=p_id_comercio
    and v.activo
    and p.activo;

  if v_precio is null then
    raise exception 'SKU/variante inválida para el comercio';
  end if;

  -- (18/RESERVA_YA_EXISTENTE por cliente) Detección temprana SIN tocar inventario:
  -- si el MISMO cliente ya tiene una reserva activa para (sucursal, variante) la
  -- devolvemos. El índice uq_reserva_activa_variante_sucursal ahora incluye
  -- id_cliente, por lo que clientes DISTINTOS NO colisionan y pueden reservar en
  -- paralelo mientras haya stock. FOR UPDATE serializa contra fn_expirar_reserva
  -- sobre la misma fila del cliente y evita doble retorno en reintentos.
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  for update;

  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;

  -- Bloqueo pesimista: solo una transacción modifica esta fila. Este lock serializa
  -- la carrera primera-reserva/reintento para la misma variante+sucursal.
  select * into v_inv
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;

  if not found then
    return jsonb_build_object(
      'resultado','SIN_STOCK',
      'motivo','NO_EXISTE_INVENTARIO'
    );
  end if;

  -- (18/RESERVA_YA_EXISTENTE por cliente) Re-verificación DENTRO del lock de
  -- inventario para cerrar la carrera primer-reserva/reintento del MISMO cliente.
  -- Una transacción concurrente del mismo cliente pudo crear la reserva mientras
  -- esta esperaba el lock. Cliente distinto no cuenta (puede reservar si hay stock).
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  limit 1;

  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;

  if (v_inv.stock_actual-v_inv.stock_reservado) >= p_cantidad then

    update tbl_inventario
    set stock_reservado=stock_reservado+p_cantidad
    where id_inventario=v_inv.id_inventario;

    insert into tbl_reservas(
      id_comercio,id_sucursal,id_variante,id_cliente,
      origen,estado,cantidad,fecha_inicio,fecha_expiracion
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,
      'DIRECTA','ACTIVA',p_cantidad,now(),
      now() + make_interval(mins=>v_cfg.tiempo_reserva_minutos)
    )
    returning id_reserva into v_reserva;

    insert into tbl_inventario_movimientos(
      id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,'RESERVA',
      p_cantidad,'RESERVA',v_reserva,fn_current_usuario_id()
    );

    return jsonb_build_object(
      'resultado','RESERVA_CREADA',
      'id_reserva',v_reserva,
      'fecha_expiracion',(
        select fecha_expiracion from tbl_reservas where id_reserva=v_reserva
      )
    );
  end if;

  return jsonb_build_object(
    'resultado','SIN_STOCK',
    'motivo','PRODUCTO_RESERVADO_O_AGOTADO'
  );
end;
$$;


-- Agregar a lista de espera
-- v1 ELIMINADA en migración 54 (superseded por fn_agregar_lista_espera_v2)


-- Expirar reserva
create or replace function fn_expirar_reserva(p_id_reserva uuid)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_res tbl_reservas%rowtype;
begin
  select * into v_res
  from tbl_reservas
  where id_reserva=p_id_reserva
  for update;

  if not found then
    raise exception 'Reserva inexistente';
  end if;

  if v_res.estado <> 'ACTIVA' then
    return jsonb_build_object('resultado','SIN_CAMBIO','estado',v_res.estado);
  end if;

  if v_res.fecha_expiracion > now() then
    return jsonb_build_object(
      'resultado','AUN_ACTIVA',
      'fecha_expiracion',v_res.fecha_expiracion
    );
  end if;

  update tbl_reservas
  set estado='VENCIDA',
      fecha_finalizacion=now()
  where id_reserva=p_id_reserva;

  update tbl_inventario
  set stock_reservado=stock_reservado-v_res.cantidad
  where id_sucursal=v_res.id_sucursal
    and id_variante=v_res.id_variante
    and stock_reservado >= v_res.cantidad;

  if not found then
    raise exception 'Inconsistencia de inventario al liberar reserva %',p_id_reserva;
  end if;

  insert into tbl_inventario_movimientos(
    id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id
  )
  values(
    v_res.id_comercio,v_res.id_sucursal,v_res.id_variante,
    'LIBERACION_RESERVA',v_res.cantidad,'RESERVA',v_res.id_reserva
  );

  return jsonb_build_object(
    'resultado','RESERVA_LIBERADA',
    'id_reserva',p_id_reserva
  );
end;
$$;


-- Notificar siguiente de la lista (m32: salta clientes con oferta NOTIFICADO vigente en cualquier grupo — H-17)
create or replace function fn_notificar_siguiente_lista_espera(
  p_id_sucursal uuid,
  p_id_variante uuid
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_item tbl_lista_espera%rowtype;
  v_cfg tbl_comercio_config%rowtype;
begin
  select * into v_item
  from tbl_lista_espera cand
  where cand.id_sucursal=p_id_sucursal
    and cand.id_variante=p_id_variante
    and cand.estado='ESPERANDO'
    and not exists (
      select 1 from tbl_lista_espera act
      where act.id_cliente = cand.id_cliente
        and act.estado='NOTIFICADO'
        and act.fecha_expiracion > now()
    )
  order by cand.posicion
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object('resultado','LISTA_VACIA');
  end if;

  select * into v_cfg
  from tbl_comercio_config
  where id_comercio=v_item.id_comercio;

  update tbl_lista_espera
  set estado='NOTIFICADO',
      fecha_notificacion=now(),
      fecha_expiracion=now()+make_interval(
        mins=>v_cfg.tiempo_aceptacion_lista_espera_minutos
      )
  where id_lista_espera=v_item.id_lista_espera;

  return jsonb_build_object(
    'resultado','CLIENTE_NOTIFICADO',
    'id_lista_espera',v_item.id_lista_espera,
    'id_cliente',v_item.id_cliente,
    'fecha_expiracion',(
      select fecha_expiracion
      from tbl_lista_espera
      where id_lista_espera=v_item.id_lista_espera
    )
  );
end;
$$;


-- Aceptar oportunidad
create or replace function fn_aceptar_lista_espera(p_id_lista_espera uuid)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_item tbl_lista_espera%rowtype;
  v_result jsonb;
begin
  select * into v_item
  from tbl_lista_espera
  where id_lista_espera=p_id_lista_espera
  for update;

  if not found then
    raise exception 'Entrada de lista inexistente';
  end if;

  if v_item.estado <> 'NOTIFICADO' then
    raise exception 'La oportunidad ya no está disponible';
  end if;

  if v_item.fecha_expiracion < now() then
    update tbl_lista_espera
    set estado='VENCIDO'
    where id_lista_espera=p_id_lista_espera;

    return jsonb_build_object('resultado','OPORTUNIDAD_VENCIDA');
  end if;

  update tbl_lista_espera
  set estado='ACEPTADO',
      fecha_aceptacion=now()
  where id_lista_espera=p_id_lista_espera;

  v_result := fn_solicitar_reserva(
    v_item.id_comercio,
    v_item.id_sucursal,
    v_item.id_variante,
    v_item.id_cliente,
    1
  );

  if v_result->>'resultado' = 'RESERVA_CREADA' then
    update tbl_lista_espera
    set estado='CONVERTIDO_RESERVA',
        id_reserva_generada=(v_result->>'id_reserva')::uuid
    where id_lista_espera=p_id_lista_espera;
  else
    update tbl_lista_espera
    set estado='VENCIDO'
    where id_lista_espera=p_id_lista_espera;
  end if;

  return v_result;
end;
$$;


-- Crear pedido desde reserva
-- (migración 19 / H-1) Idempotencia: reintento de la MISMA reserva devuelve el pedido existente.
create or replace function fn_crear_pedido_desde_reserva(p_id_reserva uuid)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_res tbl_reservas%rowtype;
  v_var tbl_variantes%rowtype;
  v_prod tbl_productos%rowtype;
  v_pedido uuid;
  v_subtotal numeric(14,2);
begin
  select * into v_res
  from tbl_reservas
  where id_reserva=p_id_reserva
  for update;

  if not found then
    raise exception 'Reserva inexistente';
  end if;

  if v_res.estado not in ('ACTIVA','PAGO_VALIDANDO') then
    raise exception 'La reserva no puede generar pedido';
  end if;

  -- H-1 (migración 19): idempotencia por reserva
  if v_res.id_pedido is not null then
    return v_res.id_pedido;
  end if;

  select v.* into v_var
  from tbl_variantes v
  where v.id_variante=v_res.id_variante;

  select p.* into v_prod
  from tbl_productos p
  where p.id_producto=v_var.id_producto;

  v_subtotal := v_var.precio * v_res.cantidad;

  insert into tbl_pedidos(
    id_comercio,id_sucursal,id_cliente,estado,subtotal,descuento,id_reserva
  )
  values(
    v_res.id_comercio,v_res.id_sucursal,v_res.id_cliente,
    'ESPERANDO_PAGO',v_subtotal,0,p_id_reserva
  )
  returning id_pedido into v_pedido;

  insert into tbl_pedido_detalles(
    id_pedido,id_variante,sku_snapshot,nombre_snapshot,precio_unitario,cantidad
  )
  values(
    v_pedido,v_var.id_variante,v_var.sku,
    v_prod.nombre || ' - ' || v_var.nombre,
    v_var.precio,v_res.cantidad
  );

  update tbl_reservas
  set id_pedido=v_pedido
  where id_reserva=p_id_reserva;

  return v_pedido;
end;
$$;


-- Consumo atómico de créditos
create or replace function fn_consumir_creditos(
  p_id_comercio uuid,
  p_id_servicio uuid,
  p_referencia_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_cuenta tbl_cuentas_creditos%rowtype;
  v_serv tbl_servicios_creditos%rowtype;
  v_anterior bigint;
  v_nuevo bigint;
begin
  select * into v_serv
  from tbl_servicios_creditos
  where id_servicio=p_id_servicio
    and activo
  for share;

  if not found then
    raise exception 'Servicio de créditos inexistente o inactivo';
  end if;

  select * into v_cuenta
  from tbl_cuentas_creditos
  where id_comercio=p_id_comercio
  for update;

  if not found then
    insert into tbl_cuentas_creditos(id_comercio,saldo_actual)
    values(p_id_comercio,0)
    returning * into v_cuenta;
  end if;

  v_anterior := v_cuenta.saldo_actual;

  if v_anterior < v_serv.costo_creditos then
    raise exception 'SALDO_INSUFICIENTE';
  end if;

  v_nuevo := v_anterior-v_serv.costo_creditos;

  update tbl_cuentas_creditos
  set saldo_actual=v_nuevo
  where id_cuenta_creditos=v_cuenta.id_cuenta_creditos;

  insert into tbl_movimientos_creditos(
    id_comercio,id_cuenta_creditos,tipo,cantidad,
    saldo_anterior,saldo_posterior,concepto,referencia_tipo,referencia_id
  )
  values(
    p_id_comercio,v_cuenta.id_cuenta_creditos,
    'CONSUMO_VERIFICACION',-v_serv.costo_creditos,
    v_anterior,v_nuevo,
    'Consumo de servicio de verificación',
    'VERIFICACION',p_referencia_id
  );

  update tbl_verificaciones
  set creditos_consumidos=v_serv.costo_creditos
  where id_verificacion=p_referencia_id;

  return v_serv.costo_creditos;
end;
$$;


-- Acreditar créditos
create or replace function fn_acreditar_creditos(
  p_id_comercio uuid,
  p_cantidad bigint,
  p_tipo tipo_movimiento_credito,
  p_concepto text default null,
  p_referencia_tipo text default null,
  p_referencia_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_cuenta tbl_cuentas_creditos%rowtype;
  v_anterior bigint;
  v_nuevo bigint;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser positiva';
  end if;

  insert into tbl_cuentas_creditos(id_comercio,saldo_actual)
  values(p_id_comercio,0)
  on conflict(id_comercio) do nothing;

  select * into v_cuenta
  from tbl_cuentas_creditos
  where id_comercio=p_id_comercio
  for update;

  v_anterior := v_cuenta.saldo_actual;
  v_nuevo := v_anterior+p_cantidad;

  update tbl_cuentas_creditos
  set saldo_actual=v_nuevo
  where id_cuenta_creditos=v_cuenta.id_cuenta_creditos;

  insert into tbl_movimientos_creditos(
    id_comercio,id_cuenta_creditos,tipo,cantidad,
    saldo_anterior,saldo_posterior,concepto,referencia_tipo,referencia_id
  )
  values(
    p_id_comercio,v_cuenta.id_cuenta_creditos,p_tipo,p_cantidad,
    v_anterior,v_nuevo,p_concepto,p_referencia_tipo,p_referencia_id
  );

  return v_nuevo;
end;
$$;


-- Confirmar pago
create or replace function fn_confirmar_pago(
  p_id_verificacion uuid,
  p_resultado jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_ver tbl_verificaciones%rowtype;
  v_res tbl_reservas%rowtype;
begin
  select * into v_ver
  from tbl_verificaciones
  where id_verificacion=p_id_verificacion
  for update;

  if not found then
    raise exception 'Verificación inexistente';
  end if;

  -- H-01: guarda de idempotencia por verificación
  if v_ver.estado = 'COMPLETADA' then
    return jsonb_build_object(
      'resultado','YA_PROCESADO',
      'id_pedido', v_ver.id_pedido,
      'mensaje','Esta verificación ya fue confirmada previamente; no se repiten efectos de inventario.'
    );
  end if;

  select * into v_res
  from tbl_reservas
  where id_pedido=v_ver.id_pedido
  for update;

  if not found then
    raise exception 'No existe reserva asociada al pedido';
  end if;

  -- H-12: el pedido no debe confirmarse dos veces
  if exists (select 1 from tbl_pedidos where id_pedido=v_ver.id_pedido and estado='PAGADO') then
    return jsonb_build_object(
      'resultado','YA_PROCESADO',
      'id_pedido', v_ver.id_pedido,
      'mensaje','El pedido ya estaba pagado; no se repiten efectos de inventario.'
    );
  end if;

  -- H-12: la reserva debe seguir viva para poder convertirse en venta
  if v_res.estado not in ('ACTIVA','PAGO_VALIDANDO') or v_res.fecha_expiracion < now() then
    return jsonb_build_object(
      'resultado','RESERVA_VENCIDA',
      'id_pedido', v_ver.id_pedido,
      'mensaje','La reserva expiró. El comprador debe solicitar el SKU nuevamente.'
    );
  end if;

  update tbl_verificaciones
  set estado='COMPLETADA',
      resultado=p_resultado,
      fecha_fin=now()
  where id_verificacion=p_id_verificacion;

  update tbl_comprobantes_pago
  set estado='VALIDO'
  where id_comprobante=v_ver.id_comprobante;

  update tbl_pedidos
  set estado='PAGADO',
      fecha_confirmacion=now()
  where id_pedido=v_ver.id_pedido;

  update tbl_reservas
  set estado='CONFIRMADA',
      fecha_finalizacion=now()
  where id_reserva=v_res.id_reserva;

  update tbl_inventario
  set stock_reservado=stock_reservado-v_res.cantidad,
      stock_actual=stock_actual-v_res.cantidad
  where id_sucursal=v_res.id_sucursal
    and id_variante=v_res.id_variante
    and stock_reservado >= v_res.cantidad
    and stock_actual >= v_res.cantidad;

  if not found then
    raise exception 'Inconsistencia de inventario al confirmar venta';
  end if;

  insert into tbl_inventario_movimientos(
    id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id
  )
  values(
    v_res.id_comercio,v_res.id_sucursal,v_res.id_variante,
    'VENTA',v_res.cantidad,'PEDIDO',v_ver.id_pedido
  );

  -- D14 (migración 27): consume 1 crédito por venta confirmada en la misma transacción
  PERFORM fn_consumir_credito_venta(v_res.id_comercio, v_ver.id_pedido);

  return jsonb_build_object(
    'resultado','PAGO_CONFIRMADO',
    'id_pedido',v_ver.id_pedido,
    'id_reserva',v_res.id_reserva
  );
end;
$$;


-- (v2/A9/HU-065) Rechazo: comprobante INVALIDO pero el pedido vuelve a
-- ESPERANDO_PAGO para permitir reenvío. CANCELADO solo por decisión admin.
create or replace function fn_rechazar_verificacion(
  p_id_verificacion uuid,
  p_resultado jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_ver tbl_verificaciones%rowtype;
begin
  select * into v_ver
  from tbl_verificaciones
  where id_verificacion=p_id_verificacion
  for update;

  if not found then
    raise exception 'Verificación inexistente';
  end if;

  update tbl_verificaciones
  set estado='COMPLETADA',
      resultado=p_resultado,
      fecha_fin=now()
  where id_verificacion=p_id_verificacion;

  update tbl_comprobantes_pago
  set estado='INVALIDO'
  where id_comprobante=v_ver.id_comprobante;

  update tbl_pedidos
  set estado='ESPERANDO_PAGO'
  where id_pedido=v_ver.id_pedido
    and estado in ('ESPERANDO_PAGO','PAGO_RECIBIDO','PAGO_VALIDANDO');

  return jsonb_build_object(
    'resultado','PAGO_RECHAZADO',
    'id_pedido',v_ver.id_pedido,
    'pedido','ESPERANDO_PAGO',
    'puede_reenviar',true
  );
end;
$$;

-- (v2/WF-21/HU-057..058) Registra un comprobante de pago y lo vincula al pedido en
-- espera de pago del cliente/comercio. SECURITY DEFINER para que n8n pueda invocarla
-- con la credencial anon (mismo patrón que fn_upsert_cliente), sin requerir
-- service_role en el app layer. Resuelve id_pedido si no se provee.
-- Migración 20: idempotencia de reenvío (D5). Migración 21: fix ambigüedad PL/pgSQL.
create or replace function fn_registrar_comprobante(
  p_id_comercio uuid,
  p_id_cliente uuid,
  p_tipo_archivo text,
  p_archivo_url text,
  p_monto_detectado numeric default null,
  p_fecha_detectada timestamptz default null,
  p_numero_operacion text default null,
  p_nombre_pagador text default null,
  p_estado rsuelvo.estado_comprobante default 'RECIBIDO',
  p_id_pedido uuid default null
)
returns table(id_comprobante uuid, id_pedido uuid)
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_id_comprobante uuid := gen_random_uuid();
  v_id_pedido uuid := p_id_pedido;
  v_existente uuid;
  v_pedido_existente uuid;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;

  if v_id_pedido is null then
    select p.id_pedido into v_id_pedido
    from tbl_pedidos p
    where p.id_comercio = p_id_comercio
      and p.id_cliente = p_id_cliente
      and p.estado = 'ESPERANDO_PAGO'
    order by p.created_at desc
    limit 1;
  end if;

  if v_id_pedido is null then
    raise exception 'No se encontro pedido en espera de pago para vincular el comprobante';
  end if;

  -- Idempotencia de reenvío: mismo numero de operacion en el mismo comercio
  if p_numero_operacion is not null then
    select c.id_comprobante, c.id_pedido
      into v_existente, v_pedido_existente
      from tbl_comprobantes_pago c
      where c.id_comercio = p_id_comercio
        and c.numero_operacion = p_numero_operacion
      limit 1;

    if v_existente is not null then
      if v_pedido_existente = v_id_pedido then
        update tbl_comprobantes_pago as c
           set tipo_archivo     = p_tipo_archivo,
               archivo_url      = p_archivo_url,
               monto_detectado  = coalesce(p_monto_detectado, c.monto_detectado),
               fecha_detectada  = coalesce(p_fecha_detectada, c.fecha_detectada),
               nombre_pagador   = coalesce(p_nombre_pagador, c.nombre_pagador),
               estado           = p_estado
         where c.id_comprobante = v_existente;
        return query select v_existente, v_id_pedido;
        return;
      else
        raise exception 'COMPROBANTE_DUPLICADO: el numero de operacion % ya fue registrado para otro pedido', p_numero_operacion;
      end if;
    end if;
  end if;

  insert into tbl_comprobantes_pago (
    id_comprobante, id_comercio, id_pedido, id_cliente,
    tipo_archivo, archivo_url, monto_detectado, fecha_detectada,
    numero_operacion, nombre_pagador, estado
  ) values (
    v_id_comprobante, p_id_comercio, v_id_pedido, p_id_cliente,
    p_tipo_archivo, p_archivo_url, p_monto_detectado, p_fecha_detectada,
    p_numero_operacion, p_nombre_pagador, p_estado
  );

  return query select v_id_comprobante, v_id_pedido;
end;
$$;

grant execute on function fn_registrar_comprobante(
  uuid, uuid, text, text, numeric, timestamptz, text, text, rsuelvo.estado_comprobante, uuid
) to anon, authenticated, service_role;


-- Crear envío
create or replace function fn_crear_envio(
  p_id_pedido uuid,
  p_direccion text,
  p_referencia text,
  p_telefono_contacto text
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_pedido tbl_pedidos%rowtype;
  v_id uuid;
begin
  select * into v_pedido
  from tbl_pedidos
  where id_pedido=p_id_pedido
  for update;

  if not found then
    raise exception 'Pedido inexistente';
  end if;

  if v_pedido.estado <> 'PAGADO' then
    raise exception 'El pedido todavía no está pagado';
  end if;

  insert into tbl_envios(
    id_comercio,id_pedido,id_sucursal,direccion,referencia,telefono_contacto
  )
  values(
    v_pedido.id_comercio,p_id_pedido,v_pedido.id_sucursal,
    p_direccion,p_referencia,p_telefono_contacto
  )
  returning id_envio into v_id;

  insert into tbl_env_seguimiento_estados(
    id_envio,estado,observacion,usuario_id
  )
  values(
    v_id,'PENDIENTE','Envío creado',fn_current_usuario_id()
  );

  update tbl_pedidos
  set estado='PREPARANDO'
  where id_pedido=p_id_pedido;

  return v_id;
end;
$$;


-- (v2/A4/HU-056) Generar cobro QR del pedido (referencia única por comercio).
-- (migración 19 / H-1) Idempotencia: reintento del MISMO pedido devuelve el cobro GENERADO vigente.
create or replace function fn_generar_cobro(
  p_id_pedido uuid,
  p_qr_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_pedido tbl_pedidos%rowtype;
  v_metodo uuid;
  v_id uuid;
begin
  select * into v_pedido from tbl_pedidos
  where id_pedido=p_id_pedido for update;

  if not found then
    raise exception 'Pedido inexistente';
  end if;

  if v_pedido.estado not in ('CREADO','ESPERANDO_PAGO') then
    raise exception 'El pedido % no admite cobro en estado %',p_id_pedido,v_pedido.estado;
  end if;

  -- H-1 (migración 19): idempotencia por pedido (retorna cobro GENERADO vigente)
  select id_qr_cobro into v_id from tbl_qr_cobros
  where id_pedido=p_id_pedido and estado='GENERADO' limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select id_metodo_pago into v_metodo
  from tbl_metodos_pago
  where id_comercio=v_pedido.id_comercio and activo
  order by created_at
  limit 1;

  if v_metodo is null then
    raise exception 'El comercio no tiene métodos de pago configurados';
  end if;

  update tbl_pedidos set estado='ESPERANDO_PAGO' where id_pedido=p_id_pedido;

  insert into tbl_qr_cobros(
    id_comercio,id_pedido,id_metodo_pago,monto,referencia,qr_url,estado
  )
  values(
    v_pedido.id_comercio,p_id_pedido,v_metodo,v_pedido.total,
    'RS-'||lpad(v_pedido.numero_pedido::text,8,'0'),
    p_qr_url,'GENERADO'
  )
  returning id_qr_cobro into v_id;

  return v_id;
end;
$$;

-- (v2/A3/HU-141) Iniciar verificación ATÓMICA: crea verificación + consume créditos.
create or replace function fn_iniciar_verificacion(
  p_id_comprobante uuid,
  p_codigo_servicio text default 'VERIFICACION_COMPROBANTE',
  p_forzar boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_comp tbl_comprobantes_pago%rowtype;
  v_serv tbl_servicios_creditos%rowtype;
  v_ver uuid;
  v_costo bigint;
begin
  select * into v_comp from tbl_comprobantes_pago
  where id_comprobante=p_id_comprobante for update;

  if not found then
    raise exception 'Comprobante inexistente';
  end if;

  if v_comp.estado not in ('RECIBIDO') then
    return jsonb_build_object('resultado','ESTADO_NO_VERIFICABLE','estado',v_comp.estado);
  end if;

  select * into v_serv from tbl_servicios_creditos
  where codigo=p_codigo_servicio and activo for share;

  if not found then
    raise exception 'Servicio de créditos inexistente: %',p_codigo_servicio;
  end if;
  v_costo := v_serv.costo_creditos;

  insert into tbl_verificaciones(
    id_comercio,id_comprobante,id_pedido,tipo_verificacion,estado,fecha_inicio
  )
  values(
    v_comp.id_comercio,p_id_comprobante,v_comp.id_pedido,
    p_codigo_servicio,'PROCESANDO',now()
  )
  returning id_verificacion into v_ver;

  begin
    perform 1 from tbl_cuentas_creditos
    where id_comercio=v_comp.id_comercio for update;

    if (select coalesce(saldo_actual,0) from tbl_cuentas_creditos
        where id_comercio=v_comp.id_comercio) < v_costo then
      raise exception 'SALDO_INSUFICIENTE';
    end if;

    perform fn_consumir_creditos(v_comp.id_comercio,v_serv.id_servicio,v_ver);

  exception
    when others then
      if sqlerrm='SALDO_INSUFICIENTE' and not p_forzar then
        update tbl_verificaciones
        set estado='BLOQUEADA',
            resultado=jsonb_build_object('motivo','SIN_CREDITOS'),
            fecha_fin=now()
        where id_verificacion=v_ver;

        return jsonb_build_object(
          'resultado','SIN_CREDITOS',
          'id_verificacion',v_ver,
          'mensaje','Recibimos tu comprobante. El comercio no puede completar la verificación en este momento.'
        );
      else
        update tbl_verificaciones
        set estado='ERROR',
            resultado=jsonb_build_object('error',sqlerrm),
            fecha_fin=now()
        where id_verificacion=v_ver;
        raise;
      end if;
  end;

  update tbl_comprobantes_pago
  set estado='PROCESANDO'
  where id_comprobante=p_id_comprobante;

  return jsonb_build_object('resultado','VERIFICACION_INICIADA','id_verificacion',v_ver);
end;
$$;

-- (v2/A5/HU-092-094) Transición de estado logístico validada.
-- Máquina de estados v2 (m33): saltos hacia adelante permitidos (OBS-003 decisión 2)
create or replace function fn_actualizar_estado_envio(
  p_id_envio uuid,
  p_nuevo_estado rsuelvo.estado_envio,
  p_observacion text DEFAULT NULL,
  p_latitud numeric DEFAULT NULL,
  p_longitud numeric DEFAULT NULL
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_env tbl_envios%rowtype;
  v_rank_actual integer;
  v_rank_nuevo integer;
begin
  select * into v_env from tbl_envios
  where id_envio=p_id_envio for update;

  if not found then
    raise exception 'Envío inexistente';
  end if;

  v_rank_actual := case v_env.estado
    when 'PENDIENTE' then 1 when 'PREPARANDO' then 2 when 'ASIGNADO' then 3
    when 'EN_RUTA' then 4 when 'ENTREGADO' then 5 else null end;
  v_rank_nuevo := case p_nuevo_estado
    when 'PENDIENTE' then 1 when 'PREPARANDO' then 2 when 'ASIGNADO' then 3
    when 'EN_RUTA' then 4 when 'ENTREGADO' then 5 else null end;

  if p_nuevo_estado = 'CANCELADO' then
    if v_env.estado in ('ENTREGADO','CANCELADO') then
      raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
    end if;
  elsif p_nuevo_estado = 'NO_ENTREGADO' then
    if v_env.estado not in ('ASIGNADO','EN_RUTA') then
      raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
    end if;
    if coalesce(p_observacion,'') = '' then
      raise exception 'NO_ENTREGADO requiere observación';
    end if;
  elsif p_nuevo_estado = 'EN_RUTA' and v_env.estado = 'NO_ENTREGADO' then
    null; -- reintento tras no-entrega (patrón previo preservado)
  elsif v_rank_actual is null or v_rank_nuevo is null
     or v_rank_nuevo <= v_rank_actual then
    raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
  end if;

  update tbl_envios
  set estado=p_nuevo_estado,
      updated_at=now(),
      id_repartidor=case
        when p_nuevo_estado='EN_RUTA' and v_env.id_repartidor is null
        then fn_current_usuario_id()
        else v_env.id_repartidor end
  where id_envio=p_id_envio;

  insert into tbl_env_seguimiento_estados(
    id_envio,estado,observacion,latitud,longitud,usuario_id
  )
  values(
    p_id_envio,p_nuevo_estado,p_observacion,p_latitud,p_longitud,
    fn_current_usuario_id()
  );

  return jsonb_build_object(
    'resultado','ESTADO_ACTUALIZADO',
    'id_envio',p_id_envio,
    'estado',p_nuevo_estado
  );
end;
$$;

-- (v2/HU-032/033/034) Movimientos manuales de inventario (entradas/salidas/ajustes).
create or replace function fn_movimiento_inventario(
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_tipo tipo_movimiento_inventario,
  p_cantidad integer,
  p_referencia_tipo text default 'MANUAL',
  p_referencia_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_inv tbl_inventario%rowtype;
  v_delta int;
begin
  if p_tipo not in ('ENTRADA','SALIDA','AJUSTE','DEVOLUCION') then
    raise exception 'Tipo manual inválido: use ENTRADA/SALIDA/AJUSTE/DEVOLUCION';
  end if;
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser positiva';
  end if;
  if not fn_tiene_acceso_sucursal(
    (select s.id_comercio from tbl_sucursales s where s.id_sucursal=p_id_sucursal),
    p_id_sucursal) then
    raise exception 'Sin acceso a la sucursal';
  end if;

  select * into v_inv from tbl_inventario
  where id_sucursal=p_id_sucursal and id_variante=p_id_variante
  for update;

  if not found then
    if p_tipo<>'ENTRADA' then
      raise exception 'No existe inventario para esa variante en la sucursal';
    end if;
    insert into tbl_inventario(id_sucursal,id_variante,stock_actual,stock_reservado)
    values(p_id_sucursal,p_id_variante,0,0)
    returning * into v_inv;
  end if;

  v_delta := case p_tipo when 'SALIDA' then -p_cantidad else p_cantidad end;

  update tbl_inventario
  set stock_actual=stock_actual+v_delta
  where id_inventario=v_inv.id_inventario;

  if (select stock_actual from tbl_inventario where id_inventario=v_inv.id_inventario)<0 then
    raise exception 'Stock insuficiente para SALIDA de %',p_cantidad;
  end if;

  insert into tbl_inventario_movimientos(
    id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
  )
  values(
    (select id_comercio from tbl_sucursales where id_sucursal=p_id_sucursal),
    p_id_sucursal,p_id_variante,p_tipo,p_cantidad,
    p_referencia_tipo,p_referencia_id,fn_current_usuario_id()
  );

  return jsonb_build_object('resultado','MOVIMIENTO_OK','delta',v_delta);
end;
$$;


-- Auditoría genérica
create or replace function fn_auditar_cambio()
returns trigger
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_id_comercio uuid;
  v_registro_id uuid;
begin
  begin
    v_registro_id := coalesce((to_jsonb(new)->>'id')::uuid,(to_jsonb(old)->>'id')::uuid);
  exception when others then
    v_registro_id := null;
  end;

  begin
    v_id_comercio := coalesce(
      (to_jsonb(new)->>'id_comercio')::uuid,
      (to_jsonb(old)->>'id_comercio')::uuid
    );
  exception when others then
    v_id_comercio := null;
  end;

  insert into tbl_logs_auditoria(
    id_comercio,id_usuario,accion,tabla,registro_id,
    datos_anteriores,datos_nuevos
  )
  values(
    v_id_comercio,fn_current_usuario_id(),tg_op,tg_table_name,
    v_registro_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );

  return coalesce(new,old);
end;
$$;


-- (v2/A12) Auditoría ACTIVA en tablas críticas (HU-127..131).
do $$
declare t text;
begin
  foreach t in array array[
    'tbl_usuario_comercio','tbl_comercio_config','tbl_variantes','tbl_inventario',
    'tbl_reservas','tbl_pedidos','tbl_comprobantes_pago','tbl_verificaciones',
    'tbl_movimientos_creditos','tbl_envios'
  ] loop
    execute format('drop trigger if exists trg_audit_%s on %I',t,t);
    execute format(
      'create trigger trg_audit_%s after insert or update or delete on %I for each row execute function fn_auditar_cambio()',t,t);
  end loop;
end $$;


-- Procesar reservas vencidas (cron / WF-30)
create or replace function fn_procesar_reservas_vencidas(p_limite integer default 100)
returns integer
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_count integer := 0;
  r record;
begin
  for r in
    select id_reserva
    from tbl_reservas
    where estado='ACTIVA'
      and fecha_expiracion <= now()
    order by fecha_expiracion
    limit p_limite
    for update skip locked
  loop
    begin
      perform fn_expirar_reserva(r.id_reserva);
      v_count := v_count+1;
    exception when others then
      raise warning 'No se pudo expirar reserva %: %',r.id_reserva,sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;

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
alter table tbl_plantillas_whatsapp enable row level security;
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
-- H-07 (Auditoría 2026-08-29, Regla de Oro 9): INSERT directo solo superadmin.
-- La auditoría normal entra via trigger fn_auditar_cambio (SECURITY DEFINER) o roles BYPASSRLS (n8n).
create policy audit_insert on tbl_logs_auditoria for insert with check (fn_es_superadmin());

-- CANALES WHATSAPP
create policy canal_select on tbl_canal_whatsapp for select using (fn_tiene_acceso_comercio(id_comercio));
create policy canal_manage on tbl_canal_whatsapp for all using (fn_es_admin_comercio(id_comercio)) with check (fn_es_admin_comercio(id_comercio));

-- OPT-OUT
create policy contact_pref_all on tbl_contact_preferences for all using (fn_tiene_acceso_comercio(id_comercio)) with check (fn_tiene_acceso_comercio(id_comercio));

-- PLANTILLAS META: catálogo leíble por la app; gestión solo admin (WF-80/HU-124)
create policy plantillas_select on tbl_plantillas_whatsapp for select using (true);
create policy plantillas_manage on tbl_plantillas_whatsapp for all using (fn_es_superadmin()) with check (fn_es_superadmin());


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

-- ============================================================
-- RSUELVO v2 :: 10. SEED — DATOS INICIALES
-- ============================================================

set search_path = rsuelvo, public;

insert into tbl_roles (codigo,nombre,nivel) values
('ROLE_SUPERADMIN','Superadministrador',100),
('ROLE_SYSADMIN','Administrador de infraestructura',90),
('ROLE_SUPPORT','Soporte',50),
('ROLE_TENANT_ADMIN','Administrador del comercio',30),
('ROLE_TENANT_CASHIER','Cajero',20),
('ROLE_LOGISTICS_AGENT','Repartidor',10)
on conflict (codigo) do nothing;


insert into tbl_servicios_creditos(codigo,nombre,descripcion,costo_creditos)
values
('VERIFICACION_COMPROBANTE','Verificación de comprobante','Verificación completa de un comprobante de pago',1),
('VERIFICACION_MANUAL','Verificación manual (cajero)','Verificación de comprobante por el cajero en la app (D13). No consume al iniciar; consumo por venta (D14).',0),
('OCR_COMPROBANTE','OCR de comprobante','Extracción de información del comprobante',1),
('VALIDACION_AVANZADA','Validación avanzada','Validaciones adicionales del comprobante',3)
on conflict (codigo) do nothing;


-- Paquetes de créditos activos (wireframe 15 / HU-072/073)
insert into tbl_paquetes_creditos(nombre,creditos,precio,moneda) values
  ('Basico',100,100,'BOB'),
  ('Pro',500,450,'BOB'),
  ('Empresa',1000,800,'BOB')
on conflict (nombre) do nothing;

-- codigo_tienda se asigna al crear el comercio (HU-002/HU-104):
-- update rsuelvo.tbl_comercios set codigo_tienda='FER' where nombre_comercial='Feria La Paz';


-- Plantillas Meta (guía §37; nombres reales se aprueban en Meta y se registran aquí)
insert into tbl_plantillas_whatsapp(template_code,template_name,language,parametros) values
  ('RESERVA_EXPIRADA','rsuelvo_reserva_expirada','es','["producto","sku"]'),
  ('TURNO_DISPONIBLE','rsuelvo_turno_disponible','es','["producto","sku","minutos"]'),
  ('PAGO_CONFIRMADO','rsuelvo_pago_confirmado','es','["pedido","total"]'),
  ('PEDIDO_CONFIRMADO','rsuelvo_pedido_confirmado','es','["pedido"]'),
  ('ENVIO_CREADO','rsuelvo_envio_creado','es','["pedido","guia"]'),
  ('ENVIO_EN_RUTA','rsuelvo_envio_en_ruta','es','["pedido"]'),
  ('ENVIO_ENTREGADO','rsuelvo_envio_entregado','es','["pedido"]'),
  ('ENVIO_NO_ENTREGADO','rsuelvo_envio_no_entregado','es','["pedido","motivo"]')
on conflict (template_code) do nothing;

-- ============================================================
-- RSUELVO v2 :: 11. STORAGE — BUCKETS Y PATHS
-- ============================================================

set search_path = rsuelvo, public;

insert into storage.buckets(id,name,public)
values ('comprobantes-pago','comprobantes-pago',false),
       ('qr-pagos','qr-pagos',false)
on conflict (id) do nothing;

-- Paths:
--   comprobantes-pago/{id_comercio}/{id_pedido}/{uuid}.{ext}
--   qr-pagos/{id_comercio}/tienda.{ext}
-- Plantilla de política por tenancy (adaptar por bucket):
--
-- create policy "comprobantes_tenant_read" on storage.objects
-- for select to authenticated
-- using (bucket_id='comprobantes-pago'
--   and (storage.foldername(name))[1] in (
--     select uc.id_comercio::text
--     from rsuelvo.tbl_usuario_comercio uc
--     join rsuelvo.tbl_usuarios u on u.id_usuario=uc.id_usuario
--     where u.auth_user_id=auth.uid() and uc.activo));

-- ============================================================
-- RSUELVO v2 :: 12. CRON — EXPIRACIÓN DE RESERVAS
-- ============================================================

set search_path = rsuelvo, public;

select cron.schedule(
  'rsuelvo_expirar_reservas',
  '* * * * *',
  $$select rsuelvo.fn_procesar_reservas_vencidas(200);$$
);

-- Alternativa n8n: WF-30 (Schedule) -> RPC fn_procesar_reservas_vencidas()
--                  WF-31 -> fn_notificar_siguiente_lista_espera() por variante liberada.
-- Nunca implementar expiración/liberación dentro de n8n.

comment on function fn_solicitar_reserva is
'Reserva atómica de inventario (v2/18, opción B). Una reserva activa POR CLIENTE por sucursal+variante; clientes distintos pueden reservar en paralelo mientras haya stock. Retorna RESERVA_CREADA, SIN_STOCK, o RESERVA_YA_EXISTENTE (solo si el MISMO cliente ya tiene reserva activa) — sin duplicar filas ni mutar inventario. Bloquea inventario con FOR UPDATE; debe llamarse vía RPC desde n8n/Backend.';

comment on function fn_expirar_reserva is
'Libera stock de una reserva vencida de forma transaccional.';

comment on function fn_notificar_siguiente_lista_espera is
'Selecciona la siguiente posición de la lista con bloqueo SKIP LOCKED y crea la oportunidad de notificación.';

comment on function fn_consumir_creditos is
'Consume créditos de forma atómica usando bloqueo de la cuenta y registra el ledger.';

comment on function fn_confirmar_pago is
'Confirma pago, actualiza pedido/reserva e inventario en una única transacción.';


comment on function fn_identificar_comercio_por_whatsapp is 'Resuelve comercio/sucursal desde el número WhatsApp destino (WF-04). Solo service_role.';
comment on function fn_iniciar_verificacion is 'Crea la verificación y consume créditos en una sola transacción (SIN_CREDITOS -> BLOQUEADA).';
comment on function fn_actualizar_estado_envio is 'Máquina de estados logística validada + registro de seguimiento.';
comment on function fn_generar_cobro is 'Crea el cobro QR con referencia única RS-XXXXXXXX.';
comment on table tbl_variantes is 'SKU v2: 6 caracteres [3 tienda][3 producto] base36. id_comercio denormalizado por trigger.';
comment on table tbl_canal_whatsapp is '1 WhatsApp = 1 tienda. Soporta OpenWA y Meta (política §17).';
comment on table tbl_contact_preferences is 'Opt-out del comprador (política §16 / HU-142).';

-- (D14/migración 27) Consume 1 crédito por venta confirmada — SD-1: saldo puede quedar
-- negativo (la venta NUNCA se bloquea); atribuye usuario_id del cajero vía JWT (D13).
create or replace function fn_consumir_credito_venta(
  p_id_comercio uuid,
  p_id_pedido uuid
)
returns bigint
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_cuenta tbl_cuentas_creditos%rowtype;
  v_anterior bigint;
  v_nuevo bigint;
begin
  select * into v_cuenta
  from tbl_cuentas_creditos
  where id_comercio=p_id_comercio
  for update;

  if not found then
    insert into tbl_cuentas_creditos(id_comercio,saldo_actual)
    values(p_id_comercio,0)
    returning * into v_cuenta;
  end if;

  v_anterior := v_cuenta.saldo_actual;
  v_nuevo := v_anterior - 1;

  update tbl_cuentas_creditos
  set saldo_actual=v_nuevo
  where id_cuenta_creditos=v_cuenta.id_cuenta_creditos;

  insert into tbl_movimientos_creditos(
    id_comercio,id_cuenta_creditos,tipo,cantidad,
    saldo_anterior,saldo_posterior,concepto,referencia_tipo,referencia_id,usuario_id
  )
  values(
    p_id_comercio,v_cuenta.id_cuenta_creditos,
    'CONSUMO_VENTA',-1,
    v_anterior,v_nuevo,
    'Consumo de crédito por venta confirmada (D14)',
    'PEDIDO',p_id_pedido,
    fn_current_usuario_id()
  );

  return 1;
end;
$$;

commit;
-- Migración 30 (2026-09-02) [monolito]: F5 — logística de entrega event-driven (D13/D14)
--   1. fn_registrar_entrega(p_id_pedido, p_datos jsonb): valida PAGADO, actualiza el
--      nombre del cliente, crea el envío vía fn_crear_envio (pedido -> PREPARANDO).
--      Datos: nombre/direccion/referencia/telefono (json, del formato WhatsApp
--      NOMBRE:/DIRECCIÓN:/REFERENCIA:/TELÉFONO:).
--   2. Triggers event-driven (patrón pg_net probado en lista de espera):
--      * tbl_pedidos estado -> PAGADO → webhook 'webhook/entrega/request'
--        → n8n pide los datos de entrega al comprador
--      * tbl_envios estado (transición) → webhook 'webhook/entrega/estado'
--        → n8n notifica al comprador (PREPARANDO/ASIGNADO/EN_RUTA/ENTREGADO/NO_ENTREGADO)
--   El token lo verifican los workflows n8n contra $vars.ENTREGA_TOKEN
--   (RSU_entrega_notif_7Qk2mXwP). Requiere pg_net (migración 26).

-- ========== 1. Registrar entrega (wrapper para n8n) ==========
CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_entrega(p_id_pedido uuid, p_datos jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_pedido tbl_pedidos%rowtype;
  v_nombre text;
  v_direccion text;
  v_referencia text;
  v_telefono text;
  v_id_envio uuid;
BEGIN
  SELECT * INTO v_pedido
  FROM tbl_pedidos
  WHERE id_pedido=p_id_pedido
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido inexistente';
  END IF;

  IF v_pedido.estado <> 'PAGADO' THEN
    RAISE EXCEPTION 'El pedido % no está PAGADO (estado: %)', p_id_pedido, v_pedido.estado;
  END IF;

  IF EXISTS (SELECT 1 FROM tbl_envios WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'El pedido ya tiene envío registrado';
  END IF;

  v_nombre     := NULLIF(trim(COALESCE(p_datos->>'nombre','')), '');
  v_direccion  := NULLIF(trim(COALESCE(p_datos->>'direccion','')), '');
  v_referencia := NULLIF(trim(COALESCE(p_datos->>'referencia','')), '');
  v_telefono   := NULLIF(trim(COALESCE(p_datos->>'telefono','')), '');

  IF v_direccion IS NULL OR v_telefono IS NULL THEN
    RAISE EXCEPTION 'Faltan datos de entrega obligatorios (direccion, telefono)';
  END IF;

  IF v_nombre IS NOT NULL THEN
    UPDATE tbl_clientes SET nombre=v_nombre WHERE id_cliente=v_pedido.id_cliente;
  END IF;

  v_id_envio := fn_crear_envio(p_id_pedido, v_direccion, v_referencia, v_telefono);

  RETURN jsonb_build_object(
    'resultado','ENTREGA_REGISTRADA',
    'id_envio',v_id_envio,
    'id_pedido',p_id_pedido,
    'estado_envio','PENDIENTE'
  );
END;
$function$;

-- ========== 2. Trigger: pedido PAGADO → pedir datos de entrega ==========
CREATE OR REPLACE FUNCTION rsuelvo.fn_notifica_pedido_pagado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_phone text;
BEGIN
  IF NEW.estado = 'PAGADO' AND OLD.estado IS DISTINCT FROM 'PAGADO' THEN
    SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
    FROM tbl_clientes
    WHERE id_cliente = NEW.id_cliente;

    PERFORM net.http_post(
      url    => 'https://rsuelvotest.app.n8n.cloud/webhook/entrega/request',
      body   => jsonb_build_object(
        'token', 'RSU_entrega_notif_7Qk2mXwP',
        'id_pedido', NEW.id_pedido,
        'id_comercio', NEW.id_comercio,
        'id_cliente', NEW.id_cliente,
        'phone', v_phone
      ),
      headers => jsonb_build_object('Content-Type', 'application/json')
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_pedido_pagado_notifica
AFTER UPDATE OF estado ON rsuelvo.tbl_pedidos
FOR EACH ROW
WHEN (NEW.estado = 'PAGADO' AND OLD.estado IS DISTINCT FROM 'PAGADO')
EXECUTE FUNCTION rsuelvo.fn_notifica_pedido_pagado();

-- ========== 3. Trigger: cambio de estado del envío → notificar al comprador ==========
CREATE OR REPLACE FUNCTION rsuelvo.fn_notifica_envio_estado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_phone text;
  v_msg text;
BEGIN
  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
    FROM tbl_clientes
    WHERE id_cliente = (SELECT id_cliente FROM tbl_pedidos WHERE id_pedido = NEW.id_pedido);

    v_msg := CASE NEW.estado
      WHEN 'PREPARANDO'   THEN '📦 Tu pedido está en preparación.'
      WHEN 'ASIGNADO'     THEN '🛵 Tu pedido fue asignado al repartidor.'
      WHEN 'EN_RUTA'      THEN '🚚 ¡Tu pedido está EN CAMINO!'
      WHEN 'ENTREGADO'    THEN '✅ Tu pedido fue ENTREGADO. ¡Gracias por tu compra!'
      WHEN 'NO_ENTREGADO' THEN '❌ No pudimos entregar tu pedido. Reintentaremos — contáctanos si necesitas coordinar.'
      ELSE NULL
    END CASE;

    IF v_msg IS NOT NULL AND v_phone IS NOT NULL THEN
      PERFORM net.http_post(
        url    => 'https://rsuelvotest.app.n8n.cloud/webhook/entrega/estado',
        body   => jsonb_build_object(
          'token', 'RSU_entrega_notif_7Qk2mXwP',
          'id_envio', NEW.id_envio,
          'id_pedido', NEW.id_pedido,
          'id_comercio', NEW.id_comercio,
          'estado', NEW.estado,
          'phone', v_phone,
          'numero_guia', NEW.numero_guia
        ),
        headers => jsonb_build_object('Content-Type', 'application/json')
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_envio_estado_notifica
AFTER UPDATE OF estado ON rsuelvo.tbl_envios
FOR EACH ROW
WHEN (NEW.estado IS DISTINCT FROM OLD.estado)
EXECUTE FUNCTION rsuelvo.fn_notifica_envio_estado();

-- ============================================================
-- MIGRACIÓN 26/32 (2026-08-31 / 2026-09-07): CRON EVENT-DRIVEN + TURNO ÚNICO
-- (m26 instaló pg_net y fn_cron_expirar_y_notificar; m32 añade guardas H-16/17/18)
-- ============================================================

CREATE OR REPLACE FUNCTION rsuelvo.fn_cron_expirar_y_notificar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_expiradas integer;
  v_turnos_vencidos integer;
  v_notificables boolean;
  v_http bigint;
BEGIN
  -- 0) Vence turnos NOTIFICADO expirados (H-18)
  WITH vencidos AS (
    UPDATE tbl_lista_espera
    SET estado='VENCIDO'
    WHERE estado='NOTIFICADO'
      AND fecha_expiracion <= now()
    RETURNING 1
  )
  SELECT count(*) INTO v_turnos_vencidos FROM vencidos;

  -- 1) Expira reservas vencidas (libera stock, registra movimientos)
  v_expiradas := rsuelvo.fn_procesar_reservas_vencidas(200);

  -- 2) ¿Hay grupos con stock disponible y SIN turno en vuelo? (H-16)
  SELECT EXISTS (
    SELECT 1
    FROM tbl_lista_espera le
    JOIN tbl_inventario i
      ON i.id_sucursal = le.id_sucursal
     AND i.id_variante = le.id_variante
    WHERE le.estado = 'ESPERANDO'
      AND (i.stock_actual - i.stock_reservado) >= 1
      AND NOT EXISTS (
        SELECT 1
        FROM tbl_lista_espera act
        WHERE act.id_sucursal = le.id_sucursal
          AND act.id_variante = le.id_variante
          AND act.estado = 'NOTIFICADO'
          AND act.fecha_expiracion > now()
      )
  ) INTO v_notificables;

  -- 3) Si hay trabajo, despierta a WF-13 (event-driven, no polling)
  IF v_notificables THEN
    SELECT net.http_post(
      url    => 'https://rsuelvotest.app.n8n.cloud/webhook/webhooks/lista-espera/notify',
      body   => jsonb_build_object(
        'token', 'RSU_lst_notify_9f3Kz71XqW',
        'motivo', 'waitlist_stock_disponible',
        'fecha', to_char(now() AT TIME ZONE 'America/La_Paz', 'YYYY-MM-DD HH24:MI:SS')
      ),
      headers => jsonb_build_object('Content-Type', 'application/json')
    ) INTO v_http;
  END IF;

  RETURN jsonb_build_object(
    'expiradas', v_expiradas,
    'turnos_vencidos', v_turnos_vencidos,
    'notificables', v_notificables,
    'http_request_id', v_http
  );
END;
$function$;

SELECT cron.alter_job(1, command => 'select rsuelvo.fn_cron_expirar_y_notificar();');

-- Catálogo de puntos de entrega para selección guiada (m33 / OBS-003)
create or replace function fn_listar_puntos_entrega(p_id_sucursal uuid)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_opciones jsonb := '[]'::jsonb;
  r RECORD;
  v_n integer := 0;
begin
  for r in
    select p.*, t.nombre as transportadora
    from tbl_puntos_entrega p
    left join tbl_transportadoras t on t.id_transportadora = p.id_transportadora
    where p.id_sucursal = p_id_sucursal and p.activo
    order by p.orden, p.nombre
  loop
    v_n := v_n + 1;
    v_opciones := v_opciones || jsonb_build_object(
      'opcion', v_n,
      'id_punto_entrega', r.id_punto_entrega,
      'tipo', r.tipo,
      'nombre', r.nombre,
      'ciudad', r.ciudad,
      'direccion', r.direccion,
      'referencia', r.referencia,
      'transportadora', r.transportadora
    );
  end loop;
  return jsonb_build_object('puntos', v_opciones);
end;
$$;

-- Registro de entrega v2 (m33 / OBS-003): selección guiada por punto; elimina dirección libre
create or replace function fn_registrar_entrega(p_id_pedido uuid, p_datos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
DECLARE
  v_pedido tbl_pedidos%rowtype;
  v_punto tbl_puntos_entrega%rowtype;
  v_nombre text;
  v_telefono text;
  v_id_envio uuid;
BEGIN
  SELECT * INTO v_pedido
  FROM tbl_pedidos
  WHERE id_pedido=p_id_pedido
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido inexistente';
  END IF;

  IF v_pedido.estado <> 'PAGADO' THEN
    RAISE EXCEPTION 'El pedido % no está PAGADO (estado: %)', p_id_pedido, v_pedido.estado;
  END IF;

  IF EXISTS (SELECT 1 FROM tbl_envios WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'El pedido ya tiene envío registrado';
  END IF;

  v_telefono := NULLIF(trim(COALESCE(p_datos->>'telefono','')), '');
  IF v_telefono IS NULL THEN
    RAISE EXCEPTION 'Faltan datos de entrega obligatorios (telefono)';
  END IF;

  SELECT * INTO v_punto
  FROM tbl_puntos_entrega
  WHERE id_punto_entrega = (p_datos->>'id_punto_entrega')::uuid
    AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Punto de entrega inexistente o inactivo';
  END IF;
  IF v_punto.id_sucursal <> v_pedido.id_sucursal THEN
    RAISE EXCEPTION 'El punto no pertenece a la sucursal del pedido';
  END IF;

  -- El nombre actualiza el perfil del cliente (tbl_clientes.nombre)
  v_nombre := NULLIF(trim(COALESCE(p_datos->>'nombre','')), '');
  IF v_nombre IS NOT NULL THEN
    UPDATE tbl_clientes SET nombre=v_nombre WHERE id_cliente=v_pedido.id_cliente;
  END IF;

  -- Denormalización para la hoja de ruta del repartidor
  v_id_envio := fn_crear_envio(
    p_id_pedido,
    v_punto.nombre || ' - ' || v_punto.ciudad || '. ' || v_punto.direccion,
    v_punto.referencia,
    v_telefono
  );
  UPDATE tbl_envios SET id_punto_entrega=v_punto.id_punto_entrega WHERE id_envio=v_id_envio;

  RETURN jsonb_build_object(
    'resultado','ENTREGA_REGISTRADA',
    'id_envio',v_id_envio,
    'id_pedido',p_id_pedido,
    'id_punto_entrega',v_punto.id_punto_entrega,
    'tipo_punto',v_punto.tipo,
    'estado_envio','PENDIENTE'
  );
END;
$$;

-- Helper del estado conversacional de entrega (m33b / OBS-003):
-- el pedido PAGADO sin envío ES la pregunta pendiente — la BD decide, n8n orquesta (Regla 3)
create or replace function fn_pedido_entrega_pendiente(p_telefono text)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
DECLARE
  v_pedido RECORD;
BEGIN
  SELECT p.id_pedido, p.numero_pedido, p.id_sucursal
  INTO v_pedido
  FROM tbl_pedidos p
  JOIN tbl_clientes c ON c.id_cliente = p.id_cliente
  WHERE COALESCE(c.telefono_whatsapp, c.telefono) = p_telefono
    AND p.estado = 'PAGADO'
    AND NOT EXISTS (SELECT 1 FROM tbl_envios e WHERE e.id_pedido = p.id_pedido)
  ORDER BY p.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('pendiente', false);
  END IF;

  RETURN jsonb_build_object(
    'pendiente', true,
    'id_pedido', v_pedido.id_pedido,
    'numero_pedido', v_pedido.numero_pedido,
    'id_sucursal', v_pedido.id_sucursal
  );
END;
$$;

comment on function fn_pedido_entrega_pendiente(text) is 'Resuelve si el comprador tiene un pedido PAGADO sin envío (pregunta de entrega pendiente — OBS-003). Retorna pendiente/id_pedido/numero_pedido/id_sucursal.';

-- ==== MIGRACIÓN 40 (2026-09-10): catálogo por sucursal ====
CREATE TABLE IF NOT EXISTS rsuelvo.tbl_variante_sucursal (
  id_variante uuid NOT NULL REFERENCES rsuelvo.tbl_variantes(id_variante) ON DELETE CASCADE,
  id_sucursal uuid NOT NULL REFERENCES rsuelvo.tbl_sucursales(id_sucursal) ON DELETE CASCADE,
  nombre text,
  precio numeric(14,2),
  activo boolean,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tbl_variante_sucursal_pkey PRIMARY KEY (id_variante, id_sucursal),
  CONSTRAINT chk_vs_precio CHECK (precio IS NULL OR precio > 0)
);
CREATE INDEX IF NOT EXISTS idx_variante_sucursal_suc ON rsuelvo.tbl_variante_sucursal(id_sucursal);
ALTER TABLE rsuelvo.tbl_variante_sucursal ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_tbl_variante_sucursal_updated_at BEFORE UPDATE ON rsuelvo.tbl_variante_sucursal
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_tbl_variante_sucursal AFTER INSERT OR DELETE OR UPDATE ON rsuelvo.tbl_variante_sucursal
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();
GRANT ALL ON rsuelvo.tbl_variante_sucursal TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON rsuelvo.tbl_variante_sucursal TO authenticated;

-- == HELPERS Y FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_es_admin_o_cajero_comercio(p_id_comercio uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select fn_es_service_role() or fn_es_superadmin() or exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid() and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_TENANT_CASHIER')
  );
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_puede_gestionar_catalogo(p_id_comercio uuid, p_id_sucursal uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select fn_es_service_role() or fn_es_superadmin() or exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid() and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and (r.codigo='ROLE_TENANT_ADMIN' or (r.codigo='ROLE_TENANT_CASHIER' and uc.id_sucursal=p_id_sucursal))
  );
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_variante_efectiva(p_id_variante uuid, p_id_sucursal uuid)
RETURNS TABLE(nombre text, precio numeric, activo boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select coalesce(vs.nombre, v.nombre), coalesce(vs.precio, v.precio), coalesce(vs.activo, v.activo)
  from tbl_variantes v
  left join tbl_variante_sucursal vs on vs.id_variante=v.id_variante and vs.id_sucursal=p_id_sucursal
  where v.id_variante=p_id_variante;
$function$;

-- fn_resolver_variante_por_sku v2 (con sucursal; se elimina la firma vieja de 2 args)
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_variante_por_sku(p_id_comercio uuid, p_sku text, p_id_sucursal uuid DEFAULT NULL)
RETURNS TABLE(id_variante uuid, nombre text, precio numeric, id_producto uuid)
LANGUAGE plpgsql STABLE SET search_path TO 'rsuelvo', 'pg_catalog'
AS $function$
begin
  if p_sku is null or p_sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido. Formato requerido: exactamente 6 caracteres [A-Z0-9]' using errcode = '22023';
  end if;
  return query
  select v.id_variante, e.nombre, e.precio, v.id_producto
  from tbl_variantes v
  cross join lateral fn_variante_efectiva(v.id_variante, p_id_sucursal) e
  where v.id_comercio=p_id_comercio and v.sku=p_sku and e.activo;
end;
$function$;
DROP FUNCTION IF EXISTS rsuelvo.fn_resolver_variante_por_sku(uuid, text);

-- Listado por sucursal (efectivo + override flag + stock)
CREATE OR REPLACE FUNCTION rsuelvo.fn_listar_variantes_sucursal(p_id_sucursal uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_comercio uuid;
  v_out jsonb;
BEGIN
  SELECT s.id_comercio INTO v_comercio FROM tbl_sucursales s WHERE s.id_sucursal=p_id_sucursal;
  IF v_comercio IS NULL THEN RAISE EXCEPTION 'Sucursal inexistente'; END IF;
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'sku'),'[]'::jsonb) INTO v_out FROM (
    SELECT jsonb_build_object(
      'id_variante',v.id_variante,'sku',v.sku,'id_producto',v.id_producto,
      'nombre_global',v.nombre,'precio_global',v.precio,'activo_global',v.activo,
      'nombre',e.nombre,'precio',e.precio,'activo',e.activo,
      'tiene_override',(vs.id_variante IS NOT NULL),
      'stock_actual',coalesce(i.stock_actual,0),'stock_reservado',coalesce(i.stock_reservado,0)
    ) AS x
    FROM tbl_variantes v
    CROSS JOIN LATERAL fn_variante_efectiva(v.id_variante,p_id_sucursal) e
    LEFT JOIN tbl_variante_sucursal vs ON vs.id_variante=v.id_variante AND vs.id_sucursal=p_id_sucursal
    LEFT JOIN tbl_inventario i ON i.id_variante=v.id_variante AND i.id_sucursal=p_id_sucursal
    WHERE v.id_comercio=v_comercio
  ) t;
  RETURN jsonb_build_object('variantes',v_out);
END;
$function$;

-- == RLS Y POLICIES ==
DROP POLICY IF EXISTS variante_sucursal_select ON rsuelvo.tbl_variante_sucursal;
CREATE POLICY variante_sucursal_select ON rsuelvo.tbl_variante_sucursal FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s WHERE s.id_sucursal=tbl_variante_sucursal.id_sucursal AND rsuelvo.fn_tiene_acceso_comercio(s.id_comercio)));
DROP POLICY IF EXISTS variante_sucursal_manage ON rsuelvo.tbl_variante_sucursal;
CREATE POLICY variante_sucursal_manage ON rsuelvo.tbl_variante_sucursal FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s WHERE s.id_sucursal=tbl_variante_sucursal.id_sucursal AND rsuelvo.fn_puede_gestionar_catalogo(s.id_comercio, s.id_sucursal)))
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s WHERE s.id_sucursal=tbl_variante_sucursal.id_sucursal AND rsuelvo.fn_puede_gestionar_catalogo(s.id_comercio, s.id_sucursal)));
DROP POLICY IF EXISTS products_manage ON rsuelvo.tbl_productos;
CREATE POLICY products_manage ON rsuelvo.tbl_productos FOR ALL TO authenticated
  USING (rsuelvo.fn_es_admin_o_cajero_comercio(id_comercio))
  WITH CHECK (rsuelvo.fn_es_admin_o_cajero_comercio(id_comercio));

-- NOTA: los cuerpos completos actualizados de fn_crear_pedido_desde_reserva (usa
-- fn_variante_efectiva para congelar el precio de la sucursal) y
-- fn_notificar_siguiente_lista_espera (devuelve nombre/precio efectivos +
-- tiempo_aceptacion_minutos) están aplicados en cloud y espejados en
-- 06_functions.sql / _monolito_…_v2.sql.

-- m40: snapshot de venta con precio EFECTIVO de la sucursal
create or replace function fn_crear_pedido_desde_reserva(p_id_reserva uuid)
returns uuid language plpgsql security definer set search_path = rsuelvo, public
as $$
declare
  v_res tbl_reservas%rowtype; v_var tbl_variantes%rowtype; v_prod tbl_productos%rowtype;
  v_pedido uuid; v_subtotal numeric(14,2); v_ef_nombre text; v_ef_precio numeric(14,2);
begin
  select * into v_res from tbl_reservas where id_reserva=p_id_reserva for update;
  if not found then raise exception 'Reserva inexistente'; end if;
  if v_res.estado not in ('ACTIVA','PAGO_VALIDANDO') then raise exception 'La reserva no puede generar pedido'; end if;
  if v_res.id_pedido is not null then return v_res.id_pedido; end if;

  select v.* into v_var from tbl_variantes v where v.id_variante=v_res.id_variante;
  select p.* into v_prod from tbl_productos p where p.id_producto=v_var.id_producto;

  select e.nombre, e.precio into v_ef_nombre, v_ef_precio
  from fn_variante_efectiva(v_res.id_variante, v_res.id_sucursal) e;
  v_ef_nombre := coalesce(v_ef_nombre, v_var.nombre);
  v_ef_precio := coalesce(v_ef_precio, v_var.precio);
  v_subtotal := v_ef_precio * v_res.cantidad;

  insert into tbl_pedidos(id_comercio,id_sucursal,id_cliente,estado,subtotal,descuento,id_reserva)
  values(v_res.id_comercio,v_res.id_sucursal,v_res.id_cliente,'ESPERANDO_PAGO',v_subtotal,0,p_id_reserva)
  returning id_pedido into v_pedido;

  insert into tbl_pedido_detalles(id_pedido,id_variante,sku_snapshot,nombre_snapshot,precio_unitario,cantidad)
  values(v_pedido,v_var.id_variante,v_var.sku,v_prod.nombre || ' - ' || v_ef_nombre,v_ef_precio,v_res.cantidad);

  update tbl_reservas set id_pedido=v_pedido where id_reserva=p_id_reserva;
  return v_pedido;
end;
$$;


-- ==== 34_entrega_captura_destino.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 34 (2026-09-0x)
-- ENTREGA CON CAPTURA DE DESTINO (OBS-003) + datos de cliente/puntos
-- ============================================================
-- Reconstrucción fiel desde el estado cloud (fuente de verdad).
-- Cubre: captura de destino en 1 mensaje para ENVIO_TRANSPORTE
-- (tbl_entrega_captura + fn_iniciar/estado/procesar), apellidos del
-- cliente, ciudad/zona de destino en envíos, y horarios/guía de
-- puntos de entrega. fn_registrar_guia se crea aquí (versión con
-- numero_guia + destino); m36 amplía la firma con p_guia_foto_url
-- (ver cuerpo final vigente en 36_guia_foto.sql).
-- Refinamientos 37/38 (dígito = re-selección de punto, solo ciudad,
-- zona eliminada) incluidos en el cuerpo final de fn_procesar_captura_destino.

-- == TABLAS ==
CREATE TABLE IF NOT EXISTS rsuelvo.tbl_entrega_captura (
  id_pedido uuid NOT NULL PRIMARY KEY REFERENCES rsuelvo.tbl_pedidos(id_pedido),
  id_comercio uuid NOT NULL REFERENCES rsuelvo.tbl_comercios(id_comercio),
  id_punto_entrega uuid NOT NULL REFERENCES rsuelvo.tbl_puntos_entrega(id_punto_entrega),
  destino_ciudad text,
  destino_zona text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_entrega_captura_comercio ON rsuelvo.tbl_entrega_captura(id_comercio);
ALTER TABLE rsuelvo.tbl_entrega_captura ENABLE ROW LEVEL SECURITY;
GRANT ALL ON rsuelvo.tbl_entrega_captura TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON rsuelvo.tbl_entrega_captura TO authenticated;

-- == TRIGGERS ==
CREATE TRIGGER trg_entrega_captura_updated_at BEFORE UPDATE ON rsuelvo.tbl_entrega_captura
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_entrega_captura AFTER INSERT OR UPDATE OR DELETE ON rsuelvo.tbl_entrega_captura
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();

-- == RLS ==
DROP POLICY IF EXISTS entrega_captura_all ON rsuelvo.tbl_entrega_captura;
CREATE POLICY entrega_captura_all ON rsuelvo.tbl_entrega_captura FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_pedidos p JOIN rsuelvo.tbl_sucursales s ON s.id_sucursal=p.id_sucursal
                 WHERE p.id_pedido=tbl_entrega_captura.id_pedido AND rsuelvo.fn_tiene_acceso_sucursal(s.id_comercio, s.id_sucursal)))
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_pedidos p JOIN rsuelvo.tbl_sucursales s ON s.id_sucursal=p.id_sucursal
                 WHERE p.id_pedido=tbl_entrega_captura.id_pedido AND rsuelvo.fn_tiene_acceso_sucursal(s.id_comercio, s.id_sucursal)));

-- == COLUMNAS_M34 ==
ALTER TABLE rsuelvo.tbl_clientes ADD COLUMN IF NOT EXISTS apellido_paterno text;
ALTER TABLE rsuelvo.tbl_clientes ADD COLUMN IF NOT EXISTS apellido_materno text;
ALTER TABLE rsuelvo.tbl_envios ADD COLUMN IF NOT EXISTS destino_ciudad text;
ALTER TABLE rsuelvo.tbl_envios ADD COLUMN IF NOT EXISTS destino_zona text;
ALTER TABLE rsuelvo.tbl_envios ADD COLUMN IF NOT EXISTS numero_guia text;
-- NOTA: tbl_puntos_entrega.ciudad (NOT NULL) y tipo (NOT NULL) se agregaron con
-- backfill en la migración original; aquí queda el estado final:
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS ciudad text;
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS tipo text;
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS id_transportadora uuid REFERENCES rsuelvo.tbl_transportadoras(id_transportadora);
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS dias_atencion text;
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS horario_inicio time;
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS horario_fin time;
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS referencia text;
ALTER TABLE rsuelvo.tbl_puntos_entrega ADD COLUMN IF NOT EXISTS orden integer NOT NULL DEFAULT 0;

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_iniciar_captura_destino(p_id_pedido uuid, p_id_punto_entrega uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_pedido tbl_pedidos%rowtype;
  v_punto tbl_puntos_entrega%rowtype;
  v_transportadora text;
BEGIN
  SELECT * INTO v_pedido FROM tbl_pedidos WHERE id_pedido=p_id_pedido FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido inexistente'; END IF;
  IF v_pedido.estado <> 'PAGADO' THEN
    RAISE EXCEPTION 'El pedido % no está PAGADO (estado: %)', p_id_pedido, v_pedido.estado;
  END IF;
  IF EXISTS (SELECT 1 FROM tbl_envios WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'El pedido ya tiene envío registrado';
  END IF;
  IF EXISTS (SELECT 1 FROM tbl_entrega_captura WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'Ya existe una captura de destino en curso para este pedido';
  END IF;
  SELECT * INTO v_punto FROM tbl_puntos_entrega WHERE id_punto_entrega=p_id_punto_entrega AND activo;
  IF NOT FOUND THEN RAISE EXCEPTION 'Punto de entrega inexistente o inactivo'; END IF;
  IF v_punto.tipo <> 'ENVIO_TRANSPORTE' THEN
    RAISE EXCEPTION 'La captura de destino aplica solo a ENVIO_TRANSPORTE';
  END IF;
  IF v_punto.id_sucursal <> v_pedido.id_sucursal THEN
    RAISE EXCEPTION 'El punto no pertenece a la sucursal del pedido';
  END IF;
  SELECT t.nombre INTO v_transportadora FROM tbl_transportadoras t WHERE t.id_transportadora=v_punto.id_transportadora;
  INSERT INTO tbl_entrega_captura (id_pedido, id_comercio, id_punto_entrega)
  VALUES (p_id_pedido, v_pedido.id_comercio, p_id_punto_entrega);
  RETURN jsonb_build_object(
    'resultado','CAPTURA_INICIADA',
    'id_pedido',p_id_pedido,
    'id_punto_entrega',p_id_punto_entrega,
    'transportadora',v_transportadora
  );
END;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_entrega_captura_estado(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_row RECORD;
BEGIN
  SELECT c.id_pedido, c.destino_ciudad, c.destino_zona, pe.nombre AS punto, t.nombre AS transportadora
  INTO v_row
  FROM tbl_entrega_captura c
  JOIN tbl_pedidos p ON p.id_pedido = c.id_pedido
  JOIN tbl_clientes cl ON cl.id_cliente = p.id_cliente
  JOIN tbl_puntos_entrega pe ON pe.id_punto_entrega = c.id_punto_entrega
  LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
  WHERE COALESCE(cl.telefono_whatsapp, cl.telefono) = p_telefono
    AND p.estado = 'PAGADO'
    AND NOT EXISTS (SELECT 1 FROM tbl_envios e WHERE e.id_pedido = c.id_pedido)
    AND c.id_pedido = (SELECT p2.id_pedido FROM tbl_pedidos p2
                       WHERE p2.id_cliente = p.id_cliente
                         AND p2.estado = 'PAGADO'
                         AND NOT EXISTS (SELECT 1 FROM tbl_envios e2 WHERE e2.id_pedido = p2.id_pedido)
                       ORDER BY p2.created_at DESC LIMIT 1)
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('captura', false);
  END IF;
  RETURN jsonb_build_object(
    'captura', true,
    'paso', 'DESTINO',
    'id_pedido', v_row.id_pedido,
    'punto', v_row.punto,
    'transportadora', v_row.transportadora
  );
END;
$function$;

-- Cuerpo final vigente (incluye refinamientos 37/38: dígito = re-selección,
-- texto = solo ciudad, zona eliminada del flujo).
CREATE OR REPLACE FUNCTION rsuelvo.fn_procesar_captura_destino(p_telefono text, p_texto text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_punto RECORD;
  v_texto text;
  v_result jsonb;
BEGIN
  v_texto := NULLIF(trim(COALESCE(p_texto,'')), '');
  IF v_texto IS NULL THEN
    RAISE EXCEPTION 'Texto vacío';
  END IF;
  SELECT c.id_pedido, c.id_comercio, c.id_punto_entrega, c.destino_ciudad, c.destino_zona
  INTO v_row
  FROM tbl_entrega_captura c
  JOIN tbl_pedidos p ON p.id_pedido = c.id_pedido
  JOIN tbl_clientes cl ON cl.id_cliente = p.id_cliente
  WHERE COALESCE(cl.telefono_whatsapp, cl.telefono) = p_telefono
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('resultado','SIN_CAPTURA');
  END IF;
  -- Si responde un NÚMERO: es re-selección del punto de la lista (no una ciudad)
  IF v_texto ~ '^[0-9]+$' THEN
    SELECT pe.id_punto_entrega, pe.nombre, pe.tipo, pe.ciudad, pe.dias_atencion,
           pe.referencia, pe.horario_inicio, pe.horario_fin, t.nombre AS transportadora
    INTO v_punto
    FROM (
      SELECT pe2.*, row_number() OVER (ORDER BY pe2.orden, pe2.nombre) AS opcion
      FROM tbl_puntos_entrega pe2
      WHERE pe2.id_sucursal = (SELECT p3.id_sucursal FROM tbl_pedidos p3 WHERE p3.id_pedido = v_row.id_pedido)
        AND pe2.activo
    ) pe
    LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
    WHERE pe.opcion = v_texto::integer;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('resultado','OPCION_INVALIDA');
    END IF;
    IF v_punto.tipo = 'ENVIO_TRANSPORTE' THEN
      UPDATE tbl_entrega_captura
      SET id_punto_entrega = v_punto.id_punto_entrega,
          destino_ciudad = NULL,
          destino_zona = NULL
      WHERE id_pedido = v_row.id_pedido;
      RETURN jsonb_build_object(
        'resultado','CAPTURA_REINICIADA',
        'transportadora', v_punto.transportadora
      );
    END IF;
    -- Re-selección a punto no-transporte: registra la entrega directo
    v_result := fn_registrar_entrega(
      v_row.id_pedido,
      jsonb_build_object(
        'id_punto_entrega', v_punto.id_punto_entrega,
        'telefono', p_telefono
      )
    );
    DELETE FROM tbl_entrega_captura WHERE id_pedido = v_row.id_pedido;
    RETURN v_result;
  END IF;
  -- Texto normal = la ciudad
  v_texto := left(v_texto, 120);
  UPDATE tbl_entrega_captura
  SET destino_ciudad = v_texto, destino_zona = NULL
  WHERE id_pedido = v_row.id_pedido;
  v_result := fn_registrar_entrega(
    v_row.id_pedido,
    jsonb_build_object(
      'id_punto_entrega', v_row.id_punto_entrega,
      'telefono', p_telefono,
      'destino_ciudad', v_texto
    )
  );
  DELETE FROM tbl_entrega_captura WHERE id_pedido = v_row.id_pedido;
  RETURN v_result;
END;
$function$;


-- ==== 35_lista_pendiente_momento1.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 35 (2026-09-0x)
-- MOMENTO 1 — confirmación SI/NO antes de entrar a lista de espera
-- ============================================================
-- Reconstrucción fiel desde el estado cloud (fuente de verdad).
-- Cuando no hay stock, el comprador recibe "¿te anoto en la lista?"
-- (Momento 1) en vez de entrar directo. tbl_lista_pendiente guarda
-- UN pendiente por cliente (PK id_cliente, upsert). Al responder SI:
-- fn_aceptar_pendiente_lista devuelve PENDIENTE_OK o YA_EN_LISTA
-- (guarda anti-duplicado si ya está ESPERANDO/NOTIFICADO).

-- == TABLAS ==
CREATE TABLE IF NOT EXISTS rsuelvo.tbl_lista_pendiente (
  id_cliente uuid NOT NULL PRIMARY KEY REFERENCES rsuelvo.tbl_clientes(id_cliente) ON DELETE CASCADE,
  id_comercio uuid NOT NULL REFERENCES rsuelvo.tbl_comercios(id_comercio),
  id_sucursal uuid NOT NULL REFERENCES rsuelvo.tbl_sucursales(id_sucursal),
  id_variante uuid NOT NULL REFERENCES rsuelvo.tbl_variantes(id_variante),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE rsuelvo.tbl_lista_pendiente ENABLE ROW LEVEL SECURITY;
GRANT ALL ON rsuelvo.tbl_lista_pendiente TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON rsuelvo.tbl_lista_pendiente TO authenticated;

-- == TRIGGERS ==
CREATE TRIGGER trg_lista_pendiente_updated_at BEFORE UPDATE ON rsuelvo.tbl_lista_pendiente
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_lista_pendiente AFTER INSERT OR UPDATE OR DELETE ON rsuelvo.tbl_lista_pendiente
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();

-- == RLS ==
DROP POLICY IF EXISTS lista_pendiente_all ON rsuelvo.tbl_lista_pendiente;
CREATE POLICY lista_pendiente_all ON rsuelvo.tbl_lista_pendiente FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s
                 WHERE s.id_sucursal=tbl_lista_pendiente.id_sucursal AND rsuelvo.fn_tiene_acceso_sucursal(s.id_comercio, s.id_sucursal)))
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s
                 WHERE s.id_sucursal=tbl_lista_pendiente.id_sucursal AND rsuelvo.fn_tiene_acceso_sucursal(s.id_comercio, s.id_sucursal)));

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_pendiente_lista(p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
BEGIN
  INSERT INTO tbl_lista_pendiente (id_cliente, id_comercio, id_sucursal, id_variante)
  VALUES (p_id_cliente, p_id_comercio, p_id_sucursal, p_id_variante)
  ON CONFLICT (id_cliente) DO UPDATE
    SET id_comercio = EXCLUDED.id_comercio,
        id_sucursal = EXCLUDED.id_sucursal,
        id_variante = EXCLUDED.id_variante;
  RETURN jsonb_build_object('resultado','PENDIENTE_LISTA');
END;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_aceptar_pendiente_lista(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_pend RECORD;
  v_sku text;
  v_nombre text;
  v_precio numeric;
  v_pos_existente integer;
BEGIN
  SELECT * INTO v_pend
  FROM tbl_lista_pendiente
  WHERE id_cliente = (SELECT id_cliente FROM tbl_clientes WHERE COALESCE(telefono_whatsapp, telefono) = p_telefono LIMIT 1)
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('resultado','SIN_PENDIENTE');
  END IF;
  -- Guarda: si ya está en la lista para esta variante, no duplicar
  SELECT posicion INTO v_pos_existente
  FROM tbl_lista_espera
  WHERE id_cliente = v_pend.id_cliente
    AND id_variante = v_pend.id_variante
    AND estado IN ('ESPERANDO','NOTIFICADO')
  LIMIT 1;
  DELETE FROM tbl_lista_pendiente WHERE id_cliente = v_pend.id_cliente;
  SELECT sku, nombre, precio INTO v_sku, v_nombre, v_precio
  FROM tbl_variantes WHERE id_variante = v_pend.id_variante;
  IF v_pos_existente IS NOT NULL THEN
    RETURN jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'posicion', v_pos_existente,
      'id_comercio', v_pend.id_comercio,
      'sku', v_sku,
      'nombre', v_nombre,
      'precio', v_precio
    );
  END IF;
  RETURN jsonb_build_object(
    'resultado','PENDIENTE_OK',
    'id_comercio', v_pend.id_comercio,
    'id_sucursal', v_pend.id_sucursal,
    'id_variante', v_pend.id_variante,
    'id_cliente', v_pend.id_cliente,
    'sku', v_sku,
    'nombre', v_nombre,
    'precio', v_precio
  );
END;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_rechazar_pendiente_lista(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  DELETE FROM tbl_lista_pendiente
  WHERE id_cliente = (SELECT id_cliente FROM tbl_clientes WHERE COALESCE(telefono_whatsapp, telefono) = p_telefono LIMIT 1);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RETURN jsonb_build_object('resultado','SIN_PENDIENTE');
  END IF;
  RETURN jsonb_build_object('resultado','LISTA_RECHAZADA');
END;
$function$;


-- ==== 36_guia_foto.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 36 (2026-09-0x)
-- FOTO DE GUÍA / CÓDIGO (OBS-004)
-- ============================================================
-- Reconstrucción fiel desde el estado cloud (fuente de verdad).
-- La app del repartidor/admin sube la foto de la guía al bucket
-- privado guias-envios y registra la URL pública/firmada con
-- fn_registrar_guia (firma final: numero y/o foto, al menos uno).
-- La fn notifica por webhook a WF-25-C (motivo guia_registrada).

-- == TABLAS ==
ALTER TABLE rsuelvo.tbl_envios ADD COLUMN IF NOT EXISTS guia_foto_url text;

-- == STORAGE ==
INSERT INTO storage.buckets (id, name, public) VALUES ('guias-envios','guias-envios', false)
ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS guias_envios_insert ON storage.objects;
CREATE POLICY guias_envios_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'guias-envios');
DROP POLICY IF EXISTS guias_envios_select ON storage.objects;
CREATE POLICY guias_envios_select ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'guias-envios');
DROP POLICY IF EXISTS guias_envios_update ON storage.objects;
CREATE POLICY guias_envios_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'guias-envios') WITH CHECK (bucket_id = 'guias-envios');

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_guia(p_id_envio uuid, p_numero_guia text DEFAULT NULL, p_guia_foto_url text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_env tbl_envios%rowtype;
  v_tipo text;
  v_transportadora text;
  v_phone text;
  v_nuevo_num text;
  v_nueva_foto text;
BEGIN
  SELECT * INTO v_env FROM tbl_envios WHERE id_envio=p_id_envio FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Envío inexistente'; END IF;
  SELECT pe.tipo, t.nombre INTO v_tipo, v_transportadora
  FROM tbl_puntos_entrega pe
  LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
  WHERE pe.id_punto_entrega = v_env.id_punto_entrega;
  IF v_tipo IS NULL OR v_tipo NOT IN ('ENVIO_TRANSPORTE','PUNTO_LOCAL') THEN
    RAISE EXCEPTION 'La guía/código aplica solo a ENVIO_TRANSPORTE o PUNTO_LOCAL';
  END IF;
  IF v_env.estado NOT IN ('PREPARANDO','ASIGNADO','EN_RUTA') THEN
    RAISE EXCEPTION 'El envío debe estar PREPARANDO, ASIGNADO o EN_RUTA (estado: %)', v_env.estado;
  END IF;
  v_nuevo_num  := NULLIF(trim(COALESCE(p_numero_guia,'')), '');
  v_nueva_foto := NULLIF(trim(COALESCE(p_guia_foto_url,'')), '');
  IF v_nuevo_num IS NULL AND v_nueva_foto IS NULL THEN
    RAISE EXCEPTION 'Debe proporcionar numero_guia y/o guia_foto_url';
  END IF;
  UPDATE tbl_envios
  SET numero_guia   = COALESCE(v_nuevo_num, numero_guia),
      guia_foto_url = COALESCE(v_nueva_foto, guia_foto_url)
  WHERE id_envio = p_id_envio
  RETURNING numero_guia, guia_foto_url INTO v_nuevo_num, v_nueva_foto;
  SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
  FROM tbl_clientes
  WHERE id_cliente = (SELECT id_cliente FROM tbl_pedidos WHERE id_pedido = v_env.id_pedido);
  PERFORM net.http_post(
    url    => 'https://rsuelvotest.app.n8n.cloud/webhook/entrega/estado',
    body   => jsonb_build_object(
      'token', 'RSU_entrega_notif_7Qk2mXwP',
      'motivo', 'guia_registrada',
      'id_envio', v_env.id_envio,
      'id_pedido', v_env.id_pedido,
      'id_comercio', v_env.id_comercio,
      'phone', v_phone,
      'numero_guia', v_nuevo_num,
      'guia_foto_url', v_nueva_foto,
      'transportadora', v_transportadora,
      'destino_ciudad', v_env.destino_ciudad,
      'destino_zona', v_env.destino_zona
    ),
    headers => jsonb_build_object('Content-Type', 'application/json')
  );
  RETURN jsonb_build_object(
    'resultado','GUIA_REGISTRADA',
    'id_envio', p_id_envio,
    'numero_guia', v_nuevo_num,
    'guia_foto_url', v_nueva_foto,
    'tipo_punto', v_tipo
  );
END;
$function$;


-- -- m31 fn_rechazar_lista_espera (espejo)
CREATE OR REPLACE FUNCTION rsuelvo.fn_rechazar_lista_espera(p_id_lista_espera uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_item tbl_lista_espera%rowtype;
  v_nuevo_estado estado_lista_espera;
BEGIN
  SELECT * INTO v_item FROM tbl_lista_espera WHERE id_lista_espera = p_id_lista_espera FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrada de lista inexistente'; END IF;
  IF v_item.estado = 'NOTIFICADO' THEN
    v_nuevo_estado := 'RECHAZADO';
  ELSIF v_item.estado = 'ESPERANDO' THEN
    v_nuevo_estado := 'CANCELADO';
  ELSE
    RAISE EXCEPTION 'Solo se pueden rechazar entradas NOTIFICADO o cancelar ESPERANDO (estado actual: %)', v_item.estado;
  END IF;
  UPDATE tbl_lista_espera SET estado = v_nuevo_estado, updated_at = now() WHERE id_lista_espera = p_id_lista_espera;
  RETURN jsonb_build_object(
    'resultado', 'OPORTUNIDAD_RECHAZADA',
    'estado_anterior', v_item.estado,
    'estado_nuevo', v_nuevo_estado,
    'id_lista_espera', p_id_lista_espera,
    'id_sucursal', v_item.id_sucursal,
    'id_variante', v_item.id_variante
  );
END;
$function$;


-- -- m40 fn_notificar_siguiente_lista_espera (cuerpo exacto cloud)
CREATE OR REPLACE FUNCTION rsuelvo.fn_notificar_siguiente_lista_espera(p_id_sucursal uuid, p_id_variante uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_item tbl_lista_espera%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_ef_nombre text;
  v_ef_precio numeric(14,2);
begin
  select * into v_item
  from tbl_lista_espera cand
  where cand.id_sucursal=p_id_sucursal
    and cand.id_variante=p_id_variante
    and cand.estado='ESPERANDO'
    and not exists (
      select 1 from tbl_lista_espera act
      where act.id_cliente = cand.id_cliente
        and act.estado='NOTIFICADO'
        and act.fecha_expiracion > now()
    )
  order by cand.posicion
  limit 1
  for update skip locked;
  if not found then
    return jsonb_build_object('resultado','LISTA_VACIA');
  end if;
  select * into v_cfg from tbl_comercio_config where id_comercio=v_item.id_comercio;
  update tbl_lista_espera
  set estado='NOTIFICADO',
      fecha_notificacion=now(),
      fecha_expiracion=now()+make_interval(mins=>v_cfg.tiempo_aceptacion_lista_espera_minutos)
  where id_lista_espera=v_item.id_lista_espera;
  -- m40: valores efectivos de la sucursal del grupo (para el mensaje de oportunidad)
  select e.nombre, e.precio into v_ef_nombre, v_ef_precio
  from fn_variante_efectiva(v_item.id_variante, v_item.id_sucursal) e;
  return jsonb_build_object(
    'resultado','CLIENTE_NOTIFICADO',
    'id_lista_espera',v_item.id_lista_espera,
    'id_cliente',v_item.id_cliente,
    'fecha_expiracion',(select fecha_expiracion from tbl_lista_espera where id_lista_espera=v_item.id_lista_espera),
    'nombre', v_ef_nombre,
    'precio', v_ef_precio,
    'tiempo_aceptacion_minutos', v_cfg.tiempo_aceptacion_lista_espera_minutos
  );
end;
$function$;


-- ==== 41_lista_espera_agregar_v2.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 41 (2026-09-11)
-- LISTA DE ESPERA: alta atómica con resultado estructurado (base de F5)
-- ============================================================
-- fn_agregar_lista_espera_v2: misma atomicidad que v1 (lock FOR UPDATE sobre
-- la fila de inventario por sucursal×variante) pero devuelve jsonb en vez de
-- excepciones: AGREGADO {id_lista_espera, posicion} · YA_EN_LISTA {id,posicion}
-- · LISTA_LLENA {activos, maximo}. Incluye red de seguridad unique_violation
-- (carrera residual → YA_EN_LISTA en vez de excepción).
-- v1 se conserva intacta hasta que F5 migre WF-12 a v2 (luego se elimina).
-- Regla de Oro 3: cupo y unicidad se deciden en la BD; n8n solo muestra.
-- Validado en transacción: AGREGADO pos 1 → YA_EN_LISTA (mismo id/pos) →
-- LISTA_LLENA (activos 1, maximo 1); rollback.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_agregar_lista_espera_v2(
  p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_max integer;
  v_activos integer;
  v_pos integer;
  v_id uuid;
  v_existente record;
begin
  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;
  select max_lista_espera_por_producto into v_max
  from tbl_comercio_config
  where id_comercio=p_id_comercio;
  if v_max is null then
    raise exception 'Configuración de comercio inexistente';
  end if;
  perform 1
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;
  select id_lista_espera, posicion into v_existente
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
  limit 1;
  if found then
    return jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera', v_existente.id_lista_espera,
      'posicion', v_existente.posicion
    );
  end if;
  select count(*) into v_activos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');
  if v_activos >= v_max then
    return jsonb_build_object(
      'resultado','LISTA_LLENA',
      'activos', v_activos,
      'maximo', v_max
    );
  end if;
  select coalesce(max(posicion),0)+1 into v_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO');
  insert into tbl_lista_espera(
    id_comercio,id_sucursal,id_variante,id_cliente,posicion,estado
  )
  values(
    p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,v_pos,'ESPERANDO'
  )
  returning id_lista_espera into v_id;
  return jsonb_build_object(
    'resultado','AGREGADO',
    'id_lista_espera', v_id,
    'posicion', v_pos
  );
exception
  when unique_violation then
    select id_lista_espera, posicion into v_existente
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
      and id_variante=p_id_variante
      and id_cliente=p_id_cliente
      and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
    limit 1;
    return jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera', v_existente.id_lista_espera,
      'posicion', v_existente.posicion
    );
end;
$function$;


-- ==== 42_solicitar_reserva_ya_en_lista.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 42 (2026-09-11)
-- SIN_STOCK avisa si ya está en lista (base del atajo UX en WF-10)
-- ============================================================
-- Decisión del dueño: quien ya está en lista y reenvía el SKU recibe directo
-- "Ya estás en la lista #N" sin la pregunta SI/NO de Momento 1.
-- Se agregan a AMBOS retornos SIN_STOCK: ya_en_lista (boolean),
-- posicion (integer|null), id_lista_espera (uuid|null). Lookup por
-- (sucursal, variante, cliente) con estado en (ESPERANDO, NOTIFICADO, ACEPTADO).
-- Sin regresiones: RESERVA_CREADA/YA_EXISTENTE intactos; el NO de Momento 1 solo
-- borraba el pendiente, así que saltar la pregunta no quita vías de salida.
-- Validado: buyer2/FERC01 → ya_en_lista true pos 1; buyer1/FERC01 → false/nulls.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_solicitar_reserva(p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid, p_cantidad integer DEFAULT 1)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_inv tbl_inventario%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_reserva uuid;
  v_pedido uuid;
  v_precio numeric(14,2);
  v_reserva_existente uuid;
  v_fecha_expiracion timestamptz;
  v_lista_id uuid;
  v_lista_pos integer;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0';
  end if;
  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;
  select * into v_cfg from tbl_comercio_config where id_comercio=p_id_comercio;
  if not found then
    raise exception 'El comercio no tiene configuración';
  end if;
  select v.precio into v_precio
  from tbl_variantes v
  join tbl_productos p on p.id_producto=v.id_producto
  where v.id_variante=p_id_variante
    and p.id_comercio=p_id_comercio
    and v.activo
    and p.activo;
  if v_precio is null then
    raise exception 'SKU/variante inválida para el comercio';
  end if;
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  for update;
  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;
  select * into v_inv
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;
  if not found then
    -- m42: avisar si ya está en lista (misma sucursal×variante, vigente)
    select id_lista_espera, posicion into v_lista_id, v_lista_pos
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
      and id_variante=p_id_variante
      and id_cliente=p_id_cliente
      and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
    limit 1;
    return jsonb_build_object(
      'resultado','SIN_STOCK',
      'motivo','NO_EXISTE_INVENTARIO',
      'ya_en_lista', found,
      'posicion', v_lista_pos,
      'id_lista_espera', v_lista_id
    );
  end if;
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  limit 1;
  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;
  if (v_inv.stock_actual-v_inv.stock_reservado) >= p_cantidad then
    update tbl_inventario
    set stock_reservado=stock_reservado+p_cantidad
    where id_inventario=v_inv.id_inventario;
    insert into tbl_reservas(
      id_comercio,id_sucursal,id_variante,id_cliente,
      origen,estado,cantidad,fecha_inicio,fecha_expiracion
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,
      'DIRECTA','ACTIVA',p_cantidad,now(),
      now() + make_interval(mins=>v_cfg.tiempo_reserva_minutos)
    )
    returning id_reserva into v_reserva;
    insert into tbl_inventario_movimientos(
      id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,'RESERVA',
      p_cantidad,'RESERVA',v_reserva,fn_current_usuario_id()
    );
    return jsonb_build_object(
      'resultado','RESERVA_CREADA',
      'id_reserva',v_reserva,
      'fecha_expiracion',(
        select fecha_expiracion from tbl_reservas where id_reserva=v_reserva
      )
    );
  end if;
  -- m42: avisar si ya está en lista (misma sucursal×variante, vigente)
  select id_lista_espera, posicion into v_lista_id, v_lista_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
  limit 1;
  return jsonb_build_object(
    'resultado','SIN_STOCK',
    'motivo','PRODUCTO_RESERVADO_O_AGOTADO',
    'ya_en_lista', found,
    'posicion', v_lista_pos,
    'id_lista_espera', v_lista_id
  );
end;
$function$;


-- ==== 43_solicitar_reserva_lista_llena.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 43 (2026-09-11)
-- SIN_STOCK avisa si la lista está LLENA (OBS-006, base del atajo en WF-10)
-- ============================================================
-- OBS del dueño: con lista llena, el comprador nuevo recibe directo
-- "Lo sentimos, el producto que busca no tiene stock y la lista de espera está llena"
-- sin la pregunta SI/NO de Momento 1.
-- Se agrega a AMBOS retornos SIN_STOCK (solo cuando NO está en lista):
-- lista_llena (boolean), activos (integer|null), maximo (integer|null).
-- Conteo con el mismo conjunto vigente de m41/m42 (ESPERANDO/NOTIFICADO/ACEPTADO);
-- el máximo se reusa de v_cfg (ya cargado); COALESCE contra config nula → nunca llena
-- (degrada a la pregunta; v2 impone el límite real al aceptar).
-- Validado con cupo temporal 1: buyer1/FERC01 → lista_llena true (1/1);
-- buyer2/FERC01 → ya_en_lista true (conteo omitido). Cupo restaurado a 5.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_solicitar_reserva(p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid, p_cantidad integer DEFAULT 1)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_inv tbl_inventario%rowtype;
  v_cfg tbl_comercio_config%rowtype;
  v_reserva uuid;
  v_pedido uuid;
  v_precio numeric(14,2);
  v_reserva_existente uuid;
  v_fecha_expiracion timestamptz;
  v_lista_id uuid;
  v_lista_pos integer;
  v_ya boolean;
  v_llena boolean;
  v_activos integer;
begin
  if p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0';
  end if;
  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;
  select * into v_cfg from tbl_comercio_config where id_comercio=p_id_comercio;
  if not found then
    raise exception 'El comercio no tiene configuración';
  end if;
  select v.precio into v_precio
  from tbl_variantes v
  join tbl_productos p on p.id_producto=v.id_producto
  where v.id_variante=p_id_variante
    and p.id_comercio=p_id_comercio
    and v.activo
    and p.activo;
  if v_precio is null then
    raise exception 'SKU/variante inválida para el comercio';
  end if;
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  for update;
  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;
  select * into v_inv
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;
  if not found then
    -- m42: avisar si ya está en lista (misma sucursal×variante, vigente)
    select id_lista_espera, posicion into v_lista_id, v_lista_pos
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
      and id_variante=p_id_variante
      and id_cliente=p_id_cliente
      and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
    limit 1;
    v_ya := found;
    v_llena := false;
    v_activos := null;
    if not v_ya then
      select count(*) into v_activos
      from tbl_lista_espera
      where id_sucursal=p_id_sucursal
        and id_variante=p_id_variante
        and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');
      v_llena := v_activos >= coalesce(v_cfg.max_lista_espera_por_producto, 2147483647);
    end if;
    return jsonb_build_object(
      'resultado','SIN_STOCK',
      'motivo','NO_EXISTE_INVENTARIO',
      'ya_en_lista', v_ya,
      'posicion', v_lista_pos,
      'id_lista_espera', v_lista_id,
      'lista_llena', v_llena,
      'activos', v_activos,
      'maximo', v_cfg.max_lista_espera_por_producto
    );
  end if;
  select id_reserva, fecha_expiracion
    into v_reserva_existente, v_fecha_expiracion
  from tbl_reservas
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  limit 1;
  if found then
    return jsonb_build_object(
      'resultado','RESERVA_YA_EXISTENTE',
      'id_reserva',v_reserva_existente,
      'fecha_expiracion',v_fecha_expiracion
    );
  end if;
  if (v_inv.stock_actual-v_inv.stock_reservado) >= p_cantidad then
    update tbl_inventario
    set stock_reservado=stock_reservado+p_cantidad
    where id_inventario=v_inv.id_inventario;
    insert into tbl_reservas(
      id_comercio,id_sucursal,id_variante,id_cliente,
      origen,estado,cantidad,fecha_inicio,fecha_expiracion
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,
      'DIRECTA','ACTIVA',p_cantidad,now(),
      now() + make_interval(mins=>v_cfg.tiempo_reserva_minutos)
    )
    returning id_reserva into v_reserva;
    insert into tbl_inventario_movimientos(
      id_comercio,id_sucursal,id_variante,tipo,cantidad,referencia_tipo,referencia_id,usuario_id
    )
    values(
      p_id_comercio,p_id_sucursal,p_id_variante,'RESERVA',
      p_cantidad,'RESERVA',v_reserva,fn_current_usuario_id()
    );
    return jsonb_build_object(
      'resultado','RESERVA_CREADA',
      'id_reserva',v_reserva,
      'fecha_expiracion',(
        select fecha_expiracion from tbl_reservas where id_reserva=v_reserva
      )
    );
  end if;
  -- m42: avisar si ya está en lista (misma sucursal×variante, vigente)
  select id_lista_espera, posicion into v_lista_id, v_lista_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
  limit 1;
  v_ya := found;
  v_llena := false;
  v_activos := null;
  if not v_ya then
    select count(*) into v_activos
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');
    v_llena := v_activos >= coalesce(v_cfg.max_lista_espera_por_producto, 2147483647);
  end if;
  return jsonb_build_object(
    'resultado','SIN_STOCK',
    'motivo','PRODUCTO_RESERVADO_O_AGOTADO',
    'ya_en_lista', v_ya,
    'posicion', v_lista_pos,
    'id_lista_espera', v_lista_id,
    'lista_llena', v_llena,
    'activos', v_activos,
    'maximo', v_cfg.max_lista_espera_por_producto
  );
end;
$function$;


-- ==== 44_comprobante_congela_reserva.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 44 (2026-09-11)
-- El comprobante congela el reloj de la reserva (PAGO_VALIDANDO)
-- ============================================================
-- Decisión del dueño: los 10 minutos corren hasta que llega el comprobante;
-- desde entonces la reserva queda PAGO_VALIDANDO (inmune a
-- fn_procesar_reservas_vencidas, que solo expira ACTIVA) hasta que el cajero
-- confirme/rechace. fn_confirmar_pago ya aceptaba ACTIVA/PAGO_VALIDANDO.
-- Si la reserva venció ANTES de llegar el comprobante, NO revive (stock ya
-- liberado; el comprador reserva de nuevo). Aplica también al reenvío
-- (misma operación, mismo pedido; guardado por WHERE estado='ACTIVA').
-- Nota técnica: UPDATEs calificados con alias (r.) porque RETURNS TABLE expone
-- id_comprobante/id_pedido como OUT params y el nombre desnudo es ambiguo.
-- Validado E2E sintético: reserva ACTIVA → comprobante → PAGO_VALIDANDO.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_comprobante(p_id_comercio uuid, p_id_cliente uuid, p_tipo_archivo text, p_archivo_url text, p_monto_detectado numeric DEFAULT NULL, p_fecha_detectada timestamp with time zone DEFAULT NULL, p_numero_operacion text DEFAULT NULL, p_nombre_pagador text DEFAULT NULL, p_estado rsuelvo.estado_comprobante DEFAULT 'RECIBIDO', p_id_pedido uuid DEFAULT NULL)
 RETURNS TABLE(id_comprobante uuid, id_pedido uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_id_comprobante uuid := gen_random_uuid();
  v_id_pedido uuid := p_id_pedido;
  v_existente uuid;
  v_pedido_existente uuid;
BEGIN
  IF NOT fn_tiene_acceso_comercio(p_id_comercio) THEN
    RAISE EXCEPTION 'Sin acceso al comercio';
  END IF;
  IF v_id_pedido IS NULL THEN
    SELECT p.id_pedido INTO v_id_pedido
    FROM tbl_pedidos p
    JOIN tbl_reservas r ON r.id_pedido = p.id_pedido AND r.estado = 'ACTIVA'
    WHERE p.id_comercio = p_id_comercio
      AND p.id_cliente = p_id_cliente
      AND p.estado = 'ESPERANDO_PAGO'
    ORDER BY p.created_at DESC
    LIMIT 1;
    IF v_id_pedido IS NULL THEN
      SELECT p.id_pedido INTO v_id_pedido
      FROM tbl_pedidos p
      WHERE p.id_comercio = p_id_comercio
        AND p.id_cliente = p_id_cliente
        AND p.estado = 'ESPERANDO_PAGO'
      ORDER BY p.created_at DESC
      LIMIT 1;
    END IF;
  END IF;
  IF v_id_pedido IS NULL THEN
    RAISE EXCEPTION 'No se encontro pedido en espera de pago para vincular el comprobante';
  END IF;
  IF p_numero_operacion IS NOT NULL THEN
    SELECT c.id_comprobante, c.id_pedido
      INTO v_existente, v_pedido_existente
      FROM tbl_comprobantes_pago c
      WHERE c.id_comercio = p_id_comercio
        AND c.numero_operacion = p_numero_operacion
      LIMIT 1;
    IF v_existente IS NOT NULL THEN
      IF v_pedido_existente = v_id_pedido THEN
        UPDATE tbl_comprobantes_pago AS c
           SET tipo_archivo     = p_tipo_archivo,
               archivo_url      = p_archivo_url,
               monto_detectado  = COALESCE(p_monto_detectado, c.monto_detectado),
               fecha_detectada  = COALESCE(p_fecha_detectada, c.fecha_detectada),
               nombre_pagador   = COALESCE(p_nombre_pagador, c.nombre_pagador),
               estado           = p_estado
         WHERE c.id_comprobante = v_existente;
        UPDATE tbl_reservas AS r
        SET estado='PAGO_VALIDANDO'
        WHERE r.id_pedido=v_id_pedido AND r.estado='ACTIVA';
        RETURN QUERY SELECT v_existente, v_id_pedido;
        RETURN;
      ELSE
        RAISE EXCEPTION 'COMPROBANTE_DUPLICADO: el numero de operacion % ya fue registrado para otro pedido', p_numero_operacion;
      END IF;
    END IF;
  END IF;
  INSERT INTO tbl_comprobantes_pago (
    id_comprobante, id_comercio, id_pedido, id_cliente,
    tipo_archivo, archivo_url, monto_detectado, fecha_detectada,
    numero_operacion, nombre_pagador, estado
  ) VALUES (
    v_id_comprobante, p_id_comercio, v_id_pedido, p_id_cliente,
    p_tipo_archivo, p_archivo_url, p_monto_detectado, p_fecha_detectada,
    p_numero_operacion, p_nombre_pagador, p_estado
  );
  UPDATE tbl_reservas AS r
  SET estado='PAGO_VALIDANDO'
  WHERE r.id_pedido=v_id_pedido AND r.estado='ACTIVA';
  RETURN QUERY SELECT v_id_comprobante, v_id_pedido;
END;
$function$;


-- ==== 45_dispositivos_push.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 45 (2026-09-11)
-- Dispositivos push FCM por usuario (base notificaciones de reserva)
-- ============================================================
-- Diseño de Codex (Fase 1, docs/push-inventario-fase-1.md), aplicado por
-- orquestador + triggers de proyecto (updated_at/auditoría).
-- El registro lo hará la app vía Edge Function con JWT (dueño desde auth.uid);
-- RLS solo-propios; sin service_role en Flutter. Emisor + FCM en Fase 2
-- (requiere proyecto Firebase, google-services.json y secreto service account).

-- == TABLAS ==
CREATE TABLE IF NOT EXISTS rsuelvo.tbl_dispositivos_push (
  id_dispositivo uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  id_usuario uuid NOT NULL REFERENCES rsuelvo.tbl_usuarios(id_usuario) ON DELETE CASCADE,
  token_fcm text NOT NULL UNIQUE,
  plataforma text NOT NULL CHECK (plataforma IN ('ANDROID','IOS')),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dispositivos_push_usuario_activo
  ON rsuelvo.tbl_dispositivos_push (id_usuario) WHERE activo;
ALTER TABLE rsuelvo.tbl_dispositivos_push ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON rsuelvo.tbl_dispositivos_push TO authenticated;
GRANT ALL ON rsuelvo.tbl_dispositivos_push TO service_role;

-- == TRIGGERS ==
CREATE TRIGGER trg_dispositivos_push_updated_at BEFORE UPDATE ON rsuelvo.tbl_dispositivos_push
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_dispositivos_push AFTER INSERT OR UPDATE OR DELETE ON rsuelvo.tbl_dispositivos_push
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();

-- == RLS ==
DROP POLICY IF EXISTS dispositivos_push_select_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_select_propios ON rsuelvo.tbl_dispositivos_push FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));
DROP POLICY IF EXISTS dispositivos_push_update_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_update_propios ON rsuelvo.tbl_dispositivos_push FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));
DROP POLICY IF EXISTS dispositivos_push_insert_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_insert_propios ON rsuelvo.tbl_dispositivos_push FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));
DROP POLICY IF EXISTS dispositivos_push_delete_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_delete_propios ON rsuelvo.tbl_dispositivos_push FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));


-- ==== 46_trigger_push_reserva.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 46 (2026-09-11)
-- Trigger: push al crearse una reserva ACTIVA (Fase 2 notificaciones)
-- ============================================================
-- Cada INSERT de reserva ACTIVA dispara pg_net (fire-and-forget) a la Edge
-- Function interna `notificar-reserva-sucursal`, que avisa por FCM a los
-- ADMIN/CAJERO con vínculo activo a (comercio, sucursal).
-- SECRETOS (nunca en archivos): el trigger lee `rsuelvo_push_webhook_secret`
-- desde supabase_vault (por nombre); la EF valida contra su secreto de entorno
-- PUSH_WEBHOOK_SECRET + FCM_SERVICE_ACCOUNT_JSON (ambos se pegan en el
-- dashboard: Edge Functions → Secrets). Sin n8n (D11 intacto).
-- El push JAMÁS bloquea una venta: cualquier fallo se traga en el EXCEPTION.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_notificar_reserva_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name='rsuelvo_push_webhook_secret'
  limit 1;
  if v_secret is null then
    return new;
  end if;
  perform net.http_post(
    url     => 'https://iwfaktlxebxtocmswdvv.supabase.co/functions/v1/notificar-reserva-sucursal',
    body    => jsonb_build_object('id_reserva', NEW.id_reserva),
    headers => jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret)
  );
  return new;
exception when others then
  return new;
end;
$function$;

-- == TRIGGERS ==
DROP TRIGGER IF EXISTS trg_reserva_push ON rsuelvo.tbl_reservas;
CREATE TRIGGER trg_reserva_push
AFTER INSERT ON rsuelvo.tbl_reservas
FOR EACH ROW
WHEN (NEW.estado = 'ACTIVA')
EXECUTE FUNCTION rsuelvo.fn_notificar_reserva_push();


-- ==== 47_push_eventos_v1.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 47 (2026-09-11)
-- Push v1: 6 eventos (despachador + triggers + cron por-vencer)
-- ============================================================
-- Decisión del dueño: notificar (1) reserva nueva, (2) comprobante recibido,
-- (3) reserva por vencer, (4) envío asignado, (5) stock bajo/agotado,
-- (6) pago confirmado y entrega completada. Teléfono del comprador SOLO para
-- ADMIN; sin horario silencioso.
-- Diseño: triggers AFTER no-mutantes (solo pg_net) + Edge Function
-- `notificar-reserva-sucursal` v2 despachadora por motivo. Secreto solo en
-- supabase_vault (nombre fijo) + secreto de entorno de la EF; nunca en archivos.
-- NO INTERFERENCIA n8n (verificado): ninguna fn_* existente modificada (solo la
-- trigger-fn propia de m46, que n8n no llama); triggers nuevos coexisten con
-- audit/tenant/updated_at y con trg_pedido_pagado_notifica/trg_envio_estado_notifica;
-- el cron es un job nuevo (el existente intacto); la EF es la misma slug.
-- Evento 3: banda 60-120s (≈1 tick normal). Reenvío de comprobante (UPDATE) no
-- dispara evento 2 en v1 (solo INSERT); seguimiento futuro.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_push_evento(p_motivo text, p_payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name='rsuelvo_push_webhook_secret'
  limit 1;
  if v_secret is null then
    return;
  end if;
  perform net.http_post(
    url     => 'https://iwfaktlxebxtocmswdvv.supabase.co/functions/v1/notificar-reserva-sucursal',
    body    => jsonb_build_object('motivo', p_motivo) || coalesce(p_payload, '{}'::jsonb),
    headers => jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret)
  );
exception when others then
  return;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_notificar_reserva_push()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('reserva_nueva', jsonb_build_object('id_reserva', NEW.id_reserva));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_comprobante()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('comprobante_recibido', jsonb_build_object('id_comprobante', NEW.id_comprobante));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_envio()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  if NEW.estado = 'ASIGNADO' then
    perform rsuelvo.fn_push_evento('envio_asignado', jsonb_build_object('id_envio', NEW.id_envio));
  elsif NEW.estado = 'ENTREGADO' then
    perform rsuelvo.fn_push_evento('entrega_completada', jsonb_build_object('id_envio', NEW.id_envio));
  end if;
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('pago_confirmado', jsonb_build_object('id_pedido', NEW.id_pedido));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_push_stock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
begin
  perform rsuelvo.fn_push_evento('stock_bajo', jsonb_build_object(
    'id_sucursal', NEW.id_sucursal,
    'id_variante', NEW.id_variante,
    'disponible', (NEW.stock_actual - NEW.stock_reservado)
  ));
  return new;
exception when others then
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_cron_notificar_por_vencer()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select id_reserva from tbl_reservas
    where estado='ACTIVA'
      and fecha_expiracion > now() + interval '60 seconds'
      and fecha_expiracion <= now() + interval '120 seconds'
    order by fecha_expiracion
    limit 50
    for update skip locked
  loop
    perform rsuelvo.fn_push_evento('reserva_por_vencer', jsonb_build_object('id_reserva', r.id_reserva));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

-- == TRIGGERS ==
DROP TRIGGER IF EXISTS trg_push_comprobante ON rsuelvo.tbl_comprobantes_pago;
CREATE TRIGGER trg_push_comprobante
AFTER INSERT ON rsuelvo.tbl_comprobantes_pago
FOR EACH ROW
EXECUTE FUNCTION rsuelvo.fn_push_comprobante();

DROP TRIGGER IF EXISTS trg_push_envio ON rsuelvo.tbl_envios;
CREATE TRIGGER trg_push_envio
AFTER UPDATE ON rsuelvo.tbl_envios
FOR EACH ROW
WHEN (NEW.estado IN ('ASIGNADO','ENTREGADO') AND OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION rsuelvo.fn_push_envio();

DROP TRIGGER IF EXISTS trg_push_pedido ON rsuelvo.tbl_pedidos;
CREATE TRIGGER trg_push_pedido
AFTER UPDATE ON rsuelvo.tbl_pedidos
FOR EACH ROW
WHEN (NEW.estado = 'PAGADO' AND OLD.estado IS DISTINCT FROM 'PAGADO')
EXECUTE FUNCTION rsuelvo.fn_push_pedido();

DROP TRIGGER IF EXISTS trg_push_stock ON rsuelvo.tbl_inventario;
CREATE TRIGGER trg_push_stock
AFTER UPDATE ON rsuelvo.tbl_inventario
FOR EACH ROW
WHEN ((NEW.stock_actual - NEW.stock_reservado) <= 5 AND (OLD.stock_actual - OLD.stock_reservado) > 5)
EXECUTE FUNCTION rsuelvo.fn_push_stock();

-- == CRON ==
-- select cron.schedule('rsuelvo_push_por_vencer', '* * * * *',
--   $$select rsuelvo.fn_cron_notificar_por_vencer();$$);
-- (job creado en cloud; espejo en 12_cron.sql)


-- ==== 48_guia_cierra_entrega.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 48 (2026-09-11)
-- La guía cierra la entrega (OBS-007)
-- ============================================================
-- Decisión del dueño (E2E logística: 3 avisos en 25s): al registrar número
-- y/o foto, en la misma transacción envío→ENTREGADO + pedido→ENTREGADO.
-- El comprador SÍ recibe el aviso de despacho con número/foto (su tracking);
-- ASIGNADO/EN_RUTA/ENTREGADO no le avisan (WF-25-C, prompt aparte).
-- Guarda de pago: el pedido solo se cierra si estaba PAGADO/PREPARANDO/
-- DESPACHADO — ESPERANDO_PAGO (o cualquier pre-pago) jamás se salta.
-- Validado sintético: envío PREPARANDO→ENTREGADO con guía TEST48;
-- pedido ESPERANDO_PAGO intacto. Limpieza total posterior.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_guia(p_id_envio uuid, p_numero_guia text DEFAULT NULL, p_guia_foto_url text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_env tbl_envios%rowtype;
  v_tipo text;
  v_transportadora text;
  v_phone text;
  v_nuevo_num text;
  v_nueva_foto text;
BEGIN
  SELECT * INTO v_env FROM tbl_envios WHERE id_envio=p_id_envio FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Envío inexistente'; END IF;
  SELECT pe.tipo, t.nombre INTO v_tipo, v_transportadora
  FROM tbl_puntos_entrega pe
  LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
  WHERE pe.id_punto_entrega = v_env.id_punto_entrega;
  IF v_tipo IS NULL OR v_tipo NOT IN ('ENVIO_TRANSPORTE','PUNTO_LOCAL') THEN
    RAISE EXCEPTION 'La guía/código aplica solo a ENVIO_TRANSPORTE o PUNTO_LOCAL';
  END IF;
  IF v_env.estado NOT IN ('PREPARANDO','ASIGNADO','EN_RUTA') THEN
    RAISE EXCEPTION 'El envío debe estar PREPARANDO, ASIGNADO o EN_RUTA (estado: %)', v_env.estado;
  END IF;
  v_nuevo_num  := NULLIF(trim(COALESCE(p_numero_guia,'')), '');
  v_nueva_foto := NULLIF(trim(COALESCE(p_guia_foto_url,'')), '');
  IF v_nuevo_num IS NULL AND v_nueva_foto IS NULL THEN
    RAISE EXCEPTION 'Debe proporcionar numero_guia y/o guia_foto_url';
  END IF;
  UPDATE tbl_envios
  SET numero_guia   = COALESCE(v_nuevo_num, numero_guia),
      guia_foto_url = COALESCE(v_nueva_foto, guia_foto_url)
  WHERE id_envio = p_id_envio
  RETURNING numero_guia, guia_foto_url INTO v_nuevo_num, v_nueva_foto;
  UPDATE tbl_envios
  SET estado='ENTREGADO'
  WHERE id_envio=p_id_envio AND estado <> 'ENTREGADO';
  UPDATE tbl_pedidos
  SET estado='ENTREGADO'
  WHERE id_pedido=v_env.id_pedido
    AND estado IN ('PAGADO','PREPARANDO','DESPACHADO');
  SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
  FROM tbl_clientes
  WHERE id_cliente = (SELECT id_cliente FROM tbl_pedidos WHERE id_pedido = v_env.id_pedido);
  PERFORM net.http_post(
    url    => 'https://rsuelvotest.app.n8n.cloud/webhook/entrega/estado',
    body   => jsonb_build_object(
      'token', 'RSU_entrega_notif_7Qk2mXwP',
      'motivo', 'guia_registrada',
      'id_envio', v_env.id_envio,
      'id_pedido', v_env.id_pedido,
      'id_comercio', v_env.id_comercio,
      'phone', v_phone,
      'numero_guia', v_nuevo_num,
      'guia_foto_url', v_nueva_foto,
      'transportadora', v_transportadora,
      'destino_ciudad', v_env.destino_ciudad,
      'destino_zona', v_env.destino_zona
    ),
    headers => jsonb_build_object('Content-Type', 'application/json')
  );
  RETURN jsonb_build_object(
    'resultado','GUIA_REGISTRADA',
    'id_envio', p_id_envio,
    'numero_guia', v_nuevo_num,
    'guia_foto_url', v_nueva_foto,
    'tipo_punto', v_tipo
  );
END;
$function$;


-- ==== 49_guia_webhook_sku.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 49 (2026-09-12)
-- Webhook de guía incluye SKU (OBS-009)
-- ============================================================
-- El comprador puede comprar en varios comercios: el aviso de despacho debe
-- identificar la compra. Se agrega `sku` (de pedido_detalles, primer ítem) al
-- body del webhook `guia_registrada`. Aditivo puro: ningún otro comportamiento
-- cambia (m48 intacto). WF-25-C lo usa en el caption (prompt aparte).
-- Validado live: ejecución #741 recibió `sku:FERC01`; #742 probó rama silenciosa.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_guia(p_id_envio uuid, p_numero_guia text DEFAULT NULL, p_guia_foto_url text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_env tbl_envios%rowtype;
  v_tipo text;
  v_transportadora text;
  v_phone text;
  v_nuevo_num text;
  v_nueva_foto text;
  v_sku text;
BEGIN
  SELECT * INTO v_env FROM tbl_envios WHERE id_envio=p_id_envio FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Envío inexistente'; END IF;
  SELECT pe.tipo, t.nombre INTO v_tipo, v_transportadora
  FROM tbl_puntos_entrega pe
  LEFT JOIN tbl_transportadoras t ON t.id_transportadora = pe.id_transportadora
  WHERE pe.id_punto_entrega = v_env.id_punto_entrega;
  IF v_tipo IS NULL OR v_tipo NOT IN ('ENVIO_TRANSPORTE','PUNTO_LOCAL') THEN
    RAISE EXCEPTION 'La guía/código aplica solo a ENVIO_TRANSPORTE o PUNTO_LOCAL';
  END IF;
  IF v_env.estado NOT IN ('PREPARANDO','ASIGNADO','EN_RUTA') THEN
    RAISE EXCEPTION 'El envío debe estar PREPARANDO, ASIGNADO o EN_RUTA (estado: %)', v_env.estado;
  END IF;
  v_nuevo_num  := NULLIF(trim(COALESCE(p_numero_guia,'')), '');
  v_nueva_foto := NULLIF(trim(COALESCE(p_guia_foto_url,'')), '');
  IF v_nuevo_num IS NULL AND v_nueva_foto IS NULL THEN
    RAISE EXCEPTION 'Debe proporcionar numero_guia y/o guia_foto_url';
  END IF;
  UPDATE tbl_envios
  SET numero_guia   = COALESCE(v_nuevo_num, numero_guia),
      guia_foto_url = COALESCE(v_nueva_foto, guia_foto_url)
  WHERE id_envio = p_id_envio
  RETURNING numero_guia, guia_foto_url INTO v_nuevo_num, v_nueva_foto;
  UPDATE tbl_envios
  SET estado='ENTREGADO'
  WHERE id_envio=p_id_envio AND estado <> 'ENTREGADO';
  UPDATE tbl_pedidos
  SET estado='ENTREGADO'
  WHERE id_pedido=v_env.id_pedido
    AND estado IN ('PAGADO','PREPARANDO','DESPACHADO');
  SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
  FROM tbl_clientes
  WHERE id_cliente = (SELECT id_cliente FROM tbl_pedidos WHERE id_pedido = v_env.id_pedido);
  SELECT d.sku_snapshot INTO v_sku
  FROM tbl_pedido_detalles d
  WHERE d.id_pedido = v_env.id_pedido
  LIMIT 1;
  PERFORM net.http_post(
    url    => 'https://rsuelvotest.app.n8n.cloud/webhook/entrega/estado',
    body   => jsonb_build_object(
      'token', 'RSU_entrega_notif_7Qk2mXwP',
      'motivo', 'guia_registrada',
      'id_envio', v_env.id_envio,
      'id_pedido', v_env.id_pedido,
      'id_comercio', v_env.id_comercio,
      'phone', v_phone,
      'numero_guia', v_nuevo_num,
      'guia_foto_url', v_nueva_foto,
      'transportadora', v_transportadora,
      'destino_ciudad', v_env.destino_ciudad,
      'destino_zona', v_env.destino_zona,
      'sku', v_sku
    ),
    headers => jsonb_build_object('Content-Type', 'application/json')
  );
  RETURN jsonb_build_object(
    'resultado','GUIA_REGISTRADA',
    'id_envio', p_id_envio,
    'numero_guia', v_nuevo_num,
    'guia_foto_url', v_nueva_foto,
    'tipo_punto', v_tipo
  );
END;
$function$;


-- ==== 50_upsert_origen_nombre.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 50 (2026-09-12)
-- Nombre confirmado nunca se pisa con perfil/fallback (Q8)
-- ============================================================
-- Regla: el nombre que da el comprador (o edita el cajero, CONFIRMADO) nunca se
-- sobrescribe con perfil ni 'Cliente WhatsApp'; el perfil solo rellena vacíos.
-- `p_origen_nombre` nuevo con DEFAULT 'PERFIL' (llamadas viejas compatibles).
-- Incidente resuelto: el CREATE inicial duplicó la firma (7 vs 8 args) y los
-- llamadores seguían en la vieja → DROP de la sobrecarga vieja (precedente m34b).
-- Validado secuencial: CONFIRMADO pisa, PERFIL/fallback preservan, apellidos
-- intactos, dato de prueba restaurado.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_upsert_cliente(p_id_comercio uuid, p_nombre text, p_telefono text DEFAULT NULL, p_telefono_whatsapp text DEFAULT NULL, p_email text DEFAULT NULL, p_apellido_paterno text DEFAULT NULL, p_apellido_materno text DEFAULT NULL, p_origen_nombre text DEFAULT 'PERFIL')
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_id uuid;
  v_nombre_completo text;
  v_origen text;
  v_cur_nom text;
  v_cur_pat text;
  v_cur_mat text;
  v_nuevo_nom text;
  v_nuevo_pat text;
  v_nuevo_mat text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;
  v_origen := upper(coalesce(nullif(trim(p_origen_nombre),''), 'PERFIL'));
  if v_origen not in ('CONFIRMADO','PERFIL') then
    raise exception 'origen de nombre inválido (CONFIRMADO|PERFIL)';
  end if;
  v_nombre_completo := nullif(trim(concat_ws(' ',
    nullif(trim(coalesce(p_nombre,'')), ''),
    nullif(trim(coalesce(p_apellido_paterno,'')), ''),
    nullif(trim(coalesce(p_apellido_materno,'')), '')
  )), '');
  if p_telefono_whatsapp is not null then
    select id_cliente into v_id
    from tbl_clientes
    where id_comercio=p_id_comercio
      and telefono_whatsapp=p_telefono_whatsapp
    for update;
    if v_id is not null then
      select nombre, apellido_paterno, apellido_materno
        into v_cur_nom, v_cur_pat, v_cur_mat
      from tbl_clientes
      where id_cliente = v_id;
      if v_origen = 'CONFIRMADO' then
        v_nuevo_nom := coalesce(v_nombre_completo, v_cur_nom);
        v_nuevo_pat := coalesce(nullif(trim(p_apellido_paterno),''), v_cur_pat);
        v_nuevo_mat := coalesce(nullif(trim(p_apellido_materno),''), v_cur_mat);
      else
        if coalesce(trim(v_cur_nom),'') in ('', 'Cliente WhatsApp') then
          v_nuevo_nom := coalesce(v_nombre_completo, v_cur_nom);
        else
          v_nuevo_nom := v_cur_nom;
        end if;
        v_nuevo_pat := coalesce(nullif(trim(v_cur_pat),''), nullif(trim(p_apellido_paterno),''), v_cur_pat);
        v_nuevo_mat := coalesce(nullif(trim(v_cur_mat),''), nullif(trim(p_apellido_materno),''), v_cur_mat);
      end if;
      update tbl_clientes
      set nombre = v_nuevo_nom,
          apellido_paterno = v_nuevo_pat,
          apellido_materno = v_nuevo_mat,
          telefono = coalesce(p_telefono, telefono),
          email = coalesce(p_email, email)
      where id_cliente = v_id;
      return v_id;
    end if;
  end if;
  insert into tbl_clientes(
    id_comercio, nombre, apellido_paterno, apellido_materno, telefono, telefono_whatsapp, email
  )
  values(
    p_id_comercio,
    coalesce(v_nombre_completo, p_nombre),
    nullif(trim(p_apellido_paterno),''),
    nullif(trim(p_apellido_materno),''),
    p_telefono, p_telefono_whatsapp, p_email
  )
  returning id_cliente into v_id;
  return v_id;
end;
$function$;

DROP FUNCTION IF EXISTS rsuelvo.fn_upsert_cliente(uuid, text, text, text, text, text, text);


-- ==== 51_estado_pago_cliente.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 51 (2026-09-12)
-- Snapshot de estado de pago por cliente (R5, solo lectura)
-- ============================================================
-- `fn_estado_pago_cliente` para respuestas post-QR coherentes sin mutar nada:
-- reserva activa+expiración, pedido ESPERANDO_PAGO, verificación en curso
-- (por comprobante, no por último pedido), último comprobante. STABLE,
-- SECURITY DEFINER. Validada en buyers 1/2 con historial real.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_estado_pago_cliente(p_id_comercio uuid, p_id_cliente uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_res record;
  v_ped record;
  v_ver record;
  v_comp text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;
  select id_reserva, estado, fecha_expiracion,
         extract(epoch from (fecha_expiracion - now()))/60 as expira_min
  into v_res
  from tbl_reservas
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  order by created_at desc
  limit 1;
  select id_pedido, estado, subtotal
  into v_ped
  from tbl_pedidos
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado='ESPERANDO_PAGO'
  order by created_at desc
  limit 1;
  select v.id_verificacion, v.estado
  into v_ver
  from tbl_verificaciones v
  join tbl_comprobantes_pago c on c.id_comprobante = v.id_comprobante
  where v.id_comercio=p_id_comercio
    and c.id_cliente=p_id_cliente
    and v.estado in ('PENDIENTE','PROCESANDO')
  order by v.created_at desc
  limit 1;
  select estado into v_comp
  from tbl_comprobantes_pago
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
  order by created_at desc
  limit 1;
  return jsonb_build_object(
    'tiene_reserva_activa', (v_res.id_reserva is not null),
    'reserva_estado', v_res.estado,
    'reserva_expira_min', case when v_res.expira_min is null then null
      when v_res.expira_min < 0 then 0 else floor(v_res.expira_min)::integer end,
    'pedido_esperando_pago', case when v_ped.id_pedido is null then null else jsonb_build_object(
      'id_pedido', v_ped.id_pedido, 'estado', v_ped.estado, 'total', v_ped.subtotal) end,
    'verificacion_en_curso', case when v_ver.id_verificacion is null then null else jsonb_build_object(
      'id_verificacion', v_ver.id_verificacion, 'estado', v_ver.estado) end,
    'ultimo_comprobante_estado', v_comp
  );
end;
$function$;


-- ==== 52_estado_pago_verif_con_contexto.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 52 (2026-09-12)
-- R5: verificación en curso solo con contexto activo
-- ============================================================
-- Incidente E2E: una verificación PROCESANDO zombi (corrida caída) contaminaba
-- el snapshot y WF-04 respondía "lo estamos verificando" sin verificación real.
-- Fix: `verificacion_en_curso` solo si su comprobante cuelga del pedido de la
-- reserva activa o del pedido ESPERANDO_PAGO. Además se marcó ERROR la zombi
-- 21a6a189 (fuera de migración, higiene de tenant de pruebas).
-- Validado: buyer2 → en_curso null + pedido_esperando_pago correcto.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_estado_pago_cliente(p_id_comercio uuid, p_id_cliente uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_res record;
  v_ped record;
  v_ver record;
  v_comp text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;
  select id_reserva, estado, id_pedido, fecha_expiracion,
         extract(epoch from (fecha_expiracion - now()))/60 as expira_min
  into v_res
  from tbl_reservas
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  order by created_at desc
  limit 1;
  select id_pedido, estado, subtotal
  into v_ped
  from tbl_pedidos
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado='ESPERANDO_PAGO'
  order by created_at desc
  limit 1;
  select v.id_verificacion, v.estado
  into v_ver
  from tbl_verificaciones v
  join tbl_comprobantes_pago c on c.id_comprobante = v.id_comprobante
  where v.id_comercio=p_id_comercio
    and c.id_cliente=p_id_cliente
    and v.estado in ('PENDIENTE','PROCESANDO')
    and (c.id_pedido = v_ped.id_pedido or c.id_pedido = v_res.id_pedido)
  order by v.created_at desc
  limit 1;
  select estado into v_comp
  from tbl_comprobantes_pago
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
  order by created_at desc
  limit 1;
  return jsonb_build_object(
    'tiene_reserva_activa', (v_res.id_reserva is not null),
    'reserva_estado', v_res.estado,
    'reserva_expira_min', case when v_res.expira_min is null then null
      when v_res.expira_min < 0 then 0 else floor(v_res.expira_min)::integer end,
    'pedido_esperando_pago', case when v_ped.id_pedido is null then null else jsonb_build_object(
      'id_pedido', v_ped.id_pedido, 'estado', v_ped.estado, 'total', v_ped.subtotal) end,
    'verificacion_en_curso', case when v_ver.id_verificacion is null then null else jsonb_build_object(
      'id_verificacion', v_ver.id_verificacion, 'estado', v_ver.estado) end,
    'ultimo_comprobante_estado', v_comp
  );
end;
$function$;


-- ==== 53_estado_pago_comp_con_contexto.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 53 (2026-09-12)
-- R5: último comprobante también con contexto activo
-- ============================================================
-- Mismo bug que m52 pero en la otra rama: un VALIDO de otra compra vieja
-- disparaba "pago confirmado" sin pago. Ahora solo cuenta el comprobante del
-- pedido esperando o de la reserva. Validado: buyer2 → null + pedido correcto.

-- == FUNCIONES ==
-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_estado_pago_cliente(p_id_comercio uuid, p_id_cliente uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_res record;
  v_ped record;
  v_ver record;
  v_comp text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;
  select id_reserva, estado, id_pedido, fecha_expiracion,
         extract(epoch from (fecha_expiracion - now()))/60 as expira_min
  into v_res
  from tbl_reservas
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado in ('ACTIVA','PAGO_VALIDANDO')
  order by created_at desc
  limit 1;
  select id_pedido, estado, subtotal
  into v_ped
  from tbl_pedidos
  where id_comercio=p_id_comercio
    and id_cliente=p_id_cliente
    and estado='ESPERANDO_PAGO'
  order by created_at desc
  limit 1;
  select v.id_verificacion, v.estado
  into v_ver
  from tbl_verificaciones v
  join tbl_comprobantes_pago c on c.id_comprobante = v.id_comprobante
  where v.id_comercio=p_id_comercio
    and c.id_cliente=p_id_cliente
    and v.estado in ('PENDIENTE','PROCESANDO')
    and (c.id_pedido = v_ped.id_pedido or c.id_pedido = v_res.id_pedido)
  order by v.created_at desc
  limit 1;
  select c.estado into v_comp
  from tbl_comprobantes_pago c
  where c.id_comercio=p_id_comercio
    and c.id_cliente=p_id_cliente
    and (c.id_pedido = v_ped.id_pedido or c.id_pedido = v_res.id_pedido)
  order by c.created_at desc
  limit 1;
  return jsonb_build_object(
    'tiene_reserva_activa', (v_res.id_reserva is not null),
    'reserva_estado', v_res.estado,
    'reserva_expira_min', case when v_res.expira_min is null then null
      when v_res.expira_min < 0 then 0 else floor(v_res.expira_min)::integer end,
    'pedido_esperando_pago', case when v_ped.id_pedido is null then null else jsonb_build_object(
      'id_pedido', v_ped.id_pedido, 'estado', v_ped.estado, 'total', v_ped.subtotal) end,
    'verificacion_en_curso', case when v_ver.id_verificacion is null then null else jsonb_build_object(
      'id_verificacion', v_ver.id_verificacion, 'estado', v_ver.estado) end,
    'ultimo_comprobante_estado', v_comp
  );
end;
$function$;


-- ==== 55_sku_sin_letra_o.sql: trigger base35 + decoder O→0 (ver archivo) ====


-- ==== 56_resolucion_universal.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 56 (2026-09-15)
-- Resolución universal M1 (SKU) + M2 (contexto por teléfono)
-- ============================================================
-- Base del ruteo con número único (D16 en diseño): el SKU identifica comercio
-- (tienda global única) y sucursal (única fila de inventario, o la de mayor
-- disponible en legacy compartidos); el contexto cubre mensajes sin SKU.
-- Solo lectura (STABLE), sin tocar nada existente. Validadas en datos reales:
-- FERC01→SKU_UNICO, FERK02→SKU_COMPARTIDO, O tolerada, ZZZ999/FERZZZ→motivos,
-- buyer1/2→PEDIDO, desconocido→DESCONOCIDO.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_sku_universal(p_sku text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_sku text := replace(upper(trim(coalesce(p_sku,''))), 'O', '0');
  v_comercio uuid;
  v_com_estado text;
  v_var record;
  v_n integer;
  v_cand record;
  v_ef_nom text;
  v_ef_pre numeric;
  v_ef_act boolean;
begin
  if v_sku !~ '^[A-Z0-9]{6}$' then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','FORMATO_INVALIDO');
  end if;
  select c.id_comercio, c.estado into v_comercio, v_com_estado
  from tbl_comercios c
  where c.codigo_tienda = substr(v_sku,1,3);
  if not found then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','TIENDA_DESCONOCIDA');
  end if;
  select v.id_variante, v.id_producto, v.sku into v_var
  from tbl_variantes v
  join tbl_productos p on p.id_producto = v.id_producto
  where v.id_comercio = v_comercio
    and v.sku = v_sku
    and v.activo and p.activo;
  if not found then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','SKU_INEXISTENTE',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado);
  end if;
  select count(*) into v_n
  from tbl_inventario
  where id_variante = v_var.id_variante;
  if v_n = 0 then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','SIN_INVENTARIO',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado,
      'id_variante', v_var.id_variante);
  end if;
  select i.id_sucursal, (i.stock_actual - i.stock_reservado) as disp into v_cand
  from tbl_inventario i
  where i.id_variante = v_var.id_variante
  order by (i.stock_actual - i.stock_reservado) > 0 desc,
           (i.stock_actual - i.stock_reservado) desc,
           i.id_sucursal
  limit 1;
  select e.nombre, e.precio, e.activo into v_ef_nom, v_ef_pre, v_ef_act
  from fn_variante_efectiva(v_var.id_variante, v_cand.id_sucursal) e;
  if coalesce(v_ef_act, true) = false then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','VARIANTE_INACTIVA',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado,
      'id_variante', v_var.id_variante);
  end if;
  return jsonb_build_object(
    'resultado','RESUELTO',
    'id_comercio', v_comercio,
    'comercio_estado', v_com_estado,
    'id_sucursal', v_cand.id_sucursal,
    'id_variante', v_var.id_variante,
    'id_producto', v_var.id_producto,
    'sku', v_var.sku,
    'nombre', v_ef_nom,
    'precio', v_ef_pre,
    'origen', case when v_n = 1 then 'SKU_UNICO' else 'SKU_COMPARTIDO' end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_contexto_por_telefono(p_telefono text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_tel text := nullif(trim(coalesce(p_telefono,'')), '');
  v_cli record;
  v_cap record;
  v_pen record;
  v_op record;
  v_res record;
  v_ped record;
  v_last uuid;
begin
  if v_tel is null then
    return jsonb_build_object('origen','DESCONOCIDO');
  end if;
  for v_cli in
    select id_cliente, id_comercio
    from tbl_clientes
    where coalesce(telefono_whatsapp, telefono) = v_tel
    order by updated_at desc
  loop
    select p.id_pedido, p.id_sucursal into v_cap
    from tbl_pedidos p
    where p.id_cliente = v_cli.id_cliente
      and p.estado = 'PAGADO'
      and not exists (select 1 from tbl_envios e where e.id_pedido = p.id_pedido)
      and exists (select 1 from tbl_entrega_captura c where c.id_pedido = p.id_pedido)
    order by p.created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','CAPTURA', 'id_comercio', v_cli.id_comercio,
        'id_pedido', v_cap.id_pedido, 'id_sucursal', v_cap.id_sucursal);
    end if;
    select id_sucursal, id_variante into v_pen
    from tbl_lista_pendiente
    where id_cliente = v_cli.id_cliente;
    if found then
      return jsonb_build_object('origen','PENDIENTE', 'id_comercio', v_cli.id_comercio,
        'id_sucursal', v_pen.id_sucursal, 'id_variante', v_pen.id_variante);
    end if;
    select id_lista_espera, id_sucursal, id_variante into v_op
    from tbl_lista_espera
    where id_cliente = v_cli.id_cliente
      and estado = 'NOTIFICADO'
      and fecha_expiracion > now()
    order by fecha_notificacion desc
    limit 1;
    if found then
      return jsonb_build_object('origen','OPORTUNIDAD', 'id_comercio', v_cli.id_comercio,
        'id_lista_espera', v_op.id_lista_espera,
        'id_sucursal', v_op.id_sucursal, 'id_variante', v_op.id_variante);
    end if;
    select id_reserva, id_sucursal, id_variante into v_res
    from tbl_reservas
    where id_cliente = v_cli.id_cliente
      and estado in ('ACTIVA','PAGO_VALIDANDO')
    order by created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','RESERVA', 'id_comercio', v_cli.id_comercio,
        'id_reserva', v_res.id_reserva,
        'id_sucursal', v_res.id_sucursal, 'id_variante', v_res.id_variante);
    end if;
    select id_pedido, id_sucursal into v_ped
    from tbl_pedidos
    where id_cliente = v_cli.id_cliente
      and estado = 'ESPERANDO_PAGO'
    order by created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','PEDIDO', 'id_comercio', v_cli.id_comercio,
        'id_pedido', v_ped.id_pedido, 'id_sucursal', v_ped.id_sucursal);
    end if;
  end loop;
  select id_comercio into v_last
  from tbl_clientes
  where coalesce(telefono_whatsapp, telefono) = v_tel
  order by updated_at desc
  limit 1;
  if found then
    return jsonb_build_object('origen','ULTIMO_COMERCIO', 'id_comercio', v_last);
  end if;
  return jsonb_build_object('origen','DESCONOCIDO');
end;
$function$;


-- ==== 57_v3a_solo_no_entregado_postea.sql (contenido íntegro) ====
-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 57 (2026-09-14)
-- V3-A: solo NO_ENTREGADO despierta a WF-25-C (P2-P8)
-- ============================================================
-- PREPARANDO/ASIGNADO/EN_RUTA/ENTREGADO son silenciosos en n8n (verificado),
-- así que ni siquiera se emite el POST (ahorra 1T/1Q por transición).
-- Guía va por vía propia (fn_registrar_guia, intacta). Si un estado futuro
-- vuelve a notificar, agregarlo al IF. Push (triggers m47) intacto.
-- Validado: ASIGNADO → 0 roots n8n + push evento-4 OK; NO_ENTREGADO → root +
-- mensaje al comprador. Limpieza total posterior.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_notifica_envio_estado()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_phone text;
BEGIN
  IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'NO_ENTREGADO' THEN
    SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
    FROM tbl_clientes
    WHERE id_cliente = (SELECT id_cliente FROM tbl_pedidos WHERE id_pedido = NEW.id_pedido);
    IF v_phone IS NOT NULL THEN
      PERFORM net.http_post(
        url    => 'https://rsuelvotest.app.n8n.cloud/webhook/entrega/estado',
        body   => jsonb_build_object(
          'token', 'RSU_entrega_notif_7Qk2mXwP',
          'id_envio', NEW.id_envio,
          'id_pedido', NEW.id_pedido,
          'id_comercio', NEW.id_comercio,
          'estado', NEW.estado,
          'phone', v_phone,
          'numero_guia', NEW.numero_guia
        ),
        headers => jsonb_build_object('Content-Type', 'application/json')
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
-- ═══ MIG 58_alta_superadmin (aplicada 2026-09-15) ═══
-- 58_alta_superadmin.sql
-- F8-slice backend: alta de comercios + cambio de estado + fix identificacion universal.
-- HU-105/106 (suspender/bloquear/reactivar) · D4 (alta self-service) · D13 (verif manual por defecto)
-- D15 (lanzamiento solo-manual) · D16 (numero universal: identificar no desambigua compartidos).
-- PostgREST: fns en schema rsuelvo (expuesto) -> RPC automatico; RETURNS jsonb;
--   errores de negocio como {ok:false} (patron casa), RAISE solo si no es superadmin.

-- ── fn_alta_comercio ─────────────────────────────────────────────────────────
create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
begin
  if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;

  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, p_nombre, p_telefono, p_email, 'ACTIVO')
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', 'DESCONECTADO', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus
  );
end;
$fn$;

-- ── fn_cambiar_estado_comercio (HU-105/106) ───────────────────────────────────
create or replace function rsuelvo.fn_cambiar_estado_comercio(
  p_id_comercio uuid,
  p_estado rsuelvo.estado_comercio
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_anterior rsuelvo.estado_comercio;
begin
  if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  select estado into v_anterior
  from rsuelvo.tbl_comercios where id_comercio = p_id_comercio;

  if v_anterior is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;

  if v_anterior = p_estado then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cambio', 'estado', v_anterior);
  end if;

  update rsuelvo.tbl_comercios
  set estado = p_estado, updated_at = now()
  where id_comercio = p_id_comercio;

  return jsonb_build_object('ok', true, 'anterior', v_anterior, 'nuevo', p_estado);
end;
$fn$;

-- ── Fix identificacion: numero/pnid compartido (universal) no desambigua ─────
-- Un solo canal activo -> lo devuelve (comportamiento actual intacto).
-- Varios (numero universal D16) -> vacio para que el llamador caiga a M1/M2.
create or replace function rsuelvo.fn_identificar_comercio_por_whatsapp(p_numero text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  with m as (
    select c.id_comercio, c.id_sucursal, c.provider::text as provider
    from tbl_canal_whatsapp c
    where c.numero = p_numero and c.activo
  )
  select * from m where (select count(*) from m) = 1;
$fn$;

create or replace function rsuelvo.fn_identificar_comercio_por_phone_number_id(p_pnid text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  with m as (
    select c.id_comercio, c.id_sucursal, c.provider::text as provider
    from tbl_canal_whatsapp c
    where c.provider_phone_number_id = p_pnid and c.activo
  )
  select * from m where (select count(*) from m) = 1;
$fn$;
-- ═══ MIG 59_rls_superadmin_qr (aplicada 2026-09-15) ═══
-- 59_rls_superadmin_qr.sql
-- F8-slice: el panel (superadmin) debe poder subir/leer/actualizar el QR del comercio
-- en el bucket qr-pagos. Lecturas de tablas ya cubiertas (fn_tiene_acceso_comercio y
-- fn_es_admin_comercio incluyen superadmin). PostgREST: policies sobre storage.objects
-- aplican al upload via API con JWT de superadmin (TO authenticated).

-- Limpieza idempotente
drop policy if exists qr_pagos_superadmin_select on storage.objects;
drop policy if exists qr_pagos_superadmin_insert on storage.objects;
drop policy if exists qr_pagos_superadmin_update on storage.objects;

create policy qr_pagos_superadmin_select on storage.objects
  for select to authenticated
  using (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin());

create policy qr_pagos_superadmin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin());

create policy qr_pagos_superadmin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin())
  with check (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin());
-- ═══ MIG 60_canal_numero_compartido (aplicada 2026-09-15) ═══
-- 60_canal_numero_compartido.sql
-- D16 (numero universal): el numero de WhatsApp es compartido entre comercios
-- (todos usan el 59157005003). El UNIQUE en numero lo impedia: el alta del 2do
-- comercio reventaba con 23505. Se elimina; la desambiguacion vive en M1/M2
-- (fn_resolver_sku_universal + fn_contexto_por_telefono) y fn_identificar_* ya
-- devuelve vacio ante multiples (mig 58). HU-105/106, F8-slice.

alter table rsuelvo.tbl_canal_whatsapp
  drop constraint if exists tbl_canal_whatsapp_numero_key;

drop index if exists rsuelvo.uq_canal_numero_activo;
-- ═══ MIG 61_fix_fn_es_service_role (aplicada 2026-09-15) ═══
-- 61_fix_fn_es_service_role.sql
-- INCIDENTE 2026-09-15: fn_es_service_role() devolvia TRUE para CUALQUIER usuario
-- autenticado (e incluso anon). Causa: leia current_setting('request.jwt.claim.role'),
-- GUC singular que PostgREST 14 ya no setea -> NULL -> coalesce a 'service_role'.
-- Efecto: todo guard `fn_es_service_role() or ...` (casi todas las policies RLS y
-- guards de fn_*) pasaba para cualquier logueado (probado: alta de tenant sin rol).
-- Fix: patron canonico via auth.jwt() (lee request.jwt.claims, siempre seteado).
-- anon -> NULL -> false; usuario -> 'authenticated' -> false; service_role -> true.

create or replace function rsuelvo.fn_es_service_role()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select coalesce(auth.jwt()->>'role', '') = 'service_role';
$fn$;
-- ═══ MIG 62_pendiente_aprobacion_qr_dueno (aplicada 2026-09-16, en 3 partes: alter-type + A/B + C) ═══
-- 62_pendiente_aprobacion_qr_dueno.sql
-- D17 + roles expandidos: alta con estado (staff->pendiente), cuarentena de no-ACTIVO,
-- QR del dueño (tenant). HU-105/106, F8-slice.
-- NOTA: el `alter type ... add value` va en llamada SEPARADA (no corre en bloque txn).

-- ── fn_alta_comercio: p_estado + coercion staff ──────────────────────────────
create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100,
  p_estado rsuelvo.estado_comercio default 'ACTIVO'
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT') then
    v_estado_final := 'PENDIENTE_APROBACION';
  else
    raise exception 'solo staff autorizado';
  end if;

  if v_estado_final not in ('ACTIVO', 'PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'estado_invalido');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;

  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final)
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', 'DESCONECTADO', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus
  );
end;
$fn$;

-- ── Cuarentena D17: identificar exige comercio ACTIVO ────────────────────────
create or replace function rsuelvo.fn_identificar_comercio_por_whatsapp(p_numero text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  with m as (
    select c.id_comercio, c.id_sucursal, c.provider::text as provider
    from tbl_canal_whatsapp c
    join tbl_comercios co on co.id_comercio = c.id_comercio
    where c.numero = p_numero and c.activo and co.estado = 'ACTIVO'
  )
  select * from m where (select count(*) from m) = 1;
$fn$;

create or replace function rsuelvo.fn_identificar_comercio_por_phone_number_id(p_pnid text)
returns table(id_comercio uuid, id_sucursal uuid, provider text)
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  with m as (
    select c.id_comercio, c.id_sucursal, c.provider::text as provider
    from tbl_canal_whatsapp c
    join tbl_comercios co on co.id_comercio = c.id_comercio
    where c.provider_phone_number_id = p_pnid and c.activo and co.estado = 'ACTIVO'
  )
  select * from m where (select count(*) from m) = 1;
$fn$;

-- ── Cuarentena D17: resolver SKU exige comercio ACTIVO ───────────────────────
create or replace function rsuelvo.fn_resolver_sku_universal(p_sku text)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $function$
declare
  v_sku text := replace(upper(trim(coalesce(p_sku,''))), 'O', '0');
  v_comercio uuid;
  v_com_estado text;
  v_var record;
  v_n integer;
  v_cand record;
  v_ef_nom text;
  v_ef_pre numeric;
  v_ef_act boolean;
begin
  if v_sku !~ '^[A-Z0-9]{6}$' then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','FORMATO_INVALIDO');
  end if;

  select c.id_comercio, c.estado into v_comercio, v_com_estado
  from tbl_comercios c
  where c.codigo_tienda = substr(v_sku,1,3);
  if not found then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','TIENDA_DESCONOCIDA');
  end if;

  if v_com_estado is distinct from 'ACTIVO' then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','COMERCIO_NO_ACTIVO',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado);
  end if;

  select v.id_variante, v.id_producto, v.sku into v_var
  from tbl_variantes v
  join tbl_productos p on p.id_producto = v.id_producto
  where v.id_comercio = v_comercio
    and v.sku = v_sku
    and v.activo and p.activo;
  if not found then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','SKU_INEXISTENTE',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado);
  end if;

  select count(*) into v_n
  from tbl_inventario
  where id_variante = v_var.id_variante;
  if v_n = 0 then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','SIN_INVENTARIO',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado,
      'id_variante', v_var.id_variante);
  end if;

  select i.id_sucursal, (i.stock_actual - i.stock_reservado) as disp into v_cand
  from tbl_inventario i
  where i.id_variante = v_var.id_variante
  order by (i.stock_actual - i.stock_reservado) > 0 desc,
           (i.stock_actual - i.stock_reservado) desc,
           i.id_sucursal
  limit 1;

  select e.nombre, e.precio, e.activo into v_ef_nom, v_ef_pre, v_ef_act
  from fn_variante_efectiva(v_var.id_variante, v_cand.id_sucursal) e;
  if coalesce(v_ef_act, true) = false then
    return jsonb_build_object('resultado','NO_ENCONTRADO','motivo','VARIANTE_INACTIVA',
      'id_comercio', v_comercio, 'comercio_estado', v_com_estado,
      'id_variante', v_var.id_variante);
  end if;

  return jsonb_build_object(
    'resultado','RESUELTO',
    'id_comercio', v_comercio,
    'comercio_estado', v_com_estado,
    'id_sucursal', v_cand.id_sucursal,
    'id_variante', v_var.id_variante,
    'id_producto', v_var.id_producto,
    'sku', v_var.sku,
    'nombre', v_ef_nom,
    'precio', v_ef_pre,
    'origen', case when v_n = 1 then 'SKU_UNICO' else 'SKU_COMPARTIDO' end
  );
end;
$function$;

-- ── Cuarentena D17: contexto M2 (parche programatico abajo) ─────────────────
CREATE OR REPLACE FUNCTION rsuelvo.fn_contexto_por_telefono(p_telefono text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_tel text := nullif(trim(coalesce(p_telefono,'')), '');
  v_cli record;
  v_cap record;
  v_pen record;
  v_op record;
  v_res record;
  v_ped record;
  v_last uuid;
begin
  if v_tel is null then
    return jsonb_build_object('origen','DESCONOCIDO');
  end if;

  for v_cli in
    select id_cliente, id_comercio
    from tbl_clientes
    where coalesce(telefono_whatsapp, telefono) = v_tel
    order by updated_at desc
  loop
    -- cuarentena D17: ignora comercios no ACTIVO
    if (select c.estado from tbl_comercios c where c.id_comercio = v_cli.id_comercio) is distinct from 'ACTIVO' then
      continue;
    end if;
    -- 1. captura de destino en curso
    select p.id_pedido, p.id_sucursal into v_cap
    from tbl_pedidos p
    where p.id_cliente = v_cli.id_cliente
      and p.estado = 'PAGADO'
      and not exists (select 1 from tbl_envios e where e.id_pedido = p.id_pedido)
      and exists (select 1 from tbl_entrega_captura c where c.id_pedido = p.id_pedido)
    order by p.created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','CAPTURA', 'id_comercio', v_cli.id_comercio,
        'id_pedido', v_cap.id_pedido, 'id_sucursal', v_cap.id_sucursal);
    end if;

    -- 2. pendiente Momento 1 (PK por cliente: una fila como máximo)
    select id_sucursal, id_variante into v_pen
    from tbl_lista_pendiente
    where id_cliente = v_cli.id_cliente;
    if found then
      return jsonb_build_object('origen','PENDIENTE', 'id_comercio', v_cli.id_comercio,
        'id_sucursal', v_pen.id_sucursal, 'id_variante', v_pen.id_variante);
    end if;

    -- 3. oportunidad NOTIFICADO vigente
    select id_lista_espera, id_sucursal, id_variante into v_op
    from tbl_lista_espera
    where id_cliente = v_cli.id_cliente
      and estado = 'NOTIFICADO'
      and fecha_expiracion > now()
    order by fecha_notificacion desc
    limit 1;
    if found then
      return jsonb_build_object('origen','OPORTUNIDAD', 'id_comercio', v_cli.id_comercio,
        'id_lista_espera', v_op.id_lista_espera,
        'id_sucursal', v_op.id_sucursal, 'id_variante', v_op.id_variante);
    end if;

    -- 4. reserva viva
    select id_reserva, id_sucursal, id_variante into v_res
    from tbl_reservas
    where id_cliente = v_cli.id_cliente
      and estado in ('ACTIVA','PAGO_VALIDANDO')
    order by created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','RESERVA', 'id_comercio', v_cli.id_comercio,
        'id_reserva', v_res.id_reserva,
        'id_sucursal', v_res.id_sucursal, 'id_variante', v_res.id_variante);
    end if;

    -- 5. pedido esperando pago
    select id_pedido, id_sucursal into v_ped
    from tbl_pedidos
    where id_cliente = v_cli.id_cliente
      and estado = 'ESPERANDO_PAGO'
    order by created_at desc
    limit 1;
    if found then
      return jsonb_build_object('origen','PEDIDO', 'id_comercio', v_cli.id_comercio,
        'id_pedido', v_ped.id_pedido, 'id_sucursal', v_ped.id_sucursal);
    end if;
  end loop;

  -- 6. último comercio activo del teléfono (sin sucursal)
  select cl.id_comercio into v_last
  from tbl_clientes cl
  join tbl_comercios c on c.id_comercio = cl.id_comercio
  where coalesce(cl.telefono_whatsapp, cl.telefono) = v_tel
    and c.estado = 'ACTIVO'
  order by cl.updated_at desc
  limit 1;
  if found then
    return jsonb_build_object('origen','ULTIMO_COMERCIO', 'id_comercio', v_last);
  end if;

  return jsonb_build_object('origen','DESCONOCIDO');
end;
$function$


-- ── QR del dueño: policies tenant sobre qr-pagos (el path manda) ────────────
drop policy if exists qr_pagos_dueno_select on storage.objects;
drop policy if exists qr_pagos_dueno_insert on storage.objects;
drop policy if exists qr_pagos_dueno_update on storage.objects;

create policy qr_pagos_dueno_select on storage.objects
  for select to authenticated
  using (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));

create policy qr_pagos_dueno_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));

create policy qr_pagos_dueno_update on storage.objects
  for update to authenticated
  using (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid))
  with check (bucket_id = 'qr-pagos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));
-- ═══ MIG 63_creditos_clientes (aplicada 2026-09-16, en 2 partes A/B) ═══
-- 63_creditos_clientes.sql
-- A) Clientes: `nombre` guardaba el CONCATENADO (nombre+apellidos) y la app volvia
--    a concatenar -> "Juan Pérez García Pérez García". Fix: el escritor normaliza
--    (despoja apellidos de `nombre`) + limpieza de filas existentes. Display en app
--    (concat) queda intacto, sin cambios.
-- B) Creditos: extension `tbl_compras_creditos` + bucket `depositos-creditos` +
--    `fn_solicitar_creditos` (dueño) + `fn_resolver_compra_creditos` (staff).
--    HU-pendientes roles expandidos, D17-adjacente.

-- ═══ A1. Limpieza: despojar apellidos de `nombre` (solo si queda no-vacio) ═══
update rsuelvo.tbl_clientes
set nombre = trim(both ' ' from regexp_replace(
  regexp_replace(nombre,
    '(?i)\m' || regexp_replace(coalesce(apellido_paterno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'),
  '(?i)\m' || regexp_replace(coalesce(apellido_materno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'))
where apellido_paterno is not null
  and nullif(trim(both ' ' from regexp_replace(
    regexp_replace(nombre,
      '(?i)\m' || regexp_replace(coalesce(apellido_paterno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'),
    '(?i)\m' || regexp_replace(coalesce(apellido_materno,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g')), '') is not null
  and (nombre ilike '%' || apellido_paterno || '%' or nombre ilike '%' || apellido_materno || '%');

-- ═══ A2. Escritor: fn_upsert_cliente normaliza (reescritura completa) ═══
create or replace function rsuelvo.fn_upsert_cliente(p_id_comercio uuid, p_nombre text, p_telefono text DEFAULT NULL::text, p_telefono_whatsapp text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_apellido_paterno text DEFAULT NULL::text, p_apellido_materno text DEFAULT NULL::text, p_origen_nombre text DEFAULT 'PERFIL'::text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'rsuelvo', 'public'
as $function$
declare
  v_id uuid;
  v_origen text;
  v_pat text := nullif(trim(coalesce(p_apellido_paterno,'')), '');
  v_mat text := nullif(trim(coalesce(p_apellido_materno,'')), '');
  v_nom_limpio text;
  v_cur_nom text;
  v_cur_pat text;
  v_cur_mat text;
  v_nuevo_nom text;
  v_nuevo_pat text;
  v_nuevo_mat text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;

  v_origen := upper(coalesce(nullif(trim(p_origen_nombre),''), 'PERFIL'));
  if v_origen not in ('CONFIRMADO','PERFIL') then
    raise exception 'origen de nombre inválido (CONFIRMADO|PERFIL)';
  end if;

  -- `nombre` guarda SOLO nombres: se despojan los apellidos que vengan pegados
  -- (p.ej. perfil WhatsApp "Juan Pérez García" + pat/Mat). Si quedara vacio,
  -- se conserva el original recortado (nunca NULL por normalizacion).
  v_nom_limpio := trim(both ' ' from regexp_replace(
    regexp_replace(coalesce(trim(p_nombre), ''),
      '(?i)\m' || regexp_replace(coalesce(v_pat,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'),
    '(?i)\m' || regexp_replace(coalesce(v_mat,''), '([.*+?^${}()|[\]\\])', '\\\1', 'g') || '\M', '', 'g'));
  if v_nom_limpio = '' then
    v_nom_limpio := nullif(trim(coalesce(p_nombre,'')), '');
  end if;

  if p_telefono_whatsapp is not null then
    select id_cliente into v_id
    from tbl_clientes
    where id_comercio=p_id_comercio
      and telefono_whatsapp=p_telefono_whatsapp
    for update;

    if v_id is not null then
      -- Q8: el nombre confirmado (comprador/cajero) nunca se pisa con perfil/fallback.
      select nombre, apellido_paterno, apellido_materno
        into v_cur_nom, v_cur_pat, v_cur_mat
      from tbl_clientes
      where id_cliente = v_id;

      if v_origen = 'CONFIRMADO' then
        v_nuevo_nom := coalesce(v_nom_limpio, v_cur_nom);
        v_nuevo_pat := coalesce(v_pat, v_cur_pat);
        v_nuevo_mat := coalesce(v_mat, v_cur_mat);
      else
        if coalesce(trim(v_cur_nom),'') in ('', 'Cliente WhatsApp') then
          v_nuevo_nom := coalesce(v_nom_limpio, v_cur_nom);
        else
          v_nuevo_nom := v_cur_nom;
        end if;
        v_nuevo_pat := coalesce(nullif(trim(v_cur_pat),''), v_pat, v_cur_pat);
        v_nuevo_mat := coalesce(nullif(trim(v_cur_mat),''), v_mat, v_cur_mat);
      end if;

      update tbl_clientes
      set nombre = v_nuevo_nom,
          apellido_paterno = v_nuevo_pat,
          apellido_materno = v_nuevo_mat,
          telefono = coalesce(p_telefono, telefono),
          email = coalesce(p_email, email)
      where id_cliente = v_id;
      return v_id;
    end if;
  end if;

  insert into tbl_clientes(
    id_comercio, nombre, apellido_paterno, apellido_materno, telefono, telefono_whatsapp, email
  )
  values(
    p_id_comercio,
    v_nom_limpio,
    v_pat,
    v_mat,
    p_telefono, p_telefono_whatsapp, p_email
  )
  returning id_cliente into v_id;

  return v_id;
end;
$function$;

-- ═══ B1. Extension compras + bucket ═══
alter table rsuelvo.tbl_compras_creditos
  add column if not exists comprobante_deposito_url text,
  add column if not exists id_revisor uuid references rsuelvo.tbl_usuarios(id_usuario),
  add column if not exists fecha_revision timestamptz,
  add column if not exists motivo_rechazo text;

insert into storage.buckets (id, name, public)
values ('depositos-creditos', 'depositos-creditos', false)
on conflict (id) do nothing;

drop policy if exists depositos_dueno_select on storage.objects;
drop policy if exists depositos_dueno_insert on storage.objects;
drop policy if exists depositos_staff_select on storage.objects;

create policy depositos_dueno_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid));

create policy depositos_dueno_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'depositos-creditos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));

create policy depositos_staff_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
    and (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')
      or rsuelvo.fn_tiene_rol('ROLE_SUPPORT')));

-- ═══ B2. RLS compras: lectura dueño/staff, escritura solo via fns ═══
alter table rsuelvo.tbl_compras_creditos enable row level security;

drop policy if exists compras_select on rsuelvo.tbl_compras_creditos;
drop policy if exists compras_no_direct_write on rsuelvo.tbl_compras_creditos;

create policy compras_select on rsuelvo.tbl_compras_creditos
  for select to authenticated
  using (rsuelvo.fn_tiene_acceso_comercio(id_comercio)
    or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')
    or rsuelvo.fn_tiene_rol('ROLE_SUPPORT'));

create policy compras_no_direct_write on rsuelvo.tbl_compras_creditos
  for all to authenticated
  using (false) with check (false);

-- ═══ B3. fn_solicitar_creditos (dueño) ═══
create or replace function rsuelvo.fn_solicitar_creditos(
  p_id_paquete uuid,
  p_comprobante_url text
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_comercio uuid;
  v_n integer;
  v_paq record;
  v_compra uuid;
begin
  select uc.id_comercio into v_comercio
  from tbl_usuario_comercio uc
  join tbl_usuarios u on u.id_usuario = uc.id_usuario
  join tbl_roles r on r.id_rol = uc.id_rol
  where u.auth_user_id = auth.uid()
    and u.activo and uc.activo
    and r.codigo = 'ROLE_TENANT_ADMIN';

  select count(*) into v_n from (
    select uc.id_comercio
    from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario = uc.id_usuario
    join tbl_roles r on r.id_rol = uc.id_rol
    where u.auth_user_id = auth.uid()
      and u.activo and uc.activo
      and r.codigo = 'ROLE_TENANT_ADMIN'
  ) t;
  if v_comercio is null then
    return jsonb_build_object('ok', false, 'codigo', 'solo_dueno');
  end if;
  if v_n > 1 then
    return jsonb_build_object('ok', false, 'codigo', 'multi_comercio');
  end if;

  select id_paquete, creditos, precio into v_paq
  from tbl_paquetes_creditos
  where id_paquete = p_id_paquete and activo;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'paquete_invalido');
  end if;

  if nullif(trim(coalesce(p_comprobante_url,'')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'falta_comprobante');
  end if;

  insert into tbl_compras_creditos
    (id_comercio, id_paquete, creditos_comprados, monto, moneda, estado, comprobante_deposito_url)
  values
    (v_comercio, v_paq.id_paquete, v_paq.creditos, v_paq.precio, 'Bs', 'PENDIENTE', trim(p_comprobante_url))
  returning id_compra into v_compra;

  return jsonb_build_object('ok', true, 'id_compra', v_compra,
    'creditos', v_paq.creditos, 'monto', v_paq.precio);
end;
$fn$;

-- ═══ B4. fn_resolver_compra_creditos (staff aprueba/rechaza; dueño cancela) ═══
create or replace function rsuelvo.fn_resolver_compra_creditos(
  p_id_compra uuid,
  p_decision text
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_c record;
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT');
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not rsuelvo.fn_es_admin_comercio(v_c.id_comercio) then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$fn$;
-- ═══ MIG 64_comprobantes_path (aplicada 2026-09-16; backfill por script: 9 paths, 3 lookaside irrecuperables) ═══
-- 64_comprobantes_path.sql
-- URLs firmadas (`/object/sign/...?token=exp`) y lookaside Meta vencen: la app no
-- puede mostrar comprobantes viejos. Fix: columna `archivo_path` (path en bucket,
-- firma ON-DEMAND al visualizar) + policies de lectura en `comprobantes-pago`.
-- El backfill de paths va por script (decodifica el `url` del token JWT).
-- WF-20 debe guardar PATH (prompt aparte); la app firma al ver (prompt aparte).

alter table rsuelvo.tbl_comprobantes_pago
  add column if not exists archivo_path text;

drop policy if exists comprobantes_tenant_select on storage.objects;
drop policy if exists comprobantes_staff_select on storage.objects;

create policy comprobantes_tenant_select on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes-pago'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid));

create policy comprobantes_staff_select on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes-pago'
    and (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')
      or rsuelvo.fn_tiene_rol('ROLE_SUPPORT')));
-- ═══ MIG 65_registrar_path (aplicada 2026-09-16; incluye DROP overload viejo) ═══
-- 65_registrar_path.sql
-- fn_registrar_comprobante gana p_archivo_path (opcional): WF-21/WF-22 persistiran
-- el path en bucket (`<id_comercio>/<mid>.jpg`) para firma on-demand (mig 64).
-- INSERT + rama reenvio (UPDATE) lo guardan. Resto intacto (m44, duplicados).
-- OJO: CREATE OR REPLACE con param nuevo crea overload; se elimino la firma vieja
-- (10 params, DROP limpio sin dependientes) para RPC no ambiguo.

drop function if exists rsuelvo.fn_registrar_comprobante(uuid, uuid, text, text, numeric, timestamptz, text, text, rsuelvo.estado_comprobante, uuid);

create or replace function rsuelvo.fn_registrar_comprobante(p_id_comercio uuid, p_id_cliente uuid, p_tipo_archivo text, p_archivo_url text, p_monto_detectado numeric DEFAULT NULL::numeric, p_fecha_detectada timestamp with time zone DEFAULT NULL::timestamp with time zone, p_numero_operacion text DEFAULT NULL::text, p_nombre_pagador text DEFAULT NULL::text, p_estado rsuelvo.estado_comprobante DEFAULT 'RECIBIDO'::rsuelvo.estado_comprobante, p_id_pedido uuid DEFAULT NULL::uuid, p_archivo_path text DEFAULT NULL::text)
 returns table(id_comprobante uuid, id_pedido uuid)
 language plpgsql
 security definer
 set search_path to 'rsuelvo', 'public'
as $function$
DECLARE
  v_id_comprobante uuid := gen_random_uuid();
  v_id_pedido uuid := p_id_pedido;
  v_existente uuid;
  v_pedido_existente uuid;
BEGIN
  IF NOT fn_tiene_acceso_comercio(p_id_comercio) THEN
    RAISE EXCEPTION 'Sin acceso al comercio';
  END IF;

  IF v_id_pedido IS NULL THEN
    SELECT p.id_pedido INTO v_id_pedido
    FROM tbl_pedidos p
    JOIN tbl_reservas r ON r.id_pedido = p.id_pedido AND r.estado = 'ACTIVA'
    WHERE p.id_comercio = p_id_comercio
      AND p.id_cliente = p_id_cliente
      AND p.estado = 'ESPERANDO_PAGO'
    ORDER BY p.created_at DESC
    LIMIT 1;

    IF v_id_pedido IS NULL THEN
      SELECT p.id_pedido INTO v_id_pedido
      FROM tbl_pedidos p
      WHERE p.id_comercio = p_id_comercio
        AND p.id_cliente = p_id_cliente
        AND p.estado = 'ESPERANDO_PAGO'
      ORDER BY p.created_at DESC
      LIMIT 1;
    END IF;
  END IF;

  IF v_id_pedido IS NULL THEN
    RAISE EXCEPTION 'No se encontro pedido en espera de pago para vincular el comprobante';
  END IF;

  IF p_numero_operacion IS NOT NULL THEN
    SELECT c.id_comprobante, c.id_pedido
      INTO v_existente, v_pedido_existente
      FROM tbl_comprobantes_pago c
      WHERE c.id_comercio = p_id_comercio
        AND c.numero_operacion = p_numero_operacion
      LIMIT 1;

    IF v_existente IS NOT NULL THEN
      IF v_pedido_existente = v_id_pedido THEN
        UPDATE tbl_comprobantes_pago AS c
           SET tipo_archivo     = p_tipo_archivo,
               archivo_url      = p_archivo_url,
               archivo_path     = COALESCE(p_archivo_path, c.archivo_path),
               monto_detectado  = COALESCE(p_monto_detectado, c.monto_detectado),
               fecha_detectada  = COALESCE(p_fecha_detectada, c.fecha_detectada),
               nombre_pagador   = COALESCE(p_nombre_pagador, c.nombre_pagador),
               estado           = p_estado
         WHERE c.id_comprobante = v_existente;
        UPDATE tbl_reservas AS r
        SET estado='PAGO_VALIDANDO'
        WHERE r.id_pedido=v_id_pedido AND r.estado='ACTIVA';
        RETURN QUERY SELECT v_existente, v_id_pedido;
        RETURN;
      ELSE
        RAISE EXCEPTION 'COMPROBANTE_DUPLICADO: el numero de operacion % ya fue registrado para otro pedido', p_numero_operacion;
      END IF;
    END IF;
  END IF;

  INSERT INTO tbl_comprobantes_pago (
    id_comprobante, id_comercio, id_pedido, id_cliente,
    tipo_archivo, archivo_url, archivo_path, monto_detectado, fecha_detectada,
    numero_operacion, nombre_pagador, estado
  ) VALUES (
    v_id_comprobante, p_id_comercio, v_id_pedido, p_id_cliente,
    p_tipo_archivo, p_archivo_url, p_archivo_path, p_monto_detectado, p_fecha_detectada,
    p_numero_operacion, p_nombre_pagador, p_estado
  );

  UPDATE tbl_reservas AS r
  SET estado='PAGO_VALIDANDO'
  WHERE r.id_pedido=v_id_pedido AND r.estado='ACTIVA';

  RETURN QUERY SELECT v_id_comprobante, v_id_pedido;
END;
$function$;
-- ═══ MIG 66 (aplicada 2026-09-17, en 3 partes + DROP overload alta) ═══
-- 66_staff_lectura_estado_robusto.sql
-- Auditoria P0 (hallazgos 1,3 + robustez): SUPPORT fuera de admin-tenant,
-- lecturas staff explicitas, EXECUTE restringido, maquina de estados,
-- bonus>=0, motivo de rechazo. HU roles expandidos, D17.

-- ── 1. fn_es_admin_comercio sin SUPPORT ─────────────────────────────────────
create or replace function rsuelvo.fn_es_admin_comercio(p_id_comercio uuid)
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        join tbl_roles r on r.id_rol=uc.id_rol
        where u.auth_user_id=auth.uid()
          and u.activo and uc.activo
          and uc.id_comercio=p_id_comercio
          and r.codigo = 'ROLE_TENANT_ADMIN'
      );
$fn$;

-- ── 2. Lectura staff (sysadmin/soporte, global, sin escritura) ──────────────
create or replace function rsuelvo.fn_lectura_staff()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select fn_es_service_role()
      or fn_es_superadmin()
      or fn_tiene_rol('ROLE_SYSADMIN')
      or fn_tiene_rol('ROLE_SUPPORT');
$fn$;

drop policy if exists staff_read on rsuelvo.tbl_comercios;
create policy staff_read on rsuelvo.tbl_comercios
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_comercio_config;
create policy staff_read on rsuelvo.tbl_comercio_config
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_cuentas_creditos;
create policy staff_read on rsuelvo.tbl_cuentas_creditos
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_movimientos_creditos;
create policy staff_read on rsuelvo.tbl_movimientos_creditos
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_sucursales;
create policy staff_read on rsuelvo.tbl_sucursales
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_canal_whatsapp;
create policy staff_read on rsuelvo.tbl_canal_whatsapp
  for select to authenticated using (rsuelvo.fn_lectura_staff());

-- Auditoria: sysadmin la conserva (matriz), support no (ya la pierde al salir de admin_fn)
drop policy if exists audit_sysadmin_select on rsuelvo.tbl_logs_auditoria;
create policy audit_sysadmin_select on rsuelvo.tbl_logs_auditoria
  for select to authenticated
  using (rsuelvo.fn_es_service_role()
    or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN'));

-- ── 3. EXECUTE: fuera PUBLIC, solo authenticated + service_role ─────────────
-- (incluye DROP del overload 8-params de fn_alta heredado de mig 58)
drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer);
revoke execute on function rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio) from public;
grant execute on function rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio) to authenticated, service_role;

revoke execute on function rsuelvo.fn_cambiar_estado_comercio(uuid, rsuelvo.estado_comercio) from public;
grant execute on function rsuelvo.fn_cambiar_estado_comercio(uuid, rsuelvo.estado_comercio) to authenticated, service_role;

revoke execute on function rsuelvo.fn_solicitar_creditos(uuid, text) from public;
grant execute on function rsuelvo.fn_solicitar_creditos(uuid, text) to authenticated, service_role;

revoke execute on function rsuelvo.fn_registrar_comprobante(uuid, uuid, text, text, numeric, timestamptz, text, text, rsuelvo.estado_comprobante, uuid, text) from public;
grant execute on function rsuelvo.fn_registrar_comprobante(uuid, uuid, text, text, numeric, timestamptz, text, text, rsuelvo.estado_comprobante, uuid, text) to authenticated, service_role;

-- ── 4. fn_alta: bonus>=0 (re-aplicada identica a mig 62 + guard) ───────
-- ── fn_alta_comercio: p_estado + coercion staff ──────────────────────────────
create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100,
  p_estado rsuelvo.estado_comercio default 'ACTIVO'
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT') then
    v_estado_final := 'PENDIENTE_APROBACION';
  else
    raise exception 'solo staff autorizado';
  end if;

  if v_estado_final not in ('ACTIVO', 'PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'estado_invalido');
  end if;

  if coalesce(p_bonus, 0) < 0 then
    return jsonb_build_object('ok', false, 'codigo', 'bonus_invalido');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;

  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final)
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', 'DESCONECTADO', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus
  );
end;
$fn$;



-- ── 5. fn_cambiar_estado: maquina de estados ─────────────────────────────────
create or replace function rsuelvo.fn_cambiar_estado_comercio(
  p_id_comercio uuid,
  p_estado rsuelvo.estado_comercio
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_anterior rsuelvo.estado_comercio;
  v_ok boolean := false;
begin
  if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  select estado into v_anterior
  from rsuelvo.tbl_comercios where id_comercio = p_id_comercio;

  if v_anterior is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;

  if v_anterior = p_estado then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cambio', 'estado', v_anterior);
  end if;

  v_ok := (v_anterior = 'PENDIENTE_APROBACION' and p_estado in ('ACTIVO','CANCELADO'))
       or (v_anterior = 'ACTIVO' and p_estado in ('SUSPENDIDO','BLOQUEADO','CANCELADO'))
       or (v_anterior = 'SUSPENDIDO' and p_estado in ('ACTIVO','BLOQUEADO','CANCELADO'))
       or (v_anterior = 'BLOQUEADO' and p_estado in ('ACTIVO','SUSPENDIDO'))
       or (v_anterior = 'CANCELADO' and p_estado = 'ACTIVO');

  if not v_ok then
    return jsonb_build_object('ok', false, 'codigo', 'transicion_invalida',
      'anterior', v_anterior, 'nuevo', p_estado);
  end if;

  update rsuelvo.tbl_comercios
  set estado = p_estado, updated_at = now()
  where id_comercio = p_id_comercio;

  return jsonb_build_object('ok', true, 'anterior', v_anterior, 'nuevo', p_estado);
end;
$fn$;

-- ── 6. fn_resolver_compra: p_motivo (nueva firma 3 params; DROP vieja abajo) ─
create or replace function rsuelvo.fn_resolver_compra_creditos(
  p_id_compra uuid,
  p_decision text,
  p_motivo text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT');
  v_c record;
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not rsuelvo.fn_es_admin_comercio(v_c.id_comercio) then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        motivo_rechazo = nullif(trim(coalesce(p_motivo,'')), ''),
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  if v_cuenta is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cuenta');
  end if;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$fn$;

drop function if exists rsuelvo.fn_resolver_compra_creditos(uuid, text);
-- ═══ MIG 67 (aplicada 2026-09-17, en 3 partes + fix AJUSTE con signo) ═══
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
-- ═══ MIG 68 (aplicada 2026-09-17) ═══
-- 68_usuarios_staff.sql
-- Auditoria: CRUD global usuarios (superadmin) + invariantes de vinculos.
-- HU roles expandidos. Protegidos: SUPERADMIN (no editar/asignar/desactivar),
-- ultimo superadmin implicito (solo existe 1: el dueño).

-- ── fn_editar_usuario ───────────────────────────────────────────────────────
create or replace function rsuelvo.fn_editar_usuario(
  p_id_usuario uuid,
  p_nombre text default null,
  p_apellido text default null,
  p_telefono text default null,
  p_activo boolean default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_tiene_super boolean;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.activo
      and r.codigo = 'ROLE_SUPERADMIN'
  ) into v_tiene_super;

  if v_tiene_super then
    return jsonb_build_object('ok', false, 'codigo', 'protegido');
  end if;

  update tbl_usuarios
  set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
      apellido = coalesce(nullif(trim(p_apellido), ''), apellido),
      telefono = coalesce(nullif(trim(p_telefono), ''), telefono),
      activo = coalesce(p_activo, activo),
      updated_at = now()
  where id_usuario = p_id_usuario;

  if coalesce(p_activo, true) = false then
    update tbl_usuario_comercio set activo = false
    where id_usuario = p_id_usuario and activo;
  end if;

  return jsonb_build_object('ok', true, 'id_usuario', p_id_usuario);
end;
$fn$;

-- ── fn_gestionar_vinculo ────────────────────────────────────────────────────
create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,
  p_id_comercio uuid,
  p_id_rol smallint,
  p_id_sucursal uuid default null,
  p_accion text default 'CREAR'
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_acc text := upper(trim(coalesce(p_accion,'CREAR')));
  v_codigo text;
  v_estado text;
  v_existente uuid;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  select codigo into v_codigo from tbl_roles where id_rol = p_id_rol;
  if v_codigo is null then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;
  if v_codigo = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'protegido');
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  if v_acc = 'DESACTIVAR' then
    select id into v_existente from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and activo;
    if v_existente is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set activo = false where id = v_existente;
    return jsonb_build_object('ok', true, 'nuevo', 'DESACTIVADO');
  end if;

  if v_acc != 'CREAR' then
    return jsonb_build_object('ok', false, 'codigo', 'accion_invalida');
  end if;

  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible', 'estado', v_estado);
  end if;

  if p_id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = p_id_sucursal
                       and id_comercio = p_id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  if v_codigo = 'ROLE_LOGISTICS_AGENT' and p_id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;

  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.activo
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  select id into v_existente from tbl_usuario_comercio
  where id_usuario = p_id_usuario and id_comercio = p_id_comercio
    and id_rol = p_id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000');
  if v_existente is not null then
    update tbl_usuario_comercio set activo = true where id = v_existente;
    return jsonb_build_object('ok', true, 'reactivado', true);
  end if;

  insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, activo)
  values (p_id_usuario, p_id_comercio, p_id_rol, p_id_sucursal, true);

  return jsonb_build_object('ok', true, 'reactivado', false);
end;
$fn$;

revoke execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) from public;
grant execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) to authenticated, service_role;

revoke execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text) from public;
grant execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text) to authenticated, service_role;
-- ═══ MIG 69 (aplicada 2026-09-18, +fix sucursal-NULL solo admin) ═══
-- 69_staff_sistema.sql
-- Staff sin comercio (opcion B): tenant sistema SYS (BLOQUEADO, sin flujos) +
-- SUPPORT fuera de fn_tiene_acceso_sucursal + lecturas staff en tablas operativas.
-- HU roles expandidos. PROD 2026-09-18: SYS=439b6482-494a-4420-bcae-27d628131bf3.

-- ── 1. Tenant sistema (idempotente; solo fila base, sin config/cuenta/sucursal)
insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, estado)
values ('SYS', 'RSUELVO Plataforma (sistema)', 'BLOQUEADO')
on conflict (codigo_tienda) do nothing;

-- ── 2. SUPPORT fuera del bypass de sucursal ─────────────────────────────────
create or replace function rsuelvo.fn_tiene_acceso_sucursal(p_id_comercio uuid, p_id_sucursal uuid)
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        where u.auth_user_id=auth.uid()
          and u.activo
          and uc.activo
          and uc.id_comercio=p_id_comercio
          and (
            (uc.id_sucursal is null
              and exists (
                select 1 from tbl_roles r2
                where r2.id_rol = uc.id_rol
                  and r2.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPERADMIN')))
            or uc.id_sucursal=p_id_sucursal
            or exists (
              select 1
              from tbl_roles r
              where r.id_rol=uc.id_rol
                and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPERADMIN')
            )
          )
      );
$fn$;

-- ── 3. Lecturas staff en operativas (SELECT, sin escritura) ─────────────────
drop policy if exists staff_read on rsuelvo.tbl_pedidos;
create policy staff_read on rsuelvo.tbl_pedidos
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_reservas;
create policy staff_read on rsuelvo.tbl_reservas
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_lista_espera;
create policy staff_read on rsuelvo.tbl_lista_espera
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_clientes;
create policy staff_read on rsuelvo.tbl_clientes
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_envios;
create policy staff_read on rsuelvo.tbl_envios
  for select to authenticated using (rsuelvo.fn_lectura_staff());
-- ═══ MIG 70 (aplicada 2026-09-18: tabla+RLS+RPC+GRANT) ═══
-- 70_solicitudes_alta.sql
-- Postulacion publica desde la landing (contrato web docs/solicitudes-backend.md):
-- entidad nueva, sin reutilizar enums; RLS niega todo salvo superadmin-lectura;
-- resolucion una sola vez via RPC. El alta posterior sigue el flujo D17 normal.

do $$ begin
  create type rsuelvo.estado_solicitud_alta as enum ('PENDIENTE','APROBADA','RECHAZADA');
exception when duplicate_object then null; end $$;

create table if not exists rsuelvo.tbl_solicitudes_alta (
  id_solicitud uuid primary key default gen_random_uuid(),
  nombre text not null,
  telefono text not null,
  tienda text not null,
  mensaje text not null,
  plan text,
  origen text not null default 'landing',
  estado rsuelvo.estado_solicitud_alta not null default 'PENDIENTE',
  idempotency_key text not null unique,
  payload_hash text not null,
  ip_origen text,
  id_revisor uuid references rsuelvo.tbl_usuarios(id_usuario),
  motivo text,
  fecha_revision timestamptz,
  created_at timestamptz not null default now()
);

alter table rsuelvo.tbl_solicitudes_alta enable row level security;

drop policy if exists solicitudes_superadmin_select on rsuelvo.tbl_solicitudes_alta;
create policy solicitudes_superadmin_select on rsuelvo.tbl_solicitudes_alta
  for select to authenticated using (rsuelvo.fn_es_superadmin());

-- Sin policies de escritura: solo service_role (EF) escribe. UPDATE via RPC.
create or replace function rsuelvo.fn_resolver_solicitud_alta(
  p_id_solicitud uuid,
  p_aprueba boolean,
  p_motivo text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_estado rsuelvo.estado_solicitud_alta;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  select estado into v_estado
  from tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
  end if;
  if v_estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_estado);
  end if;

  update tbl_solicitudes_alta
  set estado = case when p_aprueba then 'APROBADA'::rsuelvo.estado_solicitud_alta else 'RECHAZADA'::rsuelvo.estado_solicitud_alta end,
      motivo = nullif(trim(coalesce(p_motivo,'')), ''),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_solicitud = p_id_solicitud;

  return jsonb_build_object('ok', true,
    'nuevo', case when p_aprueba then 'APROBADA' else 'RECHAZADA' end);
end;
$fn$;

revoke execute on function rsuelvo.fn_resolver_solicitud_alta(uuid, boolean, text) from public;
grant execute on function rsuelvo.fn_resolver_solicitud_alta(uuid, boolean, text) to authenticated, service_role;

-- GRANTs (PostgREST los exige antes que RLS; RLS sigue negando no-superadmin)
grant all on rsuelvo.tbl_solicitudes_alta to anon, authenticated, service_role;
-- ═══ MIG 71 (aplicada 2026-09-18: reserva+sugerir+consumo) ═══
-- 71_codigo_solicitud.sql
-- Codigo de 3 caracteres elegible desde la solicitud: propuesta + reserva +
-- sugerencias + consumo en el alta + linaje. HU D17 extension.

-- ── Solicitud: codigo propuesto (reserva = UNIQUE parcial en PENDIENTE/APROBADA)
alter table rsuelvo.tbl_solicitudes_alta
  add column if not exists codigo_sugerido text;

create unique index if not exists uq_solicitud_codigo_reserva
  on rsuelvo.tbl_solicitudes_alta (codigo_sugerido)
  where codigo_sugerido is not null and estado in ('PENDIENTE','APROBADA');

-- ── Linaje comercio <- solicitud
alter table rsuelvo.tbl_comercios
  add column if not exists id_solicitud uuid references rsuelvo.tbl_solicitudes_alta(id_solicitud);

-- ── Normalizacion de codigo (mayus, sin O, 3 alnum). NULL si invalido.
create or replace function rsuelvo.fn_normalizar_codigo(p_codigo text)
returns text
language sql immutable
set search_path to 'rsuelvo', 'public'
as $fn$
  select case
    when upper(regexp_replace(coalesce(trim(p_codigo),''), '[^A-Z0-9]', '', 'gi')) ~ '^[A-Z0-9]{3}$'
     and position('O' in upper(regexp_replace(coalesce(trim(p_codigo),''), '[^A-Z0-9]', '', 'gi'))) = 0
    then upper(regexp_replace(coalesce(trim(p_codigo),''), '[^A-Z0-9]', '', 'gi'))
  end;
$fn$;

-- ── Sugerencias (anonimo: sin auth, solo lectura). Max 5.
create or replace function rsuelvo.fn_sugerir_codigo(p_base text)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_clean text := upper(regexp_replace(coalesce(trim(p_base),''), '[^A-Z0-9]', '', 'gi'));
  v_base text := '';
  v_out text[] := '{}';
  v_cand text;
  v_letras constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ123456789';
  i integer;
  j integer;
begin
  -- base: 3 exactos validos, o primeros 3 si vienen de mas (sin O); si no, ABC
  if v_clean ~ '^[A-Z0-9]{3}$' and position('O' in v_clean) = 0 then
    v_base := v_clean;
  elsif length(v_clean) >= 3
    and substr(v_clean, 1, 3) ~ '^[A-Z0-9]{3}$'
    and position('O' in substr(v_clean, 1, 3)) = 0 then
    v_base := substr(v_clean, 1, 3);
  else
    v_base := 'ABC';
  end if;

  -- 1. la base si esta libre (comercios + reservas vivas)
  if not exists (select 1 from tbl_comercios where codigo_tienda = v_base)
     and not exists (select 1 from tbl_solicitudes_alta
                     where codigo_sugerido = v_base and estado in ('PENDIENTE','APROBADA')) then
    v_out := v_out || v_base;
  end if;

  -- 2. variantes cambiando ultimo char
  for j in 1..length(v_letras) loop
    exit when array_length(v_out, 1) >= 5;
    v_cand := substr(v_base, 1, 2) || substr(v_letras, j, 1);
    if v_cand = v_base then continue; end if;
    if not exists (select 1 from tbl_comercios where codigo_tienda = v_cand)
       and not exists (select 1 from tbl_solicitudes_alta
                       where codigo_sugerido = v_cand and estado in ('PENDIENTE','APROBADA')) then
      v_out := v_out || v_cand;
    end if;
  end loop;

  -- 3. variantes cambiando segundo char (si faltan)
  for j in 1..length(v_letras) loop
    exit when array_length(v_out, 1) >= 5;
    v_cand := substr(v_base, 1, 1) || substr(v_letras, j, 1) || substr(v_base, 3, 1);
    if v_cand = any (v_out) then continue; end if;
    if not exists (select 1 from tbl_comercios where codigo_tienda = v_cand)
       and not exists (select 1 from tbl_solicitudes_alta
                       where codigo_sugerido = v_cand and estado in ('PENDIENTE','APROBADA')) then
      v_out := v_out || v_cand;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'base', v_base, 'sugerencias', to_jsonb(v_out));
end;
$fn$;

revoke execute on function rsuelvo.fn_sugerir_codigo(text) from public;
grant execute on function rsuelvo.fn_sugerir_codigo(text) to anon, authenticated, service_role;

-- ── Alta consume reserva (p_id_solicitud opcional) ───────────────────────────
-- NOTA: re-aplica fn completa identica a mig 66 + bloque solicitud (parche abajo).
create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100,
  p_estado rsuelvo.estado_comercio default 'ACTIVO',
  p_id_solicitud uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_sol record;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT') then
    v_estado_final := 'PENDIENTE_APROBACION';
  else
    raise exception 'solo staff autorizado';
  end if;

  if v_estado_final not in ('ACTIVO', 'PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'estado_invalido');
  end if;

  if coalesce(p_bonus, 0) < 0 then
    return jsonb_build_object('ok', false, 'codigo', 'bonus_invalido');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if p_id_solicitud is not null then
    select id_solicitud, codigo_sugerido, estado into v_sol
    from rsuelvo.tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
    if not found then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
    end if;
    if v_sol.estado != 'APROBADA' then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_aprobada');
    end if;
    if v_sol.codigo_sugerido is null then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_sin_codigo');
    end if;
    if exists (select 1 from rsuelvo.tbl_comercios where id_solicitud = p_id_solicitud) then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_consumida');
    end if;
    if upper(trim(p_codigo_tienda)) != v_sol.codigo_sugerido then
      return jsonb_build_object('ok', false, 'codigo', 'codigo_mismatch');
    end if;
    v_codigo := v_sol.codigo_sugerido;
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;



  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado, id_solicitud)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final, p_id_solicitud)
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', 'DESCONECTADO', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus,
    'id_solicitud', p_id_solicitud
  );
end;
$fn$;





drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio);
-- ═══ MIG 72 (aplicada 2026-09-18: cajero RPC + CHECK <>) ═══
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
-- ═══ MIG 73 (aplicada 2026-09-18: sysadmin solicitudes) ═══
-- 73_solicitudes_sysadmin.sql
-- SysAdmin ve y resuelve solicitudes igual que SuperAdmin (solo esos dos roles).

create policy solicitudes_staff_select on rsuelvo.tbl_solicitudes_alta
  for select to authenticated
  using (rsuelvo.fn_es_superadmin() or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN'));

create or replace function rsuelvo.fn_resolver_solicitud_alta(
  p_id_solicitud uuid,
  p_aprueba boolean,
  p_motivo text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_estado rsuelvo.estado_solicitud_alta;
begin
  if not (fn_es_service_role() or fn_es_superadmin()
          or fn_tiene_rol('ROLE_SYSADMIN')) then
    raise exception 'solo staff autorizado';
  end if;

  select estado into v_estado
  from tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
  end if;
  if v_estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_estado);
  end if;

  update tbl_solicitudes_alta
  set estado = case when p_aprueba then 'APROBADA'::rsuelvo.estado_solicitud_alta else 'RECHAZADA'::rsuelvo.estado_solicitud_alta end,
      motivo = nullif(trim(coalesce(p_motivo,'')), ''),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_solicitud = p_id_solicitud;

  return jsonb_build_object('ok', true,
    'nuevo', case when p_aprueba then 'APROBADA' else 'RECHAZADA' end);
end;
$fn$;
-- ═══ MIG 63 addendum (depositos_dueno_delete, aplicada 2026-09-18) ═══

-- 2026-09-18: dueño elimina sus depositos (reemplazo de comprobante)
drop policy if exists depositos_dueno_delete on storage.objects;
create policy depositos_dueno_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'depositos-creditos'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_es_admin_comercio(split_part(name, '/', 1)::uuid));
-- ═══ MIG 74 (aplicada 2026-09-18: QR paquetes) ═══
-- 74_qr_paquetes.sql
-- SuperAdmin asocia un QR a cada paquete; el comerciante lo ve al solicitar
-- segun el paquete elegido. QR plataforma en qr-pagos/paquetes/*.png.

alter table rsuelvo.tbl_paquetes_creditos
  add column if not exists qr_path text;

drop policy if exists paquetes_superadmin_update on rsuelvo.tbl_paquetes_creditos;
create policy paquetes_superadmin_update on rsuelvo.tbl_paquetes_creditos
  for update to authenticated
  using (rsuelvo.fn_es_superadmin())
  with check (rsuelvo.fn_es_superadmin());

drop policy if exists qr_paquetes_public_select on storage.objects;
create policy qr_paquetes_public_select on storage.objects
  for select to authenticated
  using (bucket_id = 'qr-pagos' and name like 'paquetes/%');
-- ═══ MIG 75 (aplicada 2026-09-18: email solicitud) ═══
-- 75_solicitud_email.sql
-- La solicitud suma email (opcional, para invitar al aprobar sin pedirlo despues).

alter table rsuelvo.tbl_solicitudes_alta
  add column if not exists email text;
-- ═══ MIG 76 (aplicada 2026-09-19: backend identity + pnid universal) ═══
-- 76_backend_identity_pnid.sql
-- INCIDENTE 2026-09-19: la mig 61 (correcta) dejo sin identidad a las conexiones
-- directas a PG (n8n usa usuario postgres sin JWT) -> todo PG node con guard de
-- acceso moria con 'Sin acceso'. Fix: postgres/service_role por current_user son
-- backend (quien tiene esa clave ya puede bypassear todo; PostgREST sigue con
-- authenticator -> JWT, sin cambios). + pnid universal por defecto en altas.

create or replace function rsuelvo.fn_es_service_role()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select coalesce(auth.jwt()->>'role', '') = 'service_role'
      or current_user in ('postgres', 'service_role');
$fn$;

create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100,
  p_estado rsuelvo.estado_comercio default 'ACTIVO',
  p_id_solicitud uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_sol record;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT') then
    v_estado_final := 'PENDIENTE_APROBACION';
  else
    raise exception 'solo staff autorizado';
  end if;

  if v_estado_final not in ('ACTIVO', 'PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'estado_invalido');
  end if;

  if coalesce(p_bonus, 0) < 0 then
    return jsonb_build_object('ok', false, 'codigo', 'bonus_invalido');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if p_id_solicitud is not null then
    select id_solicitud, codigo_sugerido, estado into v_sol
    from rsuelvo.tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
    if not found then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
    end if;
    if v_sol.estado != 'APROBADA' then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_aprobada');
    end if;
    if v_sol.codigo_sugerido is null then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_sin_codigo');
    end if;
    if exists (select 1 from rsuelvo.tbl_comercios where id_solicitud = p_id_solicitud) then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_consumida');
    end if;
    if upper(trim(p_codigo_tienda)) != v_sol.codigo_sugerido then
      return jsonb_build_object('ok', false, 'codigo', 'codigo_mismatch');
    end if;
    v_codigo := v_sol.codigo_sugerido;
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;



  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado, id_solicitud)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final, p_id_solicitud)
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  -- D16: numero universal; pnid universal por defecto (por comercio a futuro)
  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, provider_phone_number_id, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', '1275143265687773', 'DESCONECTADO', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus,
    'id_solicitud', p_id_solicitud
  );
end;
$fn$;






drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio);
-- backfill pnid universal donde falta
-- (UNIQUE provider_phone_number_id es anti-D16 como el de numero en mig 60: fuera)
alter table rsuelvo.tbl_canal_whatsapp drop constraint if exists tbl_canal_whatsapp_provider_phone_number_id_key;
update rsuelvo.tbl_canal_whatsapp set provider_phone_number_id = '1275143265687773' where provider_phone_number_id is null;
-- ═══ MIG 77 (aplicada 2026-09-19: metodo default en alta) ═══
-- 77_alta_metodo_default.sql
-- Alta crea metodo QR por defecto (fn_generar_cobro lo exige).

create or replace function rsuelvo.fn_alta_comercio(
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null,
  p_reserva_min integer default 10,
  p_verificacion_automatica boolean default false,
  p_bonus integer default 100,
  p_estado rsuelvo.estado_comercio default 'ACTIVO',
  p_id_solicitud uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_sol record;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') or rsuelvo.fn_tiene_rol('ROLE_SUPPORT') then
    v_estado_final := 'PENDIENTE_APROBACION';
  else
    raise exception 'solo staff autorizado';
  end if;

  if v_estado_final not in ('ACTIVO', 'PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'estado_invalido');
  end if;

  if coalesce(p_bonus, 0) < 0 then
    return jsonb_build_object('ok', false, 'codigo', 'bonus_invalido');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if p_id_solicitud is not null then
    select id_solicitud, codigo_sugerido, estado into v_sol
    from rsuelvo.tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
    if not found then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
    end if;
    if v_sol.estado != 'APROBADA' then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_aprobada');
    end if;
    if v_sol.codigo_sugerido is null then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_sin_codigo');
    end if;
    if exists (select 1 from rsuelvo.tbl_comercios where id_solicitud = p_id_solicitud) then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_consumida');
    end if;
    if upper(trim(p_codigo_tienda)) != v_sol.codigo_sugerido then
      return jsonb_build_object('ok', false, 'codigo', 'codigo_mismatch');
    end if;
    v_codigo := v_sol.codigo_sugerido;
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;



  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado, id_solicitud)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final, p_id_solicitud)
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  -- D16: numero universal; pnid universal por defecto (por comercio a futuro)
  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, provider_phone_number_id, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', '1275143265687773', 'DESCONECTADO', true);

  -- metodo de pago por defecto (fn_generar_cobro lo exige)
  insert into rsuelvo.tbl_metodos_pago (id_comercio, nombre, tipo, activo)
  values (v_comercio, 'QR Estático', 'QR', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus,
    'id_solicitud', p_id_solicitud
  );
end;
$fn$;






drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio);
-- backfill pnid universal donde falta
-- (UNIQUE provider_phone_number_id es anti-D16 como el de numero en mig 60: fuera)
alter table rsuelvo.tbl_canal_whatsapp drop constraint if exists tbl_canal_whatsapp_provider_phone_number_id_key;
update rsuelvo.tbl_canal_whatsapp set provider_phone_number_id = '1275143265687773' where provider_phone_number_id is null;

drop function if exists rsuelvo.fn_alta_comercio(text, text, text, text, text, integer, boolean, integer, rsuelvo.estado_comercio);
-- ═══ MIG 78 (aplicada 2026-09-19: transportadoras tenant) ═══
-- 78_transportadoras_tenant.sql
-- Opcion B: transportadoras por comercio (NULL = global/plantilla).
-- RLS: globales visibles para autenticados; propias full para el dueño.

alter table rsuelvo.tbl_transportadoras
  add column if not exists id_comercio uuid references rsuelvo.tbl_comercios(id_comercio);

drop policy if exists transportadoras_read on rsuelvo.tbl_transportadoras;
drop policy if exists transportadoras_manage on rsuelvo.tbl_transportadoras;

create policy transportadoras_read on rsuelvo.tbl_transportadoras
  for select to authenticated
  using (id_comercio is null or rsuelvo.fn_tiene_acceso_comercio(id_comercio));

create policy transportadoras_manage on rsuelvo.tbl_transportadoras
  for all to authenticated
  using (id_comercio is not null and rsuelvo.fn_es_admin_comercio(id_comercio))
  with check (id_comercio is not null and rsuelvo.fn_es_admin_comercio(id_comercio));

-- GRANTs (PostgREST los exige antes que RLS)
grant all on rsuelvo.tbl_transportadoras to anon, authenticated, service_role;
-- ═══ MIG 79 (aplicada 2026-09-21: invitaciones seguras IAM-1) ═══
-- 79_invitaciones_seguras.sql
-- IAM-1 backend. Implementa 01-Arquitectura/D-IAM-INVITACIONES.md.
-- Supabase es el unico secreto; tbl_invitaciones = contexto/estado (sin tokens).
-- N-4 (cajero_multiplo) NO se toca: va a IAM-2.

-- ── 1. lifecycle minimo en tbl_usuario_comercio (aditivo) ──
alter table rsuelvo.tbl_usuario_comercio
  add column if not exists estado text not null default 'ACTIVE',
  add column if not exists invited_by uuid null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  add column if not exists accepted_at timestamptz null;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'uc_estado_chk') then
    alter table rsuelvo.tbl_usuario_comercio
      add constraint uc_estado_chk check (estado in ('ACTIVE','SUSPENDED','REVOKED'));
  end if;
end $$;

-- ── 2. tbl_invitaciones (contexto/estado, JAMAS secretos) ──
create table if not exists rsuelvo.tbl_invitaciones (
  id uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete cascade,
  id_rol smallint not null references rsuelvo.tbl_roles(id_rol),
  id_sucursal uuid null references rsuelvo.tbl_sucursales(id_sucursal) on delete set null,
  email text not null,
  invited_by uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  estado text not null default 'PENDIENTE',
  expira_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint invit_estado_chk check (estado in ('PENDIENTE','ACEPTADA','VENCIDA','REVOCADA'))
);
-- Idempotencia sobre PENDIENTE (C-02): el historial se conserva siempre
create unique index if not exists invit_pendiente_unica
  on rsuelvo.tbl_invitaciones (lower(email), id_comercio) where estado = 'PENDIENTE';

-- deny-by-default: sin policies -> solo service_role + SECURITY DEFINER
alter table rsuelvo.tbl_invitaciones enable row level security;
grant all on rsuelvo.tbl_invitaciones to service_role;

-- ── 3. fn_mis_invitaciones_pendientes (descubrimiento server-side) ──
create or replace function rsuelvo.fn_mis_invitaciones_pendientes()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_email text;
begin
  select lower(email) into v_email from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_email is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  return jsonb_build_object('ok', true, 'invitaciones', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_invitacion', i.id, 'id_comercio', i.id_comercio,
      'comercio', c.nombre_comercial, 'id_rol', i.id_rol,
      'rol', r.codigo, 'id_sucursal', i.id_sucursal,
      'sucursal', s.nombre, 'estado', i.estado, 'expira_at', i.expira_at
    ))
    from tbl_invitaciones i
    join tbl_comercios c on c.id_comercio = i.id_comercio
    join tbl_roles r on r.id_rol = i.id_rol
    left join tbl_sucursales s on s.id_sucursal = i.id_sucursal
    where lower(i.email) = v_email and i.estado = 'PENDIENTE' and i.expira_at > now()
  ), '[]'::jsonb));
end;
$fn$;
revoke execute on function rsuelvo.fn_mis_invitaciones_pendientes() from public;
grant execute on function rsuelvo.fn_mis_invitaciones_pendientes() to authenticated, service_role;

-- ── 4. fn_aceptar_invitacion (identidad SOLO del JWT) ──
create or replace function rsuelvo.fn_aceptar_invitacion(p_id_invitacion uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email text;
  v_inv record;
  v_estado_comercio text;
  v_codigo_rol text;
  v_vinculo uuid;
  v_cajeros integer;
begin
  select id_usuario, lower(email) into v_usuario, v_email from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;

  select * into v_inv from tbl_invitaciones where id = p_id_invitacion for update;
  if v_inv.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_existe');
  end if;
  if lower(v_inv.email) != v_email then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_ajena');
  end if;
  if v_inv.estado != 'PENDIENTE' or v_inv.expira_at <= now() then
    if v_inv.estado = 'PENDIENTE' then
      update tbl_invitaciones set estado = 'VENCIDA' where id = p_id_invitacion;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_vencida');
  end if;

  select estado into v_estado_comercio from tbl_comercios where id_comercio = v_inv.id_comercio;
  if v_estado_comercio is null or v_estado_comercio not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible');
  end if;

  select codigo into v_codigo_rol from tbl_roles where id_rol = v_inv.id_rol;
  if v_codigo_rol is null or v_codigo_rol = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;
  if v_inv.id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = v_inv.id_sucursal
                       and id_comercio = v_inv.id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;
  if v_codigo_rol = 'ROLE_LOGISTICS_AGENT' and v_inv.id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;
  -- N-4 intacto hasta IAM-2: regla global vigente
  if v_codigo_rol = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.activo and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  -- Idempotencia: vinculo equivalente ya activo -> aceptar sin duplicar
  select id into v_vinculo from tbl_usuario_comercio
  where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
    and id_rol = v_inv.id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
    and activo;
  if v_vinculo is null then
    insert into tbl_usuario_comercio
      (id_usuario, id_comercio, id_rol, id_sucursal, activo, estado, invited_by, accepted_at)
    values
      (v_usuario, v_inv.id_comercio, v_inv.id_rol, v_inv.id_sucursal, true, 'ACTIVE', v_inv.invited_by, now());
  end if;

  update tbl_invitaciones set estado = 'ACEPTADA', accepted_at = now() where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_aceptada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true, 'id_comercio', v_inv.id_comercio);
end;
$fn$;
revoke execute on function rsuelvo.fn_aceptar_invitacion(uuid) from public;
grant execute on function rsuelvo.fn_aceptar_invitacion(uuid) to authenticated, service_role;

-- ── 5. fn_revocar_invitacion (invitador / admin comercio / superadmin) ──
create or replace function rsuelvo.fn_revocar_invitacion(p_id_invitacion uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_inv record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;

  select * into v_inv from tbl_invitaciones where id = p_id_invitacion for update;
  if v_inv.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_existe');
  end if;
  if v_inv.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_pendiente');
  end if;
  if v_inv.invited_by != v_usuario
     and not fn_es_admin_comercio(v_inv.id_comercio)
     and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'sin_permiso');
  end if;

  update tbl_invitaciones set estado = 'REVOCADA' where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_revocada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_revocar_invitacion(uuid) from public;
grant execute on function rsuelvo.fn_revocar_invitacion(uuid) to authenticated, service_role;
-- ═══ MIG 80 (aplicada 2026-09-21: invited_by nullable) ═══
-- 80_fix_invited_by_nullable.sql
-- IAM-1 parche revision ChatGPT: invited_by nullable (auditoria historica
-- preservada con ON DELETE SET NULL). No reescribe mig 79.

alter table rsuelvo.tbl_invitaciones alter column invited_by drop not null;
-- ═══ MIG 81 (aplicada 2026-09-22: membership lifecycle + N-4 todos los paths) ═══
-- 81_membership_lifecycle.sql
-- IAM-2B backend. Implementa D-IAM-MEMBERSHIP.md rev2 + CAMBIAR atomico.
-- Depende de IAM-2A Flutter verificado (1160232). NO reescribe migs 68/79/80.

-- ── 1. anti-duplicado no-terminal (preflight limpio 2026-09-22) ──
create unique index if not exists uc_tupla_vigente_unica
  on rsuelvo.tbl_usuario_comercio
    (id_usuario, id_comercio, id_rol, coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000'))
  where estado in ('ACTIVE', 'SUSPENDED');

-- ── 2. trigger canonico activo = (estado = 'ACTIVE') ──
create or replace function rsuelvo.fn_uc_sincronizar_activo()
returns trigger
language plpgsql
set search_path to 'rsuelvo', 'public'
as $fn$
begin
  new.activo := (new.estado = 'ACTIVE');
  new.updated_at := now();
  return new;
end;
$fn$;
drop trigger if exists trg_uc_sincronizar_activo on rsuelvo.tbl_usuario_comercio;
create trigger trg_uc_sincronizar_activo
  before insert or update on rsuelvo.tbl_usuario_comercio
  for each row execute function rsuelvo.fn_uc_sincronizar_activo();

-- ── 3. fn_gestionar_vinculo: N-4 por comercio + SUSPENDER/REVOCAR/CAMBIAR ──
create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,
  p_id_comercio uuid,
  p_id_rol smallint,
  p_id_sucursal uuid default null,
  p_accion text default 'CREAR',
  p_rol_nuevo smallint default null,
  p_sucursal_nueva uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_acc text := upper(trim(coalesce(p_accion,'CREAR')));
  v_codigo text;
  v_estado text;
  v_row record;
  v_nuevo_rol smallint;
  v_nueva_suc uuid;
  v_nuevo_codigo text;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if v_acc = 'CAMBIAR' then
    -- ── reemplazo atomico: (p_id_rol,p_id_sucursal)=viejo, (p_rol_nuevo,p_sucursal_nueva)=nuevo ──
    if p_rol_nuevo is null then
      return jsonb_build_object('ok', false, 'codigo', 'falta_rol_nuevo');
    end if;
    select * into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;

    select codigo into v_nuevo_codigo from tbl_roles where id_rol = p_rol_nuevo;
    if v_nuevo_codigo is null or v_nuevo_codigo = 'ROLE_SUPERADMIN' then
      return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
    end if;
    if p_sucursal_nueva is not null
       and not exists (select 1 from tbl_sucursales
                       where id_sucursal = p_sucursal_nueva
                         and id_comercio = p_id_comercio and activo) then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
    end if;
    if v_nuevo_codigo = 'ROLE_LOGISTICS_AGENT' and p_sucursal_nueva is null then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
    end if;
    -- N-4 por comercio (solo si el destino es cajero y no lo era ya en este comercio)
    if v_nuevo_codigo = 'ROLE_TENANT_CASHIER' and p_rol_nuevo != v_row.id_rol then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER';
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;

    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;

    -- reutiliza semantica CREAR sobre el destino (misma transaccion)
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_rol_nuevo
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED'
    for update;
    if v_row.id is not null then
      update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
    else
      begin
        insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
        values (p_id_usuario, p_id_comercio, p_rol_nuevo, p_sucursal_nueva, 'ACTIVE');
      exception when unique_violation then
        update tbl_usuario_comercio set estado = 'ACTIVE'
        where id_usuario = p_id_usuario and id_comercio = p_id_comercio
          and id_rol = p_rol_nuevo
          and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
            = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
          and estado = 'SUSPENDED';
      end;
    end if;

    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
  end if;

  -- ── acciones simples ──
  if v_acc in ('DESACTIVAR','SUSPENDER') then
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'ACTIVE'
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_suspendido', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'SUSPENDIDO');
  end if;

  if v_acc = 'REVOCAR' then
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'REVOKED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_revocado', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'REVOCADO');
  end if;

  if v_acc != 'CREAR' then
    return jsonb_build_object('ok', false, 'codigo', 'accion_invalida');
  end if;

  select codigo into v_codigo from tbl_roles where id_rol = p_id_rol;
  if v_codigo is null or v_codigo = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible', 'estado', v_estado);
  end if;

  if p_id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = p_id_sucursal
                       and id_comercio = p_id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  if v_codigo = 'ROLE_LOGISTICS_AGENT' and p_id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;

  -- N-4 por comercio + vigentes (rev2)
  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
      and uc.estado in ('ACTIVE','SUSPENDED')
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      -- idempotente si es la misma tupla vigente
      select id into v_row from tbl_usuario_comercio
      where id_usuario = p_id_usuario and id_comercio = p_id_comercio
        and id_rol = p_id_rol
        and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
          = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
        and estado in ('ACTIVE','SUSPENDED');
      if v_row.id is not null then
        update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
        return jsonb_build_object('ok', true, 'reactivado', true);
      end if;
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  -- semantica CREAR: ACTIVE→idempotente; SUSPENDED→misma fila; solo-REVOKED→nueva
  select id, estado into v_row from tbl_usuario_comercio
  where id_usuario = p_id_usuario and id_comercio = p_id_comercio
    and id_rol = p_id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED')
  for update;
  if v_row.id is not null then
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
    return jsonb_build_object('ok', true, 'reactivado', v_row.estado = 'SUSPENDED');
  end if;

  begin
    insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
    values (p_id_usuario, p_id_comercio, p_id_rol, p_id_sucursal, 'ACTIVE');
  exception when unique_violation then
    update tbl_usuario_comercio set estado = 'ACTIVE'
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED';
  end;
  return jsonb_build_object('ok', true, 'reactivado', false);
end;
$fn$;

revoke execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text, smallint, uuid) from public;
grant execute on function rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text, smallint, uuid) to authenticated, service_role;

-- ── 4. fn_aceptar_invitacion: SOLO N-4 por comercio + vigentes (resto IAM-1 intacto) ──
create or replace function rsuelvo.fn_aceptar_invitacion(p_id_invitacion uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email text;
  v_inv record;
  v_estado_comercio text;
  v_codigo_rol text;
  v_vinculo uuid;
  v_cajeros integer;
begin
  select id_usuario, lower(email) into v_usuario, v_email from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;

  select * into v_inv from tbl_invitaciones where id = p_id_invitacion for update;
  if v_inv.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_existe');
  end if;
  if lower(v_inv.email) != v_email then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_ajena');
  end if;
  if v_inv.estado != 'PENDIENTE' or v_inv.expira_at <= now() then
    if v_inv.estado = 'PENDIENTE' then
      update tbl_invitaciones set estado = 'VENCIDA' where id = p_id_invitacion;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_vencida');
  end if;

  select estado into v_estado_comercio from tbl_comercios where id_comercio = v_inv.id_comercio;
  if v_estado_comercio is null or v_estado_comercio not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible');
  end if;

  select codigo into v_codigo_rol from tbl_roles where id_rol = v_inv.id_rol;
  if v_codigo_rol is null or v_codigo_rol = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;
  if v_inv.id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = v_inv.id_sucursal
                       and id_comercio = v_inv.id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;
  if v_codigo_rol = 'ROLE_LOGISTICS_AGENT' and v_inv.id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;
  -- N-4 por comercio + vigentes (rev2; resto intacto)
  if v_codigo_rol = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.id_comercio = v_inv.id_comercio
      and uc.estado in ('ACTIVE','SUSPENDED')
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  select id into v_vinculo from tbl_usuario_comercio
  where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
    and id_rol = v_inv.id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED');
  if v_vinculo is null then
    begin
      insert into tbl_usuario_comercio
        (id_usuario, id_comercio, id_rol, id_sucursal, activo, estado, invited_by, accepted_at)
      values
        (v_usuario, v_inv.id_comercio, v_inv.id_rol, v_inv.id_sucursal, true, 'ACTIVE', v_inv.invited_by, now());
    exception when unique_violation then
      update tbl_usuario_comercio set estado = 'ACTIVE'
      where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
        and id_rol = v_inv.id_rol
        and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
          = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
        and estado = 'SUSPENDED';
    end;
  else
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_vinculo;
  end if;

  update tbl_invitaciones set estado = 'ACEPTADA', accepted_at = now() where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_aceptada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true, 'id_comercio', v_inv.id_comercio);
end;
$fn$;
revoke execute on function rsuelvo.fn_aceptar_invitacion(uuid) from public;
grant execute on function rsuelvo.fn_aceptar_invitacion(uuid) to authenticated, service_role;

-- ── 5. fn_editar_usuario: cascada a SUSPENDED, sin auto-restaurar ──
create or replace function rsuelvo.fn_editar_usuario(
  p_id_usuario uuid,
  p_nombre text default null,
  p_apellido text default null,
  p_telefono text default null,
  p_activo boolean default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_tiene_super boolean;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.activo
      and r.codigo = 'ROLE_SUPERADMIN'
  ) into v_tiene_super;

  if v_tiene_super then
    return jsonb_build_object('ok', false, 'codigo', 'protegido');
  end if;

  update tbl_usuarios
  set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
      apellido = coalesce(nullif(trim(p_apellido), ''), apellido),
      telefono = coalesce(nullif(trim(p_telefono), ''), telefono),
      activo = coalesce(p_activo, activo),
      updated_at = now()
  where id_usuario = p_id_usuario;

  if coalesce(p_activo, true) = false then
    -- rev2: SUSPENDED, no REVOKED; reactivar usuario NO restaura memberships
    update tbl_usuario_comercio set estado = 'SUSPENDED'
    where id_usuario = p_id_usuario and estado = 'ACTIVE';
  end if;

  return jsonb_build_object('ok', true, 'id_usuario', p_id_usuario);
end;
$fn$;

revoke execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) from public;
grant execute on function rsuelvo.fn_editar_usuario(uuid, text, text, text, boolean) to authenticated, service_role;

-- ── 6. backfill divergencia historica (ejecutado 2026-09-22: 1 fila fosil) ──
update rsuelvo.tbl_usuario_comercio set estado = 'SUSPENDED'
where estado = 'ACTIVE' and activo = false;

-- ── 7. N-4 tercer path: trigger de asignacion por comercio + vigentes (rev2) ──
create or replace function rsuelvo.fn_validar_asignacion_usuario_comercio()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_codigo rsuelvo.rol_codigo;
begin
  select codigo into v_codigo from rsuelvo.tbl_roles where id_rol=new.id_rol;

  if v_codigo in ('ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT')
     and new.id_sucursal is null then
    raise exception 'El rol % requiere una sucursal',v_codigo;
  end if;

  if v_codigo='ROLE_TENANT_CASHIER' then
    if exists (
      select 1
      from rsuelvo.tbl_usuario_comercio uc
      join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
      where uc.id_usuario=new.id_usuario
        and uc.id_comercio=new.id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo='ROLE_TENANT_CASHIER'
        and uc.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
    ) then
      raise exception 'Un cashier solo puede tener una asignación activa por comercio';
    end if;
  end if;

  return new;
end;
$$;
-- ═══ MIG 82 (aplicada 2026-09-22: fixes lifecycle) ═══
-- 82_membership_lifecycle_fixes.sql
-- IAM-2B parche revision ChatGPT. NO reescribe mig 81.
-- 1) CAMBIAR mismo rol: UPDATE in-place (obligatorio CASHIER por N-4).
-- 2) accept/CREAR: tupla exacta primero, N-4 despues.
-- 3) CAMBIAR auditoria con id destino determinista.

-- ── fn_gestionar_vinculo rev2 ──
create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,
  p_id_comercio uuid,
  p_id_rol smallint,
  p_id_sucursal uuid default null,
  p_accion text default 'CREAR',
  p_rol_nuevo smallint default null,
  p_sucursal_nueva uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_acc text := upper(trim(coalesce(p_accion,'CREAR')));
  v_codigo text;
  v_estado text;
  v_row record;
  v_dest_id uuid;
  v_nuevo_codigo text;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if v_acc = 'CAMBIAR' then
    if p_rol_nuevo is null then
      return jsonb_build_object('ok', false, 'codigo', 'falta_rol_nuevo');
    end if;
    select * into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;

    select codigo into v_nuevo_codigo from tbl_roles where id_rol = p_rol_nuevo;
    if v_nuevo_codigo is null or v_nuevo_codigo = 'ROLE_SUPERADMIN' then
      return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
    end if;
    if p_sucursal_nueva is not null
       and not exists (select 1 from tbl_sucursales
                       where id_sucursal = p_sucursal_nueva
                         and id_comercio = p_id_comercio and activo) then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
    end if;
    if v_nuevo_codigo = 'ROLE_LOGISTICS_AGENT' and p_sucursal_nueva is null then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
    end if;

    -- FIX82-1: mismo rol -> UPDATE in-place (sin segunda fila; N-4 no aplica)
    if p_rol_nuevo = v_row.id_rol then
      update tbl_usuario_comercio
      set id_sucursal = p_sucursal_nueva, estado = 'ACTIVE'
      where id = v_row.id;
      insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
      values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_row.id);
      return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
    end if;

    -- N-4 por comercio (cambio de rol a cajero)
    if v_nuevo_codigo = 'ROLE_TENANT_CASHIER' then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER'
        and uc.id <> v_row.id;
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;

    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;

    select id into v_dest_id from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_rol_nuevo
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED'
    for update;
    if v_dest_id is not null then
      update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_dest_id;
    else
      begin
        insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
        values (p_id_usuario, p_id_comercio, p_rol_nuevo, p_sucursal_nueva, 'ACTIVE')
        returning id into v_dest_id;
      exception when unique_violation then
        update tbl_usuario_comercio set estado = 'ACTIVE'
        where id_usuario = p_id_usuario and id_comercio = p_id_comercio
          and id_rol = p_rol_nuevo
          and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
            = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
          and estado = 'SUSPENDED'
        returning id into v_dest_id;
      end;
    end if;

    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_dest_id);
    return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
  end if;

  if v_acc in ('DESACTIVAR','SUSPENDER') then
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'ACTIVE'
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_suspendido', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'SUSPENDIDO');
  end if;

  if v_acc = 'REVOCAR' then
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'REVOKED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_revocado', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'REVOCADO');
  end if;

  if v_acc != 'CREAR' then
    return jsonb_build_object('ok', false, 'codigo', 'accion_invalida');
  end if;

  select codigo into v_codigo from tbl_roles where id_rol = p_id_rol;
  if v_codigo is null or v_codigo = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible', 'estado', v_estado);
  end if;

  if p_id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = p_id_sucursal
                       and id_comercio = p_id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  if v_codigo = 'ROLE_LOGISTICS_AGENT' and p_id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;

  -- FIX82-2 (gestionar): tupla exacta primero; N-4 solo si no existe
  select id, estado into v_row from tbl_usuario_comercio
  where id_usuario = p_id_usuario and id_comercio = p_id_comercio
    and id_rol = p_id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED')
  for update;
  if v_row.id is not null then
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
    return jsonb_build_object('ok', true, 'reactivado', v_row.estado = 'SUSPENDED');
  end if;

  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
      and uc.estado in ('ACTIVE','SUSPENDED')
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  begin
    insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
    values (p_id_usuario, p_id_comercio, p_id_rol, p_id_sucursal, 'ACTIVE');
  exception when unique_violation then
    update tbl_usuario_comercio set estado = 'ACTIVE'
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED';
  end;
  return jsonb_build_object('ok', true, 'reactivado', false);
end;
$fn$;

-- ── fn_aceptar_invitacion rev2: tupla exacta primero, N-4 despues ──
create or replace function rsuelvo.fn_aceptar_invitacion(p_id_invitacion uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email text;
  v_inv record;
  v_estado_comercio text;
  v_codigo_rol text;
  v_vinculo uuid;
  v_vinc_estado text;
  v_cajeros integer;
begin
  select id_usuario, lower(email) into v_usuario, v_email from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;

  select * into v_inv from tbl_invitaciones where id = p_id_invitacion for update;
  if v_inv.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_no_existe');
  end if;
  if lower(v_inv.email) != v_email then
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_ajena');
  end if;
  if v_inv.estado != 'PENDIENTE' or v_inv.expira_at <= now() then
    if v_inv.estado = 'PENDIENTE' then
      update tbl_invitaciones set estado = 'VENCIDA' where id = p_id_invitacion;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'invitacion_vencida');
  end if;

  select estado into v_estado_comercio from tbl_comercios where id_comercio = v_inv.id_comercio;
  if v_estado_comercio is null or v_estado_comercio not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible');
  end if;

  select codigo into v_codigo_rol from tbl_roles where id_rol = v_inv.id_rol;
  if v_codigo_rol is null or v_codigo_rol = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;
  if v_inv.id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = v_inv.id_sucursal
                       and id_comercio = v_inv.id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;
  if v_codigo_rol = 'ROLE_LOGISTICS_AGENT' and v_inv.id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;

  -- FIX82-2 (accept): tupla exacta primero
  select id, estado into v_vinculo, v_vinc_estado from tbl_usuario_comercio
  where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
    and id_rol = v_inv.id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED')
  for update;
  if v_vinculo is not null then
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_vinculo;
  else
    if v_codigo_rol = 'ROLE_TENANT_CASHIER' then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = v_usuario and uc.id_comercio = v_inv.id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER';
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;
    begin
      insert into tbl_usuario_comercio
        (id_usuario, id_comercio, id_rol, id_sucursal, activo, estado, invited_by, accepted_at)
      values
        (v_usuario, v_inv.id_comercio, v_inv.id_rol, v_inv.id_sucursal, true, 'ACTIVE', v_inv.invited_by, now());
    exception when unique_violation then
      update tbl_usuario_comercio set estado = 'ACTIVE'
      where id_usuario = v_usuario and id_comercio = v_inv.id_comercio
        and id_rol = v_inv.id_rol
        and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
          = coalesce(v_inv.id_sucursal, '00000000-0000-0000-0000-000000000000')
        and estado = 'SUSPENDED';
    end;
  end if;

  update tbl_invitaciones set estado = 'ACEPTADA', accepted_at = now() where id = p_id_invitacion;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_inv.id_comercio, v_usuario, 'invitacion_aceptada', 'tbl_invitaciones', p_id_invitacion);

  return jsonb_build_object('ok', true, 'id_comercio', v_inv.id_comercio);
end;
$fn$;
-- ═══ MIG 83 (aplicada 2026-09-22: owner + operaciones criticas) ═══
-- 83_owner_operaciones_criticas.sql
-- IAM-4 backend. Implementa D-IAM-OWNER.md rev2.
-- Preflight 2026-09-22: FER/FEE/ABC = 1 admin (auto); resto 0 (NULL); 0 ambiguos.

-- ── 1. propietario + backfill regla 1-admin ──
alter table rsuelvo.tbl_comercios
  add column if not exists propietario_id uuid null
  references rsuelvo.tbl_usuarios(id_usuario) on delete set null;

update rsuelvo.tbl_comercios c set propietario_id = (
  select uc.id_usuario from rsuelvo.tbl_usuario_comercio uc
  join rsuelvo.tbl_roles r on r.id_rol = uc.id_rol
  where uc.id_comercio = c.id_comercio and uc.estado = 'ACTIVE'
    and r.codigo = 'ROLE_TENANT_ADMIN'
  limit 1
)
where (select count(*) from rsuelvo.tbl_usuario_comercio uc
       join rsuelvo.tbl_roles r on r.id_rol = uc.id_rol
       where uc.id_comercio = c.id_comercio and uc.estado = 'ACTIVE'
         and r.codigo = 'ROLE_TENANT_ADMIN') = 1
  and c.propietario_id is null;

-- ── 2. transferencias con lifecycle ──
create table if not exists rsuelvo.tbl_transferencias_propiedad (
  id uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete cascade,
  propietario_origen uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  propietario_destino uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  estado text not null default 'PENDIENTE',
  initiated_by uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  expira_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint transf_estado_chk check (estado in ('PENDIENTE','ACEPTADA','RECHAZADA','CANCELADA','VENCIDA'))
);
create unique index if not exists transf_pendiente_unica
  on rsuelvo.tbl_transferencias_propiedad (id_comercio) where estado = 'PENDIENTE';
alter table rsuelvo.tbl_transferencias_propiedad enable row level security;
grant all on rsuelvo.tbl_transferencias_propiedad to service_role;

-- ── 3. fn_es_owner canonico (identidad desde JWT) ──
create or replace function rsuelvo.fn_es_owner(p_id_comercio uuid)
returns boolean
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then return false; end if;
  if not exists (select 1 from tbl_comercios
                 where id_comercio = p_id_comercio and propietario_id = v_usuario) then
    return false;
  end if;
  return exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.id_comercio = p_id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE'
  );
end;
$fn$;
revoke execute on function rsuelvo.fn_es_owner(uuid) from public;
grant execute on function rsuelvo.fn_es_owner(uuid) to authenticated, service_role;

-- ── 4. transferencia: iniciar / responder / cancelar ──
create or replace function rsuelvo.fn_iniciar_transferencia(p_id_comercio uuid, p_destino uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_tid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  if p_destino = v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_destino and uc.id_comercio = p_id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  if exists (select 1 from tbl_transferencias_propiedad
             where id_comercio = p_id_comercio and estado = 'PENDIENTE') then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end if;
  insert into tbl_transferencias_propiedad
    (id_comercio, propietario_origen, propietario_destino, initiated_by)
  values (p_id_comercio, v_usuario, p_destino, v_usuario)
  returning id into v_tid;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'transferencia_iniciada', 'tbl_transferencias_propiedad', v_tid);
  return jsonb_build_object('ok', true, 'id_transferencia', v_tid);
end;
$fn$;
revoke execute on function rsuelvo.fn_iniciar_transferencia(uuid, uuid) from public;
grant execute on function rsuelvo.fn_iniciar_transferencia(uuid, uuid) to authenticated, service_role;

create or replace function rsuelvo.fn_responder_transferencia(p_id uuid, p_acepta boolean)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_t record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_t from tbl_transferencias_propiedad where id = p_id for update;
  if v_t.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_existe');
  end if;
  if v_t.propietario_destino != v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_ajena');
  end if;
  if v_t.estado != 'PENDIENTE' or v_t.expira_at <= now() then
    if v_t.estado = 'PENDIENTE' then
      update tbl_transferencias_propiedad set estado = 'VENCIDA' where id = p_id;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_vencida');
  end if;
  if not p_acepta then
    update tbl_transferencias_propiedad set estado = 'RECHAZADA' where id = p_id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (v_t.id_comercio, v_usuario, 'transferencia_rechazada', 'tbl_transferencias_propiedad', p_id);
    return jsonb_build_object('ok', true, 'estado', 'RECHAZADA');
  end if;
  -- revalidacion total antes del cambio atomico
  if not exists (select 1 from tbl_comercios
                 where id_comercio = v_t.id_comercio and propietario_id = v_t.propietario_origen) then
    return jsonb_build_object('ok', false, 'codigo', 'origen_ya_no_owner');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.id_comercio = v_t.id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  update tbl_comercios set propietario_id = v_usuario, updated_at = now()
  where id_comercio = v_t.id_comercio;
  update tbl_transferencias_propiedad set estado = 'ACEPTADA', accepted_at = now() where id = p_id;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_t.id_comercio, v_usuario, 'transferencia_aceptada', 'tbl_transferencias_propiedad', p_id);
  return jsonb_build_object('ok', true, 'estado', 'ACEPTADA');
end;
$fn$;
revoke execute on function rsuelvo.fn_responder_transferencia(uuid, boolean) from public;
grant execute on function rsuelvo.fn_responder_transferencia(uuid, boolean) to authenticated, service_role;

create or replace function rsuelvo.fn_cancelar_transferencia(p_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_t record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_t from tbl_transferencias_propiedad where id = p_id for update;
  if v_t.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_existe');
  end if;
  if v_t.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_pendiente');
  end if;
  if v_t.propietario_origen != v_usuario
     and not fn_es_admin_comercio(v_t.id_comercio)
     and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'sin_permiso');
  end if;
  update tbl_transferencias_propiedad set estado = 'CANCELADA' where id = p_id;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_t.id_comercio, v_usuario, 'transferencia_cancelada', 'tbl_transferencias_propiedad', p_id);
  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_cancelar_transferencia(uuid) from public;
grant execute on function rsuelvo.fn_cancelar_transferencia(uuid) to authenticated, service_role;

-- ── 5. anti-degradar owner en gestionar (SUSPENDER/REVOCAR/CAMBIAR-rol) ──
create or replace function rsuelvo.fn_es_vinculo_owner(p_usuario uuid, p_comercio uuid)
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select exists (
    select 1 from tbl_comercios c
    join tbl_usuario_comercio uc on uc.id_usuario = c.propietario_id
      and uc.id_comercio = c.id_comercio
    join tbl_roles r on r.id_rol = uc.id_rol
    where c.id_comercio = p_comercio and c.propietario_id = p_usuario
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE'
  );
$fn$;

-- ── 6. fn_cerrar_comercio (owner voluntario / superadmin excepcional) ──
create or replace function rsuelvo.fn_cerrar_comercio(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_owner(p_id_comercio) and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'CANCELADO' then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cambio');
  end if;
  update tbl_comercios set estado = 'CANCELADO', updated_at = now()
  where id_comercio = p_id_comercio;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'comercio_cerrado', 'tbl_comercios', p_id_comercio);
  return jsonb_build_object('ok', true, 'anterior', v_estado, 'nuevo', 'CANCELADO');
end;
$fn$;
revoke execute on function rsuelvo.fn_cerrar_comercio(uuid) from public;
grant execute on function rsuelvo.fn_cerrar_comercio(uuid) to authenticated, service_role;

-- ── 7. auto-owner: primer admin ACTIVE sin propietario (cubre alta/invite/gestionar) ──
create or replace function rsuelvo.fn_uc_auto_owner()
returns trigger
language plpgsql security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text;
  v_prop uuid;
begin
  if new.estado != 'ACTIVE' then return new; end if;
  select codigo into v_codigo from tbl_roles where id_rol = new.id_rol;
  if v_codigo != 'ROLE_TENANT_ADMIN' then return new; end if;
  select propietario_id into v_prop from tbl_comercios where id_comercio = new.id_comercio;
  if v_prop is null then
    update tbl_comercios set propietario_id = new.id_usuario, updated_at = now()
    where id_comercio = new.id_comercio;
  end if;
  return new;
end;
$fn$;
drop trigger if exists trg_uc_auto_owner on rsuelvo.tbl_usuario_comercio;
create trigger trg_uc_auto_owner
  after insert or update of estado on rsuelvo.tbl_usuario_comercio
  for each row execute function rsuelvo.fn_uc_auto_owner();

-- ── 8. gestionar rev3: anti-degradar owner (resto mig 82 intacto) ──
create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,
  p_id_comercio uuid,
  p_id_rol smallint,
  p_id_sucursal uuid default null,
  p_accion text default 'CREAR',
  p_rol_nuevo smallint default null,
  p_sucursal_nueva uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_acc text := upper(trim(coalesce(p_accion,'CREAR')));
  v_codigo text;
  v_estado text;
  v_row record;
  v_dest_id uuid;
  v_nuevo_codigo text;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if v_acc = 'CAMBIAR' then
    if p_rol_nuevo is null then
      return jsonb_build_object('ok', false, 'codigo', 'falta_rol_nuevo');
    end if;
    select * into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    -- owner: solo in-place mismo rol; cualquier cambio de tupla requiere transferencia previa
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) and p_rol_nuevo != v_row.id_rol then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;

    select codigo into v_nuevo_codigo from tbl_roles where id_rol = p_rol_nuevo;
    if v_nuevo_codigo is null or v_nuevo_codigo = 'ROLE_SUPERADMIN' then
      return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
    end if;
    if p_sucursal_nueva is not null
       and not exists (select 1 from tbl_sucursales
                       where id_sucursal = p_sucursal_nueva
                         and id_comercio = p_id_comercio and activo) then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
    end if;
    if v_nuevo_codigo = 'ROLE_LOGISTICS_AGENT' and p_sucursal_nueva is null then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
    end if;

    if p_rol_nuevo = v_row.id_rol then
      update tbl_usuario_comercio
      set id_sucursal = p_sucursal_nueva, estado = 'ACTIVE'
      where id = v_row.id;
      insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
      values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_row.id);
      return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
    end if;

    if v_nuevo_codigo = 'ROLE_TENANT_CASHIER' then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER'
        and uc.id <> v_row.id;
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;

    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;

    select id into v_dest_id from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_rol_nuevo
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED'
    for update;
    if v_dest_id is not null then
      update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_dest_id;
    else
      begin
        insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
        values (p_id_usuario, p_id_comercio, p_rol_nuevo, p_sucursal_nueva, 'ACTIVE')
        returning id into v_dest_id;
      exception when unique_violation then
        update tbl_usuario_comercio set estado = 'ACTIVE'
        where id_usuario = p_id_usuario and id_comercio = p_id_comercio
          and id_rol = p_rol_nuevo
          and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
            = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
          and estado = 'SUSPENDED'
        returning id into v_dest_id;
      end;
    end if;

    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_dest_id);
    return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
  end if;

  if v_acc in ('DESACTIVAR','SUSPENDER') then
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'ACTIVE'
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_suspendido', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'SUSPENDIDO');
  end if;

  if v_acc = 'REVOCAR' then
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'REVOKED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_revocado', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'REVOCADO');
  end if;

  if v_acc != 'CREAR' then
    return jsonb_build_object('ok', false, 'codigo', 'accion_invalida');
  end if;

  select codigo into v_codigo from tbl_roles where id_rol = p_id_rol;
  if v_codigo is null or v_codigo = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible', 'estado', v_estado);
  end if;

  if p_id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = p_id_sucursal
                       and id_comercio = p_id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  if v_codigo = 'ROLE_LOGISTICS_AGENT' and p_id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;

  select id, estado into v_row from tbl_usuario_comercio
  where id_usuario = p_id_usuario and id_comercio = p_id_comercio
    and id_rol = p_id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED')
  for update;
  if v_row.id is not null then
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
    return jsonb_build_object('ok', true, 'reactivado', v_row.estado = 'SUSPENDED');
  end if;

  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
      and uc.estado in ('ACTIVE','SUSPENDED')
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  begin
    insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
    values (p_id_usuario, p_id_comercio, p_id_rol, p_id_sucursal, 'ACTIVE');
  exception when unique_violation then
    update tbl_usuario_comercio set estado = 'ACTIVE'
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED';
  end;
  return jsonb_build_object('ok', true, 'reactivado', false);
end;
$fn$;

-- ── 9. editar rev2: bloquea si es owner ACTIVE en algun comercio ──
create or replace function rsuelvo.fn_editar_usuario(
  p_id_usuario uuid,
  p_nombre text default null,
  p_apellido text default null,
  p_telefono text default null,
  p_activo boolean default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_tiene_super boolean;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.activo
      and r.codigo = 'ROLE_SUPERADMIN'
  ) into v_tiene_super;

  if v_tiene_super then
    return jsonb_build_object('ok', false, 'codigo', 'protegido');
  end if;

  if coalesce(p_activo, true) = false
     and exists (select 1 from tbl_comercios c
                 join tbl_usuario_comercio uc on uc.id_usuario = c.propietario_id
                   and uc.id_comercio = c.id_comercio
                 join tbl_roles r on r.id_rol = uc.id_rol
                 where c.propietario_id = p_id_usuario
                   and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
  end if;

  update tbl_usuarios
  set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
      apellido = coalesce(nullif(trim(p_apellido), ''), apellido),
      telefono = coalesce(nullif(trim(p_telefono), ''), telefono),
      activo = coalesce(p_activo, activo),
      updated_at = now()
  where id_usuario = p_id_usuario;

  if coalesce(p_activo, true) = false then
    update tbl_usuario_comercio set estado = 'SUSPENDED'
    where id_usuario = p_id_usuario and estado = 'ACTIVE';
  end if;

  return jsonb_build_object('ok', true, 'id_usuario', p_id_usuario);
end;
$fn$;
-- ═══ MIG 84 (aplicada 2026-09-22: hardening transferencias) ═══
-- 84_owner_transfer_fixes.sql
-- IAM-4 hardening revision ChatGPT. NO reescribe mig 83.

-- ── 1. cancelar: solo origen o superadmin ──
create or replace function rsuelvo.fn_cancelar_transferencia(p_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_t record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_t from tbl_transferencias_propiedad where id = p_id for update;
  if v_t.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_existe');
  end if;
  if v_t.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_pendiente');
  end if;
  if v_t.propietario_origen != v_usuario and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'sin_permiso');
  end if;
  update tbl_transferencias_propiedad set estado = 'CANCELADA' where id = p_id;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_t.id_comercio, v_usuario, 'transferencia_cancelada', 'tbl_transferencias_propiedad', p_id);
  return jsonb_build_object('ok', true);
end;
$fn$;

-- ── 2+3. iniciar: sweep expiracion + unique_violation determinista ──
create or replace function rsuelvo.fn_iniciar_transferencia(p_id_comercio uuid, p_destino uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_tid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  if p_destino = v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_destino and uc.id_comercio = p_id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  -- FIX84-2: expiradas no bloquean (sweep antes de comprobar)
  update tbl_transferencias_propiedad set estado = 'VENCIDA'
  where id_comercio = p_id_comercio and estado = 'PENDIENTE' and expira_at <= now();
  if exists (select 1 from tbl_transferencias_propiedad
             where id_comercio = p_id_comercio and estado = 'PENDIENTE') then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end if;
  begin
    insert into tbl_transferencias_propiedad
      (id_comercio, propietario_origen, propietario_destino, initiated_by)
    values (p_id_comercio, v_usuario, p_destino, v_usuario)
    returning id into v_tid;
  exception when unique_violation then
    -- FIX84-3: carrera -> determinista, sin excepcion SQL
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'transferencia_iniciada', 'tbl_transferencias_propiedad', v_tid);
  return jsonb_build_object('ok', true, 'id_transferencia', v_tid);
end;
$fn$;

-- ── 4. auto-owner: solo si queda exactamente 1 admin ACTIVE ──
create or replace function rsuelvo.fn_uc_auto_owner()
returns trigger
language plpgsql security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_codigo text;
  v_prop uuid;
  v_admins integer;
begin
  if new.estado != 'ACTIVE' then return new; end if;
  select codigo into v_codigo from tbl_roles where id_rol = new.id_rol;
  if v_codigo != 'ROLE_TENANT_ADMIN' then return new; end if;
  select propietario_id into v_prop from tbl_comercios where id_comercio = new.id_comercio;
  if v_prop is not null then return new; end if;
  select count(*) into v_admins
  from tbl_usuario_comercio uc
  join tbl_roles r on r.id_rol = uc.id_rol
  where uc.id_comercio = new.id_comercio and uc.estado = 'ACTIVE'
    and r.codigo = 'ROLE_TENANT_ADMIN';
  if v_admins = 1 then
    update tbl_comercios set propietario_id = new.id_usuario, updated_at = now()
    where id_comercio = new.id_comercio;
  end if;
  return new;
end;
$fn$;

-- ── 5. responder: revalidar origen admin ACTIVE ──
create or replace function rsuelvo.fn_responder_transferencia(p_id uuid, p_acepta boolean)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_t record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_t from tbl_transferencias_propiedad where id = p_id for update;
  if v_t.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_existe');
  end if;
  if v_t.propietario_destino != v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_ajena');
  end if;
  if v_t.estado != 'PENDIENTE' or v_t.expira_at <= now() then
    if v_t.estado = 'PENDIENTE' then
      update tbl_transferencias_propiedad set estado = 'VENCIDA' where id = p_id;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_vencida');
  end if;
  if not p_acepta then
    update tbl_transferencias_propiedad set estado = 'RECHAZADA' where id = p_id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (v_t.id_comercio, v_usuario, 'transferencia_rechazada', 'tbl_transferencias_propiedad', p_id);
    return jsonb_build_object('ok', true, 'estado', 'RECHAZADA');
  end if;
  if not exists (select 1 from tbl_comercios
                 where id_comercio = v_t.id_comercio and propietario_id = v_t.propietario_origen) then
    return jsonb_build_object('ok', false, 'codigo', 'origen_ya_no_owner');
  end if;
  -- FIX84-5: origen debe seguir admin ACTIVE
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_t.propietario_origen and uc.id_comercio = v_t.id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'origen_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.id_comercio = v_t.id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  update tbl_comercios set propietario_id = v_usuario, updated_at = now()
  where id_comercio = v_t.id_comercio;
  update tbl_transferencias_propiedad set estado = 'ACEPTADA', accepted_at = now() where id = p_id;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_t.id_comercio, v_usuario, 'transferencia_aceptada', 'tbl_transferencias_propiedad', p_id);
  return jsonb_build_object('ok', true, 'estado', 'ACEPTADA');
end;
$fn$;
-- ═══ MIG 85 (aplicada 2026-09-22: descubrimiento transferencias) ═══
-- 85_transferencias_descubrimiento.sql
-- IAM-4 UI enablement: descubrimiento server-side (mismo patron invitaciones).
-- Solo lectura; no cambia contratos.

create or replace function rsuelvo.fn_mis_transferencias_pendientes()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  return jsonb_build_object('ok', true, 'transferencias', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_transferencia', t.id, 'id_comercio', t.id_comercio,
      'comercio', c.nombre_comercial,
      'soy_origen', t.propietario_origen = v_usuario,
      'origen_email', uo.email, 'destino_email', ud.email,
      'estado', t.estado, 'expira_at', t.expira_at, 'created_at', t.created_at
    ))
    from tbl_transferencias_propiedad t
    join tbl_comercios c on c.id_comercio = t.id_comercio
    left join tbl_usuarios uo on uo.id_usuario = t.propietario_origen
    left join tbl_usuarios ud on ud.id_usuario = t.propietario_destino
    where (t.propietario_origen = v_usuario or t.propietario_destino = v_usuario)
      and t.estado = 'PENDIENTE' and t.expira_at > now()
  ), '[]'::jsonb));
end;
$fn$;
revoke execute on function rsuelvo.fn_mis_transferencias_pendientes() from public;
grant execute on function rsuelvo.fn_mis_transferencias_pendientes() to authenticated, service_role;
-- ═══ MIG 86 (aplicada 2026-09-22: fn_tiene_aal2 + guards criticas) ═══
-- 86_mfa_aal2_guards.sql
-- IAM-5 backend. Helper canonico + guards en operaciones criticas.
-- service_role conserva paths (passthrough primero).

-- ── 1. helper ──
create or replace function rsuelvo.fn_tiene_aal2()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select case
    when coalesce(auth.jwt()->>'role', '') = 'service_role' then true
    else coalesce(auth.jwt()->>'aal', '') = 'aal2'
  end;
$fn$;
revoke execute on function rsuelvo.fn_tiene_aal2() from public;
grant execute on function rsuelvo.fn_tiene_aal2() to authenticated, service_role;

-- ── 2. guards: transferencia iniciar/responder/cerrar/gestionar/editar-off ──
-- Patron por funcion: tras resolver identidad humana (no service_role),
-- exigir fn_tiene_aal2() o devolver {ok:false,codigo:'mfa_requerido'}.
-- Se aplica con CREATE OR REPLACE minimos que preservan cada cuerpo.

-- ── iniciar transferencia (guard tras identidad) ──
create or replace function rsuelvo.fn_iniciar_transferencia(p_id_comercio uuid, p_destino uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_tid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  if p_destino = v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_destino and uc.id_comercio = p_id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  update tbl_transferencias_propiedad set estado = 'VENCIDA'
  where id_comercio = p_id_comercio and estado = 'PENDIENTE' and expira_at <= now();
  if exists (select 1 from tbl_transferencias_propiedad
             where id_comercio = p_id_comercio and estado = 'PENDIENTE') then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end if;
  begin
    insert into tbl_transferencias_propiedad
      (id_comercio, propietario_origen, propietario_destino, initiated_by)
    values (p_id_comercio, v_usuario, p_destino, v_usuario)
    returning id into v_tid;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'transferencia_iniciada', 'tbl_transferencias_propiedad', v_tid);
  return jsonb_build_object('ok', true, 'id_transferencia', v_tid);
end;
$fn$;

-- ── responder transferencia (guard tras identidad) ──
create or replace function rsuelvo.fn_responder_transferencia(p_id uuid, p_acepta boolean)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_t record;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  select * into v_t from tbl_transferencias_propiedad where id = p_id for update;
  if v_t.id is null then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_no_existe');
  end if;
  if v_t.propietario_destino != v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_ajena');
  end if;
  if v_t.estado != 'PENDIENTE' or v_t.expira_at <= now() then
    if v_t.estado = 'PENDIENTE' then
      update tbl_transferencias_propiedad set estado = 'VENCIDA' where id = p_id;
    end if;
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_vencida');
  end if;
  if not p_acepta then
    update tbl_transferencias_propiedad set estado = 'RECHAZADA' where id = p_id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (v_t.id_comercio, v_usuario, 'transferencia_rechazada', 'tbl_transferencias_propiedad', p_id);
    return jsonb_build_object('ok', true, 'estado', 'RECHAZADA');
  end if;
  if not exists (select 1 from tbl_comercios
                 where id_comercio = v_t.id_comercio and propietario_id = v_t.propietario_origen) then
    return jsonb_build_object('ok', false, 'codigo', 'origen_ya_no_owner');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_t.propietario_origen and uc.id_comercio = v_t.id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'origen_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = v_usuario and uc.id_comercio = v_t.id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  update tbl_comercios set propietario_id = v_usuario, updated_at = now()
  where id_comercio = v_t.id_comercio;
  update tbl_transferencias_propiedad set estado = 'ACEPTADA', accepted_at = now() where id = p_id;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_t.id_comercio, v_usuario, 'transferencia_aceptada', 'tbl_transferencias_propiedad', p_id);
  return jsonb_build_object('ok', true, 'estado', 'ACEPTADA');
end;
$fn$;

-- ── cerrar comercio (guard tras identidad) ──
create or replace function rsuelvo.fn_cerrar_comercio(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) and not fn_es_superadmin() then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'CANCELADO' then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cambio');
  end if;
  update tbl_comercios set estado = 'CANCELADO', updated_at = now()
  where id_comercio = p_id_comercio;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'comercio_cerrado', 'tbl_comercios', p_id_comercio);
  return jsonb_build_object('ok', true, 'anterior', v_estado, 'nuevo', 'CANCELADO');
end;
$fn$;

-- ── editar rev3: guard solo en rama desactivacion ──
create or replace function rsuelvo.fn_editar_usuario(
  p_id_usuario uuid,
  p_nombre text default null,
  p_apellido text default null,
  p_telefono text default null,
  p_activo boolean default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_tiene_super boolean;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.activo
      and r.codigo = 'ROLE_SUPERADMIN'
  ) into v_tiene_super;

  if v_tiene_super then
    return jsonb_build_object('ok', false, 'codigo', 'protegido');
  end if;

  if coalesce(p_activo, true) = false then
    if not fn_es_service_role() and not fn_tiene_aal2() then
      return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
    end if;
    if exists (select 1 from tbl_comercios c
               join tbl_usuario_comercio uc on uc.id_usuario = c.propietario_id
                 and uc.id_comercio = c.id_comercio
               join tbl_roles r on r.id_rol = uc.id_rol
               where c.propietario_id = p_id_usuario
                 and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
  end if;

  update tbl_usuarios
  set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
      apellido = coalesce(nullif(trim(p_apellido), ''), apellido),
      telefono = coalesce(nullif(trim(p_telefono), ''), telefono),
      activo = coalesce(p_activo, activo),
      updated_at = now()
  where id_usuario = p_id_usuario;

  if coalesce(p_activo, true) = false then
    update tbl_usuario_comercio set estado = 'SUSPENDED'
    where id_usuario = p_id_usuario and estado = 'ACTIVE';
  end if;

  return jsonb_build_object('ok', true, 'id_usuario', p_id_usuario);
end;
$fn$;

-- ── gestionar rev4: AAL guard + anti-degradar owner (ensamblado de 82+83) ──
create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,
  p_id_comercio uuid,
  p_id_rol smallint,
  p_id_sucursal uuid default null,
  p_accion text default 'CREAR',
  p_rol_nuevo smallint default null,
  p_sucursal_nueva uuid default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_acc text := upper(trim(coalesce(p_accion,'CREAR')));
  v_codigo text;
  v_estado text;
  v_row record;
  v_dest_id uuid;
  v_nuevo_codigo text;
  v_cajeros integer;
begin
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;

  if v_acc = 'CAMBIAR' then
    if p_rol_nuevo is null then
      return jsonb_build_object('ok', false, 'codigo', 'falta_rol_nuevo');
    end if;
    select * into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    -- owner: solo in-place mismo rol; cualquier cambio de tupla requiere transferencia previa
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) and p_rol_nuevo != v_row.id_rol then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;

    select codigo into v_nuevo_codigo from tbl_roles where id_rol = p_rol_nuevo;
    if v_nuevo_codigo is null or v_nuevo_codigo = 'ROLE_SUPERADMIN' then
      return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
    end if;
    if p_sucursal_nueva is not null
       and not exists (select 1 from tbl_sucursales
                       where id_sucursal = p_sucursal_nueva
                         and id_comercio = p_id_comercio and activo) then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
    end if;
    if v_nuevo_codigo = 'ROLE_LOGISTICS_AGENT' and p_sucursal_nueva is null then
      return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
    end if;

    -- FIX82-1: mismo rol -> UPDATE in-place (sin segunda fila; N-4 no aplica)
    if p_rol_nuevo = v_row.id_rol then
      update tbl_usuario_comercio
      set id_sucursal = p_sucursal_nueva, estado = 'ACTIVE'
      where id = v_row.id;
      insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
      values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_row.id);
      return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
    end if;

    -- N-4 por comercio (cambio de rol a cajero)
    if v_nuevo_codigo = 'ROLE_TENANT_CASHIER' then
      select count(*) into v_cajeros from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol = uc.id_rol
      where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
        and uc.estado in ('ACTIVE','SUSPENDED')
        and r.codigo = 'ROLE_TENANT_CASHIER'
        and uc.id <> v_row.id;
      if v_cajeros > 0 then
        return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
      end if;
    end if;

    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;

    select id into v_dest_id from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_rol_nuevo
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED'
    for update;
    if v_dest_id is not null then
      update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_dest_id;
    else
      begin
        insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
        values (p_id_usuario, p_id_comercio, p_rol_nuevo, p_sucursal_nueva, 'ACTIVE')
        returning id into v_dest_id;
      exception when unique_violation then
        update tbl_usuario_comercio set estado = 'ACTIVE'
        where id_usuario = p_id_usuario and id_comercio = p_id_comercio
          and id_rol = p_rol_nuevo
          and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
            = coalesce(p_sucursal_nueva, '00000000-0000-0000-0000-000000000000')
          and estado = 'SUSPENDED'
        returning id into v_dest_id;
      end;
    end if;

    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_cambiado', 'tbl_usuario_comercio', v_dest_id);
    return jsonb_build_object('ok', true, 'nuevo', 'CAMBIADO');
  end if;

  if v_acc in ('DESACTIVAR','SUSPENDER') then
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'ACTIVE'
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'SUSPENDED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_suspendido', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'SUSPENDIDO');
  end if;

  if v_acc = 'REVOCAR' then
    if fn_es_vinculo_owner(p_id_usuario, p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'owner_protegido');
    end if;
    select id into v_row from tbl_usuario_comercio
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado in ('ACTIVE','SUSPENDED')
    for update;
    if v_row.id is null then
      return jsonb_build_object('ok', false, 'codigo', 'vinculo_no_existe');
    end if;
    update tbl_usuario_comercio set estado = 'REVOKED' where id = v_row.id;
    insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
    values (p_id_comercio, p_id_usuario, 'vinculo_revocado', 'tbl_usuario_comercio', v_row.id);
    return jsonb_build_object('ok', true, 'nuevo', 'REVOCADO');
  end if;

  if v_acc != 'CREAR' then
    return jsonb_build_object('ok', false, 'codigo', 'accion_invalida');
  end if;

  select codigo into v_codigo from tbl_roles where id_rol = p_id_rol;
  if v_codigo is null or v_codigo = 'ROLE_SUPERADMIN' then
    return jsonb_build_object('ok', false, 'codigo', 'rol_invalido');
  end if;

  if not exists (select 1 from tbl_usuarios where id_usuario = p_id_usuario) then
    return jsonb_build_object('ok', false, 'codigo', 'usuario_no_existe');
  end if;

  select estado into v_estado from tbl_comercios where id_comercio = p_id_comercio;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado not in ('ACTIVO','PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_incompatible', 'estado', v_estado);
  end if;

  if p_id_sucursal is not null
     and not exists (select 1 from tbl_sucursales
                     where id_sucursal = p_id_sucursal
                       and id_comercio = p_id_comercio and activo) then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_invalida');
  end if;

  if v_codigo = 'ROLE_LOGISTICS_AGENT' and p_id_sucursal is null then
    return jsonb_build_object('ok', false, 'codigo', 'sucursal_obligatoria');
  end if;

  -- FIX82-2 (gestionar): tupla exacta primero; N-4 solo si no existe
  select id, estado into v_row from tbl_usuario_comercio
  where id_usuario = p_id_usuario and id_comercio = p_id_comercio
    and id_rol = p_id_rol
    and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
      = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
    and estado in ('ACTIVE','SUSPENDED')
  for update;
  if v_row.id is not null then
    update tbl_usuario_comercio set estado = 'ACTIVE' where id = v_row.id;
    return jsonb_build_object('ok', true, 'reactivado', v_row.estado = 'SUSPENDED');
  end if;

  if v_codigo = 'ROLE_TENANT_CASHIER' then
    select count(*) into v_cajeros from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_id_usuario and uc.id_comercio = p_id_comercio
      and uc.estado in ('ACTIVE','SUSPENDED')
      and r.codigo = 'ROLE_TENANT_CASHIER';
    if v_cajeros > 0 then
      return jsonb_build_object('ok', false, 'codigo', 'cajero_multiplo');
    end if;
  end if;

  begin
    insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
    values (p_id_usuario, p_id_comercio, p_id_rol, p_id_sucursal, 'ACTIVE');
  exception when unique_violation then
    update tbl_usuario_comercio set estado = 'ACTIVE'
    where id_usuario = p_id_usuario and id_comercio = p_id_comercio
      and id_rol = p_id_rol
      and coalesce(id_sucursal, '00000000-0000-0000-0000-000000000000')
        = coalesce(p_id_sucursal, '00000000-0000-0000-0000-000000000000')
      and estado = 'SUSPENDED';
  end;
  return jsonb_build_object('ok', true, 'reactivado', false);
end;
$fn$;
-- ═══ MIG 87 (aplicada 2026-09-22: fix P0 service_role + drop overload) ═══
-- 87_fix_service_role_jwt.sql
-- INCIDENTE P0 2026-09-22: mig 76 agrego `or current_user in ('postgres',
-- 'service_role')`. Como todas las fns son SECURITY DEFINER con owner
-- postgres, current_user='postgres' SIEMPRE -> fn_es_service_role()=true
-- para cualquier usuario autenticado (RLS y gates con ese helper abiertos).
-- Fix: JWT manda cuando hay JWT (PostgREST siempre lo pone); el fallback
-- current_user SOLO aplica sin JWT (conexiones PG directas backend/n8n).

create or replace function rsuelvo.fn_es_service_role()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select coalesce(auth.jwt()->>'role', '') = 'service_role'
      or (auth.jwt() is null and current_user in ('postgres', 'service_role'));
$fn$;

-- mismo patron en el helper AAL2 (mig 86)
create or replace function rsuelvo.fn_tiene_aal2()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select case
    when auth.jwt() is null then current_user in ('postgres', 'service_role')
    when coalesce(auth.jwt()->>'role', '') = 'service_role' then true
    else coalesce(auth.jwt()->>'aal', '') = 'aal2'
  end;
$fn$;

-- overload fantasma de gestionar (5 params, mig 68): rompe PostgREST PGRST203
-- y deja el dialogo IAM-2A sin funcionar. La firma vigente es la de 7 params.
drop function if exists rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text);
-- ═══ MIG 88 (aplicada 2026-09-22: regression test guards) ═══
-- 88_guard_regression_test.sql
-- P0-IR: test permanente. Falla si SECURITY DEFINER vuelve a convertir
-- current_user en bypass (el helper solo puede usar current_user cuando
-- NO hay JWT: conexiones PG directas backend/n8n).

create or replace function rsuelvo.fn_verificar_guards_sanos()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'rsuelvo' and p.proname = 'fn_es_service_role';

  -- prohibido: current_user como OR incondicional (bypass P0 2026-09-22)
  if v_def like '%current_user%' and v_def not like '%auth.jwt() is null%' then
    return jsonb_build_object('ok', false, 'codigo', 'bypass_current_user');
  end if;
  -- obligatorio: via JWT con service_role
  if v_def not like '%auth.jwt()%role%service_role%' then
    return jsonb_build_object('ok', false, 'codigo', 'sin_check_jwt');
  end if;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'rsuelvo' and p.proname = 'fn_tiene_aal2';
  if v_def like '%current_user%' and v_def not like '%auth.jwt() is null%' then
    return jsonb_build_object('ok', false, 'codigo', 'bypass_current_user_aal2');
  end if;

  -- comportamental: sin JWT (backend) debe seguir true
  if not fn_es_service_role() then
    return jsonb_build_object('ok', false, 'codigo', 'backend_roto');
  end if;

  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_verificar_guards_sanos() from public;
grant execute on function rsuelvo.fn_verificar_guards_sanos() to authenticated, service_role;

select rsuelvo.fn_verificar_guards_sanos();
-- ═══ MIG 89 (aplicada 2026-09-22: N-6 + SUPPORT writes) ═══
-- 89_iam6_depositos_support.sql
-- IAM-6 DB (paso 1, para revision antes de clientes).
-- N-6 DB+Storage (credits.deposit.read congelado: SUPERADMIN + OWNER mismo
-- comercio; SYSADMIN/SUPPORT DENY) + SUPPORT fuera de writes. Helpers
-- compartidos INTACTOS (dependency audit: 46 policies los usan; ventas/n8n
-- a salvo). Export server-side: no existe RPC frontera -> best-effort
-- documentado, sin cambio DB.

-- ── 1. N-6 tabla ──
drop policy if exists compras_select on rsuelvo.tbl_compras_creditos;
create policy compras_select on rsuelvo.tbl_compras_creditos
  for select to authenticated
  using (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_es_owner(id_comercio));

drop policy if exists credit_purchases_select on rsuelvo.tbl_compras_creditos;
create policy credit_purchases_select on rsuelvo.tbl_compras_creditos
  for select to authenticated
  using (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_es_owner(id_comercio));

-- ── 2. N-6 storage ──
drop policy if exists depositos_staff_select on storage.objects;
create policy depositos_staff_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
     and rsuelvo.fn_es_superadmin());

drop policy if exists depositos_dueno_select on storage.objects;
create policy depositos_dueno_select on storage.objects
  for select to authenticated
  using (bucket_id = 'depositos-creditos'
     and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
     and rsuelvo.fn_es_owner((split_part(name, '/', 1))::uuid));
-- parche IAM-6 aplicado sobre cuerpo vivo 66
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_compra_creditos(p_id_compra uuid, p_decision text, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()
    or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN');
  v_c record;
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not (rsuelvo.fn_es_superadmin() or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')) then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        motivo_rechazo = nullif(trim(coalesce(p_motivo,'')), ''),
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  if v_cuenta is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cuenta');
  end if;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$function$
;
-- parche IAM-6: SUPPORT fuera de alta (cuerpo vivo)
CREATE OR REPLACE FUNCTION rsuelvo.fn_alta_comercio(p_nombre text, p_codigo_tienda text, p_sucursal text DEFAULT 'Sucursal Principal'::text, p_telefono text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_reserva_min integer DEFAULT 10, p_verificacion_automatica boolean DEFAULT false, p_bonus integer DEFAULT 100, p_estado rsuelvo.estado_comercio DEFAULT 'ACTIVO'::rsuelvo.estado_comercio, p_id_solicitud uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_codigo text := upper(trim(p_codigo_tienda));
  v_estado_final rsuelvo.estado_comercio;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_sol record;
begin
  if rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin() then
    v_estado_final := p_estado;
  elsif rsuelvo.fn_tiene_rol('ROLE_SYSADMIN') then
    v_estado_final := 'PENDIENTE_APROBACION';
  else
    raise exception 'solo staff autorizado';
  end if;

  if v_estado_final not in ('ACTIVO', 'PENDIENTE_APROBACION') then
    return jsonb_build_object('ok', false, 'codigo', 'estado_invalido');
  end if;

  if coalesce(p_bonus, 0) < 0 then
    return jsonb_build_object('ok', false, 'codigo', 'bonus_invalido');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;

  if p_id_solicitud is not null then
    select id_solicitud, codigo_sugerido, estado into v_sol
    from rsuelvo.tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
    if not found then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
    end if;
    if v_sol.estado != 'APROBADA' then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_aprobada');
    end if;
    if v_sol.codigo_sugerido is null then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_sin_codigo');
    end if;
    if exists (select 1 from rsuelvo.tbl_comercios where id_solicitud = p_id_solicitud) then
      return jsonb_build_object('ok', false, 'codigo', 'solicitud_consumida');
    end if;
    if upper(trim(p_codigo_tienda)) != v_sol.codigo_sugerido then
      return jsonb_build_object('ok', false, 'codigo', 'codigo_mismatch');
    end if;
    v_codigo := v_sol.codigo_sugerido;
  end if;

  if exists (select 1 from rsuelvo.tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;



  insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado, id_solicitud)
  values (v_codigo, p_nombre, p_telefono, p_email, v_estado_final, p_id_solicitud)
  returning id_comercio into v_comercio;

  insert into rsuelvo.tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, p_reserva_min, p_verificacion_automatica);

  insert into rsuelvo.tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into rsuelvo.tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto)
  values
    (v_comercio, v_cuenta, 'BONIFICACION', p_bonus, 0, p_bonus, 'Bono de bienvenida (alta)');

  update rsuelvo.tbl_cuentas_creditos
  set saldo_actual = p_bonus
  where id_cuenta_creditos = v_cuenta;

  insert into rsuelvo.tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, p_sucursal, true)
  returning id_sucursal into v_sucursal;

  -- D16: numero universal; pnid universal por defecto (por comercio a futuro)
  insert into rsuelvo.tbl_canal_whatsapp (id_comercio, id_sucursal, numero, provider, provider_phone_number_id, status, activo)
  values (v_comercio, v_sucursal, '59157005003', 'META', '1275143265687773', 'DESCONECTADO', true);

  -- metodo de pago por defecto (fn_generar_cobro lo exige)
  insert into rsuelvo.tbl_metodos_pago (id_comercio, nombre, tipo, activo)
  values (v_comercio, 'QR Estático', 'QR', true);

  return jsonb_build_object(
    'ok', true,
    'id_comercio', v_comercio,
    'codigo_tienda', v_codigo,
    'estado', v_estado_final,
    'id_sucursal', v_sucursal,
    'bonus', p_bonus,
    'id_solicitud', p_id_solicitud
  );
end;
$function$
;
-- ═══ MIG 90 (aplicada 2026-09-22: resolve solo SUPERADMIN) ═══
-- mig 90: resolve solo SUPERADMIN (+service_role backend)
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_compra_creditos(p_id_compra uuid, p_decision text, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin();
  v_c record;
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not rsuelvo.fn_es_superadmin() then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        motivo_rechazo = nullif(trim(coalesce(p_motivo,'')), ''),
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  if v_cuenta is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cuenta');
  end if;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$function$
;
-- ═══ MIG 91 (aplicada 2026-09-22: CANCELAR consistente) ═══
-- mig 91: CANCELAR consistente service_role/superadmin
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_compra_creditos(p_id_compra uuid, p_decision text, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin();
  v_c record;
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        motivo_rechazo = nullif(trim(coalesce(p_motivo,'')), ''),
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  if v_cuenta is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cuenta');
  end if;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$function$
;
-- ═══ MIG 92 (aplicada 2026-09-22: consentimiento legal) ═══
-- 92_consentimiento_legal.sql
-- IAM-7 backend. Implementa D-IAM-CONSENTIMIENTO.md rev3.
-- Seeds = BORRADOR PENDIENTE VALIDACION LEGAL BOLIVIA.

-- ── 1. documentos ──
create table if not exists rsuelvo.tbl_documentos_legales (
  id_documento uuid primary key default gen_random_uuid(),
  tipo text not null,
  version text not null,
  titulo text not null,
  url_texto text not null,
  content_sha256 text not null,
  obligatorio boolean not null,
  vigente_desde timestamptz not null default now(),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint doc_tipo_chk check (tipo in ('TERMINOS','PRIVACIDAD','TRATAMIENTO_DATOS')),
  constraint doc_sha_chk check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint doc_version_chk check (version <> '')
);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'doc_tipo_version_uniq') then
    alter table rsuelvo.tbl_documentos_legales
      add constraint doc_tipo_version_uniq unique (tipo, version);
  end if;
end $$;
create unique index if not exists doc_activo_unico
  on rsuelvo.tbl_documentos_legales (tipo) where activo = true;
alter table rsuelvo.tbl_documentos_legales enable row level security;
grant select on rsuelvo.tbl_documentos_legales to anon, authenticated, service_role;

-- lectura: solo publicados (activos). Sin policies de escritura = deny.
drop policy if exists documentos_public_read on rsuelvo.tbl_documentos_legales;
create policy documentos_public_read on rsuelvo.tbl_documentos_legales
  for select to anon, authenticated using (activo = true);

-- ── 2. aceptaciones ──
create table if not exists rsuelvo.tbl_aceptaciones (
  id_aceptacion uuid primary key default gen_random_uuid(),
  id_usuario uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete cascade,
  id_documento uuid not null references rsuelvo.tbl_documentos_legales(id_documento) on delete restrict,
  accepted_at timestamptz not null default now(),
  canal text not null,
  created_at timestamptz not null default now(),
  constraint acept_canal_chk check (canal in ('APP','WEB'))
);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'acept_usuario_doc_uniq') then
    alter table rsuelvo.tbl_aceptaciones
      add constraint acept_usuario_doc_uniq unique (id_usuario, id_documento);
  end if;
end $$;
-- deny-by-default total: sin policies -> solo service_role + SECURITY DEFINER
alter table rsuelvo.tbl_aceptaciones enable row level security;
grant all on rsuelvo.tbl_aceptaciones to service_role;

-- ── 3. inmutabilidad verificable ──
create or replace function rsuelvo.fn_doc_inmutable()
returns trigger
language plpgsql security definer
set search_path to 'rsuelvo', 'public'
as $fn$
begin
  if exists (select 1 from tbl_aceptaciones where id_documento = old.id_documento) then
    if (new.tipo, new.version, new.titulo, new.url_texto, new.content_sha256,
        new.obligatorio, new.vigente_desde)
       is distinct from
       (old.tipo, old.version, old.titulo, old.url_texto, old.content_sha256,
        old.obligatorio, old.vigente_desde) then
      raise exception 'documento con aceptaciones es inmutable (solo activo)';
    end if;
  end if;
  return new;
end;
$fn$;
drop trigger if exists trg_doc_inmutable on rsuelvo.tbl_documentos_legales;
create trigger trg_doc_inmutable
  before update on rsuelvo.tbl_documentos_legales
  for each row execute function rsuelvo.fn_doc_inmutable();

-- ── 4. pendientes (fuente server-side) ──
create or replace function rsuelvo.fn_documentos_pendientes()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  return jsonb_build_object('ok', true, 'documentos', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_documento', d.id_documento, 'tipo', d.tipo, 'version', d.version,
      'titulo', d.titulo, 'url_texto', d.url_texto,
      'content_sha256', d.content_sha256, 'obligatorio', d.obligatorio,
      'vigente_desde', d.vigente_desde
    ) order by d.tipo)
    from tbl_documentos_legales d
    where d.activo = true
      and not exists (select 1 from tbl_aceptaciones a
                      where a.id_usuario = v_usuario
                        and a.id_documento = d.id_documento)
  ), '[]'::jsonb));
end;
$fn$;
revoke execute on function rsuelvo.fn_documentos_pendientes() from public;
grant execute on function rsuelvo.fn_documentos_pendientes() to authenticated, service_role;

-- ── 5. aceptar (idempotente, todo server-side) ──
create or replace function rsuelvo.fn_aceptar_documento(p_id_documento uuid, p_canal text)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_doc record;
begin
  if p_canal not in ('APP','WEB') then
    return jsonb_build_object('ok', false, 'codigo', 'canal_invalido');
  end if;
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_doc from tbl_documentos_legales where id_documento = p_id_documento;
  if v_doc.id_documento is null then
    return jsonb_build_object('ok', false, 'codigo', 'documento_no_existe');
  end if;
  if not v_doc.activo or v_doc.vigente_desde > now() then
    return jsonb_build_object('ok', false, 'codigo', 'documento_no_vigente');
  end if;
  -- no aceptar obsoleto habiendo version activa mas nueva del mismo tipo
  if exists (select 1 from tbl_documentos_legales
             where tipo = v_doc.tipo and activo = true
               and vigente_desde > v_doc.vigente_desde
               and id_documento <> v_doc.id_documento) then
    return jsonb_build_object('ok', false, 'codigo', 'version_obsoleta');
  end if;
  insert into tbl_aceptaciones (id_usuario, id_documento, canal)
  values (v_usuario, p_id_documento, p_canal)
  on conflict (id_usuario, id_documento) do nothing;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (null, v_usuario, 'documento_aceptado', 'tbl_aceptaciones', p_id_documento);
  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_aceptar_documento(uuid, text) from public;
grant execute on function rsuelvo.fn_aceptar_documento(uuid, text) to authenticated, service_role;

-- ── 6. seed v1 BORRADOR ──
insert into rsuelvo.tbl_documentos_legales
  (tipo, version, titulo, url_texto, content_sha256, obligatorio)
values
  ('TERMINOS', '1.0', 'Términos del servicio RSUELVO (BORRADOR — PENDIENTE VALIDACIÓN LEGAL BOLIVIA)', 'legal/terminos-1.0', '0000000000000000000000000000000000000000000000000000000000000000', true),
  ('PRIVACIDAD', '1.0', 'Política de privacidad RSUELVO (BORRADOR — PENDIENTE VALIDACIÓN LEGAL BOLIVIA)', 'legal/privacidad-1.0', '1111111111111111111111111111111111111111111111111111111111111111', true),
  ('TRATAMIENTO_DATOS', '1.0', 'Consentimiento de tratamiento de datos RSUELVO (BORRADOR — PENDIENTE VALIDACIÓN LEGAL BOLIVIA)', 'legal/tratamiento-1.0', '2222222222222222222222222222222222222222222222222222222222222222', true)
on conflict (tipo, version) do nothing;
-- ═══ MIG 93 (aplicada 2026-09-22: fixes consentimiento) ═══
-- 93_consentimiento_fixes.sql
-- IAM-7 parche revision ChatGPT. NO reescribe mig 92.
-- 1) pendientes solo vigentes. 2) obsoleta antes que vigencia.
-- 3) auditoria solo en insercion real + codigo ya_aceptado.

create or replace function rsuelvo.fn_documentos_pendientes()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  return jsonb_build_object('ok', true, 'documentos', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_documento', d.id_documento, 'tipo', d.tipo, 'version', d.version,
      'titulo', d.titulo, 'url_texto', d.url_texto,
      'content_sha256', d.content_sha256, 'obligatorio', d.obligatorio,
      'vigente_desde', d.vigente_desde
    ) order by d.tipo)
    from tbl_documentos_legales d
    where d.activo = true
      and d.vigente_desde <= now()
      and not exists (select 1 from tbl_aceptaciones a
                      where a.id_usuario = v_usuario
                        and a.id_documento = d.id_documento)
  ), '[]'::jsonb));
end;
$fn$;

create or replace function rsuelvo.fn_aceptar_documento(p_id_documento uuid, p_canal text)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_doc record;
  v_id_aceptacion uuid;
begin
  if p_canal not in ('APP','WEB') then
    return jsonb_build_object('ok', false, 'codigo', 'canal_invalido');
  end if;
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_doc from tbl_documentos_legales where id_documento = p_id_documento;
  if v_doc.id_documento is null then
    return jsonb_build_object('ok', false, 'codigo', 'documento_no_existe');
  end if;
  -- supersedido por otra version activa+vigente del mismo tipo
  if exists (select 1 from tbl_documentos_legales
             where tipo = v_doc.tipo and activo = true and vigente_desde <= now()
               and id_documento <> v_doc.id_documento) then
    return jsonb_build_object('ok', false, 'codigo', 'version_obsoleta');
  end if;
  if not v_doc.activo or v_doc.vigente_desde > now() then
    return jsonb_build_object('ok', false, 'codigo', 'documento_no_vigente');
  end if;
  insert into tbl_aceptaciones (id_usuario, id_documento, canal)
  values (v_usuario, p_id_documento, p_canal)
  on conflict (id_usuario, id_documento) do nothing
  returning id_aceptacion into v_id_aceptacion;
  if v_id_aceptacion is null then
    return jsonb_build_object('ok', true, 'codigo', 'ya_aceptado');
  end if;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (null, v_usuario, 'documento_aceptado', 'tbl_aceptaciones', v_id_aceptacion);
  return jsonb_build_object('ok', true, 'codigo', 'aceptado');
end;
$fn$;
-- ═══ MIG 94 (aplicada 2026-09-22: auto-alta V0) ═══
-- 94_auto_alta_v0.sql
-- IAM-8 backend. D-IAM-ONBOARDING.md rev3.
-- Estado, helper, idempotencia, auto-alta atomica, guards V0.

-- ── 1. estado ──
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'estado_comercio' and e.enumlabel = 'PENDIENTE_VERIFICACION') then
    alter type rsuelvo.estado_comercio add value 'PENDIENTE_VERIFICACION';
  end if;
end $$;

-- ── 2. helper NUEVO (pertenencia != habilitacion) ──
create or replace function rsuelvo.fn_comercio_habilitado(p_id_comercio uuid)
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select exists (select 1 from tbl_comercios
                 where id_comercio = p_id_comercio and estado = 'ACTIVO');
$fn$;
revoke execute on function rsuelvo.fn_comercio_habilitado(uuid) from public;
grant execute on function rsuelvo.fn_comercio_habilitado(uuid) to authenticated, service_role;

-- ── 3. idempotencia + intentos registro ──
create table if not exists rsuelvo.tbl_auto_alta_requests (
  id_usuario uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete cascade,
  id_request uuid not null,
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete cascade,
  created_at timestamptz not null default now(),
  constraint auto_alta_req_uniq unique (id_usuario, id_request)
);
alter table rsuelvo.tbl_auto_alta_requests enable row level security;
grant all on rsuelvo.tbl_auto_alta_requests to service_role;

create table if not exists rsuelvo.tbl_registro_intentos (
  id bigint generated always as identity primary key,
  email text not null,
  ip text null,
  created_at timestamptz not null default now()
);
create index if not exists reg_intentos_email_fecha
  on rsuelvo.tbl_registro_intentos (lower(email), created_at);
alter table rsuelvo.tbl_registro_intentos enable row level security;
grant all on rsuelvo.tbl_registro_intentos to service_role;

-- ── 4. fn_auto_alta_comercio ──
create or replace function rsuelvo.fn_auto_alta_comercio(
  p_request_id uuid,
  p_nombre text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono text default null,
  p_email text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email_ok boolean;
  v_codigo text := upper(trim(p_codigo_tienda));
  v_existente uuid;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_admins integer;
  v_owner uuid;
begin
  -- identidad: JWT + tbl_usuarios activo (jamás params cliente)
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    -- auto-reparo de perfil (retry tras EF registro)
    insert into tbl_usuarios (auth_user_id, email, nombre, activo)
    select v_auth, au.email, coalesce(au.raw_user_meta_data->>'nombre', 'Comerciante'), true
    from auth.users au where au.id = v_auth
    on conflict (auth_user_id) do nothing
    returning id_usuario into v_usuario;
    if v_usuario is null then
      select id_usuario into v_usuario from tbl_usuarios where auth_user_id = v_auth and activo;
    end if;
    if v_usuario is null then
      return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
    end if;
  end if;

  -- email verificado: fuente server-side auth.users (jamás cliente)
  select (email_confirmed_at is not null) into v_email_ok
  from auth.users where id = v_auth;
  if coalesce(v_email_ok, false) = false then
    return jsonb_build_object('ok', false, 'codigo', 'email_no_verificado');
  end if;

  -- idempotencia: mismo user+request -> mismo comercio
  select id_comercio into v_existente from tbl_auto_alta_requests
  where id_usuario = v_usuario and id_request = p_request_id;
  if v_existente is not null then
    return jsonb_build_object('ok', true, 'id_comercio', v_existente, 'repetido', true);
  end if;

  -- rate-limit: 1 nuevo comercio / 24h (antiabuso, no vitalicio)
  if exists (select 1 from tbl_auto_alta_requests
             where id_usuario = v_usuario and created_at > now() - interval '24 hours') then
    return jsonb_build_object('ok', false, 'codigo', 'rate_limit');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;
  if exists (select 1 from tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;
  if nullif(trim(coalesce(p_nombre, '')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'nombre_invalido');
  end if;

  -- creacion atomica
  insert into tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, trim(p_nombre), nullif(trim(coalesce(p_telefono, '')), ''),
          (select email from tbl_usuarios where id_usuario = v_usuario), 'PENDIENTE_VERIFICACION')
  returning id_comercio into v_comercio;

  insert into tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, 10, false);

  insert into tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, coalesce(nullif(trim(p_sucursal), ''), 'Sucursal Principal'), true)
  returning id_sucursal into v_sucursal;

  insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
  values (v_usuario, v_comercio,
          (select id_rol from tbl_roles where codigo = 'ROLE_TENANT_ADMIN'),
          v_sucursal, 'ACTIVE');

  update tbl_comercios set propietario_id = v_usuario where id_comercio = v_comercio;

  insert into tbl_auto_alta_requests (id_usuario, id_request, id_comercio)
  values (v_usuario, p_request_id, v_comercio);

  -- postcondiciones
  select count(*) into v_admins
  from tbl_usuario_comercio uc join tbl_roles r on r.id_rol = uc.id_rol
  where uc.id_comercio = v_comercio and uc.estado = 'ACTIVE'
    and r.codigo = 'ROLE_TENANT_ADMIN';
  select propietario_id into v_owner from tbl_comercios where id_comercio = v_comercio;
  if v_admins != 1 or v_owner is distinct from v_usuario then
    raise exception 'postcondicion owner invalida';
  end if;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_comercio, v_usuario, 'auto_alta', 'tbl_comercios', v_comercio);

  return jsonb_build_object('ok', true, 'id_comercio', v_comercio,
    'codigo_tienda', v_codigo, 'estado', 'PENDIENTE_VERIFICACION',
    'id_sucursal', v_sucursal, 'repetido', false);
end;
$fn$;
revoke execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text, text) from public;
grant execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text, text) to authenticated, service_role;

-- ── 5. V0: solicitar requiere habilitado (cuerpo vivo 63) ──
CREATE OR REPLACE FUNCTION rsuelvo.fn_solicitar_creditos(p_id_paquete uuid, p_comprobante_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_comercio uuid;
  v_n integer;
  v_paq record;
  v_compra uuid;
begin
  select uc.id_comercio into v_comercio
  from tbl_usuario_comercio uc
  join tbl_usuarios u on u.id_usuario = uc.id_usuario
  join tbl_roles r on r.id_rol = uc.id_rol
  where u.auth_user_id = auth.uid()
    and u.activo and uc.activo
    and r.codigo = 'ROLE_TENANT_ADMIN';

  select count(*) into v_n from (
    select uc.id_comercio
    from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario = uc.id_usuario
    join tbl_roles r on r.id_rol = uc.id_rol
    where u.auth_user_id = auth.uid()
      and u.activo and uc.activo
      and r.codigo = 'ROLE_TENANT_ADMIN'
  ) t;
  if v_comercio is null then
    return jsonb_build_object('ok', false, 'codigo', 'solo_dueno');
  end if;
  if not rsuelvo.fn_comercio_habilitado(v_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_habilitado');
  end if;
  if v_n > 1 then
    return jsonb_build_object('ok', false, 'codigo', 'multi_comercio');
  end if;

  select id_paquete, creditos, precio into v_paq
  from tbl_paquetes_creditos
  where id_paquete = p_id_paquete and activo;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'paquete_invalido');
  end if;

  if nullif(trim(coalesce(p_comprobante_url,'')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'falta_comprobante');
  end if;

  insert into tbl_compras_creditos
    (id_comercio, id_paquete, creditos_comprados, monto, moneda, estado, comprobante_deposito_url)
  values
    (v_comercio, v_paq.id_paquete, v_paq.creditos, v_paq.precio, 'Bs', 'PENDIENTE', trim(p_comprobante_url))
  returning id_compra into v_compra;

  return jsonb_build_object('ok', true, 'id_compra', v_compra,
    'creditos', v_paq.creditos, 'monto', v_paq.precio);
end;
$function$
;

-- ── 6. V0: transferir requiere ACTIVO ──
create or replace function rsuelvo.fn_iniciar_transferencia(p_id_comercio uuid, p_destino uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_tid uuid;
  v_estado_tmp rsuelvo.estado_comercio;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;
  if p_destino = v_usuario then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  if not exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_roles r on r.id_rol = uc.id_rol
    where uc.id_usuario = p_destino and uc.id_comercio = p_id_comercio
      and r.codigo = 'ROLE_TENANT_ADMIN' and uc.estado = 'ACTIVE') then
    return jsonb_build_object('ok', false, 'codigo', 'destino_invalido');
  end if;
  -- FIX84-2: expiradas no bloquean (sweep antes de comprobar)
  select estado into v_estado_tmp from tbl_comercios where id_comercio = p_id_comercio;
  if coalesce(v_estado_tmp::text, '') <> 'ACTIVO' then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_habilitado');
  end if;
  update tbl_transferencias_propiedad set estado = 'VENCIDA'
  where id_comercio = p_id_comercio and estado = 'PENDIENTE' and expira_at <= now();
  if exists (select 1 from tbl_transferencias_propiedad
             where id_comercio = p_id_comercio and estado = 'PENDIENTE') then
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end if;
  begin
    insert into tbl_transferencias_propiedad
      (id_comercio, propietario_origen, propietario_destino, initiated_by)
    values (p_id_comercio, v_usuario, p_destino, v_usuario)
    returning id into v_tid;
  exception when unique_violation then
    -- FIX84-3: carrera -> determinista, sin excepcion SQL
    return jsonb_build_object('ok', false, 'codigo', 'transferencia_pendiente');
  end;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'transferencia_iniciada', 'tbl_transferencias_propiedad', v_tid);
  return jsonb_build_object('ok', true, 'id_transferencia', v_tid);
end;
$fn$;;

-- ── 7. V0: QR solo habilitado (lectura publica de pago intacta) ──
drop policy if exists qr_pagos_dueno_insert on storage.objects;
create policy qr_pagos_dueno_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'qr-pagos'
    and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
    and rsuelvo.fn_es_admin_comercio((split_part(name, '/', 1))::uuid)
    and rsuelvo.fn_comercio_habilitado((split_part(name, '/', 1))::uuid));

drop policy if exists qr_pagos_dueno_update on storage.objects;
create policy qr_pagos_dueno_update on storage.objects
  for update to authenticated
  using (bucket_id = 'qr-pagos'
    and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
    and rsuelvo.fn_es_admin_comercio((split_part(name, '/', 1))::uuid)
    and rsuelvo.fn_comercio_habilitado((split_part(name, '/', 1))::uuid))
  with check (bucket_id = 'qr-pagos'
    and rsuelvo.fn_comercio_habilitado((split_part(name, '/', 1))::uuid));
-- ═══ MIG 95 (aplicada 2026-09-22: firma canonica + reclamo) ═══
-- 95_auto_alta_firma_canonical.sql
-- IAM-8 parche: firma canonica sin p_email + reclamo de fila huerfana.
-- Elimina overload anterior (PostgREST ambiguo si conviven).

drop function if exists rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text, text);

create or replace function rsuelvo.fn_auto_alta_comercio(
  p_request_id uuid,
  p_nombre_comercio text,
  p_codigo_tienda text,
  p_sucursal text default 'Sucursal Principal',
  p_telefono_comercio text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_email_auth text;
  v_email_ok boolean;
  v_codigo text := upper(trim(p_codigo_tienda));
  v_existente uuid;
  v_comercio uuid;
  v_sucursal uuid;
  v_cuenta uuid;
  v_admins integer;
  v_owner uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    -- reclamo de fila huerfana por email (reparo EF retry)
    select email into v_email_auth from auth.users where id = v_auth;
    if v_email_auth is not null then
      update tbl_usuarios set auth_user_id = v_auth, updated_at = now()
      where lower(email) = lower(v_email_auth) and auth_user_id is null
      returning id_usuario into v_usuario;
    end if;
  end if;
  if v_usuario is null then
    insert into tbl_usuarios (auth_user_id, email, nombre, activo)
    select v_auth, au.email,
           coalesce(nullif(trim(au.raw_user_meta_data->>'nombre'), ''), 'Comerciante'),
           true
    from auth.users au where au.id = v_auth
    on conflict (auth_user_id) do nothing
    returning id_usuario into v_usuario;
    if v_usuario is null then
      select id_usuario into v_usuario from tbl_usuarios where auth_user_id = v_auth and activo;
    end if;
    if v_usuario is null then
      return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
    end if;
  end if;

  select (email_confirmed_at is not null) into v_email_ok
  from auth.users where id = v_auth;
  if coalesce(v_email_ok, false) = false then
    return jsonb_build_object('ok', false, 'codigo', 'email_no_verificado');
  end if;

  select id_comercio into v_existente from tbl_auto_alta_requests
  where id_usuario = v_usuario and id_request = p_request_id;
  if v_existente is not null then
    return jsonb_build_object('ok', true, 'id_comercio', v_existente, 'repetido', true);
  end if;

  if exists (select 1 from tbl_auto_alta_requests
             where id_usuario = v_usuario and created_at > now() - interval '24 hours') then
    return jsonb_build_object('ok', false, 'codigo', 'rate_limit');
  end if;

  if v_codigo !~ '^[A-Z0-9]{3}$' or position('O' in v_codigo) > 0 then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_invalido');
  end if;
  if exists (select 1 from tbl_comercios where codigo_tienda = v_codigo) then
    return jsonb_build_object('ok', false, 'codigo', 'codigo_en_uso');
  end if;
  if nullif(trim(coalesce(p_nombre_comercio, '')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'nombre_invalido');
  end if;

  insert into tbl_comercios (codigo_tienda, nombre_comercial, telefono, email, estado)
  values (v_codigo, trim(p_nombre_comercio),
          nullif(trim(coalesce(p_telefono_comercio, '')), ''),
          (select email from tbl_usuarios where id_usuario = v_usuario), 'PENDIENTE_VERIFICACION')
  returning id_comercio into v_comercio;

  insert into tbl_comercio_config (id_comercio, tiempo_reserva_minutos, verificacion_automatica)
  values (v_comercio, 10, false);

  insert into tbl_cuentas_creditos (id_comercio, saldo_actual)
  values (v_comercio, 0)
  returning id_cuenta_creditos into v_cuenta;

  insert into tbl_sucursales (id_comercio, nombre, activo)
  values (v_comercio, coalesce(nullif(trim(p_sucursal), ''), 'Sucursal Principal'), true)
  returning id_sucursal into v_sucursal;

  insert into tbl_usuario_comercio (id_usuario, id_comercio, id_rol, id_sucursal, estado)
  values (v_usuario, v_comercio,
          (select id_rol from tbl_roles where codigo = 'ROLE_TENANT_ADMIN'),
          v_sucursal, 'ACTIVE');

  update tbl_comercios set propietario_id = v_usuario where id_comercio = v_comercio;

  insert into tbl_auto_alta_requests (id_usuario, id_request, id_comercio)
  values (v_usuario, p_request_id, v_comercio);

  select count(*) into v_admins
  from tbl_usuario_comercio uc join tbl_roles r on r.id_rol = uc.id_rol
  where uc.id_comercio = v_comercio and uc.estado = 'ACTIVE'
    and r.codigo = 'ROLE_TENANT_ADMIN';
  select propietario_id into v_owner from tbl_comercios where id_comercio = v_comercio;
  if v_admins != 1 or v_owner is distinct from v_usuario then
    raise exception 'postcondicion owner invalida';
  end if;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (v_comercio, v_usuario, 'auto_alta', 'tbl_comercios', v_comercio);

  return jsonb_build_object('ok', true, 'id_comercio', v_comercio,
    'codigo_tienda', v_codigo, 'estado', 'PENDIENTE_VERIFICACION',
    'id_sucursal', v_sucursal, 'repetido', false);
end;
$fn$;
revoke execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text) from public;
grant execute on function rsuelvo.fn_auto_alta_comercio(uuid, text, text, text, text) to authenticated, service_role;
-- ═══ MIG 96 (aplicada 2026-09-22: verificacion V1) ═══
-- 96_verificacion_v1.sql
-- IAM-9 backend. D-IAM-VERIFICACION.md rev2 + GO ChatGPT.
-- V1 = PERFIL COMERCIAL DECLARATIVO COMPLETO (nunca "empresa verificada").

-- ── 1. evidencia append-only ──
create table if not exists rsuelvo.tbl_verificaciones_comercio (
  id_verificacion uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete cascade,
  nivel text not null default 'V1',
  estado text not null,
  origen text not null,
  id_verificador uuid null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  checks_snapshot jsonb not null,
  motivo text null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  revoked_at timestamptz null,
  revoked_by uuid null references rsuelvo.tbl_usuarios(id_usuario) on delete set null,
  motivo_revocacion text null,
  constraint verif_estado_chk check (estado in ('APROBADA_AUTOMATICA','APROBADA_MANUAL','RECHAZADA','REVOCADA')),
  constraint verif_origen_chk check (origen in ('SYSTEM','SUPERADMIN')),
  constraint verif_nivel_chk check (nivel = 'V1')
);
alter table rsuelvo.tbl_verificaciones_comercio enable row level security;
grant all on rsuelvo.tbl_verificaciones_comercio to service_role;

-- ── 2. builder de checks (server-side, nombres exactos) ──
create or replace function rsuelvo.fn_checks_verificacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_c record;
  v_owner uuid;
  v_email_ok boolean;
  v_suc_ok boolean;
  v_qr_ok boolean;
  v_cfg_ok boolean;
  v_nit text;
  v_razon text;
  v_tel text;
begin
  select * into v_c from tbl_comercios where id_comercio = p_id_comercio;
  if v_c.id_comercio is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  v_owner := v_c.propietario_id;
  v_nit := upper(trim(coalesce(v_c.nit, '')));
  v_razon := trim(coalesce(v_c.razon_social, ''));
  v_tel := trim(coalesce(v_c.telefono, ''));

  if v_owner is not null then
    select (email_confirmed_at is not null) into v_email_ok
    from auth.users au join tbl_usuarios u on u.auth_user_id = au.id
    where u.id_usuario = v_owner;
  end if;

  select exists (
    select 1 from tbl_sucursales
    where id_comercio = p_id_comercio and activo
      and nullif(trim(coalesce(direccion, '')), '') is not null
  ) into v_suc_ok;

  select exists (
    select 1 from storage.objects
    where bucket_id = 'qr-pagos' and name like p_id_comercio::text || '/%'
  ) into v_qr_ok;

  select exists (
    select 1 from tbl_comercio_config
    where id_comercio = p_id_comercio
      and tiempo_reserva_minutos between 1 and 1440
  ) into v_cfg_ok;

  return jsonb_build_object(
    'ok', true,
    'checks', jsonb_build_object(
      'nit', jsonb_build_object('pass', v_nit ~ '^[0-9]{5,20}$', 'mode', 'syntactic_only'),
      'razon_social', jsonb_build_object('pass', v_razon <> '' and length(v_razon) <= 200),
      'telefono', jsonb_build_object('pass', v_tel ~ '^[0-9+\s]{7,20}$', 'mode', 'present_unverified'),
      'email_owner', jsonb_build_object('pass', coalesce(v_email_ok, false), 'mode', 'auth_confirmed'),
      'sucursal', jsonb_build_object('pass', v_suc_ok),
      'qr', jsonb_build_object('pass', v_qr_ok),
      'config', jsonb_build_object('pass', v_cfg_ok)
    )
  );
end;
$fn$;
revoke execute on function rsuelvo.fn_checks_verificacion_v1(uuid) from public;
grant execute on function rsuelvo.fn_checks_verificacion_v1(uuid) to authenticated, service_role;

-- ── 3. consulta (sin mutar) ──
create or replace function rsuelvo.fn_estado_verificacion_comercio(p_id_comercio uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_res jsonb;
  v_faltantes text[];
  v_k text;
begin
  if not (fn_es_service_role() or fn_es_superadmin()
          or fn_es_admin_comercio(p_id_comercio)) then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  v_res := fn_checks_verificacion_v1(p_id_comercio);
  if (v_res ->> 'ok')::boolean = false then return v_res; end if;
  select array_agg(k) into v_faltantes
  from jsonb_object_keys(v_res -> 'checks') k
  where ((v_res -> 'checks' -> k ->> 'pass')::boolean) = false;
  return jsonb_build_object('ok', true, 'checks', v_res -> 'checks',
    'faltantes', coalesce(v_faltantes, '{}'));
end;
$fn$;
revoke execute on function rsuelvo.fn_estado_verificacion_comercio(uuid) from public;
grant execute on function rsuelvo.fn_estado_verificacion_comercio(uuid) to authenticated, service_role;

-- ── 4. habilitacion (owner + AAL2, atomica, idempotente) ──
create or replace function rsuelvo.fn_solicitar_habilitacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
  v_res jsonb;
  v_faltantes text[];
  v_k text;
  v_vid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_es_service_role() and not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) and not fn_es_service_role() then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;

  -- lock + recheck (concurrencia: una sola transicion efectiva)
  select estado into v_estado from tbl_comercios
  where id_comercio = p_id_comercio for update;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'ACTIVO' then
    return jsonb_build_object('ok', true, 'codigo', 'ya_activo');
  end if;
  if v_estado != 'PENDIENTE_VERIFICACION' then
    return jsonb_build_object('ok', false, 'codigo', 'estado_incompatible');
  end if;

  v_res := fn_checks_verificacion_v1(p_id_comercio);
  select array_agg(k) into v_faltantes
  from jsonb_object_keys(v_res -> 'checks') k
  where ((v_res -> 'checks' -> k ->> 'pass')::boolean) = false;

  if v_faltantes is not null then
    insert into tbl_verificaciones_comercio
      (id_comercio, estado, origen, id_verificador, checks_snapshot, motivo, resolved_at)
    values (p_id_comercio, 'RECHAZADA', 'SYSTEM', v_usuario,
            v_res -> 'checks', 'faltantes: ' || array_to_string(v_faltantes, ','), now());
    return jsonb_build_object('ok', false, 'codigo', 'requisitos_faltantes',
      'faltantes', v_faltantes);
  end if;

  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot, resolved_at)
  values (p_id_comercio, 'APROBADA_AUTOMATICA', 'SYSTEM', v_usuario,
          v_res -> 'checks', now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'ACTIVO', updated_at = now()
  where id_comercio = p_id_comercio;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_aprobada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true, 'codigo', 'habilitado');
end;
$fn$;
revoke execute on function rsuelvo.fn_solicitar_habilitacion_v1(uuid) from public;
grant execute on function rsuelvo.fn_solicitar_habilitacion_v1(uuid) to authenticated, service_role;

-- ── 5. revocacion SuperAdmin (V1->V0 + REVOCADA; fraude = flujo aparte) ──
create or replace function rsuelvo.fn_revocar_verificacion_v1(
  p_id_comercio uuid, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_vid uuid;
  v_checks jsonb;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;

  v_checks := (fn_checks_verificacion_v1(p_id_comercio) -> 'checks');
  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot,
     motivo_revocacion, revoked_at, revoked_by, resolved_at)
  values (p_id_comercio, 'REVOCADA', 'SUPERADMIN', v_usuario, v_checks,
          nullif(trim(coalesce(p_motivo, ' ')), ''), now(), v_usuario, now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'PENDIENTE_VERIFICACION', updated_at = now()
  where id_comercio = p_id_comercio and estado = 'ACTIVO';

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_revocada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_revocar_verificacion_v1(uuid, text) from public;
grant execute on function rsuelvo.fn_revocar_verificacion_v1(uuid, text) to authenticated, service_role;
-- ═══ MIG 97 (aplicada 2026-09-22: staging QR + revocar real) ═══
-- 97_qr_staging_revocar.sql
-- IAM-9 parche revision ChatGPT. NO reescribe mig 96.
-- 1) staging privado (qr-pagos es PUBLIC: setup ahi seria publico).
-- 2) solicitar sin service_role (solo owner+AAL2 humanos).
-- 3) revocar como transicion real idempotente + motivo obligatorio.

-- ── 1. bucket staging privado ──
insert into storage.buckets (id, name, public)
values ('qr-pagos-setup', 'qr-pagos-setup', false)
on conflict (id) do nothing;

drop policy if exists qr_setup_owner_all on storage.objects;
create policy qr_setup_owner_all on storage.objects
  for all to authenticated
  using (bucket_id = 'qr-pagos-setup'
    and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
    and rsuelvo.fn_es_admin_comercio((split_part(name, '/', 1))::uuid))
  with check (bucket_id = 'qr-pagos-setup'
    and (split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$')
    and rsuelvo.fn_es_admin_comercio((split_part(name, '/', 1))::uuid));

-- ── 2. check qr: staging (V0) u operativo ──
create or replace function rsuelvo.fn_checks_verificacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_c record;
  v_owner uuid;
  v_email_ok boolean;
  v_suc_ok boolean;
  v_qr_ok boolean;
  v_cfg_ok boolean;
  v_nit text;
  v_razon text;
  v_tel text;
begin
  select * into v_c from tbl_comercios where id_comercio = p_id_comercio;
  if v_c.id_comercio is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  v_owner := v_c.propietario_id;
  v_nit := upper(trim(coalesce(v_c.nit, '')));
  v_razon := trim(coalesce(v_c.razon_social, ''));
  v_tel := trim(coalesce(v_c.telefono, ''));

  if v_owner is not null then
    select (email_confirmed_at is not null) into v_email_ok
    from auth.users au join tbl_usuarios u on u.auth_user_id = au.id
    where u.id_usuario = v_owner;
  end if;

  select exists (
    select 1 from tbl_sucursales
    where id_comercio = p_id_comercio and activo
      and nullif(trim(coalesce(direccion, '')), '') is not null
  ) into v_suc_ok;

  -- staging (V0 setup) u operativo; jamas contenido financiero
  select exists (
    select 1 from storage.objects
    where ((bucket_id = 'qr-pagos-setup') or (bucket_id = 'qr-pagos'))
      and name like p_id_comercio::text || '/%'
  ) into v_qr_ok;

  select exists (
    select 1 from tbl_comercio_config
    where id_comercio = p_id_comercio
      and tiempo_reserva_minutos between 1 and 1440
  ) into v_cfg_ok;

  return jsonb_build_object(
    'ok', true,
    'checks', jsonb_build_object(
      'nit', jsonb_build_object('pass', v_nit ~ '^[0-9]{5,20}$', 'mode', 'syntactic_only'),
      'razon_social', jsonb_build_object('pass', v_razon <> '' and length(v_razon) <= 200),
      'telefono', jsonb_build_object('pass', v_tel ~ '^[0-9+\s]{7,20}$', 'mode', 'present_unverified'),
      'email_owner', jsonb_build_object('pass', coalesce(v_email_ok, false), 'mode', 'auth_confirmed'),
      'sucursal', jsonb_build_object('pass', v_suc_ok),
      'qr', jsonb_build_object('pass', v_qr_ok),
      'config', jsonb_build_object('pass', v_cfg_ok)
    )
  );
end;
$fn$;

-- ── 3. solicitar sin service_role ──
create or replace function rsuelvo.fn_solicitar_habilitacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
  v_res jsonb;
  v_faltantes text[];
  v_vid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;

  select estado into v_estado from tbl_comercios
  where id_comercio = p_id_comercio for update;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'ACTIVO' then
    return jsonb_build_object('ok', true, 'codigo', 'ya_activo');
  end if;
  if v_estado != 'PENDIENTE_VERIFICACION' then
    return jsonb_build_object('ok', false, 'codigo', 'estado_incompatible');
  end if;

  v_res := fn_checks_verificacion_v1(p_id_comercio);
  select array_agg(k) into v_faltantes
  from jsonb_object_keys(v_res -> 'checks') k
  where ((v_res -> 'checks' -> k ->> 'pass')::boolean) = false;

  if v_faltantes is not null then
    insert into tbl_verificaciones_comercio
      (id_comercio, estado, origen, id_verificador, checks_snapshot, motivo, resolved_at)
    values (p_id_comercio, 'RECHAZADA', 'SYSTEM', v_usuario,
            v_res -> 'checks', 'faltantes: ' || array_to_string(v_faltantes, ','), now());
    return jsonb_build_object('ok', false, 'codigo', 'requisitos_faltantes',
      'faltantes', v_faltantes);
  end if;

  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot, resolved_at)
  values (p_id_comercio, 'APROBADA_AUTOMATICA', 'SYSTEM', v_usuario,
          v_res -> 'checks', now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'ACTIVO', updated_at = now()
  where id_comercio = p_id_comercio;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_aprobada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true, 'codigo', 'habilitado');
end;
$fn$;

-- ── 4. revocar como transicion real ──
create or replace function rsuelvo.fn_revocar_verificacion_v1(
  p_id_comercio uuid, p_motivo text default null)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
  v_checks jsonb;
  v_vid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
  end if;
  if nullif(trim(coalesce(p_motivo, ' ')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'motivo_requerido');
  end if;

  select estado into v_estado from tbl_comercios
  where id_comercio = p_id_comercio for update;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'PENDIENTE_VERIFICACION' then
    return jsonb_build_object('ok', true, 'codigo', 'ya_v0');
  end if;
  if v_estado != 'ACTIVO' then
    return jsonb_build_object('ok', false, 'codigo', 'estado_incompatible');
  end if;

  v_checks := (fn_checks_verificacion_v1(p_id_comercio) -> 'checks');
  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot,
     motivo_revocacion, revoked_at, revoked_by, resolved_at)
  values (p_id_comercio, 'REVOCADA', 'SUPERADMIN', v_usuario, v_checks,
          trim(p_motivo), now(), v_usuario, now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'PENDIENTE_VERIFICACION', updated_at = now()
  where id_comercio = p_id_comercio;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_revocada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true, 'codigo', 'revocado');
end;
$fn$;
-- ═══ MIG 98 (aplicada 2026-09-22: lifecycle finalize) ═══
-- 98_qr_lifecycle_finalize.sql
-- IAM-9 parche revision ChatGPT. NO reescribe migs 96/97.
-- 1) service_role fuera de solicitar (solo humanos owner+AAL2).
-- 2) staging->operativo via EF + finalize (sin fingir atomicidad DB+Storage).

-- ── 1. grants ──
revoke execute on function rsuelvo.fn_solicitar_habilitacion_v1(uuid) from service_role;

-- ── 2. solicitar: QR solo-staging no transiciona ──
create or replace function rsuelvo.fn_solicitar_habilitacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
  v_res jsonb;
  v_faltantes text[];
  v_qr_operativo boolean;
  v_vid uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  if not fn_tiene_aal2() then
    return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
  end if;
  if not fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
  end if;

  select estado into v_estado from tbl_comercios
  where id_comercio = p_id_comercio for update;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'ACTIVO' then
    return jsonb_build_object('ok', true, 'codigo', 'ya_activo');
  end if;
  if v_estado != 'PENDIENTE_VERIFICACION' then
    return jsonb_build_object('ok', false, 'codigo', 'estado_incompatible');
  end if;

  v_res := fn_checks_verificacion_v1(p_id_comercio);
  select array_agg(k) into v_faltantes
  from jsonb_object_keys(v_res -> 'checks') k
  where ((v_res -> 'checks' -> k ->> 'pass')::boolean) = false;

  if v_faltantes is not null then
    insert into tbl_verificaciones_comercio
      (id_comercio, estado, origen, id_verificador, checks_snapshot, motivo, resolved_at)
    values (p_id_comercio, 'RECHAZADA', 'SYSTEM', v_usuario,
            v_res -> 'checks', 'faltantes: ' || array_to_string(v_faltantes, ','), now());
    return jsonb_build_object('ok', false, 'codigo', 'requisitos_faltantes',
      'faltantes', v_faltantes);
  end if;

  -- QR solo en staging: no transiciona; la EF publica y finaliza
  select exists (
    select 1 from storage.objects
    where bucket_id = 'qr-pagos' and name like p_id_comercio::text || '/%'
  ) into v_qr_operativo;
  if not v_qr_operativo then
    return jsonb_build_object('ok', false, 'codigo', 'qr_por_publicar');
  end if;

  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot, resolved_at)
  values (p_id_comercio, 'APROBADA_AUTOMATICA', 'SYSTEM', v_usuario,
          v_res -> 'checks', now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'ACTIVO', updated_at = now()
  where id_comercio = p_id_comercio;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_aprobada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true, 'codigo', 'habilitado');
end;
$fn$;

-- ── 3. finalize (llamada solo por EF tras publicar; idempotente) ──
create or replace function rsuelvo.fn_finalizar_habilitacion_v1(p_id_comercio uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_estado text;
  v_res jsonb;
  v_faltantes text[];
  v_qr_operativo boolean;
  v_vid uuid;
begin
  -- Solo service_role (EF) o owner+AAL2 humano
  if coalesce(auth.jwt()->>'role', '') = 'service_role' then
    select propietario_id into v_usuario from tbl_comercios
    where id_comercio = p_id_comercio;
  else
    select id_usuario into v_usuario from tbl_usuarios
    where auth_user_id = v_auth and activo;
    if v_usuario is null then
      return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
    end if;
    if not fn_tiene_aal2() then
      return jsonb_build_object('ok', false, 'codigo', 'mfa_requerido');
    end if;
    if not fn_es_owner(p_id_comercio) then
      return jsonb_build_object('ok', false, 'codigo', 'solo_owner');
    end if;
  end if;

  select estado into v_estado from tbl_comercios
  where id_comercio = p_id_comercio for update;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'codigo', 'comercio_no_existe');
  end if;
  if v_estado = 'ACTIVO' then
    return jsonb_build_object('ok', true, 'codigo', 'ya_activo');
  end if;
  if v_estado != 'PENDIENTE_VERIFICACION' then
    return jsonb_build_object('ok', false, 'codigo', 'estado_incompatible');
  end if;

  v_res := fn_checks_verificacion_v1(p_id_comercio);
  select array_agg(k) into v_faltantes
  from jsonb_object_keys(v_res -> 'checks') k
  where ((v_res -> 'checks' -> k ->> 'pass')::boolean) = false;
  if v_faltantes is not null then
    return jsonb_build_object('ok', false, 'codigo', 'requisitos_faltantes',
      'faltantes', v_faltantes);
  end if;

  -- exige QR operativo confirmado (la EF ya lo publico)
  select exists (
    select 1 from storage.objects
    where bucket_id = 'qr-pagos' and name like p_id_comercio::text || '/%'
  ) into v_qr_operativo;
  if not v_qr_operativo then
    return jsonb_build_object('ok', false, 'codigo', 'qr_por_publicar');
  end if;

  insert into tbl_verificaciones_comercio
    (id_comercio, estado, origen, id_verificador, checks_snapshot, resolved_at)
  values (p_id_comercio, 'APROBADA_AUTOMATICA', 'SYSTEM', v_usuario,
          v_res -> 'checks', now())
  returning id_verificacion into v_vid;

  update tbl_comercios set estado = 'ACTIVO', updated_at = now()
  where id_comercio = p_id_comercio;

  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (p_id_comercio, v_usuario, 'verificacion_v1_aprobada',
          'tbl_verificaciones_comercio', v_vid);

  return jsonb_build_object('ok', true, 'codigo', 'habilitado');
end;
$fn$;
revoke execute on function rsuelvo.fn_finalizar_habilitacion_v1(uuid) from public;
grant execute on function rsuelvo.fn_finalizar_habilitacion_v1(uuid) to authenticated, service_role;
-- ═══ MIG 99 (aplicada 2026-09-22: grants finalize + frontera QR) ═══
-- 99_qr_entrega_grants.sql
-- IAM-9: finalizar solo service_role/EF (solicitar ya es solo-humana).
-- Frontera publica = EF qr-entrega (habilitado-gated), no el bucket.

revoke execute on function rsuelvo.fn_finalizar_habilitacion_v1(uuid) from authenticated;
