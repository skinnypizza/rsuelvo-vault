-- The helper is granted to authenticated for its protected RPC/RLS callers.
-- Require access to the target tenant before disclosing whether it is active.
CREATE OR REPLACE FUNCTION rsuelvo.fn_comercio_habilitado(p_id_comercio uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'rsuelvo', 'public', 'pg_temp'
AS $function$
  SELECT rsuelvo.fn_tiene_acceso_comercio(p_id_comercio)
     AND EXISTS (
       SELECT 1
       FROM rsuelvo.tbl_comercios c
       WHERE c.id_comercio = p_id_comercio
         AND c.estado = 'ACTIVO'
     );
$function$;
