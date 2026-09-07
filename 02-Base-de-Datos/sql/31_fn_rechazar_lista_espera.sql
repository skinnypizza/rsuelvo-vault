-- Migración 31 (2026-09-06): OBS-001 Momento 2 — rechazar oportunidad / salir de lista
-- fn_rechazar_lista_espera(p_id_lista_espera): el comprador declina su turno.
--   * NOTIFICADO (ventana vigente) → RECHAZADO (rechaza la oportunidad de reserva)
--   * ESPERANDO (cancela su inscripción, Momento 1 futuro) → CANCELADO
-- Otros estados → excepción. Retorna id_sucursal/id_variante para que el flujo n8n
-- dispare fn_notificar_siguiente_lista_espera (desplazamiento de posiciones).

CREATE OR REPLACE FUNCTION rsuelvo.fn_rechazar_lista_espera(p_id_lista_espera uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_item tbl_lista_espera%rowtype;
  v_nuevo_estado estado_lista_espera;
BEGIN
  SELECT * INTO v_item
  FROM tbl_lista_espera
  WHERE id_lista_espera = p_id_lista_espera
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrada de lista inexistente';
  END IF;

  IF v_item.estado = 'NOTIFICADO' THEN
    v_nuevo_estado := 'RECHAZADO';
  ELSIF v_item.estado = 'ESPERANDO' THEN
    v_nuevo_estado := 'CANCELADO';
  ELSE
    RAISE EXCEPTION 'Solo se pueden rechazar entradas NOTIFICADO o cancelar ESPERANDO (estado actual: %)', v_item.estado;
  END IF;

  UPDATE tbl_lista_espera
  SET estado = v_nuevo_estado,
      updated_at = now()
  WHERE id_lista_espera = p_id_lista_espera;

  RETURN jsonb_build_object(
    'resultado', 'OPORTUNIDAD_RECHAZADA',
    'estado_anterior', v_item.estado,
    'estado_nuevo', v_nuevo_estado,
    'id_lista_espera', p_id_lista_espera,
    'id_sucursal', v_item.id_sucursal,
    'id_variante', v_item.id_variante
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION rsuelvo.fn_rechazar_lista_espera(uuid) TO anon, authenticated, service_role;
