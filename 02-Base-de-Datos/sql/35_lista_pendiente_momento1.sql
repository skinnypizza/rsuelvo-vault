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
