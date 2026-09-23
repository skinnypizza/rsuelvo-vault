-- IAM-10 Security Events V1 (REV3.1)
-- One additive backend migration; no Auth, Flutter, Web, or n8n changes.
begin;

create schema if not exists rsuelvo_private authorization postgres;
revoke all on schema rsuelvo_private from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema rsuelvo_private
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema rsuelvo_private
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema rsuelvo_private
  revoke execute on functions from public, anon, authenticated, service_role;

create or replace function rsuelvo_private.fn_security_event_metadata_valid(
  p_event_type text, p_metadata jsonb
) returns boolean
language plpgsql immutable
set search_path = pg_catalog
as $fn$
declare
  v_keys text[];
  v_uuid_keys text[];
  v_key text;
  v_role_codes constant text[] := array[
    'ROLE_SUPERADMIN','ROLE_SYSADMIN','ROLE_SUPPORT','ROLE_TENANT_ADMIN',
    'ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT'
  ];
begin
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object'
     or octet_length(p_metadata::text) > 2048 then return false; end if;
  case p_event_type
    when 'OWNER.TRANSFER_STARTED' then v_keys := array['target_user_id','transfer_id']; v_uuid_keys:=v_keys;
    when 'OWNER.TRANSFER_COMPLETED' then v_keys := array['previous_owner_user_id','target_user_id','transfer_id']; v_uuid_keys:=v_keys;
    when 'OWNER.TRANSFER_CANCELLED' then v_keys := array['transfer_id']; v_uuid_keys:=v_keys;
    when 'MEMBERSHIP.SUSPENDED','MEMBERSHIP.REACTIVATED','MEMBERSHIP.REVOKED'
      then v_keys := array['membership_id','target_user_id']; v_uuid_keys:=v_keys;
    when 'MEMBERSHIP.PRIVILEGE_CHANGED'
      then v_keys := array['direction','from_role','membership_id','target_membership_id','target_user_id','to_role'];
           v_uuid_keys:=array['membership_id','target_membership_id','target_user_id'];
    when 'VERIFICATION.V1_REVOKED' then v_keys := array['verification_id']; v_uuid_keys:=v_keys;
    else return false;
  end case;
  if (select array_agg(k order by k) from jsonb_object_keys(p_metadata) k) is distinct from v_keys then
    return false;
  end if;
  foreach v_key in array v_keys loop
    if jsonb_typeof(p_metadata->v_key)<>'string' or nullif(p_metadata->>v_key,'') is null then return false; end if;
  end loop;
  foreach v_key in array v_uuid_keys loop
    begin perform (p_metadata->>v_key)::uuid;
    exception when invalid_text_representation then return false;
    end;
  end loop;
  if p_event_type='MEMBERSHIP.PRIVILEGE_CHANGED' then
    if p_metadata->>'direction' not in ('ELEVATED','REDUCED','MIXED','RECLASSIFIED')
      or not (p_metadata->>'from_role'=any(v_role_codes))
      or not (p_metadata->>'to_role'=any(v_role_codes)) then return false; end if;
  end if;
  return true;
end;
$fn$;
alter function rsuelvo_private.fn_security_event_metadata_valid(text,jsonb) owner to postgres;
revoke all on function rsuelvo_private.fn_security_event_metadata_valid(text,jsonb) from public,anon,authenticated,service_role;

create or replace function rsuelvo_private.fn_security_event_privilege_direction(
  p_from_role text,p_to_role text
) returns text language plpgsql immutable set search_path=pg_catalog as $fn$
declare v_from text[]; v_to text[];
begin
  -- IAM-6 capability comparison: do not use tbl_roles.nivel as authorization.
  v_from:=case p_from_role
    when 'ROLE_SUPERADMIN' then array['authorization.resolve','business.close','business.configure','business.create','business.read','business.state','business.transferOwnership','credits.deposit.read','credits.packages.manage','credits.read','credits.resolve','customers.export','inventory.manage','inventory.read','logistics.manage','logistics.own','members.invite','members.lifecycle','members.mutate','members.read','orders.manage','payments.verify','reports.operational','reports.sensitive','solicitudes.read','solicitudes.resolve']
    when 'ROLE_SYSADMIN' then array['business.create','business.read','credits.read','reports.operational','solicitudes.read','solicitudes.resolve']
    when 'ROLE_SUPPORT' then array['business.read','credits.read','reports.operational']
    when 'ROLE_TENANT_ADMIN' then array['business.configure','business.read','credits.read','customers.export','inventory.manage','inventory.read','logistics.manage','members.invite','members.read','orders.manage','payments.verify','reports.operational']
    when 'ROLE_TENANT_CASHIER' then array['business.read','inventory.read','orders.manage','payments.verify']
    when 'ROLE_LOGISTICS_AGENT' then array['business.read','logistics.own'] else null end;
  v_to:=case p_to_role
    when 'ROLE_SUPERADMIN' then array['authorization.resolve','business.close','business.configure','business.create','business.read','business.state','business.transferOwnership','credits.deposit.read','credits.packages.manage','credits.read','credits.resolve','customers.export','inventory.manage','inventory.read','logistics.manage','logistics.own','members.invite','members.lifecycle','members.mutate','members.read','orders.manage','payments.verify','reports.operational','reports.sensitive','solicitudes.read','solicitudes.resolve']
    when 'ROLE_SYSADMIN' then array['business.create','business.read','credits.read','reports.operational','solicitudes.read','solicitudes.resolve']
    when 'ROLE_SUPPORT' then array['business.read','credits.read','reports.operational']
    when 'ROLE_TENANT_ADMIN' then array['business.configure','business.read','credits.read','customers.export','inventory.manage','inventory.read','logistics.manage','members.invite','members.read','orders.manage','payments.verify','reports.operational']
    when 'ROLE_TENANT_CASHIER' then array['business.read','inventory.read','orders.manage','payments.verify']
    when 'ROLE_LOGISTICS_AGENT' then array['business.read','logistics.own'] else null end;
  if v_from is null or v_to is null then raise exception 'role code outside IAM-6 catalog'; end if;
  if v_from <@ v_to and v_to <@ v_from then return 'RECLASSIFIED';
  elsif v_from <@ v_to then return 'ELEVATED';
  elsif v_to <@ v_from then return 'REDUCED';
  else return 'MIXED'; end if;
end;
$fn$;
alter function rsuelvo_private.fn_security_event_privilege_direction(text,text) owner to postgres;
revoke all on function rsuelvo_private.fn_security_event_privilege_direction(text,text) from public,anon,authenticated,service_role;

