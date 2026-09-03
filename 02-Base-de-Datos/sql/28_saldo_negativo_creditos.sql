-- Migración 28 (2026-09-02): habilita saldo negativo en créditos (D14/SD-1 aprobado)
-- La venta NUNCA se bloquea: el consumo por venta (CONSUMO_VENTA) puede dejar el
-- saldo en negativo; el cobro/recargo es facturación aparte. Se eliminan los checks
-- de no-negatividad en la cuenta y el ledger. Se conserva cantidad <> 0.

ALTER TABLE rsuelvo.tbl_cuentas_creditos
  DROP CONSTRAINT IF EXISTS tbl_cuentas_creditos_saldo_actual_check;

ALTER TABLE rsuelvo.tbl_movimientos_creditos
  DROP CONSTRAINT IF EXISTS tbl_movimientos_creditos_saldo_anterior_check;

ALTER TABLE rsuelvo.tbl_movimientos_creditos
  DROP CONSTRAINT IF EXISTS tbl_movimientos_creditos_saldo_posterior_check;
