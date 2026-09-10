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
