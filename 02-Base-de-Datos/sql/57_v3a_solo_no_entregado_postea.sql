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
