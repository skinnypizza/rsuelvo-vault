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
