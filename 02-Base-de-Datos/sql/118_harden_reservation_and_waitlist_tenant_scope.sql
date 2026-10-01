-- Enforce tenant-coherent foreign references at the database boundary.
-- The shared n8n_runtime identity intentionally orchestrates multiple tenants,
-- so workflow routing alone must not permit mixed-tenant rows.

SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';

CREATE OR REPLACE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'rsuelvo', 'pg_temp'
AS $function$
DECLARE
  v_coherent boolean := false;
BEGIN
  IF TG_TABLE_SCHEMA <> 'rsuelvo' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Unsupported tenant reference table';
  END IF;

  CASE TG_TABLE_NAME
    WHEN 'tbl_reservas' THEN
      SELECT EXISTS (
        SELECT 1 FROM rsuelvo.tbl_sucursales s
        WHERE s.id_sucursal = NEW.id_sucursal AND s.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_variantes v
        JOIN rsuelvo.tbl_productos p ON p.id_producto = v.id_producto
        WHERE v.id_variante = NEW.id_variante AND p.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_clientes c
        WHERE c.id_cliente = NEW.id_cliente AND c.id_comercio = NEW.id_comercio
      ) AND (
        NEW.id_pedido IS NULL OR EXISTS (
          SELECT 1 FROM rsuelvo.tbl_pedidos o
          WHERE o.id_pedido = NEW.id_pedido
            AND o.id_comercio = NEW.id_comercio
            AND o.id_sucursal = NEW.id_sucursal
            AND o.id_cliente = NEW.id_cliente
            AND o.id_reserva = NEW.id_reserva
        )
      ) INTO v_coherent;

    WHEN 'tbl_lista_espera' THEN
      SELECT EXISTS (
        SELECT 1 FROM rsuelvo.tbl_sucursales s
        WHERE s.id_sucursal = NEW.id_sucursal AND s.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_variantes v
        JOIN rsuelvo.tbl_productos p ON p.id_producto = v.id_producto
        WHERE v.id_variante = NEW.id_variante AND p.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_clientes c
        WHERE c.id_cliente = NEW.id_cliente AND c.id_comercio = NEW.id_comercio
      ) AND (
        NEW.id_reserva_generada IS NULL OR EXISTS (
          SELECT 1 FROM rsuelvo.tbl_reservas r
          WHERE r.id_reserva = NEW.id_reserva_generada
            AND r.id_comercio = NEW.id_comercio
            AND r.id_sucursal = NEW.id_sucursal
            AND r.id_variante = NEW.id_variante
            AND r.id_cliente = NEW.id_cliente
        )
      ) INTO v_coherent;

    WHEN 'tbl_lista_pendiente' THEN
      SELECT EXISTS (
        SELECT 1 FROM rsuelvo.tbl_sucursales s
        WHERE s.id_sucursal = NEW.id_sucursal AND s.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_variantes v
        JOIN rsuelvo.tbl_productos p ON p.id_producto = v.id_producto
        WHERE v.id_variante = NEW.id_variante AND p.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_clientes c
        WHERE c.id_cliente = NEW.id_cliente AND c.id_comercio = NEW.id_comercio
      ) INTO v_coherent;

    WHEN 'tbl_pedidos' THEN
      SELECT EXISTS (
        SELECT 1 FROM rsuelvo.tbl_sucursales s
        WHERE s.id_sucursal = NEW.id_sucursal AND s.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_clientes c
        WHERE c.id_cliente = NEW.id_cliente AND c.id_comercio = NEW.id_comercio
      ) AND (
        NEW.id_reserva IS NULL OR EXISTS (
          SELECT 1 FROM rsuelvo.tbl_reservas r
          WHERE r.id_reserva = NEW.id_reserva
            AND r.id_comercio = NEW.id_comercio
            AND r.id_sucursal = NEW.id_sucursal
            AND r.id_cliente = NEW.id_cliente
        )
      ) INTO v_coherent;

    WHEN 'tbl_qr_cobros' THEN
      SELECT EXISTS (
        SELECT 1 FROM rsuelvo.tbl_pedidos o
        WHERE o.id_pedido = NEW.id_pedido AND o.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_metodos_pago m
        WHERE m.id_metodo_pago = NEW.id_metodo_pago AND m.id_comercio = NEW.id_comercio
      ) INTO v_coherent;

    WHEN 'tbl_pedido_detalles' THEN
      SELECT EXISTS (
        SELECT 1
        FROM rsuelvo.tbl_pedidos o
        JOIN rsuelvo.tbl_variantes v ON v.id_variante = NEW.id_variante
        JOIN rsuelvo.tbl_productos p ON p.id_producto = v.id_producto
        WHERE o.id_pedido = NEW.id_pedido AND o.id_comercio = p.id_comercio
      ) INTO v_coherent;

    WHEN 'tbl_envios' THEN
      SELECT EXISTS (
        SELECT 1 FROM rsuelvo.tbl_pedidos o
        WHERE o.id_pedido = NEW.id_pedido AND o.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_sucursales s
        WHERE s.id_sucursal = NEW.id_sucursal AND s.id_comercio = NEW.id_comercio
      ) INTO v_coherent;

    WHEN 'tbl_inventario_movimientos' THEN
      SELECT EXISTS (
        SELECT 1 FROM rsuelvo.tbl_sucursales s
        WHERE s.id_sucursal = NEW.id_sucursal AND s.id_comercio = NEW.id_comercio
      ) AND EXISTS (
        SELECT 1 FROM rsuelvo.tbl_variantes v
        JOIN rsuelvo.tbl_productos p ON p.id_producto = v.id_producto
        WHERE v.id_variante = NEW.id_variante AND p.id_comercio = NEW.id_comercio
      ) INTO v_coherent;

    ELSE
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Unsupported tenant reference table';
  END CASE;

  IF NOT coalesce(v_coherent, false) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'Related records must belong to the same commerce';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence()
  FROM PUBLIC, anon, authenticated, service_role, n8n_runtime;

