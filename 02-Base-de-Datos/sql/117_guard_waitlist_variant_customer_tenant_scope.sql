CREATE OR REPLACE FUNCTION rsuelvo.fn_agregar_lista_espera_v2(
  p_id_comercio uuid,
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_id_cliente uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'rsuelvo', 'pg_temp'
AS $function$
DECLARE
  v_max integer;
  v_activos integer;
  v_pos integer;
  v_id uuid;
  v_existente record;
BEGIN
  IF NOT rsuelvo.fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) THEN
    RAISE EXCEPTION 'Sin acceso al comercio/sucursal';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM rsuelvo.tbl_variantes v
    JOIN rsuelvo.tbl_productos p ON p.id_producto=v.id_producto
    WHERE v.id_variante=p_id_variante
      AND p.id_comercio=p_id_comercio
  ) OR NOT EXISTS (
    SELECT 1
    FROM rsuelvo.tbl_clientes c
    WHERE c.id_cliente=p_id_cliente
      AND c.id_comercio=p_id_comercio
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE='23514',
      MESSAGE='La variante o el cliente no pertenece al comercio';
  END IF;

  SELECT max_lista_espera_por_producto INTO v_max
  FROM rsuelvo.tbl_comercio_config
  WHERE id_comercio=p_id_comercio;
  IF v_max IS NULL THEN
    RAISE EXCEPTION 'Configuración de comercio inexistente';
  END IF;

  -- The inventory row may be absent. Locking only tbl_inventario therefore
  -- leaves the count/insert capacity check racy for zero-inventory variants.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'rsuelvo.waitlist.capacity:' || p_id_sucursal::text || ':' || p_id_variante::text,
      0
    )
  );

  PERFORM 1
  FROM rsuelvo.tbl_inventario
  WHERE id_sucursal=p_id_sucursal AND id_variante=p_id_variante
  FOR UPDATE;

  SELECT id_lista_espera, posicion INTO v_existente
  FROM rsuelvo.tbl_lista_espera
  WHERE id_sucursal=p_id_sucursal
    AND id_variante=p_id_variante
    AND id_cliente=p_id_cliente
    AND estado IN ('ESPERANDO','NOTIFICADO','ACEPTADO')
  LIMIT 1;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera',v_existente.id_lista_espera,
      'posicion',v_existente.posicion
    );
  END IF;

  SELECT count(*) INTO v_activos
  FROM rsuelvo.tbl_lista_espera
  WHERE id_sucursal=p_id_sucursal
    AND id_variante=p_id_variante
    AND estado IN ('ESPERANDO','NOTIFICADO','ACEPTADO');
  IF v_activos >= v_max THEN
    RETURN pg_catalog.jsonb_build_object(
      'resultado','LISTA_LLENA','activos',v_activos,'maximo',v_max
    );
  END IF;

  SELECT coalesce(max(posicion),0)+1 INTO v_pos
  FROM rsuelvo.tbl_lista_espera
  WHERE id_sucursal=p_id_sucursal
    AND id_variante=p_id_variante
    AND estado IN ('ESPERANDO','NOTIFICADO');

  INSERT INTO rsuelvo.tbl_lista_espera(
    id_comercio,id_sucursal,id_variante,id_cliente,posicion,estado
  ) VALUES (
    p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,v_pos,'ESPERANDO'
  ) RETURNING id_lista_espera INTO v_id;

  RETURN pg_catalog.jsonb_build_object(
    'resultado','AGREGADO','id_lista_espera',v_id,'posicion',v_pos
  );
EXCEPTION
  WHEN unique_violation THEN
    SELECT id_lista_espera, posicion INTO v_existente
    FROM rsuelvo.tbl_lista_espera
    WHERE id_sucursal=p_id_sucursal
      AND id_variante=p_id_variante
      AND id_cliente=p_id_cliente
      AND estado IN ('ESPERANDO','NOTIFICADO','ACEPTADO')
    LIMIT 1;
    RETURN pg_catalog.jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera',v_existente.id_lista_espera,
      'posicion',v_existente.posicion
    );
END;
$function$;
