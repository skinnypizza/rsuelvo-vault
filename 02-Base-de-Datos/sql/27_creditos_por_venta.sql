-- Migración 27 (2026-09-02): D14 — créditos por VENTA
--   1. Enum: CONSUMO_VENTA (nuevo; CONSUMO_VERIFICACION se conserva para V2 automático)
--   2. tbl_movimientos_creditos.usuario_id: atribución del cajero (JWT) o NULL (n8n)
--   3. CHECK de costo_creditos relajado a >= 0 (servicios gratuitos: VERIFICACION_MANUAL)
--   4. Servicio VERIFICACION_MANUAL (costo 0) — verificación de cajero no consume al iniciar
--   5. fn_consumir_credito_venta: consume 1 crédito por venta (D14) — SD-1: la venta NUNCA
--      se bloquea; el saldo puede quedar negativo (cobro = facturación, no bloqueo)
--   6. fn_confirmar_pago: consume el crédito en la MISMA transacción del PAGO_CONFIRMADO
-- Nota SD-7 (abierta): D14 aprobado como 1 crédito por confirmación; si pricing futuro
--   requiere por-unidad, cambiar el literal 1 por v_res.cantidad.

ALTER TYPE rsuelvo.tipo_movimiento_credito ADD VALUE IF NOT EXISTS 'CONSUMO_VENTA' AFTER 'CONSUMO_VERIFICACION';

ALTER TABLE rsuelvo.tbl_movimientos_creditos
  ADD COLUMN IF NOT EXISTS usuario_id uuid REFERENCES rsuelvo.tbl_usuarios(id_usuario);

COMMENT ON COLUMN rsuelvo.tbl_movimientos_creditos.usuario_id IS
  'Usuario que originó el movimiento (cajero vía JWT, D13/D14); NULL en procesos automáticos (n8n/pg_cron).';

ALTER TABLE rsuelvo.tbl_servicios_creditos
  DROP CONSTRAINT IF EXISTS tbl_servicios_creditos_costo_creditos_check;
ALTER TABLE rsuelvo.tbl_servicios_creditos
  ADD CONSTRAINT tbl_servicios_creditos_costo_creditos_check CHECK (costo_creditos >= 0);

INSERT INTO rsuelvo.tbl_servicios_creditos (codigo, nombre, descripcion, costo_creditos, activo)
SELECT 'VERIFICACION_MANUAL', 'Verificación manual (cajero)', 'Verificación de comprobante por el cajero en la app (D13). No consume créditos al iniciar; el consumo ocurre por venta confirmada (D14).', 0, true
WHERE NOT EXISTS (SELECT 1 FROM rsuelvo.tbl_servicios_creditos WHERE codigo='VERIFICACION_MANUAL');

CREATE OR REPLACE FUNCTION rsuelvo.fn_consumir_credito_venta(p_id_comercio uuid, p_id_pedido uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v_cuenta tbl_cuentas_creditos%rowtype;
  v_anterior bigint;
  v_nuevo bigint;
BEGIN
  SELECT * INTO v_cuenta
  FROM tbl_cuentas_creditos
  WHERE id_comercio=p_id_comercio
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO tbl_cuentas_creditos(id_comercio, saldo_actual)
    VALUES (p_id_comercio, 0)
    RETURNING * INTO v_cuenta;
  END IF;

  v_anterior := v_cuenta.saldo_actual;
  -- D14/SD-1: la venta NUNCA se bloquea; el saldo puede quedar negativo (cobro aparte)
  v_nuevo := v_anterior - 1;

  UPDATE tbl_cuentas_creditos
  SET saldo_actual=v_nuevo
  WHERE id_cuenta_creditos=v_cuenta.id_cuenta_creditos;

  INSERT INTO tbl_movimientos_creditos(
    id_comercio, id_cuenta_creditos, tipo, cantidad,
    saldo_anterior, saldo_posterior, concepto, referencia_tipo, referencia_id, usuario_id
  )
  VALUES (
    p_id_comercio, v_cuenta.id_cuenta_creditos,
    'CONSUMO_VENTA', -1,
    v_anterior, v_nuevo,
    'Consumo de crédito por venta confirmada (D14)',
    'PEDIDO', p_id_pedido,
    fn_current_usuario_id()
  );

  RETURN 1;
END;
$function$;

-- fn_confirmar_pago (migración 25) + consumo D14 al final (antes del RETURN):
--   PERFORM rsuelvo.fn_consumir_credito_venta(v_res.id_comercio, v_ver.id_pedido);
-- Ver cuerpo completo en 06_functions.sql / monolito.
