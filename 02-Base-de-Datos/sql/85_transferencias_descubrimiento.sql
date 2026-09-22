-- 85_transferencias_descubrimiento.sql
-- IAM-4 UI enablement: descubrimiento server-side (mismo patron invitaciones).
-- Solo lectura; no cambia contratos.

create or replace function rsuelvo.fn_mis_transferencias_pendientes()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  return jsonb_build_object('ok', true, 'transferencias', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_transferencia', t.id, 'id_comercio', t.id_comercio,
      'comercio', c.nombre_comercial,
      'soy_origen', t.propietario_origen = v_usuario,
      'origen_email', uo.email, 'destino_email', ud.email,
      'estado', t.estado, 'expira_at', t.expira_at, 'created_at', t.created_at
    ))
    from tbl_transferencias_propiedad t
    join tbl_comercios c on c.id_comercio = t.id_comercio
    left join tbl_usuarios uo on uo.id_usuario = t.propietario_origen
    left join tbl_usuarios ud on ud.id_usuario = t.propietario_destino
    where (t.propietario_origen = v_usuario or t.propietario_destino = v_usuario)
      and t.estado = 'PENDIENTE' and t.expira_at > now()
  ), '[]'::jsonb));
end;
$fn$;
revoke execute on function rsuelvo.fn_mis_transferencias_pendientes() from public;
grant execute on function rsuelvo.fn_mis_transferencias_pendientes() to authenticated, service_role;
