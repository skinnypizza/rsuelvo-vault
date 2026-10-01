-- Keep the shared WhatsApp orchestrator's pending-waitlist write tenant-coherent.
-- Runtime identity stays the sole executor; the function validates that every
-- supplied reference belongs to the same commerce before SECURITY DEFINER writes.
CREATE OR REPLACE FUNCTION rsuelvo.fn_pendiente_lista(
  p_id_comercio uuid,
  p_id_sucursal uuid,
  p_id_variante uuid,
  p_id_cliente uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'rsuelvo', 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM tbl_comercios c
    JOIN tbl_sucursales s
      ON s.id_comercio = c.id_comercio
    JOIN tbl_variantes v
      ON v.id_comercio = c.id_comercio
    JOIN tbl_clientes cli
      ON cli.id_comercio = c.id_comercio
    WHERE c.id_comercio = p_id_comercio
      AND s.id_sucursal = p_id_sucursal
      AND v.id_variante = p_id_variante
      AND cli.id_cliente = p_id_cliente
  ) THEN
    RAISE EXCEPTION 'Las referencias de lista pendiente no corresponden al comercio'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO tbl_lista_pendiente (id_cliente, id_comercio, id_sucursal, id_variante)
  VALUES (p_id_cliente, p_id_comercio, p_id_sucursal, p_id_variante)
  ON CONFLICT (id_cliente) DO UPDATE
    SET id_comercio = EXCLUDED.id_comercio,
        id_sucursal = EXCLUDED.id_sucursal,
        id_variante = EXCLUDED.id_variante;

  RETURN jsonb_build_object('resultado', 'PENDIENTE_LISTA');
END;
$function$;
