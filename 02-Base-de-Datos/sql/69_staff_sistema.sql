-- 69_staff_sistema.sql
-- Staff sin comercio (opcion B): tenant sistema SYS (BLOQUEADO, sin flujos) +
-- SUPPORT fuera de fn_tiene_acceso_sucursal + lecturas staff en tablas operativas.
-- HU roles expandidos. PROD 2026-09-18: SYS=439b6482-494a-4420-bcae-27d628131bf3.

-- ── 1. Tenant sistema (idempotente; solo fila base, sin config/cuenta/sucursal)
insert into rsuelvo.tbl_comercios (codigo_tienda, nombre_comercial, estado)
values ('SYS', 'RSUELVO Plataforma (sistema)', 'BLOQUEADO')
on conflict (codigo_tienda) do nothing;

-- ── 2. SUPPORT fuera del bypass de sucursal ─────────────────────────────────
create or replace function rsuelvo.fn_tiene_acceso_sucursal(p_id_comercio uuid, p_id_sucursal uuid)
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select fn_es_service_role()
      or fn_es_superadmin()
      or exists (
        select 1
        from tbl_usuario_comercio uc
        join tbl_usuarios u on u.id_usuario=uc.id_usuario
        where u.auth_user_id=auth.uid()
          and u.activo
          and uc.activo
          and uc.id_comercio=p_id_comercio
          and (
            (uc.id_sucursal is null
              and exists (
                select 1 from tbl_roles r2
                where r2.id_rol = uc.id_rol
                  and r2.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPERADMIN')))
            or uc.id_sucursal=p_id_sucursal
            or exists (
              select 1
              from tbl_roles r
              where r.id_rol=uc.id_rol
                and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_SUPERADMIN')
            )
          )
      );
$fn$;

-- ── 3. Lecturas staff en operativas (SELECT, sin escritura) ─────────────────
drop policy if exists staff_read on rsuelvo.tbl_pedidos;
create policy staff_read on rsuelvo.tbl_pedidos
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_reservas;
create policy staff_read on rsuelvo.tbl_reservas
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_lista_espera;
create policy staff_read on rsuelvo.tbl_lista_espera
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_clientes;
create policy staff_read on rsuelvo.tbl_clientes
  for select to authenticated using (rsuelvo.fn_lectura_staff());

drop policy if exists staff_read on rsuelvo.tbl_envios;
create policy staff_read on rsuelvo.tbl_envios
  for select to authenticated using (rsuelvo.fn_lectura_staff());
