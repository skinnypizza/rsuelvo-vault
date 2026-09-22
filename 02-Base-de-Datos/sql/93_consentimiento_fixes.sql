-- 93_consentimiento_fixes.sql
-- IAM-7 parche revision ChatGPT. NO reescribe mig 92.
-- 1) pendientes solo vigentes. 2) obsoleta antes que vigencia.
-- 3) auditoria solo en insercion real + codigo ya_aceptado.

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
      and d.vigente_desde <= now()
      and not exists (select 1 from tbl_aceptaciones a
                      where a.id_usuario = v_usuario
                        and a.id_documento = d.id_documento)
  ), '[]'::jsonb));
end;
$fn$;

create or replace function rsuelvo.fn_aceptar_documento(p_id_documento uuid, p_canal text)
returns jsonb
language plpgsql volatile security definer
set search_path to 'rsuelvo', 'public'
as $fn$
declare
  v_auth uuid := (auth.jwt() ->> 'sub')::uuid;
  v_usuario uuid;
  v_doc record;
  v_id_aceptacion uuid;
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
  -- supersedido por otra version activa+vigente del mismo tipo
  if exists (select 1 from tbl_documentos_legales
             where tipo = v_doc.tipo and activo = true and vigente_desde <= now()
               and id_documento <> v_doc.id_documento) then
    return jsonb_build_object('ok', false, 'codigo', 'version_obsoleta');
  end if;
  if not v_doc.activo or v_doc.vigente_desde > now() then
    return jsonb_build_object('ok', false, 'codigo', 'documento_no_vigente');
  end if;
  insert into tbl_aceptaciones (id_usuario, id_documento, canal)
  values (v_usuario, p_id_documento, p_canal)
  on conflict (id_usuario, id_documento) do nothing
  returning id_aceptacion into v_id_aceptacion;
  if v_id_aceptacion is null then
    return jsonb_build_object('ok', true, 'codigo', 'ya_aceptado');
  end if;
  insert into tbl_logs_auditoria (id_comercio, id_usuario, accion, tabla, registro_id)
  values (null, v_usuario, 'documento_aceptado', 'tbl_aceptaciones', v_id_aceptacion);
  return jsonb_build_object('ok', true, 'codigo', 'aceptado');
end;
$fn$;