create table rsuelvo_private.tbl_security_events (
  id_evento uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null,
  created_at timestamptz not null default transaction_timestamp(),
  event_type text not null check (event_type in (
    'OWNER.TRANSFER_STARTED','OWNER.TRANSFER_COMPLETED','OWNER.TRANSFER_CANCELLED',
    'MEMBERSHIP.SUSPENDED','MEMBERSHIP.REACTIVATED','MEMBERSHIP.REVOKED',
    'MEMBERSHIP.PRIVILEGE_CHANGED','VERIFICATION.V1_REVOKED')),
  severity text not null check (severity in ('NOTICE','HIGH','CRITICAL')),
  retention_days smallint generated always as
    (case severity when 'NOTICE' then 180 when 'HIGH' then 365 when 'CRITICAL' then 365 end) stored,
  outcome text not null check (outcome in ('SUCCESS','CANCELLED')),
  actor_type text not null,
  actor_user_id uuid references rsuelvo.tbl_usuarios(id_usuario) on delete restrict,
  id_comercio uuid not null references rsuelvo.tbl_comercios(id_comercio) on delete restrict,
  source text not null default 'POSTGRES_RPC',
  producer text not null,
  correlation_id uuid,
  metadata jsonb not null,
  constraint security_events_actor_chk check (
    (actor_type='USER' and actor_user_id is not null) or (actor_type='SERVICE_ROLE' and actor_user_id is null)),
  constraint security_events_source_chk check (source='POSTGRES_RPC'),
  constraint security_events_pair_chk check (
    (event_type='OWNER.TRANSFER_STARTED' and severity='HIGH' and outcome='SUCCESS' and producer='fn_iniciar_transferencia') or
    (event_type='OWNER.TRANSFER_COMPLETED' and severity='CRITICAL' and outcome='SUCCESS' and producer='fn_responder_transferencia') or
    (event_type='OWNER.TRANSFER_CANCELLED' and severity='NOTICE' and outcome='CANCELLED' and producer='fn_cancelar_transferencia') or
    (event_type='MEMBERSHIP.SUSPENDED' and severity='HIGH' and outcome='SUCCESS' and producer='fn_gestionar_vinculo') or
    (event_type='MEMBERSHIP.REACTIVATED' and severity='NOTICE' and outcome='SUCCESS' and producer='fn_gestionar_vinculo') or
    (event_type='MEMBERSHIP.REVOKED' and severity='HIGH' and outcome='SUCCESS' and producer='fn_gestionar_vinculo') or
    (event_type='MEMBERSHIP.PRIVILEGE_CHANGED' and severity='HIGH' and outcome='SUCCESS' and producer='fn_gestionar_vinculo') or
    (event_type='VERIFICATION.V1_REVOKED' and severity='HIGH' and outcome='SUCCESS' and producer='fn_revocar_verificacion_v1')),
  constraint security_events_metadata_chk check (
    jsonb_typeof(metadata)='object' and octet_length(metadata::text)<=2048
    and rsuelvo_private.fn_security_event_metadata_valid(event_type,metadata))
);
alter table rsuelvo_private.tbl_security_events owner to postgres;
alter table rsuelvo_private.tbl_security_events enable row level security;
alter table rsuelvo_private.tbl_security_events force row level security;
revoke all on rsuelvo_private.tbl_security_events from public,anon,authenticated,service_role;
grant all on rsuelvo_private.tbl_security_events to postgres;

create index security_events_occurred_idx on rsuelvo_private.tbl_security_events(occurred_at desc,id_evento desc);
create index security_events_type_occurred_idx on rsuelvo_private.tbl_security_events(event_type,occurred_at desc,id_evento desc);
create index security_events_commerce_occurred_idx on rsuelvo_private.tbl_security_events(id_comercio,occurred_at desc,id_evento desc);
create index security_events_actor_occurred_idx on rsuelvo_private.tbl_security_events(actor_user_id,occurred_at desc,id_evento desc);
create index security_events_severity_occurred_idx on rsuelvo_private.tbl_security_events(severity,occurred_at);

create or replace function rsuelvo_private.fn_security_events_append_only_guard()
returns trigger language plpgsql security definer set search_path=pg_catalog as $fn$
begin
  if tg_op='UPDATE' then raise exception 'SecurityEvent rows are immutable'; end if;
  if tg_op='DELETE' and current_setting('rsuelvo.security_events_purge_tx',true) is distinct from txid_current()::text then
    raise exception 'SecurityEvent deletion is reserved for retention purge';
  end if;
  return old;
end;
$fn$;
alter function rsuelvo_private.fn_security_events_append_only_guard() owner to postgres;
revoke all on function rsuelvo_private.fn_security_events_append_only_guard() from public,anon,authenticated,service_role;
create trigger trg_security_events_append_only before update or delete
on rsuelvo_private.tbl_security_events for each row
execute function rsuelvo_private.fn_security_events_append_only_guard();

create or replace function rsuelvo_private.fn_emit_security_event(
  p_event_type text,p_actor_type text,p_actor_user_id uuid,p_id_comercio uuid,
  p_producer text,p_correlation_id uuid,p_metadata jsonb
) returns uuid language plpgsql volatile security definer
set search_path=pg_catalog,rsuelvo_private,rsuelvo as $fn$
declare v_severity text; v_outcome text; v_id uuid;
begin
  case p_event_type
    when 'OWNER.TRANSFER_STARTED' then v_severity:='HIGH'; v_outcome:='SUCCESS';
    when 'OWNER.TRANSFER_COMPLETED' then v_severity:='CRITICAL'; v_outcome:='SUCCESS';
    when 'OWNER.TRANSFER_CANCELLED' then v_severity:='NOTICE'; v_outcome:='CANCELLED';
    when 'MEMBERSHIP.SUSPENDED' then v_severity:='HIGH'; v_outcome:='SUCCESS';
    when 'MEMBERSHIP.REACTIVATED' then v_severity:='NOTICE'; v_outcome:='SUCCESS';
    when 'MEMBERSHIP.REVOKED' then v_severity:='HIGH'; v_outcome:='SUCCESS';
    when 'MEMBERSHIP.PRIVILEGE_CHANGED' then v_severity:='HIGH'; v_outcome:='SUCCESS';
    when 'VERIFICATION.V1_REVOKED' then v_severity:='HIGH'; v_outcome:='SUCCESS';
    else raise exception 'SecurityEvent type not in V1 catalog';
  end case;
  if p_id_comercio is null or p_producer is null or p_actor_type not in ('USER','SERVICE_ROLE')
    or (p_actor_type='USER' and p_actor_user_id is null)
    or (p_actor_type='SERVICE_ROLE' and p_actor_user_id is not null)
    or not fn_security_event_metadata_valid(p_event_type,p_metadata) then
    raise exception 'SecurityEvent producer arguments invalid';
  end if;
  insert into tbl_security_events(occurred_at,event_type,severity,outcome,actor_type,actor_user_id,
    id_comercio,source,producer,correlation_id,metadata)
  values(clock_timestamp(),p_event_type,v_severity,v_outcome,p_actor_type,p_actor_user_id,
    p_id_comercio,'POSTGRES_RPC',p_producer,p_correlation_id,p_metadata)
  returning id_evento into v_id;
  return v_id;