DROP TRIGGER IF EXISTS trg_reservas_tenant_reference_coherence ON rsuelvo.tbl_reservas;
CREATE TRIGGER trg_reservas_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_comercio, id_sucursal, id_variante, id_cliente, id_pedido
  ON rsuelvo.tbl_reservas
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();

DROP TRIGGER IF EXISTS trg_lista_espera_tenant_reference_coherence ON rsuelvo.tbl_lista_espera;
CREATE TRIGGER trg_lista_espera_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_comercio, id_sucursal, id_variante, id_cliente, id_reserva_generada
  ON rsuelvo.tbl_lista_espera
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();

DROP TRIGGER IF EXISTS trg_lista_pendiente_tenant_reference_coherence ON rsuelvo.tbl_lista_pendiente;
CREATE TRIGGER trg_lista_pendiente_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_comercio, id_sucursal, id_variante, id_cliente
  ON rsuelvo.tbl_lista_pendiente
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();

DROP TRIGGER IF EXISTS trg_pedidos_tenant_reference_coherence ON rsuelvo.tbl_pedidos;
CREATE TRIGGER trg_pedidos_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_comercio, id_sucursal, id_cliente, id_reserva
  ON rsuelvo.tbl_pedidos
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();

DROP TRIGGER IF EXISTS trg_qr_cobros_tenant_reference_coherence ON rsuelvo.tbl_qr_cobros;
CREATE TRIGGER trg_qr_cobros_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_comercio, id_pedido, id_metodo_pago
  ON rsuelvo.tbl_qr_cobros
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();

DROP TRIGGER IF EXISTS trg_pedido_detalles_tenant_reference_coherence ON rsuelvo.tbl_pedido_detalles;
CREATE TRIGGER trg_pedido_detalles_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_pedido, id_variante
  ON rsuelvo.tbl_pedido_detalles
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();

DROP TRIGGER IF EXISTS trg_envios_tenant_reference_coherence ON rsuelvo.tbl_envios;
CREATE TRIGGER trg_envios_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_comercio, id_pedido, id_sucursal
  ON rsuelvo.tbl_envios
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();

DROP TRIGGER IF EXISTS trg_inventario_movimientos_tenant_reference_coherence ON rsuelvo.tbl_inventario_movimientos;
CREATE TRIGGER trg_inventario_movimientos_tenant_reference_coherence
  BEFORE INSERT OR UPDATE OF id_comercio, id_sucursal, id_variante
  ON rsuelvo.tbl_inventario_movimientos
  FOR EACH ROW EXECUTE FUNCTION rsuelvo_private.fn_assert_core_tenant_reference_coherence();
