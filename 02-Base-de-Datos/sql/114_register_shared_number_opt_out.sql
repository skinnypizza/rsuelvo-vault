CREATE OR REPLACE FUNCTION rsuelvo.fn_registrar_opt_out_shared_number(
  p_telefono_whatsapp text,
  p_motivo text DEFAULT 'STOP'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'rsuelvo', 'pg_temp'
AS $function$
DECLARE
  v_phone text := nullif(pg_catalog.btrim(p_telefono_whatsapp), '');
  v_rows integer := 0;
BEGIN
  IF v_phone IS NULL OR pg_catalog.length(v_phone) NOT BETWEEN 8 AND 40 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid shared-number opt-out phone';
  END IF;

  INSERT INTO rsuelvo.tbl_contact_preferences
    (id_comercio, telefono_whatsapp, opted_out, opted_out_at, motivo)
  SELECT c.id_comercio, v_phone, true, pg_catalog.now(),
         pg_catalog.left(coalesce(nullif(pg_catalog.btrim(p_motivo), ''), 'STOP'), 120)
  FROM rsuelvo.tbl_comercios c
  WHERE c.estado = 'ACTIVO'
  ON CONFLICT (id_comercio, telefono_whatsapp)
  DO UPDATE SET opted_out = true,
                opted_out_at = pg_catalog.now(),
                motivo = coalesce(EXCLUDED.motivo, rsuelvo.tbl_contact_preferences.motivo);

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$function$;

REVOKE ALL ON FUNCTION rsuelvo.fn_registrar_opt_out_shared_number(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rsuelvo.fn_registrar_opt_out_shared_number(text, text) TO service_role;