end;
$fn$;
alter function rsuelvo_private.fn_emit_security_event(text,text,uuid,uuid,text,uuid,jsonb) owner to postgres;
revoke all on function rsuelvo_private.fn_emit_security_event(text,text,uuid,uuid,text,uuid,jsonb)
  from public,anon,authenticated,service_role;

create or replace function rsuelvo_private.fn_security_event_actor(
  out actor_type text,out actor_user_id uuid
) returns record language plpgsql stable security definer
set search_path=pg_catalog,rsuelvo_private,rsuelvo as $fn$
begin
  select u.id_usuario into actor_user_id from rsuelvo.tbl_usuarios u
    where u.auth_user_id=auth.uid() and u.activo;
  if actor_user_id is not null then actor_type:='USER'; return; end if;
  if rsuelvo.fn_es_service_role() then actor_type:='SERVICE_ROLE'; actor_user_id:=null; return; end if;
  raise exception 'security_event_actor_unavailable';
end;
$fn$;
alter function rsuelvo_private.fn_security_event_actor() owner to postgres;
revoke all on function rsuelvo_private.fn_security_event_actor() from public,anon,authenticated,service_role;

create or replace function rsuelvo.fn_security_events_buscar(
  p_from timestamptz,p_to timestamptz,p_event_type text default null,
  p_id_comercio uuid default null,p_actor_user_id uuid default null,
  p_before_at timestamptz default null,p_before_id uuid default null,p_limit integer default 100
) returns table (
  id_evento uuid,occurred_at timestamptz,created_at timestamptz,event_type text,severity text,
  retention_days smallint,outcome text,actor_type text,actor_user_id uuid,id_comercio uuid,
  source text,producer text,correlation_id uuid,metadata jsonb
) language plpgsql volatile security definer
set search_path=pg_catalog,rsuelvo_private,rsuelvo as $fn$
declare v_actor uuid;
begin
  if auth.uid() is null or not (rsuelvo.fn_es_superadmin()
      or rsuelvo.fn_tiene_rol('ROLE_SYSADMIN'::rsuelvo.rol_codigo)) then raise exception 'sin_permiso'; end if;
  v_actor:=rsuelvo.fn_current_usuario_id();
  if v_actor is null then raise exception 'sin_identidad_rsuelvo'; end if;
  if p_from is null or p_to is null or p_from>=p_to or p_to>statement_timestamp()
     or p_from<statement_timestamp()-interval '365 days' or p_to-p_from>interval '31 days' then
    raise exception 'rango_fechas_invalido';
  end if;
  if p_event_type is not null and p_event_type not in (
    'OWNER.TRANSFER_STARTED','OWNER.TRANSFER_COMPLETED','OWNER.TRANSFER_CANCELLED',
    'MEMBERSHIP.SUSPENDED','MEMBERSHIP.REACTIVATED','MEMBERSHIP.REVOKED',
    'MEMBERSHIP.PRIVILEGE_CHANGED','VERIFICATION.V1_REVOKED') then raise exception 'event_type_invalido'; end if;
  if p_limit is null or p_limit not between 1 and 100 then raise exception 'limit_invalido'; end if;
  if (p_before_at is null)<>(p_before_id is null) then raise exception 'cursor_invalido'; end if;
  insert into rsuelvo.tbl_logs_auditoria(id_usuario,accion,tabla,datos_nuevos)
  values(v_actor,'security_events_consultados','tbl_security_events',jsonb_build_object(
    'from',p_from,'to',p_to,'event_type',p_event_type,'id_comercio',p_id_comercio,
    'actor_user_id',p_actor_user_id,'limit',p_limit,'cursor_used',p_before_at is not null));
  return query
  select e.id_evento,e.occurred_at,e.created_at,e.event_type,e.severity,e.retention_days,
    e.outcome,e.actor_type,e.actor_user_id,e.id_comercio,e.source,e.producer,e.correlation_id,e.metadata
  from rsuelvo_private.tbl_security_events e
  where e.occurred_at>=p_from and e.occurred_at<p_to
    and (p_event_type is null or e.event_type=p_event_type)
    and (p_id_comercio is null or e.id_comercio=p_id_comercio)
    and (p_actor_user_id is null or e.actor_user_id=p_actor_user_id)
    and (p_before_at is null or (e.occurred_at,e.id_evento)<(p_before_at,p_before_id))
  order by e.occurred_at desc,e.id_evento desc limit p_limit;
end;
$fn$;
alter function rsuelvo.fn_security_events_buscar(timestamptz,timestamptz,text,uuid,uuid,timestamptz,uuid,integer) owner to postgres;
revoke all on function rsuelvo.fn_security_events_buscar(timestamptz,timestamptz,text,uuid,uuid,timestamptz,uuid,integer)
  from public,anon,service_role;
grant execute on function rsuelvo.fn_security_events_buscar(timestamptz,timestamptz,text,uuid,uuid,timestamptz,uuid,integer)
  to authenticated;

create or replace function rsuelvo_private.fn_security_events_purge(p_batch_size integer default 500)
returns integer language plpgsql volatile security definer
set search_path=pg_catalog,rsuelvo_private,rsuelvo as $fn$
declare v_total integer:=0; v_deleted integer; v_iteration integer; v_cutoff timestamptz:=clock_timestamp();
begin
  if p_batch_size is null or p_batch_size not between 1 and 500 then raise exception 'batch_size_invalido'; end if;
  if not pg_try_advisory_xact_lock(731022,101) then return 0; end if;
  perform set_config('rsuelvo.security_events_purge_tx',txid_current()::text,true);
  for v_iteration in 1..10 loop
    with doomed as (
      select id_evento from rsuelvo_private.tbl_security_events
      where occurred_at<v_cutoff-make_interval(days=>retention_days::integer)
      order by occurred_at,id_evento for update skip locked limit p_batch_size
    ),gone as (
      delete from rsuelvo_private.tbl_security_events e using doomed d
      where e.id_evento=d.id_evento returning 1
    ) select count(*)::integer into v_deleted from gone;
    v_total:=v_total+v_deleted;
    exit when v_deleted<p_batch_size;
  end loop;
  if v_total>0 then
    insert into rsuelvo.tbl_logs_auditoria(accion,tabla,datos_nuevos)
    values('security_events_purge','tbl_security_events',jsonb_build_object(
      'deleted_count',v_total,'batch_size',p_batch_size,'max_batches',10,
      'retention_policy_version','IAM10-V1','cutoff_at',v_cutoff));
  end if;
  -- Keep the purge-only delete marker scoped to this function call, even if a
  -- privileged maintenance session runs additional statements in the transaction.
  perform set_config('rsuelvo.security_events_purge_tx','',true);
  return v_total;
end;
$fn$;
alter function rsuelvo_private.fn_security_events_purge(integer) owner to postgres;
revoke all on function rsuelvo_private.fn_security_events_purge(integer) from public,anon,authenticated,service_role;
grant execute on function rsuelvo_private.fn_security_events_purge(integer) to postgres;

