-- Only failed-delivery callbacks are sent to n8n; normal progress remains silent.
CREATE OR REPLACE FUNCTION rsuelvo.fn_notifica_envio_estado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'rsuelvo', 'public', 'pg_temp'
AS $function$
DECLARE
  v_phone text;
BEGIN
  -- V3-A (P2-P8): solo NO_ENTREGADO despierta a WF-25-C. PREPARANDO/ASIGNADO/
  -- EN_RUTA/ENTREGADO son silenciosos en n8n (verificado), así que ni siquiera
  -- se emite el POST (ahorra 1T/1Q por transición). Guía va por vía propia
  -- (fn_registrar_guia). Si un estado futuro vuelve a notificar, agregarlo aquí.
  IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'NO_ENTREGADO' THEN
    SELECT COALESCE(telefono_whatsapp, telefono) INTO v_phone
    FROM tbl_clientes
    WHERE id_cliente = (SELECT id_cliente FROM tbl_pedidos WHERE id_pedido = NEW.id_pedido);

    IF v_phone IS NOT NULL THEN
      PERFORM net.http_post(
        url    => 'https://n8n.rsuelvo.com/webhook/entrega/estado',
        body   => jsonb_build_object(
          'token', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'rsuelvo_n8n_legacy_delivery_body_token'),
          'id_envio', NEW.id_envio,
          'id_pedido', NEW.id_pedido,
          'id_comercio', NEW.id_comercio,
          'estado', NEW.estado,
          'phone', v_phone,
          'numero_guia', NEW.numero_guia
        ),
        headers => jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'rsuelvo_n8n_delivery_callback_token'))
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$

