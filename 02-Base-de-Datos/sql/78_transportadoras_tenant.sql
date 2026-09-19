-- 78_transportadoras_tenant.sql
-- Opcion B: transportadoras por comercio (NULL = global/plantilla).
-- RLS: globales visibles para autenticados; propias full para el dueño.

alter table rsuelvo.tbl_transportadoras
  add column if not exists id_comercio uuid references rsuelvo.tbl_comercios(id_comercio);

drop policy if exists transportadoras_read on rsuelvo.tbl_transportadoras;
drop policy if exists transportadoras_manage on rsuelvo.tbl_transportadoras;

create policy transportadoras_read on rsuelvo.tbl_transportadoras
  for select to authenticated
  using (id_comercio is null or rsuelvo.fn_tiene_acceso_comercio(id_comercio));

create policy transportadoras_manage on rsuelvo.tbl_transportadoras
  for all to authenticated
  using (id_comercio is not null and rsuelvo.fn_es_admin_comercio(id_comercio))
  with check (id_comercio is not null and rsuelvo.fn_es_admin_comercio(id_comercio));

-- GRANTs (PostgREST los exige antes que RLS)
grant all on rsuelvo.tbl_transportadoras to anon, authenticated, service_role;