create or replace function rsuelvo_private.fn_security_events_purge_watchdog()
returns void language plpgsql volatile security definer
set search_path=pg_catalog,rsuelvo_private,rsuelvo as $fn$
declare
  v_job_id bigint; v_last_success timestamptz; v_configured_at timestamptz; v_last_runs text[]; v_failures integer;
  v_problem boolean; v_incident_id uuid; v_incident_at timestamptz;
  v_latest_failure timestamptz; v_latest_recovery timestamptz; v_level text; v_expired boolean;
begin
  if not pg_try_advisory_xact_lock(731022,102) then return; end if;
  select max(created_at) into v_configured_at from rsuelvo.tbl_logs_auditoria
    where accion='security_events_purge_configured';
  v_configured_at:=coalesce(v_configured_at,clock_timestamp());
  select jobid into v_job_id from cron.job
    where jobname='rsuelvo-security-events-purge' and active and database=current_database()
    order by jobid desc limit 1;
  if v_job_id is null then
    -- Keep the 20-minute grace period when the job was removed/disabled; prior
    -- pg_cron run details still retain the command text for this purge producer.
    select max(start_time) filter(where status='succeeded') into v_last_success
      from cron.job_run_details
      where command ilike '%rsuelvo_private.fn_security_events_purge%';
    v_incident_at:=coalesce(v_last_success,v_configured_at)+interval '20 minutes';
    v_problem:=clock_timestamp()>v_incident_at;
  else
    select max(start_time) filter(where status='succeeded'),
      array_agg(status order by start_time desc) filter(where status in ('succeeded','failed'))
      into v_last_success,v_last_runs
    from (select start_time,status from cron.job_run_details where jobid=v_job_id
      order by start_time desc limit 2) r;
    v_failures:=case when coalesce(array_length(v_last_runs,1),0)>=2
      and v_last_runs[1]='failed' and v_last_runs[2]='failed' then 2 else 0 end;
    v_problem:=v_failures=2 or clock_timestamp()>
      coalesce(v_last_success,v_configured_at)+interval '20 minutes';
    if v_failures=2 then
      select min(start_time) into v_incident_at from (
        select start_time,status from cron.job_run_details where jobid=v_job_id
          and status in ('succeeded','failed') order by start_time desc limit 2
      ) f where status='failed';
    else v_incident_at:=coalesce(v_last_success,v_configured_at)+interval '20 minutes';
    end if;
  end if;
  select created_at,id_log into v_latest_failure,v_incident_id
    from rsuelvo.tbl_logs_auditoria where accion='security_events_purge_failure' order by created_at desc limit 1;
  select max(created_at) into v_latest_recovery from rsuelvo.tbl_logs_auditoria
    where accion='security_events_purge_recovered';
  if v_problem and (v_latest_failure is null or v_latest_failure<=coalesce(v_latest_recovery,'-infinity'::timestamptz)) then
    v_level:=case when clock_timestamp()-v_incident_at>interval '72 hours' then 'CRITICAL'
      when clock_timestamp()-v_incident_at>interval '24 hours' then 'HIGH' else 'DEGRADED' end;
    insert into rsuelvo.tbl_logs_auditoria(accion,tabla,datos_nuevos)
    values('security_events_purge_failure','tbl_security_events',jsonb_build_object(
      'incident_started_at',v_incident_at,'level_at_detection',v_level,
      'consecutive_failed_runs',v_failures,'last_success_at',v_last_success,
      'job_missing_or_inactive',v_job_id is null)) returning id_log into v_incident_id;
    v_latest_failure:=clock_timestamp();
  end if;
  if v_latest_failure is not null and v_latest_failure>coalesce(v_latest_recovery,'-infinity'::timestamptz) then
    select exists(select 1 from rsuelvo_private.tbl_security_events
      where occurred_at<clock_timestamp()-make_interval(days=>retention_days::integer)) into v_expired;
    select (datos_nuevos->>'incident_started_at')::timestamptz into v_incident_at
      from rsuelvo.tbl_logs_auditoria where accion='security_events_purge_failure'
       and id_log=v_incident_id;
    v_level:=case when clock_timestamp()-v_incident_at>interval '72 hours' then 'CRITICAL'
      when clock_timestamp()-v_incident_at>interval '24 hours' then 'HIGH' else 'DEGRADED' end;
    if v_level in ('HIGH','CRITICAL') and not exists(select 1 from rsuelvo.tbl_logs_auditoria
       where accion='security_events_purge_escalated' and registro_id=v_incident_id
         and datos_nuevos->>'level'=v_level) then
      insert into rsuelvo.tbl_logs_auditoria(accion,tabla,registro_id,datos_nuevos)
      values('security_events_purge_escalated','tbl_security_events',v_incident_id,
        jsonb_build_object('level',v_level,'incident_started_at',v_incident_at));
    end if;
    if not v_problem and not v_expired then
      insert into rsuelvo.tbl_logs_auditoria(accion,tabla,registro_id,datos_nuevos)
      values('security_events_purge_recovered','tbl_security_events',v_incident_id,
        jsonb_build_object('incident_started_at',v_incident_at,'recovered_at',clock_timestamp(),
          'expired_remaining',0,'last_success_at',v_last_success));
    end if;
  end if;
end;
$fn$;
alter function rsuelvo_private.fn_security_events_purge_watchdog() owner to postgres;
revoke all on function rsuelvo_private.fn_security_events_purge_watchdog() from public,anon,authenticated,service_role;
grant execute on function rsuelvo_private.fn_security_events_purge_watchdog() to postgres;

-- Ownership transfer producers: serialize start/completion/cancel on commerce then transfer.
create or replace function rsuelvo.fn_iniciar_transferencia(p_id_comercio uuid,p_destino uuid)
returns jsonb language plpgsql volatile security definer set search_path=rsuelvo,public as $fn$
declare
  v_usuario uuid; v_estado text; v_owner uuid;
  v_tid uuid; v_existing_owner uuid; v_existing_target uuid; v_actor record;
