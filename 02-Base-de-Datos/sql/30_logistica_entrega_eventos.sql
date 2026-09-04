-- Migración 30 (2026-09-02): F5 — logística de entrega event-driven (D13/D14)
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
      url    => 'https://rsuelvo.app.n8n.cloud/webhook/entrega/request',
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
        url    => 'https://rsuelvo.app.n8n.cloud/webhook/entrega/estado',
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
