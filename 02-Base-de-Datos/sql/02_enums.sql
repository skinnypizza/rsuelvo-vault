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
