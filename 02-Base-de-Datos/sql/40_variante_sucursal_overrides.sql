-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 40 (2026-09-10)
-- CATÁLOGO POR SUCURSAL — overrides de variante + permisos CAJERO
-- ============================================================
-- Decisión de negocio (dueño): nombre/precio/activo de una variante son
-- EDITABLES POR SUCURSAL (override nullable: NULL = hereda el global).
-- Productos: editables por ADMIN y CAJERO del mismo comercio.
-- La cadena de venta usa el precio EFECTIVO de la sucursal y lo congela
-- en tbl_pedido_detalles (ventas pasadas intactas).
-- Validado: override 75 en FER sobre global 60 → pedido total/precio_unitario = 75.

-- == TABLAS ==
CREATE TABLE IF NOT EXISTS rsuelvo.tbl_variante_sucursal (
  id_variante uuid NOT NULL REFERENCES rsuelvo.tbl_variantes(id_variante) ON DELETE CASCADE,
  id_sucursal uuid NOT NULL REFERENCES rsuelvo.tbl_sucursales(id_sucursal) ON DELETE CASCADE,
  nombre text,
  precio numeric(14,2),
  activo boolean,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tbl_variante_sucursal_pkey PRIMARY KEY (id_variante, id_sucursal),
  CONSTRAINT chk_vs_precio CHECK (precio IS NULL OR precio > 0)
);
CREATE INDEX IF NOT EXISTS idx_variante_sucursal_suc ON rsuelvo.tbl_variante_sucursal(id_sucursal);
ALTER TABLE rsuelvo.tbl_variante_sucursal ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_tbl_variante_sucursal_updated_at BEFORE UPDATE ON rsuelvo.tbl_variante_sucursal
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_tbl_variante_sucursal AFTER INSERT OR DELETE OR UPDATE ON rsuelvo.tbl_variante_sucursal
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();
GRANT ALL ON rsuelvo.tbl_variante_sucursal TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON rsuelvo.tbl_variante_sucursal TO authenticated;

