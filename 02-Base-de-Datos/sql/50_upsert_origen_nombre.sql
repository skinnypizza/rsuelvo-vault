-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 50 (2026-09-12)
-- Nombre confirmado nunca se pisa con perfil/fallback (Q8)
-- ============================================================
-- Regla: el nombre que da el comprador (o edita el cajero, CONFIRMADO) nunca se
-- sobrescribe con perfil ni 'Cliente WhatsApp'; el perfil solo rellena vacíos.
-- `p_origen_nombre` nuevo con DEFAULT 'PERFIL' (llamadas viejas compatibles).
-- Incidente resuelto: el CREATE inicial duplicó la firma (7 vs 8 args) y los
-- llamadores seguían en la vieja → DROP de la sobrecarga vieja (precedente m34b).
-- Validado secuencial: CONFIRMADO pisa, PERFIL/fallback preservan, apellidos
-- intactos, dato de prueba restaurado.

-- == FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_upsert_cliente(p_id_comercio uuid, p_nombre text, p_telefono text DEFAULT NULL, p_telefono_whatsapp text DEFAULT NULL, p_email text DEFAULT NULL, p_apellido_paterno text DEFAULT NULL, p_apellido_materno text DEFAULT NULL, p_origen_nombre text DEFAULT 'PERFIL')
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
declare
  v_id uuid;
  v_nombre_completo text;
  v_origen text;
  v_cur_nom text;
  v_cur_pat text;
  v_cur_mat text;
  v_nuevo_nom text;
  v_nuevo_pat text;
  v_nuevo_mat text;
begin
  if not fn_tiene_acceso_comercio(p_id_comercio) then
    raise exception 'Sin acceso al comercio';
  end if;
  v_origen := upper(coalesce(nullif(trim(p_origen_nombre),''), 'PERFIL'));
  if v_origen not in ('CONFIRMADO','PERFIL') then
    raise exception 'origen de nombre inválido (CONFIRMADO|PERFIL)';
  end if;
  v_nombre_completo := nullif(trim(concat_ws(' ',
    nullif(trim(coalesce(p_nombre,'')), ''),
    nullif(trim(coalesce(p_apellido_paterno,'')), ''),
    nullif(trim(coalesce(p_apellido_materno,'')), '')
  )), '');
  if p_telefono_whatsapp is not null then
    select id_cliente into v_id
    from tbl_clientes
    where id_comercio=p_id_comercio
      and telefono_whatsapp=p_telefono_whatsapp
    for update;
    if v_id is not null then
      select nombre, apellido_paterno, apellido_materno
        into v_cur_nom, v_cur_pat, v_cur_mat
      from tbl_clientes
      where id_cliente = v_id;
      if v_origen = 'CONFIRMADO' then
        v_nuevo_nom := coalesce(v_nombre_completo, v_cur_nom);
        v_nuevo_pat := coalesce(nullif(trim(p_apellido_paterno),''), v_cur_pat);
        v_nuevo_mat := coalesce(nullif(trim(p_apellido_materno),''), v_cur_mat);
      else
        if coalesce(trim(v_cur_nom),'') in ('', 'Cliente WhatsApp') then
          v_nuevo_nom := coalesce(v_nombre_completo, v_cur_nom);
        else
          v_nuevo_nom := v_cur_nom;
        end if;
        v_nuevo_pat := coalesce(nullif(trim(v_cur_pat),''), nullif(trim(p_apellido_paterno),''), v_cur_pat);
        v_nuevo_mat := coalesce(nullif(trim(v_cur_mat),''), nullif(trim(p_apellido_materno),''), v_cur_mat);
      end if;
      update tbl_clientes
      set nombre = v_nuevo_nom,
          apellido_paterno = v_nuevo_pat,
          apellido_materno = v_nuevo_mat,
          telefono = coalesce(p_telefono, telefono),
          email = coalesce(p_email, email)
      where id_cliente = v_id;
      return v_id;
    end if;
  end if;
  insert into tbl_clientes(
    id_comercio, nombre, apellido_paterno, apellido_materno, telefono, telefono_whatsapp, email
  )
  values(
    p_id_comercio,
    coalesce(v_nombre_completo, p_nombre),
    nullif(trim(p_apellido_paterno),''),
    nullif(trim(p_apellido_materno),''),
    p_telefono, p_telefono_whatsapp, p_email
  )
  returning id_cliente into v_id;
  return v_id;
end;
$function$;

DROP FUNCTION IF EXISTS rsuelvo.fn_upsert_cliente(uuid, text, text, text, text, text, text);
