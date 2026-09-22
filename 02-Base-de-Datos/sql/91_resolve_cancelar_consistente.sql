-- mig 91: CANCELAR consistente service_role/superadmin
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_compra_creditos(p_id_compra uuid, p_decision text, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_dec text := upper(trim(coalesce(p_decision,'')));
  v_staff boolean := rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin();
  v_c record;
  v_cuenta uuid;
  v_saldo bigint;
begin
  select * into v_c from tbl_compras_creditos where id_compra = p_id_compra;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'compra_no_existe');
  end if;
  if v_c.estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_c.estado);
  end if;

  if v_dec = 'CANCELAR' then
    if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then
      raise exception 'solo staff autorizado';
    end if;
    update tbl_compras_creditos set estado = 'CANCELADA' where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'CANCELADA');
  end if;

  if not v_staff then
    raise exception 'solo staff autorizado';
  end if;

  if v_dec = 'RECHAZAR' then
    update tbl_compras_creditos
    set estado = 'RECHAZADA',
        motivo_rechazo = nullif(trim(coalesce(p_motivo,'')), ''),
        id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
        fecha_revision = now()
    where id_compra = p_id_compra;
    return jsonb_build_object('ok', true, 'nuevo', 'RECHAZADA');
  end if;

  if v_dec != 'APROBAR' then
    return jsonb_build_object('ok', false, 'codigo', 'decision_invalida');
  end if;

  select id_cuenta_creditos, saldo_actual into v_cuenta, v_saldo
  from tbl_cuentas_creditos where id_comercio = v_c.id_comercio for update;

  if v_cuenta is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_cuenta');
  end if;

  update tbl_cuentas_creditos set saldo_actual = v_saldo + v_c.creditos_comprados
  where id_cuenta_creditos = v_cuenta;

  insert into tbl_movimientos_creditos
    (id_comercio, id_cuenta_creditos, tipo, cantidad, saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id)
  values
    (v_c.id_comercio, v_cuenta, 'COMPRA', v_c.creditos_comprados, v_saldo, v_saldo + v_c.creditos_comprados,
     'Compra de paquete aprobada', 'COMPRA_CREDITOS', v_c.id_compra);

  update tbl_compras_creditos
  set estado = 'PAGADA',
      fecha_pago = now(),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_compra = p_id_compra;

  return jsonb_build_object('ok', true, 'nuevo', 'PAGADA',
    'creditos', v_c.creditos_comprados, 'saldo', v_saldo + v_c.creditos_comprados);
end;
$function$
;
