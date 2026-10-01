-- This policy duplicated compras_select on the same table, role, command,
-- and predicate. Removing it does not change access; compras_select remains.
DROP POLICY IF EXISTS credit_purchases_select
  ON rsuelvo.tbl_compras_creditos;
