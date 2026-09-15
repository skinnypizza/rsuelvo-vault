-- 61_fix_fn_es_service_role.sql
-- INCIDENTE 2026-09-15: fn_es_service_role() devolvia TRUE para CUALQUIER usuario
-- autenticado (e incluso anon). Causa: leia current_setting('request.jwt.claim.role'),
-- GUC singular que PostgREST 14 ya no setea -> NULL -> coalesce a 'service_role'.
-- Efecto: todo guard `fn_es_service_role() or ...` (casi todas las policies RLS y
-- guards de fn_*) pasaba para cualquier logueado (probado: alta de tenant sin rol).
-- Fix: patron canonico via auth.jwt() (lee request.jwt.claims, siempre seteado).
-- anon -> NULL -> false; usuario -> 'authenticated' -> false; service_role -> true.

create or replace function rsuelvo.fn_es_service_role()
returns boolean
language sql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
  select coalesce(auth.jwt()->>'role', '') = 'service_role';
$fn$;