begin
  select id_usuario into v_usuario from rsuelvo.tbl_usuarios where auth_user_id=auth.uid() and activo;
  if v_usuario is null then return jsonb_build_object('ok',false,'codigo','sin_acceso'); end if;
  if not rsuelvo.fn_es_service_role() and not rsuelvo.fn_tiene_aal2() then
    return jsonb_build_object('ok',false,'codigo','mfa_requerido');
  end if;
  select estado::text,propietario_id into v_estado,v_owner from rsuelvo.tbl_comercios
    where id_comercio=p_id_comercio for update;
  if not found or v_estado<>'ACTIVO' then return jsonb_build_object('ok',false,'codigo','comercio_no_habilitado'); end if;
  if v_owner is distinct from v_usuario or not rsuelvo.fn_es_owner(p_id_comercio) then
    return jsonb_build_object('ok',false,'codigo','solo_owner');
  end if;
  if p_destino=v_usuario or not exists(
    select 1 from rsuelvo.tbl_usuario_comercio uc join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
    where uc.id_usuario=p_destino and uc.id_comercio=p_id_comercio
      and r.codigo='ROLE_TENANT_ADMIN' and uc.estado='ACTIVE') then
    return jsonb_build_object('ok',false,'codigo','destino_invalido');
  end if;
  update rsuelvo.tbl_transferencias_propiedad set estado='VENCIDA'
    where id_comercio=p_id_comercio and estado='PENDIENTE' and expira_at<=clock_timestamp();
  select id,propietario_origen,propietario_destino into v_tid,v_existing_owner,v_existing_target
    from rsuelvo.tbl_transferencias_propiedad
    where id_comercio=p_id_comercio and estado='PENDIENTE' and expira_at>clock_timestamp() for update;
  if v_tid is not null then
    if v_existing_owner=v_owner and v_existing_target=p_destino then
      return jsonb_build_object('ok',true,'id_transferencia',v_tid,'codigo','reutilizada');
    end if;
    return jsonb_build_object('ok',false,'codigo','transferencia_pendiente');
  end if;
  begin
    insert into rsuelvo.tbl_transferencias_propiedad(id_comercio,propietario_origen,propietario_destino,initiated_by)
      values(p_id_comercio,v_owner,p_destino,v_owner) returning id into v_tid;
  exception when unique_violation then
    select id,propietario_origen,propietario_destino into v_tid,v_existing_owner,v_existing_target
      from rsuelvo.tbl_transferencias_propiedad where id_comercio=p_id_comercio and estado='PENDIENTE' for update;
    if v_tid is not null and v_existing_owner=v_owner and v_existing_target=p_destino then
      return jsonb_build_object('ok',true,'id_transferencia',v_tid,'codigo','reutilizada');
    end if;
    return jsonb_build_object('ok',false,'codigo','transferencia_pendiente');
  end;
  insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
    values(p_id_comercio,v_usuario,'transferencia_iniciada','tbl_transferencias_propiedad',v_tid);
  select * into v_actor from rsuelvo_private.fn_security_event_actor();
  perform rsuelvo_private.fn_emit_security_event('OWNER.TRANSFER_STARTED',v_actor.actor_type,
    v_actor.actor_user_id,p_id_comercio,'fn_iniciar_transferencia',null,
    jsonb_build_object('transfer_id',v_tid,'target_user_id',p_destino));
  return jsonb_build_object('ok',true,'id_transferencia',v_tid);
end;$fn$;
alter function rsuelvo.fn_iniciar_transferencia(uuid,uuid) owner to postgres;
revoke all on function rsuelvo.fn_iniciar_transferencia(uuid,uuid) from public,anon;
grant execute on function rsuelvo.fn_iniciar_transferencia(uuid,uuid) to authenticated,service_role;

create or replace function rsuelvo.fn_responder_transferencia(p_id uuid,p_acepta boolean)
returns jsonb language plpgsql volatile security definer set search_path=rsuelvo,public as $fn$
declare
  v_usuario uuid; v_comercio uuid; v_t record; v_owner uuid; v_actor record;
begin
  select id_usuario into v_usuario from rsuelvo.tbl_usuarios where auth_user_id=auth.uid() and activo;
  if v_usuario is null then return jsonb_build_object('ok',false,'codigo','sin_acceso'); end if;
  if not rsuelvo.fn_es_service_role() and not rsuelvo.fn_tiene_aal2() then
    return jsonb_build_object('ok',false,'codigo','mfa_requerido');
  end if;
  select id_comercio into v_comercio from rsuelvo.tbl_transferencias_propiedad where id=p_id;
  if v_comercio is null then return jsonb_build_object('ok',false,'codigo','transferencia_no_existe'); end if;
  perform 1 from rsuelvo.tbl_comercios where id_comercio=v_comercio for update;
  select * into v_t from rsuelvo.tbl_transferencias_propiedad where id=p_id for update;
  if v_t.id is null then return jsonb_build_object('ok',false,'codigo','transferencia_no_existe'); end if;
  if v_t.propietario_destino<>v_usuario then return jsonb_build_object('ok',false,'codigo','transferencia_ajena'); end if;
  if v_t.estado<>'PENDIENTE' or v_t.expira_at<=clock_timestamp() then
    if v_t.estado='PENDIENTE' then update rsuelvo.tbl_transferencias_propiedad set estado='VENCIDA' where id=p_id; end if;
    return jsonb_build_object('ok',false,'codigo','transferencia_vencida');
  end if;
  if not p_acepta then
    update rsuelvo.tbl_transferencias_propiedad set estado='RECHAZADA' where id=p_id;
    insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
      values(v_t.id_comercio,v_usuario,'transferencia_rechazada','tbl_transferencias_propiedad',p_id);
    return jsonb_build_object('ok',true,'estado','RECHAZADA');
  end if;
  if not exists(select 1 from rsuelvo.tbl_comercios where id_comercio=v_t.id_comercio and propietario_id=v_t.propietario_origen)
     or not exists(select 1 from rsuelvo.tbl_usuario_comercio uc join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
       where uc.id_usuario=v_t.propietario_origen and uc.id_comercio=v_t.id_comercio and r.codigo='ROLE_TENANT_ADMIN' and uc.estado='ACTIVE')
     or not exists(select 1 from rsuelvo.tbl_usuario_comercio uc join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
       where uc.id_usuario=v_usuario and uc.id_comercio=v_t.id_comercio and r.codigo='ROLE_TENANT_ADMIN' and uc.estado='ACTIVE') then
    return jsonb_build_object('ok',false,'codigo','owner_o_destino_invalido');
  end if;
  update rsuelvo.tbl_comercios set propietario_id=v_usuario,updated_at=clock_timestamp()
    where id_comercio=v_t.id_comercio and propietario_id=v_t.propietario_origen returning propietario_id into v_owner;
  if v_owner is null then return jsonb_build_object('ok',false,'codigo','origen_ya_no_owner'); end if;
  update rsuelvo.tbl_transferencias_propiedad set estado='ACEPTADA',accepted_at=clock_timestamp()
    where id=p_id and estado='PENDIENTE';
  if not found then raise exception 'transferencia_transition_lost'; end if;
  insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
    values(v_t.id_comercio,v_usuario,'transferencia_aceptada','tbl_transferencias_propiedad',p_id);
  select * into v_actor from rsuelvo_private.fn_security_event_actor();
  perform rsuelvo_private.fn_emit_security_event('OWNER.TRANSFER_COMPLETED',v_actor.actor_type,
    v_actor.actor_user_id,v_t.id_comercio,'fn_responder_transferencia',null,
    jsonb_build_object('transfer_id',p_id,'previous_owner_user_id',v_t.propietario_origen,'target_user_id',v_usuario));
  return jsonb_build_object('ok',true,'estado','ACEPTADA');
end;$fn$;
alter function rsuelvo.fn_responder_transferencia(uuid,boolean) owner to postgres;
revoke all on function rsuelvo.fn_responder_transferencia(uuid,boolean) from public,anon;
grant execute on function rsuelvo.fn_responder_transferencia(uuid,boolean) to authenticated,service_role;

