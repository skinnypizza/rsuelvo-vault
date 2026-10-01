-- Least privilege for client roles. Row policies remain unchanged.
-- Public signup inserts through solicitar-alta-comercio using service_role;
-- authenticated staff only list requests and resolve them through the guarded RPC.
REVOKE ALL ON TABLE rsuelvo.tbl_solicitudes_alta FROM anon, authenticated;
GRANT SELECT ON TABLE rsuelvo.tbl_solicitudes_alta TO authenticated;

-- Flutter clients list/manage carriers as authenticated tenant admins.
-- There is no client delete path; anonymous clients need no table access.
REVOKE ALL ON TABLE rsuelvo.tbl_transportadoras FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE rsuelvo.tbl_transportadoras TO authenticated;
