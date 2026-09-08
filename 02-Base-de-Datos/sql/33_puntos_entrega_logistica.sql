-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 33 (2026-09-07)
-- PUNTOS DE ENTREGA + TRANSPORTADORAS (OBS-003)
-- ============================================================
-- Decisiones cerradas 2026-09-07: (1) el repartidor lleva los productos a los
-- puntos; (2) saltos de estado permitidos; (3) la tienda despacha a la
-- transportadora y registra numero_guia al entregar; (4) wireframes graduales.
-- El envío es POR COBRAR: RSUELVO no cobra ni muestra costo de envío.

-- ============================================================
-- MIGRACIÓN 33 (2026-09-07): PUNTOS DE ENTREGA + TRANSPORTADORAS (OBS-003)
-- Envío POR COBRAR: RSUELVO no cobra ni muestra costo de envío.
-- Decisiones: repartidor lleva productos a los puntos; saltos de estado;
-- la tienda despacha a la transportadora y registra numero_guia al entregar.
-- ============================================================

create table if not exists tbl_transportadoras (
  id_transportadora uuid primary key default gen_random_uuid(),
  nombre text not null,
  ciudades text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists tbl_puntos_entrega (
  id_punto_entrega uuid primary key default gen_random_uuid(),
  id_sucursal uuid not null references tbl_sucursales(id_sucursal),
  tipo text not null check (tipo in ('RETIRO_EN_TIENDA','PUNTO_LOCAL','ENVIO_TRANSPORTE')),
  nombre text not null,
  ciudad text not null,
  direccion text not null,
  referencia text,
  id_transportadora uuid references tbl_transportadoras(id_transportadora),
  activo boolean not null default true,
  orden integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chk_punto_transportadora check (
    (tipo = 'ENVIO_TRANSPORTE' and id_transportadora is not null)
    or (tipo <> 'ENVIO_TRANSPORTE' and id_transportadora is null)
  )
);
create index if not exists idx_puntos_entrega_sucursal on tbl_puntos_entrega(id_sucursal) where activo;

-- tbl_envios enlazado al punto elegido (denormalización direccion/referencia se conserva para la hoja de ruta)
alter table tbl_envios add column if not exists id_punto_entrega uuid references tbl_puntos_entrega(id_punto_entrega);

alter table tbl_transportadoras enable row level security;
alter table tbl_puntos_entrega enable row level security;

drop policy if exists transportadoras_read on tbl_transportadoras;
create policy transportadoras_read on tbl_transportadoras
  for select to authenticated using (true);

drop policy if exists puntos_entrega_all on tbl_puntos_entrega;
create policy puntos_entrega_all on tbl_puntos_entrega
  for all to authenticated
  using (exists (
    select 1 from tbl_sucursales s
    where s.id_sucursal = tbl_puntos_entrega.id_sucursal
      and fn_tiene_acceso_sucursal(s.id_comercio, s.id_sucursal)
  ))
  with check (exists (
    select 1 from tbl_sucursales s
    where s.id_sucursal = tbl_puntos_entrega.id_sucursal
      and fn_tiene_acceso_sucursal(s.id_comercio, s.id_sucursal)
  ));

drop trigger if exists trg_tbl_transportadoras_updated_at on tbl_transportadoras;
create trigger trg_tbl_transportadoras_updated_at before update on tbl_transportadoras
  for each row execute function fn_set_updated_at();
drop trigger if exists trg_audit_tbl_transportadoras on tbl_transportadoras;
create trigger trg_audit_tbl_transportadoras after insert or delete or update on tbl_transportadoras
  for each row execute function fn_auditar_cambio();
drop trigger if exists trg_tbl_puntos_entrega_updated_at on tbl_puntos_entrega;
create trigger trg_tbl_puntos_entrega_updated_at before update on tbl_puntos_entrega
  for each row execute function fn_set_updated_at();
drop trigger if exists trg_audit_tbl_puntos_entrega on tbl_puntos_entrega;
create trigger trg_audit_tbl_puntos_entrega after insert or delete or update on tbl_puntos_entrega
  for each row execute function fn_auditar_cambio();

grant select on tbl_transportadoras to authenticated;
grant select on tbl_puntos_entrega to authenticated;
grant all on tbl_transportadoras to service_role;
grant all on tbl_puntos_entrega to service_role;

-- Catálogo para la selección guiada del comprador (WF-25-B)
create or replace function fn_listar_puntos_entrega(p_id_sucursal uuid)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_opciones jsonb := '[]'::jsonb;
  r RECORD;
  v_n integer := 0;
begin
  for r in
    select p.*, t.nombre as transportadora
    from tbl_puntos_entrega p
    left join tbl_transportadoras t on t.id_transportadora = p.id_transportadora
    where p.id_sucursal = p_id_sucursal and p.activo
    order by p.orden, p.nombre
  loop
    v_n := v_n + 1;
    v_opciones := v_opciones || jsonb_build_object(
      'opcion', v_n,
      'id_punto_entrega', r.id_punto_entrega,
      'tipo', r.tipo,
      'nombre', r.nombre,
      'ciudad', r.ciudad,
      'direccion', r.direccion,
      'referencia', r.referencia,
      'transportadora', r.transportadora
    );
  end loop;
  return jsonb_build_object('puntos', v_opciones);
end;
$$;

-- Máquina de estados v2: saltos hacia adelante permitidos (OBS-003 decisión 2)
create or replace function fn_actualizar_estado_envio(
  p_id_envio uuid,
  p_nuevo_estado rsuelvo.estado_envio,
  p_observacion text DEFAULT NULL,
  p_latitud numeric DEFAULT NULL,
  p_longitud numeric DEFAULT NULL
)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
declare
  v_env tbl_envios%rowtype;
  v_rank_actual integer;
  v_rank_nuevo integer;
begin
  select * into v_env from tbl_envios
  where id_envio=p_id_envio for update;

  if not found then
    raise exception 'Envío inexistente';
  end if;

  v_rank_actual := case v_env.estado
    when 'PENDIENTE' then 1 when 'PREPARANDO' then 2 when 'ASIGNADO' then 3
    when 'EN_RUTA' then 4 when 'ENTREGADO' then 5 else null end;
  v_rank_nuevo := case p_nuevo_estado
    when 'PENDIENTE' then 1 when 'PREPARANDO' then 2 when 'ASIGNADO' then 3
    when 'EN_RUTA' then 4 when 'ENTREGADO' then 5 else null end;

  if p_nuevo_estado = 'CANCELADO' then
    if v_env.estado in ('ENTREGADO','CANCELADO') then
      raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
    end if;
  elsif p_nuevo_estado = 'NO_ENTREGADO' then
    if v_env.estado not in ('ASIGNADO','EN_RUTA') then
      raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
    end if;
    if coalesce(p_observacion,'') = '' then
      raise exception 'NO_ENTREGADO requiere observación';
    end if;
  elsif p_nuevo_estado = 'EN_RUTA' and v_env.estado = 'NO_ENTREGADO' then
    null; -- reintento tras no-entrega (patrón previo preservado)
  elsif v_rank_actual is null or v_rank_nuevo is null
     or v_rank_nuevo <= v_rank_actual then
    raise exception 'Transición inválida: % -> %', v_env.estado, p_nuevo_estado;
  end if;

  update tbl_envios
  set estado=p_nuevo_estado,
      updated_at=now(),
      id_repartidor=case
        when p_nuevo_estado='EN_RUTA' and v_env.id_repartidor is null
        then fn_current_usuario_id()
        else v_env.id_repartidor end
  where id_envio=p_id_envio;

  insert into tbl_env_seguimiento_estados(
    id_envio,estado,observacion,latitud,longitud,usuario_id
  )
  values(
    p_id_envio,p_nuevo_estado,p_observacion,p_latitud,p_longitud,
    fn_current_usuario_id()
  );

  return jsonb_build_object(
    'resultado','ESTADO_ACTUALIZADO',
    'id_envio',p_id_envio,
    'estado',p_nuevo_estado
  );
end;
$$;

-- Registro de entrega v2: selección guiada por punto (elimina dirección libre)
create or replace function fn_registrar_entrega(p_id_pedido uuid, p_datos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = rsuelvo, public
as $$
DECLARE
  v_pedido tbl_pedidos%rowtype;
  v_punto tbl_puntos_entrega%rowtype;
  v_nombre text;
  v_telefono text;
  v_id_envio uuid;
BEGIN
  SELECT * INTO v_pedido
  FROM tbl_pedidos
  WHERE id_pedido=p_id_pedido
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido inexistente';
  END IF;

  IF v_pedido.estado <> 'PAGADO' THEN
    RAISE EXCEPTION 'El pedido % no está PAGADO (estado: %)', p_id_pedido, v_pedido.estado;
  END IF;

  IF EXISTS (SELECT 1 FROM tbl_envios WHERE id_pedido=p_id_pedido) THEN
    RAISE EXCEPTION 'El pedido ya tiene envío registrado';
  END IF;

  v_telefono := NULLIF(trim(COALESCE(p_datos->>'telefono','')), '');
  IF v_telefono IS NULL THEN
    RAISE EXCEPTION 'Faltan datos de entrega obligatorios (telefono)';
  END IF;

  SELECT * INTO v_punto
  FROM tbl_puntos_entrega
  WHERE id_punto_entrega = (p_datos->>'id_punto_entrega')::uuid
    AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Punto de entrega inexistente o inactivo';
  END IF;
  IF v_punto.id_sucursal <> v_pedido.id_sucursal THEN
    RAISE EXCEPTION 'El punto no pertenece a la sucursal del pedido';
  END IF;

  -- El nombre actualiza el perfil del cliente (tbl_clientes.nombre)
  v_nombre := NULLIF(trim(COALESCE(p_datos->>'nombre','')), '');
  IF v_nombre IS NOT NULL THEN
    UPDATE tbl_clientes SET nombre=v_nombre WHERE id_cliente=v_pedido.id_cliente;
  END IF;

  -- Denormalización para la hoja de ruta del repartidor
  v_id_envio := fn_crear_envio(
    p_id_pedido,
    v_punto.nombre || ' - ' || v_punto.ciudad || '. ' || v_punto.direccion,
    v_punto.referencia,
    v_telefono
  );
  UPDATE tbl_envios SET id_punto_entrega=v_punto.id_punto_entrega WHERE id_envio=v_id_envio;

  RETURN jsonb_build_object(
    'resultado','ENTREGA_REGISTRADA',
    'id_envio',v_id_envio,
    'id_pedido',p_id_pedido,
    'id_punto_entrega',v_punto.id_punto_entrega,
    'tipo_punto',v_punto.tipo,
    'estado_envio','PENDIENTE'
  );
END;
$$;

-- Comentarios (Regla 10 / documentación)
comment on table rsuelvo.tbl_puntos_entrega is 'Catálogo de puntos de entrega por sucursal (OBS-003): retiro en tienda, punto local y envío por transportadora. Sin costo: la transportadora cobra aparte (contra entrega).';
comment on table rsuelvo.tbl_transportadoras is 'Empresas de transporte externas (OBS-003). Envío por cobrar: RSUELVO no cobra ni muestra costo de envío.';
comment on function rsuelvo.fn_listar_puntos_entrega(uuid) is 'Catálogo activo y ordenado de puntos de entrega de una sucursal para la selección guiada del comprador (WF-25-B, OBS-003).';
