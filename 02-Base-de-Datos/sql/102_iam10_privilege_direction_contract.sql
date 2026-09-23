-- IAM-10 B1 corrective migration, aligned to Security Events contract REV3.2.
-- Migration 101 remains immutable; existing V1 event rows are revalidated.
begin;

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
      then v_keys := array['direction','from_role','new_membership_id','previous_membership_id','target_user_id','to_role'];
           v_uuid_keys:=array['new_membership_id','previous_membership_id','target_user_id'];
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
    if p_metadata->>'direction' not in ('ELEVATED','REDUCED','MIXED')
      or p_metadata->>'from_role'=p_metadata->>'to_role'
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
  if v_from <@ v_to and v_to <@ v_from then
    if p_from_role=p_to_role then raise exception 'no_effective_privilege_change'; end if;
    raise exception 'equivalent_role_codes_require_contract_revision';
  elsif v_from <@ v_to then return 'ELEVATED';
  elsif v_to <@ v_from then return 'REDUCED';
  else return 'MIXED'; end if;
end;
$fn$;
alter function rsuelvo_private.fn_security_event_privilege_direction(text,text) owner to postgres;
revoke all on function rsuelvo_private.fn_security_event_privilege_direction(text,text) from public,anon,authenticated,service_role;

alter table rsuelvo_private.tbl_security_events
  drop constraint security_events_metadata_chk;
alter table rsuelvo_private.tbl_security_events
  add constraint security_events_metadata_chk check (
    jsonb_typeof(metadata)='object' and octet_length(metadata::text)<=2048
    and rsuelvo_private.fn_security_event_metadata_valid(event_type,metadata));

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
      p_id_comercio,'fn_gestionar_vinculo',null,jsonb_build_object('previous_membership_id',v_source.id,
        'new_membership_id',v_target.id,'target_user_id',p_id_usuario,'from_role',v_role_old,
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

commit;