-- == HELPERS Y FUNCIONES ==
CREATE OR REPLACE FUNCTION rsuelvo.fn_es_admin_o_cajero_comercio(p_id_comercio uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select fn_es_service_role() or fn_es_superadmin() or exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid() and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and r.codigo in ('ROLE_TENANT_ADMIN','ROLE_TENANT_CASHIER')
  );
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_puede_gestionar_catalogo(p_id_comercio uuid, p_id_sucursal uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select fn_es_service_role() or fn_es_superadmin() or exists (
    select 1 from tbl_usuario_comercio uc
    join tbl_usuarios u on u.id_usuario=uc.id_usuario
    join tbl_roles r on r.id_rol=uc.id_rol
    where u.auth_user_id=auth.uid() and u.activo and uc.activo
      and uc.id_comercio=p_id_comercio
      and (r.codigo='ROLE_TENANT_ADMIN' or (r.codigo='ROLE_TENANT_CASHIER' and uc.id_sucursal=p_id_sucursal))
  );
$function$;

CREATE OR REPLACE FUNCTION rsuelvo.fn_variante_efectiva(p_id_variante uuid, p_id_sucursal uuid)
RETURNS TABLE(nombre text, precio numeric, activo boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
  select coalesce(vs.nombre, v.nombre), coalesce(vs.precio, v.precio), coalesce(vs.activo, v.activo)
  from tbl_variantes v
  left join tbl_variante_sucursal vs on vs.id_variante=v.id_variante and vs.id_sucursal=p_id_sucursal
  where v.id_variante=p_id_variante;
$function$;

-- fn_resolver_variante_por_sku v2 (con sucursal; se elimina la firma vieja de 2 args)
CREATE OR REPLACE FUNCTION rsuelvo.fn_resolver_variante_por_sku(p_id_comercio uuid, p_sku text, p_id_sucursal uuid DEFAULT NULL)
RETURNS TABLE(id_variante uuid, nombre text, precio numeric, id_producto uuid)
LANGUAGE plpgsql STABLE SET search_path TO 'rsuelvo', 'pg_catalog'
AS $function$
begin
  if p_sku is null or p_sku !~ '^[A-Z0-9]{6}$' then
    raise exception 'SKU inválido. Formato requerido: exactamente 6 caracteres [A-Z0-9]' using errcode = '22023';
  end if;
  return query
  select v.id_variante, e.nombre, e.precio, v.id_producto
  from tbl_variantes v
  cross join lateral fn_variante_efectiva(v.id_variante, p_id_sucursal) e
  where v.id_comercio=p_id_comercio and v.sku=p_sku and e.activo;
end;
$function$;
DROP FUNCTION IF EXISTS rsuelvo.fn_resolver_variante_por_sku(uuid, text);

-- Listado por sucursal (efectivo + override flag + stock)
CREATE OR REPLACE FUNCTION rsuelvo.fn_listar_variantes_sucursal(p_id_sucursal uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_comercio uuid;
  v_out jsonb;
BEGIN
  SELECT s.id_comercio INTO v_comercio FROM tbl_sucursales s WHERE s.id_sucursal=p_id_sucursal;
  IF v_comercio IS NULL THEN RAISE EXCEPTION 'Sucursal inexistente'; END IF;
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'sku'),'[]'::jsonb) INTO v_out FROM (
    SELECT jsonb_build_object(
      'id_variante',v.id_variante,'sku',v.sku,'id_producto',v.id_producto,
      'nombre_global',v.nombre,'precio_global',v.precio,'activo_global',v.activo,
      'nombre',e.nombre,'precio',e.precio,'activo',e.activo,
      'tiene_override',(vs.id_variante IS NOT NULL),
      'stock_actual',coalesce(i.stock_actual,0),'stock_reservado',coalesce(i.stock_reservado,0)
    ) AS x
    FROM tbl_variantes v
    CROSS JOIN LATERAL fn_variante_efectiva(v.id_variante,p_id_sucursal) e
    LEFT JOIN tbl_variante_sucursal vs ON vs.id_variante=v.id_variante AND vs.id_sucursal=p_id_sucursal
    LEFT JOIN tbl_inventario i ON i.id_variante=v.id_variante AND i.id_sucursal=p_id_sucursal
    WHERE v.id_comercio=v_comercio
  ) t;
  RETURN jsonb_build_object('variantes',v_out);
END;
$function$;

-- == RLS Y POLICIES ==
DROP POLICY IF EXISTS variante_sucursal_select ON rsuelvo.tbl_variante_sucursal;
CREATE POLICY variante_sucursal_select ON rsuelvo.tbl_variante_sucursal FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s WHERE s.id_sucursal=tbl_variante_sucursal.id_sucursal AND rsuelvo.fn_tiene_acceso_comercio(s.id_comercio)));
DROP POLICY IF EXISTS variante_sucursal_manage ON rsuelvo.tbl_variante_sucursal;
CREATE POLICY variante_sucursal_manage ON rsuelvo.tbl_variante_sucursal FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s WHERE s.id_sucursal=tbl_variante_sucursal.id_sucursal AND rsuelvo.fn_puede_gestionar_catalogo(s.id_comercio, s.id_sucursal)))
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_sucursales s WHERE s.id_sucursal=tbl_variante_sucursal.id_sucursal AND rsuelvo.fn_puede_gestionar_catalogo(s.id_comercio, s.id_sucursal)));
DROP POLICY IF EXISTS products_manage ON rsuelvo.tbl_productos;
CREATE POLICY products_manage ON rsuelvo.tbl_productos FOR ALL TO authenticated
  USING (rsuelvo.fn_es_admin_o_cajero_comercio(id_comercio))
  WITH CHECK (rsuelvo.fn_es_admin_o_cajero_comercio(id_comercio));

-- NOTA: los cuerpos completos actualizados de fn_crear_pedido_desde_reserva (usa
-- fn_variante_efectiva para congelar el precio de la sucursal) y
-- fn_notificar_siguiente_lista_espera (devuelve nombre/precio efectivos +
-- tiempo_aceptacion_minutos) están aplicados en cloud y espejados en
-- 06_functions.sql / _monolito_…_v2.sql.
