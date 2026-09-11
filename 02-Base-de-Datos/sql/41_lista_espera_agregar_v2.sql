-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 41 (2026-09-11)
-- LISTA DE ESPERA: alta atómica con resultado estructurado (base de F5)
-- ============================================================
-- fn_agregar_lista_espera_v2: misma atomicidad que v1 (lock FOR UPDATE sobre
-- la fila de inventario por sucursal×variante) pero devuelve jsonb en vez de
-- excepciones: AGREGADO {id_lista_espera, posicion} · YA_EN_LISTA {id,posicion}
-- · LISTA_LLENA {activos, maximo}. Incluye red de seguridad unique_violation
-- (carrera residual → YA_EN_LISTA en vez de excepción).
-- v1 se conserva intacta hasta que F5 migre WF-12 a v2 (luego se elimina).
-- Regla de Oro 3: cupo y unicidad se deciden en la BD; n8n solo muestra.
-- Validado en transacción: AGREGADO pos 1 → YA_EN_LISTA (mismo id/pos) →
-- LISTA_LLENA (activos 1, maximo 1); rollback.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_agregar_lista_espera_v2(
  p_id_comercio uuid, p_id_sucursal uuid, p_id_variante uuid, p_id_cliente uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_max integer;
  v_activos integer;
  v_pos integer;
  v_id uuid;
  v_existente record;
begin
  if not fn_tiene_acceso_sucursal(p_id_comercio,p_id_sucursal) then
    raise exception 'Sin acceso al comercio/sucursal';
  end if;
  select max_lista_espera_por_producto into v_max
  from tbl_comercio_config
  where id_comercio=p_id_comercio;
  if v_max is null then
    raise exception 'Configuración de comercio inexistente';
  end if;
  perform 1
  from tbl_inventario
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
  for update;
  select id_lista_espera, posicion into v_existente
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and id_cliente=p_id_cliente
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
  limit 1;
  if found then
    return jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera', v_existente.id_lista_espera,
      'posicion', v_existente.posicion
    );
  end if;
  select count(*) into v_activos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO');
  if v_activos >= v_max then
    return jsonb_build_object(
      'resultado','LISTA_LLENA',
      'activos', v_activos,
      'maximo', v_max
    );
  end if;
  select coalesce(max(posicion),0)+1 into v_pos
  from tbl_lista_espera
  where id_sucursal=p_id_sucursal
    and id_variante=p_id_variante
    and estado in ('ESPERANDO','NOTIFICADO');
  insert into tbl_lista_espera(
    id_comercio,id_sucursal,id_variante,id_cliente,posicion,estado
  )
  values(
    p_id_comercio,p_id_sucursal,p_id_variante,p_id_cliente,v_pos,'ESPERANDO'
  )
  returning id_lista_espera into v_id;
  return jsonb_build_object(
    'resultado','AGREGADO',
    'id_lista_espera', v_id,
    'posicion', v_pos
  );
exception
  when unique_violation then
    select id_lista_espera, posicion into v_existente
    from tbl_lista_espera
    where id_sucursal=p_id_sucursal
      and id_variante=p_id_variante
      and id_cliente=p_id_cliente
      and estado in ('ESPERANDO','NOTIFICADO','ACEPTADO')
    limit 1;
    return jsonb_build_object(
      'resultado','YA_EN_LISTA',
      'id_lista_espera', v_existente.id_lista_espera,
      'posicion', v_existente.posicion
    );
end;
$function$;
