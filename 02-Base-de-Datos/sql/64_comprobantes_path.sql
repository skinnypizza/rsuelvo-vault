-- 64_comprobantes_path.sql
-- URLs firmadas (`/object/sign/...?token=exp`) y lookaside Meta vencen: la app no
-- puede mostrar comprobantes viejos. Fix: columna `archivo_path` (path en bucket,
-- firma ON-DEMAND al visualizar) + policies de lectura en `comprobantes-pago`.
-- El backfill de paths va por script (decodifica el `url` del token JWT).
-- WF-20 debe guardar PATH (prompt aparte); la app firma al ver (prompt aparte).

alter table rsuelvo.tbl_comprobantes_pago
  add column if not exists archivo_path text;

drop policy if exists comprobantes_tenant_select on storage.objects;
drop policy if exists comprobantes_staff_select on storage.objects;

create policy comprobantes_tenant_select on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes-pago'
    and split_part(name, '/', 1) ~ '^[0-9a-f-]{36}$'
    and rsuelvo.fn_tiene_acceso_comercio(split_part(name, '/', 1)::uuid));

create policy comprobantes_staff_select on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes-pago'
    and (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN')
      or rsuelvo.fn_tiene_rol('ROLE_SUPPORT')));
