-- 92_consentimiento_legal.sql
-- IAM-7 backend. Implementa D-IAM-CONSENTIMIENTO.md rev3.
-- Seeds = BORRADOR PENDIENTE VALIDACION LEGAL BOLIVIA.

-- ── 1. documentos ──
create table if not exists rsuelvo.tbl_documentos_legales (
  id_documento uuid primary key default gen_random_uuid(),
  tipo text not null,
  version text not null,
  titulo text not null,
  url_texto text not null,
  content_sha256 text not null,
  obligatorio boolean not null,
  vigente_desde timestamptz not null default now(),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint doc_tipo_chk check (tipo in ('TERMINOS','PRIVACIDAD','TRATAMIENTO_DATOS')),
  constraint doc_sha_chk check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint doc_version_chk check (version <> '')
);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'doc_tipo_version_uniq') then
    alter table rsuelvo.tbl_documentos_legales
      add constraint doc_tipo_version_uniq unique (tipo, version);
  end if;
end $$;
create unique index if not exists doc_activo_unico
  on rsuelvo.tbl_documentos_legales (tipo) where activo = true;
alter table rsuelvo.tbl_documentos_legales enable row level security;
grant select on rsuelvo.tbl_documentos_legales to anon, authenticated, service_role;

-- lectura: solo publicados (activos). Sin policies de escritura = deny.
drop policy if exists documentos_public_read on rsuelvo.tbl_documentos_legales;
create policy documentos_public_read on rsuelvo.tbl_documentos_legales
  for select to anon, authenticated using (activo = true);

-- ── 2. aceptaciones ──
create table if not exists rsuelvo.tbl_aceptaciones (
  id_aceptacion uuid primary key default gen_random_uuid(),
  id_usuario uuid not null references rsuelvo.tbl_usuarios(id_usuario) on delete cascade,
  id_documento uuid not null references rsuelvo.tbl_documentos_legales(id_documento) on delete restrict,
  accepted_at timestamptz not null default now(),
  canal text not null,
  created_at timestamptz not null default now(),
  constraint acept_canal_chk check (canal in ('APP','WEB'))
);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'acept_usuario_doc_uniq') then
    alter table rsuelvo.tbl_aceptaciones
      add constraint acept_usuario_doc_uniq unique (id_usuario, id_documento);
  end if;
end $$;
-- deny-by-default total: sin policies -> solo service_role + SECURITY DEFINER
alter table rsuelvo.tbl_aceptaciones enable row level security;
grant all on rsuelvo.tbl_aceptaciones to service_role;

-- ── 3. inmutabilidad verificable ──
create or replace function rsuelvo.fn_doc_inmutable()
returns trigger
language plpgsql security definer
set search_path to 'rsuelvo', 'public'
as $fn$
begin
  if exists (select 1 from tbl_aceptaciones where id_documento = old.id_documento) then
    if (new.tipo, new.version, new.titulo, new.url_texto, new.content_sha256,
        new.obligatorio, new.vigente_desde)
       is distinct from
       (old.tipo, old.version, old.titulo, old.url_texto, old.content_sha256,
        old.obligatorio, old.vigente_desde) then
      raise exception 'documento con aceptaciones es inmutable (solo activo)';
    end if;
  end if;
  return new;
end;
$fn$;
drop trigger if exists trg_doc_inmutable on rsuelvo.tbl_documentos_legales;
create trigger trg_doc_inmutable
  before update on rsuelvo.tbl_documentos_legales
  for each row execute function rsuelvo.fn_doc_inmutable();

-- ── 4. pendientes (fuente server-side) ──
create or replace function rsuelvo.fn_documentos_pendientes()
returns jsonb
language plpgsql stable security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
begin
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  return jsonb_build_object('ok', true, 'documentos', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_documento', d.id_documento, 'tipo', d.tipo, 'version', d.version,
      'titulo', d.titulo, 'url_texto', d.url_texto,
      'content_sha256', d.content_sha256, 'obligatorio', d.obligatorio,
      'vigente_desde', d.vigente_desde
    ) order by d.tipo)
    from tbl_documentos_legales d
    where d.activo = true
      and not exists (select 1 from tbl_aceptaciones a
                      where a.id_usuario = v_usuario
                        and a.id_documento = d.id_documento)
  ), '[]'::jsonb));
end;
$fn$;
revoke execute on function rsuelvo.fn_documentos_pendientes() from public;
grant execute on function rsuelvo.fn_documentos_pendientes() to authenticated, service_role;

-- ── 5. aceptar (idempotente, todo server-side) ──
create or replace function rsuelvo.fn_aceptar_documento(p_id_documento uuid, p_canal text)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_doc record;
begin
  if p_canal not in ('APP','WEB') then
    return jsonb_build_object('ok', false, 'codigo', 'canal_invalido');
  end if;
  select id_usuario into v_usuario from tbl_usuarios
  where auth_user_id = v_auth and activo;
  if v_usuario is null then
    return jsonb_build_object('ok', false, 'codigo', 'sin_acceso');
  end if;
  select * into v_doc from tbl_documentos_legales where id_documento = p_id_documento;
  if v_doc.id_documento is null then
    return jsonb_build_object('ok', false, 'codigo', 'documento_no_existe');
  end if;
  if not v_doc.activo or v_doc.vigente_desde > now() then
    return jsonb_build_object('ok', false, 'codigo', 'documento_no_vigente');
  end if;
  -- no aceptar obsoleto habiendo version activa mas nueva del mismo tipo
  if exists (select 1 from tbl_documentos_legales
             where tipo = v_doc.tipo and activo = true
               and vigente_desde > v_doc.vigente_desde
               and id_documento <> v_doc.id_documento) then
    return jsonb_build_object('ok', false, 'codigo', 'version_obsoleta');
  end if;
  insert into tbl_aceptaciones (id_usuario, id_documento, canal)
  values (v_usuario, p_id_documento, p_canal)
  on conflict (id_usuario, id_documento) do nothing;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (null, v_usuario, 'documento_aceptado', 'tbl_aceptaciones', p_id_documento);
  return jsonb_build_object('ok', true);
end;
$fn$;
revoke execute on function rsuelvo.fn_aceptar_documento(uuid, text) from public;
grant execute on function rsuelvo.fn_aceptar_documento(uuid, text) to authenticated, service_role;

-- ── 6. seed v1 BORRADOR ──
insert into rsuelvo.tbl_documentos_legales
  (tipo, version, titulo, url_texto, content_sha256, obligatorio)
values
  ('TERMINOS', '1.0', 'Términos del servicio RSUELVO (BORRADOR — PENDIENTE VALIDACIÓN LEGAL BOLIVIA)', 'legal/terminos-1.0', '0000000000000000000000000000000000000000000000000000000000000000', true),
  ('PRIVACIDAD', '1.0', 'Política de privacidad RSUELVO (BORRADOR — PENDIENTE VALIDACIÓN LEGAL BOLIVIA)', 'legal/privacidad-1.0', '1111111111111111111111111111111111111111111111111111111111111111', true),
  ('TRATAMIENTO_DATOS', '1.0', 'Consentimiento de tratamiento de datos RSUELVO (BORRADOR — PENDIENTE VALIDACIÓN LEGAL BOLIVIA)', 'legal/tratamiento-1.0', '2222222222222222222222222222222222222222222222222222222222222222', true)
on conflict (tipo, version) do nothing;
