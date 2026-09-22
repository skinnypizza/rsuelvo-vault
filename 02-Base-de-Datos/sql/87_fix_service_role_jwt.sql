-- 87_fix_service_role_jwt.sql
-- INCIDENTE P0 2026-09-22: mig 76 agrego `or current_user in ('postgres',
-- 'service_role')`. Como todas las fns son SECURITY DEFINER con owner
-- postgres, current_user='postgres' SIEMPRE -> fn_es_service_role()=true
-- para cualquier usuario autenticado (RLS y gates con ese helper abiertos).
-- Fix: JWT manda cuando hay JWT (PostgREST siempre lo pone); el fallback
-- current_user SOLO aplica sin JWT (conexiones PG directas backend/n8n).

create or replace function rsuelvo.fn_es_service_role()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select coalesce(auth.jwt()->>'role', '') = 'service_role'
      or (auth.jwt() is null and current_user in ('postgres', 'service_role'));
$fn$;

-- mismo patron en el helper AAL2 (mig 86)
create or replace function rsuelvo.fn_tiene_aal2()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select case
    when auth.jwt() is null then current_user in ('postgres', 'service_role')
    when coalesce(auth.jwt()->>'role', '') = 'service_role' then true
    else coalesce(auth.jwt()->>'aal', '') = 'aal2'
  end;
$fn$;

-- overload fantasma de gestionar (5 params, mig 68): rompe PostgREST PGRST203
-- y deja el dialogo IAM-2A sin funcionar. La firma vigente es la de 7 params.
drop function if exists rsuelvo.fn_gestionar_vinculo(uuid, uuid, smallint, uuid, text);
