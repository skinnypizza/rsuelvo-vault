-- ============================================================
-- RSUELVO v2 :: 17. HARDENING search_path — funciones restantes
-- ============================================================
--
-- Cierra el remanente de hardening de search_path tras la migración 16:
-- las funciones trigger `fn_validar_asignacion_usuario_comercio` y
-- `fn_validar_consistencia_tenant`, y la guarda `fn_assert_service_role`,
-- referencian objetos del esquema `rsuelvo` (tablas, tipo enum y función)
-- sin calificar y sin declarar `SET search_path`. Al ejecutarse bajo un rol
-- cuya sesión no fija `rsuelvo` en search_path (p.ej. service_role en n8n),
-- dependen del search_path de sesión y pueden fallar con "relation does not
-- exist". Se endurecen igual que la migración 16:
--   * se AÑADE `SECURITY INVOKER` (era el default; se hace explícito para
--     conservar semántica),
--   * se AÑADE `SET search_path = rsuelvo, public`,
--   * se califican explícitamente los objetos de esquema de usuario.
--
-- Fuera de alcance (sin referencias a esquema de usuario): `fn_set_updated_at`
-- y `fn_es_service_role`. No se recrean ni alteran triggers; CREATE OR REPLACE
-- conserva grants y triggers existentes. No afecta H-2 ni n8n.
--
-- IDs: F0 · Reglas de Oro 2/6 · WF-00/01/04 · HU-105/106 · fn_* canónicas.

set search_path = rsuelvo, public;

-- Validación de asignación usuario/comercio (cajero = 1 sucursal)
create or replace function rsuelvo.fn_validar_asignacion_usuario_comercio()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_codigo rsuelvo.rol_codigo;
  v_sucursal uuid;
begin
  select codigo into v_codigo from rsuelvo.tbl_roles where id_rol=new.id_rol;

  if v_codigo in ('ROLE_TENANT_CASHIER','ROLE_LOGISTICS_AGENT')
     and new.id_sucursal is null then
    raise exception 'El rol % requiere una sucursal',v_codigo;
  end if;

  if v_codigo='ROLE_TENANT_CASHIER' then
    if exists (
      select 1
      from rsuelvo.tbl_usuario_comercio uc
      join rsuelvo.tbl_roles r on r.id_rol=uc.id_rol
      where uc.id_usuario=new.id_usuario
        and uc.activo
        and r.codigo='ROLE_TENANT_CASHIER'
        and uc.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
    ) then
      raise exception 'Un cashier solo puede tener una asignación activa';
    end if;
  end if;

  return new;
end;
$$;


-- Consistencia multi-tenant
create or replace function rsuelvo.fn_validar_consistencia_tenant()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_comercio uuid;
begin
  -- Sucursal pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_lista_espera','tbl_pedidos','tbl_envios') then
    select id_comercio into v_comercio
    from rsuelvo.tbl_sucursales
    where id_sucursal=new.id_sucursal;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'La sucursal no pertenece al comercio';
    end if;
  end if;

  -- Cliente pertenece al comercio.
  if tg_table_name in ('tbl_reservas','tbl_pedidos','tbl_comprobantes_pago') then
    select id_comercio into v_comercio
    from rsuelvo.tbl_clientes
    where id_cliente=new.id_cliente;

    if v_comercio is distinct from new.id_comercio then
      raise exception 'El cliente no pertenece al comercio';
    end if;
  end if;

  return new;
end;
$$;


-- Guard: rechazar si NO es service_role
create or replace function rsuelvo.fn_assert_service_role()
returns void
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
begin
  if not rsuelvo.fn_es_service_role() then
    raise exception 'Operación reservada al backend (service_role)';
  end if;
end;
$$;
