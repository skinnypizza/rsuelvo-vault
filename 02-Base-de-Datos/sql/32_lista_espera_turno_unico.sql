-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 32 (2026-09-07)
-- LISTA DE ESPERA — TURNO ÚNICO POR CLIENTE (H-16/H-17/H-18)
-- ============================================================
-- Hallazgos del test E2E OBS-001 Momento 2 (2026-09-07):
--   H-16: fn_cron_expirar_y_notificar() re-notificaba un grupo que ya tenía un
--         turno NOTIFICADO vigente → ofertas paralelas al mismo tiempo.
--   H-17: un cliente podía acumular ofertas activas en varias variantes → el
--         SI/NO por WhatsApp es ambiguo y WF-14 resolvía arbitrario
--         (ORDER BY fecha_expiracion ASC) rechazando la oferta equivocada.
--   H-18: los turnos NOTIFICADO nunca pasaban a VENCIDO → ofertas zombis
--         (una quedó atascada 3 días) que alimentan H-17.
-- Principio (Regla de Oro 2 / D13-Opción C): la decisión de negocio vive en la
-- BD. Un cliente tiene CERO posibilidad de mantener 2 ofertas simultáneas.
-- Validado en vivo: el primer tick de pg_cron venció 3 turnos zombis y el
-- test T-B (SI → RESERVA_CREADA → QR → PAGADO) corrió con oferta única.

-- 1) H-17: salta clientes que ya tienen una oferta NOTIFICADO vigente (cualquier variante)
CREATE OR REPLACE FUNCTION rsuelvo.fn_notificar_siguiente_lista_espera(p_id_sucursal uuid, p_id_variante uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_item tbl_lista_espera%rowtype;
  v_cfg tbl_comercio_config%rowtype;
begin
  select * into v_item
  from tbl_lista_espera cand
  where cand.id_sucursal=p_id_sucursal
    and cand.id_variante=p_id_variante
    and cand.estado='ESPERANDO'
    and not exists (
      select 1 from tbl_lista_espera act
      where act.id_cliente = cand.id_cliente
        and act.estado='NOTIFICADO'
        and act.fecha_expiracion > now()
    )
  order by cand.posicion
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object('resultado','LISTA_VACIA');
  end if;

  select * into v_cfg
  from tbl_comercio_config
  where id_comercio=v_item.id_comercio;

  update tbl_lista_espera
  set estado='NOTIFICADO',
      fecha_notificacion=now(),
      fecha_expiracion=now()+make_interval(
        mins=>v_cfg.tiempo_aceptacion_lista_espera_minutos
      )
  where id_lista_espera=v_item.id_lista_espera;

  return jsonb_build_object(
    'resultado','CLIENTE_NOTIFICADO',
    'id_lista_espera',v_item.id_lista_espera,
    'id_cliente',v_item.id_cliente,
    'fecha_expiracion',(
      select fecha_expiracion
      from tbl_lista_espera
      where id_lista_espera=v_item.id_lista_espera
    )
  );
end;
$function$;

-- 2) H-18 + H-16: vence turnos expirados y no despierta WF-13 si el grupo tiene turno en vuelo
CREATE OR REPLACE FUNCTION rsuelvo.fn_cron_expirar_y_notificar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_expiradas integer;
  v_turnos_vencidos integer;
  v_notificables boolean;
  v_http bigint;
BEGIN
  -- 0) Vence turnos NOTIFICADO expirados (H-18)
  WITH vencidos AS (
    UPDATE tbl_lista_espera
    SET estado='VENCIDO'
    WHERE estado='NOTIFICADO'
      AND fecha_expiracion <= now()
    RETURNING 1
  )
  SELECT count(*) INTO v_turnos_vencidos FROM vencidos;

  -- 1) Expira reservas vencidas (libera stock, registra movimientos)
  v_expiradas := rsuelvo.fn_procesar_reservas_vencidas(200);

  -- 2) ¿Hay grupos con stock disponible y SIN turno en vuelo? (H-16)
  SELECT EXISTS (
    SELECT 1
    FROM tbl_lista_espera le
    JOIN tbl_inventario i
      ON i.id_sucursal = le.id_sucursal
     AND i.id_variante = le.id_variante
    WHERE le.estado = 'ESPERANDO'
      AND (i.stock_actual - i.stock_reservado) >= 1
      AND NOT EXISTS (
        SELECT 1
        FROM tbl_lista_espera act
        WHERE act.id_sucursal = le.id_sucursal
          AND act.id_variante = le.id_variante
          AND act.estado = 'NOTIFICADO'
          AND act.fecha_expiracion > now()
      )
  ) INTO v_notificables;

  -- 3) Si hay trabajo, despierta a WF-13 (event-driven, no polling)
  IF v_notificables THEN
    SELECT net.http_post(
      url    => 'https://rsuelvo.app.n8n.cloud/webhook/webhooks/lista-espera/notify',
      body   => jsonb_build_object(
        'token', 'RSU_lst_notify_9f3Kz71XqW',
        'motivo', 'waitlist_stock_disponible',
        'fecha', to_char(now() AT TIME ZONE 'America/La_Paz', 'YYYY-MM-DD HH24:MI:SS')
      ),
      headers => jsonb_build_object('Content-Type', 'application/json')
    ) INTO v_http;
  END IF;

  RETURN jsonb_build_object(
    'expiradas', v_expiradas,
    'turnos_vencidos', v_turnos_vencidos,
    'notificables', v_notificables,
    'http_request_id', v_http
  );
END;
$function$;
