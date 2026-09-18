-- 73_solicitudes_sysadmin.sql
-- SysAdmin ve y resuelve solicitudes igual que SuperAdmin (solo esos dos roles).

create policy solicitudes_staff_select on rsuelvo.tbl_solicitudes_alta
  for select to authenticated
  using (rsuelvo.fn_es_superadmin() or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN'));

create or replace function rsuelvo.fn_resolver_solicitud_alta(
  p_id_solicitud uuid,
  p_aprueba boolean,
  p_motivo text default null
) returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_estado rsuelvo.estado_solicitud_alta;
begin
  if not (fn_es_service_role() or fn_es_superadmin()
          or fn_tiene_rol('ROLE_SYSADMIN')) then
    raise exception 'solo staff autorizado';
  end if;

  select estado into v_estado
  from tbl_solicitudes_alta where id_solicitud = p_id_solicitud;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'solicitud_no_existe');
  end if;
  if v_estado != 'PENDIENTE' then
    return jsonb_build_object('ok', false, 'codigo', 'no_pendiente', 'estado', v_estado);
  end if;

  update tbl_solicitudes_alta
  set estado = case when p_aprueba then 'APROBADA'::rsuelvo.estado_solicitud_alta else 'RECHAZADA'::rsuelvo.estado_solicitud_alta end,
      motivo = nullif(trim(coalesce(p_motivo,'')), ''),
      id_revisor = (select id_usuario from tbl_usuarios where auth_user_id = auth.uid()),
      fecha_revision = now()
  where id_solicitud = p_id_solicitud;

  return jsonb_build_object('ok', true,
    'nuevo', case when p_aprueba then 'APROBADA' else 'RECHAZADA' end);
end;
$fn$;
