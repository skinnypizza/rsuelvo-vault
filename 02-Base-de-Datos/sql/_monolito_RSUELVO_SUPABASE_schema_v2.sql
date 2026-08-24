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
    'COMPRA','BONIFICACION','AJUSTE','CONSUMO_VERIFICACION','DEVOLUCION','EXPIRACION'
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
  created_at timestamptz not null default now()
);


-- CRÉDITOS (cuenta + ledger + servicios + paquetes + compras + pagos)
create table if not exists tbl_cuentas_creditos (
  id_cuenta_creditos uuid primary key default gen_random_uuid(),
  id_comercio uuid not null unique references tbl_comercios(id_comercio) on delete cascade,
  saldo_actual bigint not null default 0 check (saldo_actual >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists tbl_movimientos_creditos (
  id_movimiento uuid primary key default gen_random_uuid(),
  id_comercio uuid not null references tbl_comercios(id_comercio) on delete restrict,
  id_cuenta_creditos uuid not null references tbl_cuentas_creditos(id_cuenta_creditos) on delete restrict,
  tipo tipo_movimiento_credito not null,
  cantidad bigint not null check (cantidad <> 0),
  saldo_anterior bigint not null check (saldo_anterior >= 0),
  saldo_posterior bigint not null check (saldo_posterior >= 0),
  concepto text,
  referencia_tipo text,
  referencia_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists tbl_servicios_creditos (
  id_servicio uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  descripcion text,
  costo_creditos bigint not null check (costo_creditos > 0),
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
create index if not exists idx_eventos_pendientes on tbl_whatsapp_eventos(recibido)
where procesado = false;
create index if not exists idx_envios_repartidor on tbl_envios(id_repartidor,estado);
create index if not exists idx_seguimiento_envio on tbl_env_seguimiento_estados(id_envio,created_at desc);

-- ============================================================
-- RSUELVO v2 :: 6. FUNCIONES
-- ============================================================

set search_path = rsuelvo, public;

-- Validación de asignación usuario/comercio (cajero = 1 sucursal)
create or replace function fn_validar_asignacion_usuario_comercio()
returns trigger
language plpgsql
as $$
declare
  v_codigo rol_codigo;
  v_sucursal uuid;
begin
  select codigo into v_codigo from tbl_roles where id_rol=new.id_rol;

  if v_codigo in ('ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT')
     and new.id_sucursal is null then
    raise exception 'El rol % requiere una sucursal',v_codigo;
  end if;

  if v_codigo='ROLE_TENANT_CASHIER' then
    if exists (
      select 1
      from tbl_usuario_comercio uc
      join tbl_roles r on r.id_rol=uc.id_rol
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
create or replace function fn_resolver_variante_tenant_sku()
returns trigger
language plpgsql
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
    from tbl_productos p
    where p.id_producto=new.id_producto;
  end if;

  if v_comercio is null then
    raise exception 'Producto inexistente';
  end if;

  new.id_comercio := v_comercio;

  select codigo_tienda into v_codigo
  from tbl_comercios
  where id_comercio=v_comercio;

  if v_codigo is null then
    raise exception 'El comercio % no tiene codigo_tienda asignado',v_comercio;
  end if;

  -- 2) Generar SKU si no viene (o venir vacío).
  if coalesce(new.sku,'')='' then
    -- serializar por comercio: bloquea la fila del comercio.
    select 1 into v_max from tbl_comercios
    where id_comercio=v_comercio for update;

    select coalesce(max(
      ('x'||substr(v.sku,4,3))::bit(12)::int
    ),0) into v_max
    from tbl_variantes v
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
    select 1 from tbl_variantes v
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
create or replace function fn_validar_consistencia_tenant()
returns trigger
language plpgsql
as $$
declare
  v_comercio uuid;
begin
  -- Sucursal pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_lista_espera','tbl_pedidos','tbl_envios') then
    select id_comercio into v_comercio
    from tbl_sucursales
    where id_sucursal=new.id_sucursal;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'La sucursal no pertenece al comercio';
    end if;
  end if;

  -- Cliente pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_pedidos','tbl_comprobantes_pago') then
    select id_comercio into v_comercio
    from tbl_clientes
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
create or replace function fn_assert_service_role()
returns void
language plpgsql
as $$
begin
  if not fn_es_service_role() then
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


-- Reserva atómica
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

  -- Bloqueo pesimista: solo una transacción modifica esta fila.
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
create or replace function fn_agregar_lista_espera(
  p_id_comercio uuid,
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_id_cliente uuid
)
returns uuid
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_max integer;
  v_pos integer;
  v_id uuid;
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

  select count(*) into v_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');

  if v_pos >= v_max then
    raise exception 'LISTA_DE_ESPERA_LLENA';
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

  return v_id;
exception
  when unique_violation then
    raise exception 'El cliente ya está en la lista de espera activa';
end;
$$;


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


-- Notificar siguiente de la lista
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
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado='ESPERANDO'
  order by posicion
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

  select * into v_res
  from tbl_reservas
  where id_pedido=v_ver.id_pedido
  for update;

  if not found then
    raise exception 'No existe reserva asociada al pedido';
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
create or replace function fn_actualizar_estado_envio(
  p_id_envio uuid,
  p_nuevo_estado estado_envio,
  p_observacion text default null,
  p_latitud numeric(9,6) default null,
  p_longitud numeric(9,6) default null
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_env tbl_envios%rowtype;
begin
  select * into v_env from tbl_envios
  where id_envio=p_id_envio for update;

  if not found then
    raise exception 'Envío inexistente';
  end if;

  if not (
    (v_env.estado='PENDIENTE'   and p_nuevo_estado in ('PREPARANDO','CANCELADO'))
 or (v_env.estado='PREPARANDO' and p_nuevo_estado in ('ASIGNADO','CANCELADO'))
 or (v_env.estado='ASIGNADO'   and p_nuevo_estado in ('EN_RUTA','CANCELADO'))
 or (v_env.estado='EN_RUTA'    and p_nuevo_estado in ('ENTREGADO','NO_ENTREGADO'))
 or (v_env.estado='NO_ENTREGADO' and p_nuevo_estado in ('EN_RUTA'))
  ) then
    raise exception 'Transición inválida: % -> %',v_env.estado,p_nuevo_estado;
  end if;

  if p_nuevo_estado='NO_ENTREGADO' and coalesce(p_observacion,'')='' then
    raise exception 'NO_ENTREGADO requiere observación';
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
create policy audit_insert on tbl_logs_auditoria for insert with check (fn_es_superadmin() or fn_tiene_acceso_comercio(id_comercio));

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
'Reserva atómica de inventario. Bloquea la fila de inventario con FOR UPDATE. Debe ser llamada desde n8n/Backend mediante RPC y no replicarse en lógica de workflow.';

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

commit;
