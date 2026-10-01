CREATE OR REPLACE FUNCTION rsuelvo.fn_notifica_pedido_pagado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'rsuelvo', 'public', 'pg_temp'
AS $function$
DECLARE
  v_phone text;
BEGIN
  IF NEW.estado = 'PAGADO' AND OLD.estado IS DISTINCT FROM 'PAGADO' THEN
    SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
    FROM tbl_clientes
    WHERE id_cliente = NEW.id_cliente;

    PERFORM net.http_post(
      url := 'https://n8n.rsuelvo.com/webhook/entrega/request',
      body := jsonb_build_object(
        'token', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'rsuelvo_n8n_legacy_delivery_body_token'),
        'id_pedido', NEW.id_pedido,
        'id_comercio', NEW.id_comercio,
        'id_cliente', NEW.id_cliente,
        'phone', v_phone
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'rsuelvo_n8n_delivery_callback_token')
      ),
      timeout_milliseconds := 15000
    );
  END IF;
  RETURN NEW;
END;
$function$

