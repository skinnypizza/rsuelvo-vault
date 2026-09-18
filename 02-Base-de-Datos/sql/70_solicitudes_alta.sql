-- 70_solicitudes_alta.sql
-- Postulacion publica desde la landing (contrato web docs/solicitudes-backend.md):
-- entidad nueva, sin reutilizar enums; RLS niega todo salvo superadmin-lectura;
-- resolucion una sola vez via RPC. El alta posterior sigue el flujo D17 normal.

do $$ begin
  create type rsuelvo.estado_solicitud_alta as enum ('PENDIENTE','APROBADA','RECHAZADA');
exception when duplicate_object then null; end $$;

create table if not exists rsuelvo.tbl_solicitudes_alta (
  id_solicitud uuid primary key default gen_random_uuid(),
  nombre text not null,
  telefono text not null,
  tienda text not null,
  mensaje text not null,
  plan text,
  origen text not null default 'landing',
  estado rsuelvo.estado_solicitud_alta not null default 'PENDIENTE',
  idempotency_key text not null unique,
  payload_hash text not null,
  ip_origen text,
  id_revisor uuid references rsuelvo.tbl_usuarios(id_usuario),
  motivo text,
  fecha_revision timestamptz,
  created_at timestamptz not null default now()
);

alter table rsuelvo.tbl_solicitudes_alta enable row level security;

drop policy if exists solicitudes_superadmin_select on rsuelvo.tbl_solicitudes_alta;
create policy solicitudes_superadmin_select on rsuelvo.tbl_solicitudes_alta
  for select to authenticated using (rsuelvo.fn_es_superadmin());

-- Sin policies de escritura: solo service_role (EF) escribe. UPDATE via RPC.
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
  if not (fn_es_service_role() or fn_es_superadmin()) then
    raise exception 'solo superadmin';
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

revoke execute on function rsuelvo.fn_resolver_solicitud_alta(uuid, boolean, text) from public;
grant execute on function rsuelvo.fn_resolver_solicitud_alta(uuid, boolean, text) to authenticated, service_role;

-- GRANTs (PostgREST los exige antes que RLS; RLS sigue negando no-superadmin)
grant all on rsuelvo.tbl_solicitudes_alta to anon, authenticated, service_role;
