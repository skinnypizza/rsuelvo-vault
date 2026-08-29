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