create or replace function rsuelvo.fn_cancelar_transferencia(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=rsuelvo,public as $fn$
declare v_usuario uuid; v_comercio uuid; v_t record; v_actor record;
begin
  select id_usuario into v_usuario from rsuelvo.tbl_usuarios where auth_user_id=auth.uid() and activo;
  if v_usuario is null then return jsonb_build_object('ok',false,'codigo','sin_acceso'); end if;
  select id_comercio into v_comercio from rsuelvo.tbl_transferencias_propiedad where id=p_id;
  if v_comercio is null then return jsonb_build_object('ok',false,'codigo','transferencia_no_existe'); end if;
  perform 1 from rsuelvo.tbl_comercios where id_comercio=v_comercio for update;
  select * into v_t from rsuelvo.tbl_transferencias_propiedad where id=p_id for update;
  if v_t.id is null then return jsonb_build_object('ok',false,'codigo','transferencia_no_existe'); end if;
  if v_t.estado<>'PENDIENTE' then return jsonb_build_object('ok',false,'codigo','transferencia_no_pendiente'); end if;
  if v_t.propietario_origen<>v_usuario and not rsuelvo.fn_es_superadmin() then
    return jsonb_build_object('ok',false,'codigo','sin_permiso');
  end if;
  update rsuelvo.tbl_transferencias_propiedad set estado='CANCELADA' where id=p_id and estado='PENDIENTE';
  if not found then return jsonb_build_object('ok',false,'codigo','transferencia_no_pendiente'); end if;
  insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
    values(v_t.id_comercio,v_usuario,'transferencia_cancelada','tbl_transferencias_propiedad',p_id);
  select * into v_actor from rsuelvo_private.fn_security_event_actor();
  perform rsuelvo_private.fn_emit_security_event('OWNER.TRANSFER_CANCELLED',v_actor.actor_type,
    v_actor.actor_user_id,v_t.id_comercio,'fn_cancelar_transferencia',null,jsonb_build_object('transfer_id',p_id));
  return jsonb_build_object('ok',true);
end;$fn$;
alter function rsuelvo.fn_cancelar_transferencia(uuid) owner to postgres;
revoke all on function rsuelvo.fn_cancelar_transferencia(uuid) from public,anon;
grant execute on function rsuelvo.fn_cancelar_transferencia(uuid) to authenticated,service_role;

create or replace function rsuelvo.fn_revocar_verificacion_v1(p_id_comercio uuid,p_motivo text default null)
returns jsonb language plpgsql volatile security definer set search_path=rsuelvo,public as $fn$
declare
  v_usuario uuid; v_estado text; v_checks jsonb; v_vid uuid; v_actor record;
begin
  select id_usuario into v_usuario from rsuelvo.tbl_usuarios where auth_user_id=auth.uid() and activo;
  if v_usuario is null then return jsonb_build_object('ok',false,'codigo','sin_acceso'); end if;
  if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then raise exception 'solo superadmin'; end if;
  if not rsuelvo.fn_es_service_role() and not rsuelvo.fn_tiene_aal2() then
    return jsonb_build_object('ok',false,'codigo','mfa_requerido'); end if;
  if nullif(trim(coalesce(p_motivo,' ')),'') is null then return jsonb_build_object('ok',false,'codigo','motivo_requerido'); end if;
  select estado::text into v_estado from rsuelvo.tbl_comercios where id_comercio=p_id_comercio for update;
  if v_estado is null then return jsonb_build_object('ok',false,'codigo','comercio_no_existe'); end if;
  if v_estado='PENDIENTE_VERIFICACION' then return jsonb_build_object('ok',true,'codigo','ya_v0'); end if;
  if v_estado<>'ACTIVO' then return jsonb_build_object('ok',false,'codigo','estado_incompatible'); end if;
  v_checks:=rsuelvo.fn_checks_verificacion_v1(p_id_comercio)->'checks';
  insert into rsuelvo.tbl_verificaciones_comercio(id_comercio,estado,origen,id_verificador,
    checks_snapshot,motivo_revocacion,revoked_at,revoked_by,resolved_at)
  values(p_id_comercio,'REVOCADA','SUPERADMIN',v_usuario,v_checks,trim(p_motivo),clock_timestamp(),v_usuario,clock_timestamp())
  returning id_verificacion into v_vid;
  update rsuelvo.tbl_comercios set estado='PENDIENTE_VERIFICACION',updated_at=clock_timestamp()
    where id_comercio=p_id_comercio and estado='ACTIVO';
  if not found then raise exception 'verification_transition_lost'; end if;
  insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
    values(p_id_comercio,v_usuario,'verificacion_v1_revocada','tbl_verificaciones_comercio',v_vid);
  select * into v_actor from rsuelvo_private.fn_security_event_actor();
  perform rsuelvo_private.fn_emit_security_event('VERIFICATION.V1_REVOKED',v_actor.actor_type,
    v_actor.actor_user_id,p_id_comercio,'fn_revocar_verificacion_v1',null,jsonb_build_object('verification_id',v_vid));
  return jsonb_build_object('ok',true,'codigo','revocado');
end;$fn$;
alter function rsuelvo.fn_revocar_verificacion_v1(uuid,text) owner to postgres;
revoke all on function rsuelvo.fn_revocar_verificacion_v1(uuid,text) from public,anon;
grant execute on function rsuelvo.fn_revocar_verificacion_v1(uuid,text) to authenticated,service_role;

create or replace function rsuelvo.fn_gestionar_vinculo(
  p_id_usuario uuid,p_id_comercio uuid,p_id_rol smallint,p_id_sucursal uuid default null,
  p_accion text default 'CREAR',p_rol_nuevo smallint default null,p_sucursal_nueva uuid default null
) returns jsonb language plpgsql volatile security definer set search_path=rsuelvo,public as $fn$
declare
  v_acc text:=upper(trim(coalesce(p_accion,'CREAR'))); v_actor_id uuid; v_actor_type text;
  v_actor record; v_source record; v_target record; v_role_old text; v_role_new text;
  v_state text; v_commerce_state text; v_cashiers integer; v_direction text; v_target_id uuid;
begin
  if not (rsuelvo.fn_es_service_role() or rsuelvo.fn_es_superadmin()) then raise exception 'solo superadmin'; end if;
  if not rsuelvo.fn_es_service_role() and not rsuelvo.fn_tiene_aal2() then
    return jsonb_build_object('ok',false,'codigo','mfa_requerido'); end if;
  select * into v_actor from rsuelvo_private.fn_security_event_actor();
  v_actor_id:=v_actor.actor_user_id; v_actor_type:=v_actor.actor_type;

  if v_acc='CAMBIAR' then
    if p_rol_nuevo is null then return jsonb_build_object('ok',false,'codigo','falta_rol_nuevo'); end if;
    select * into v_source from rsuelvo.tbl_usuario_comercio
      where id_usuario=p_id_usuario and id_comercio=p_id_comercio and id_rol=p_id_rol
        and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)
        and estado in ('ACTIVE','SUSPENDED') for update;
    if v_source.id is null then return jsonb_build_object('ok',false,'codigo','vinculo_no_existe'); end if;
    select codigo::text into v_role_old from rsuelvo.tbl_roles where id_rol=v_source.id_rol;
    if rsuelvo.fn_es_vinculo_owner(p_id_usuario,p_id_comercio) and p_rol_nuevo<>v_source.id_rol then
      return jsonb_build_object('ok',false,'codigo','owner_protegido'); end if;
    select codigo::text into v_role_new from rsuelvo.tbl_roles where id_rol=p_rol_nuevo;
    if v_role_new is null or v_role_new='ROLE_SUPERADMIN' then return jsonb_build_object('ok',false,'codigo','rol_invalido'); end if;
    if p_sucursal_nueva is not null and not exists(select 1 from rsuelvo.tbl_sucursales
      where id_sucursal=p_sucursal_nueva and id_comercio=p_id_comercio and activo) then
      return jsonb_build_object('ok',false,'codigo','sucursal_invalida'); end if;
    if v_role_new='ROLE_LOGISTICS_AGENT' and p_sucursal_nueva is null then
      return jsonb_build_object('ok',false,'codigo','sucursal_obligatoria'); end if;
    if p_rol_nuevo=v_source.id_rol then
      if v_source.estado='ACTIVE' and v_source.id_sucursal is not distinct from p_sucursal_nueva then
        return jsonb_build_object('ok',true,'nuevo','CAMBIADO','codigo','ya_cambiado'); end if;
      update rsuelvo.tbl_usuario_comercio set id_sucursal=p_sucursal_nueva,estado='ACTIVE'
        where id=v_source.id returning id into v_target_id;
      insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
        values(p_id_comercio,v_actor_id,'vinculo_cambiado','tbl_usuario_comercio',v_target_id);
      if v_source.estado='SUSPENDED' then
        perform rsuelvo_private.fn_emit_security_event('MEMBERSHIP.REACTIVATED',v_actor_type,v_actor_id,
          p_id_comercio,'fn_gestionar_vinculo',null,jsonb_build_object('membership_id',v_target_id,'target_user_id',p_id_usuario));
      end if;
      return jsonb_build_object('ok',true,'nuevo','CAMBIADO');
    end if;

    if v_source.estado='SUSPENDED' and exists(select 1 from rsuelvo.tbl_usuario_comercio
      where id_usuario=p_id_usuario and id_comercio=p_id_comercio and id_rol=p_rol_nuevo
        and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_sucursal_nueva,'00000000-0000-0000-0000-000000000000'::uuid)
        and estado='ACTIVE') then
      return jsonb_build_object('ok',true,'nuevo','CAMBIADO','codigo','ya_cambiado'); end if;
    if v_role_new='ROLE_TENANT_CASHIER' then
      select count(*) into v_cashiers from rsuelvo.tbl_usuario_comercio uc join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
        where uc.id_usuario=p_id_usuario and uc.id_comercio=p_id_comercio and uc.estado in ('ACTIVE','SUSPENDED')
          and r.codigo='ROLE_TENANT_CASHIER' and uc.id<>v_source.id;
      if v_cashiers>0 then return jsonb_build_object('ok',false,'codigo','cajero_multiplo'); end if;
    end if;
    if v_source.estado='ACTIVE' then
      update rsuelvo.tbl_usuario_comercio set estado='SUSPENDED' where id=v_source.id;
    end if;
    select * into v_target from rsuelvo.tbl_usuario_comercio
      where id_usuario=p_id_usuario and id_comercio=p_id_comercio and id_rol=p_rol_nuevo
        and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_sucursal_nueva,'00000000-0000-0000-0000-000000000000'::uuid)
        and estado in ('ACTIVE','SUSPENDED') for update;
    if v_target.id is null then
      begin
        insert into rsuelvo.tbl_usuario_comercio(id_usuario,id_comercio,id_rol,id_sucursal,estado)
          values(p_id_usuario,p_id_comercio,p_rol_nuevo,p_sucursal_nueva,'ACTIVE') returning * into v_target;
      exception when unique_violation then
        select * into v_target from rsuelvo.tbl_usuario_comercio
          where id_usuario=p_id_usuario and id_comercio=p_id_comercio and id_rol=p_rol_nuevo
            and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_sucursal_nueva,'00000000-0000-0000-0000-000000000000'::uuid)
            and estado in ('ACTIVE','SUSPENDED') for update;
        if v_target.id is null then raise; end if;
      end;
    elsif v_target.estado='SUSPENDED' then
      update rsuelvo.tbl_usuario_comercio set estado='ACTIVE' where id=v_target.id returning * into v_target;
    end if;
    insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
      values(p_id_comercio,v_actor_id,'vinculo_cambiado','tbl_usuario_comercio',v_target.id);
    v_direction:=rsuelvo_private.fn_security_event_privilege_direction(v_role_old,v_role_new);
    perform rsuelvo_private.fn_emit_security_event('MEMBERSHIP.PRIVILEGE_CHANGED',v_actor_type,v_actor_id,
      p_id_comercio,'fn_gestionar_vinculo',null,jsonb_build_object('membership_id',v_source.id,
        'target_membership_id',v_target.id,'target_user_id',p_id_usuario,'from_role',v_role_old,
        'to_role',v_role_new,'direction',v_direction));
    return jsonb_build_object('ok',true,'nuevo','CAMBIADO');
  end if;

  if v_acc in ('DESACTIVAR','SUSPENDER') then
    if rsuelvo.fn_es_vinculo_owner(p_id_usuario,p_id_comercio) then return jsonb_build_object('ok',false,'codigo','owner_protegido'); end if;
    select * into v_source from rsuelvo.tbl_usuario_comercio where id_usuario=p_id_usuario and id_comercio=p_id_comercio
      and id_rol=p_id_rol and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)
      and estado='ACTIVE' for update;
    if v_source.id is null then return jsonb_build_object('ok',false,'codigo','vinculo_no_existe'); end if;
    update rsuelvo.tbl_usuario_comercio set estado='SUSPENDED' where id=v_source.id;
    insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
      values(p_id_comercio,v_actor_id,'vinculo_suspendido','tbl_usuario_comercio',v_source.id);
    perform rsuelvo_private.fn_emit_security_event('MEMBERSHIP.SUSPENDED',v_actor_type,v_actor_id,p_id_comercio,
      'fn_gestionar_vinculo',null,jsonb_build_object('membership_id',v_source.id,'target_user_id',p_id_usuario));
    return jsonb_build_object('ok',true,'nuevo','SUSPENDIDO');
  end if;
  if v_acc='REVOCAR' then
    if rsuelvo.fn_es_vinculo_owner(p_id_usuario,p_id_comercio) then return jsonb_build_object('ok',false,'codigo','owner_protegido'); end if;
    select * into v_source from rsuelvo.tbl_usuario_comercio where id_usuario=p_id_usuario and id_comercio=p_id_comercio
      and id_rol=p_id_rol and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)
      and estado in ('ACTIVE','SUSPENDED') for update;
    if v_source.id is null then return jsonb_build_object('ok',false,'codigo','vinculo_no_existe'); end if;
    update rsuelvo.tbl_usuario_comercio set estado='REVOKED' where id=v_source.id;
    insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
      values(p_id_comercio,v_actor_id,'vinculo_revocado','tbl_usuario_comercio',v_source.id);
    perform rsuelvo_private.fn_emit_security_event('MEMBERSHIP.REVOKED',v_actor_type,v_actor_id,p_id_comercio,
      'fn_gestionar_vinculo',null,jsonb_build_object('membership_id',v_source.id,'target_user_id',p_id_usuario));
    return jsonb_build_object('ok',true,'nuevo','REVOCADO');
  end if;
  if v_acc<>'CREAR' then return jsonb_build_object('ok',false,'codigo','accion_invalida'); end if;

  select codigo::text into v_role_new from rsuelvo.tbl_roles where id_rol=p_id_rol;
  if v_role_new is null or v_role_new='ROLE_SUPERADMIN' then return jsonb_build_object('ok',false,'codigo','rol_invalido'); end if;
  if not exists(select 1 from rsuelvo.tbl_usuarios where id_usuario=p_id_usuario) then return jsonb_build_object('ok',false,'codigo','usuario_no_existe'); end if;
  select estado::text into v_commerce_state from rsuelvo.tbl_comercios where id_comercio=p_id_comercio;
  if v_commerce_state is null then return jsonb_build_object('ok',false,'codigo','comercio_no_existe'); end if;
  if v_commerce_state not in ('ACTIVO','PENDIENTE_APROBACION') then return jsonb_build_object('ok',false,'codigo','comercio_incompatible','estado',v_commerce_state); end if;
  if p_id_sucursal is not null and not exists(select 1 from rsuelvo.tbl_sucursales
    where id_sucursal=p_id_sucursal and id_comercio=p_id_comercio and activo) then return jsonb_build_object('ok',false,'codigo','sucursal_invalida'); end if;
  if v_role_new='ROLE_LOGISTICS_AGENT' and p_id_sucursal is null then return jsonb_build_object('ok',false,'codigo','sucursal_obligatoria'); end if;
  select * into v_source from rsuelvo.tbl_usuario_comercio where id_usuario=p_id_usuario and id_comercio=p_id_comercio
    and id_rol=p_id_rol and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)
    and estado in ('ACTIVE','SUSPENDED') for update;
  if v_source.id is not null then
    if v_source.estado='ACTIVE' then return jsonb_build_object('ok',true,'reactivado',false); end if;
    update rsuelvo.tbl_usuario_comercio set estado='ACTIVE' where id=v_source.id;
    insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
      values(p_id_comercio,v_actor_id,'vinculo_reactivado','tbl_usuario_comercio',v_source.id);
    perform rsuelvo_private.fn_emit_security_event('MEMBERSHIP.REACTIVATED',v_actor_type,v_actor_id,p_id_comercio,
      'fn_gestionar_vinculo',null,jsonb_build_object('membership_id',v_source.id,'target_user_id',p_id_usuario));
    return jsonb_build_object('ok',true,'reactivado',true);
  end if;
  if exists(select 1 from rsuelvo.tbl_usuario_comercio where id_usuario=p_id_usuario and id_comercio=p_id_comercio
      and id_rol=p_id_rol and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)
      and estado='REVOKED') then return jsonb_build_object('ok',false,'codigo','vinculo_revocado_terminal'); end if;
  if v_role_new='ROLE_TENANT_CASHIER' then
    select count(*) into v_cashiers from rsuelvo.tbl_usuario_comercio uc join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
      where uc.id_usuario=p_id_usuario and uc.id_comercio=p_id_comercio and uc.estado in ('ACTIVE','SUSPENDED') and r.codigo='ROLE_TENANT_CASHIER';
    if v_cashiers>0 then return jsonb_build_object('ok',false,'codigo','cajero_multiplo'); end if;
  end if;
  begin
    insert into rsuelvo.tbl_usuario_comercio(id_usuario,id_comercio,id_rol,id_sucursal,estado)
      values(p_id_usuario,p_id_comercio,p_id_rol,p_id_sucursal,'ACTIVE');
  exception when unique_violation then
    select * into v_source from rsuelvo.tbl_usuario_comercio where id_usuario=p_id_usuario and id_comercio=p_id_comercio
      and id_rol=p_id_rol and coalesce(id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_id_sucursal,'00000000-0000-0000-0000-000000000000'::uuid)
      and estado in ('ACTIVE','SUSPENDED') for update;
    if v_source.id is null then raise; end if;
    if v_source.estado='ACTIVE' then return jsonb_build_object('ok',true,'reactivado',false); end if;
    update rsuelvo.tbl_usuario_comercio set estado='ACTIVE' where id=v_source.id;
    insert into rsuelvo.tbl_logs_auditoria(id_comercio,id_usuario,accion,tabla,registro_id)
      values(p_id_comercio,v_actor_id,'vinculo_reactivado','tbl_usuario_comercio',v_source.id);
    perform rsuelvo_private.fn_emit_security_event('MEMBERSHIP.REACTIVATED',v_actor_type,v_actor_id,p_id_comercio,
      'fn_gestionar_vinculo',null,jsonb_build_object('membership_id',v_source.id,'target_user_id',p_id_usuario));
    return jsonb_build_object('ok',true,'reactivado',true);
  end;
  return jsonb_build_object('ok',true,'reactivado',false);
end;$fn$;
alter function rsuelvo.fn_gestionar_vinculo(uuid,uuid,smallint,uuid,text,smallint,uuid) owner to postgres;
revoke all on function rsuelvo.fn_gestionar_vinculo(uuid,uuid,smallint,uuid,text,smallint,uuid) from public,anon;
grant execute on function rsuelvo.fn_gestionar_vinculo(uuid,uuid,smallint,uuid,text,smallint,uuid) to authenticated,service_role;

insert into rsuelvo.tbl_logs_auditoria(accion,tabla,datos_nuevos)
values('security_events_purge_configured','tbl_security_events',jsonb_build_object(
  'purge_schedule','*/5 * * * *','watchdog_schedule','*/15 * * * *',
  'configured_at',clock_timestamp(),'retention_policy_version','IAM10-V1'));

select cron.schedule('rsuelvo-security-events-purge','*/5 * * * *',
  'select rsuelvo_private.fn_security_events_purge(500)');
select cron.schedule('rsuelvo-security-events-purge-watchdog','*/15 * * * *',
  'select rsuelvo_private.fn_security_events_purge_watchdog()');

commit;
