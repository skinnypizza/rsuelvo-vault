-- ============================================================
-- RSUELVO v2 :: 16. FIX search_path — fn_resolver_variante_tenant_sku
-- ============================================================
--
-- Auditoría independiente (ver 00-Index/ESTADO-EJECUCION.md, entradas de
-- seed y smoke tests 4/6/7): la función trigger `fn_resolver_variante_tenant_sku`
-- referencia `tbl_productos`, `tbl_comercios` y `tbl_variantes` SIN calificar el
-- schema, y no declara `SET search_path`. Al dispararse desde un rol cuyo
-- search_path de sesión no incluye `rsuelvo` (p.ej. service_role en flujos n8n),
-- falla con "relation does not exist" salvo que la sesión fije `SET search_path`
-- manualmente. Esto es el mismo defecto de search_path corregido en A15 para las
-- funciones SECURITY DEFINER.
--
-- Fix: mismo cuerpo y firma; se AÑADE `SECURITY INVOKER` (era el default, se
-- hace explícito para conservar semántica) y `SET search_path = rsuelvo, public`,
-- y se califican explícitamente `rsuelvo.tbl_productos`, `rsuelvo.tbl_comercios`
-- y `rsuelvo.tbl_variantes`. No se recrea ni altera el trigger
-- (`trg_resolver_variante_tenant_sku`); no se tocan grants existentes
-- (CREATE OR REPLACE los conserva). No afecta H-2 (constraint
-- uq_reserva_activa_variante_sucursal = (id_sucursal,id_variante)).
--
-- IDs: F0/F1 · SKU §4.1 · WF-10 (TSC1otHnDCr0ADiW) · HU-041/H-01.

set search_path = rsuelvo, public;

-- (v2/A1) Resuelve tenant de la variante, genera SKU de 6 caracteres
-- [3 tienda][3 producto] en base36 si viene nulo, valida formato y duplicados.
create or replace function rsuelvo.fn_resolver_variante_tenant_sku()
returns trigger
language plpgsql
security invoker
set search_path = rsuelvo, public
as $$
declare
  v_comercio uuid;
  v_codigo char(3);
  v_max int;
  v_sufijo text;
  v_sku text;
begin
  -- 1) Resolver id_comercio desde el producto (siempre).
  if new.id_producto is not null then
    select p.id_comercio into v_comercio
    from rsuelvo.tbl_productos p
    where p.id_producto=new.id_producto;
  end if;

  if v_comercio is null then
    raise exception 'Producto inexistente';
  end if;

  new.id_comercio := v_comercio;

  select codigo_tienda into v_codigo
  from rsuelvo.tbl_comercios
  where id_comercio=v_comercio;

  if v_codigo is null then
    raise exception 'El comercio % no tiene codigo_tienda asignado',v_comercio;
  end if;

  -- 2) Generar SKU si no viene (o venir vacío).
  if coalesce(new.sku,'')='' then
    -- serializar por comercio: bloquea la fila del comercio.
    select 1 into v_max from rsuelvo.tbl_comercios
    where id_comercio=v_comercio for update;

    select coalesce(max(
      ('x'||substr(v.sku,4,3))::bit(12)::int
    ),0) into v_max
    from rsuelvo.tbl_variantes v
    where v.id_comercio=v_comercio
      and v.sku ~ '^[A-Z0-9]{6}$'
      and substr(v.sku,1,3)=v_codigo::text;

    v_max := v_max+1;
    if v_max > 46655 then
      raise exception 'Se agotaron los SKUs disponibles para la tienda %',v_codigo;
    end if;

    declare
      n int := v_max;
      chars text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      out text := '';
    begin
      while n>0 loop
        out := substr(chars,(n%36)+1,1)||out;
        n := n/36;
      end loop;
      v_sufijo := lpad(coalesce(nullif(out,''),'0'),3,'0');
    end;

    new.sku := upper(v_codigo::text||v_sufijo);
  else
    new.sku := upper(new.sku);
  end if;

  -- 3) Validar formato 6 caracteres tienda+producto.
  if new.sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido %. Formato requerido: 6 caracteres [3 tienda][3 producto], ej. FERA01',new.sku;
  end if;

  if substr(new.sku,1,3) <> v_codigo::text then
    raise exception 'El prefijo del SKU (%) debe ser el código de la tienda (%)',substr(new.sku,1,3),v_codigo;
  end if;

  -- 4) Duplicado amigable (el UNIQUE físico es la garantía real).
  if exists (
    select 1 from rsuelvo.tbl_variantes v
    where v.id_comercio=v_comercio
      and v.sku=new.sku
      and v.id_variante<>coalesce(new.id_variante,'00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    raise exception 'SKU duplicado dentro del comercio: %',new.sku;
  end if;

  return new;
end;
$$;
