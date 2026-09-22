-- 88_guard_regression_test.sql
-- P0-IR: test permanente. Falla si SECURITY DEFINER vuelve a convertir
-- current_user en bypass (el helper solo puede usar current_user cuando
-- NO hay JWT: conexiones PG directas backend/n8n).

create or replace function rsuelvo.fn_verificar_guards_sanos()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'rsuelvo' and p.proname = 'fn_es_service_role';

  -- prohibido: current_user como OR incondicional (bypass P0 2026-09-22)
  if v_def like '%current_user%' and v_def not like '%auth.jwt() is null%' then
    return jsonb_build_object('ok', false, 'codigo', 'bypass_current_user');
  end if;
  -- obligatorio: via JWT con service_role
  if v_def not like '%auth.jwt()%role%service_role%' then
    return jsonb_build_object('ok', false, 'codigo', 'sin_check_jwt');
  end if;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'rsuelvo' and p.proname = 'fn_tiene_aal2';
  if v_def like '%current_user%' and v_def not like '%auth.jwt() is null%' then
    return jsonb_build_object('ok', false, 'codigo', 'bypass_current_user_aal2');
  end if;

  -- comportamental: sin JWT (backend) debe seguir true
  if not fn_es_service_role() then
    return jsonb_build_object('ok', false, 'codigo', 'backend_roto');
  end if;

  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_verificar_guards_sanos() from public;
grant execute on function rsuelvo.fn_verificar_guards_sanos() to authenticated, service_role;

select rsuelvo.fn_verificar_guards_sanos();
