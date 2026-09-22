-- 99_qr_entrega_grants.sql
-- IAM-9: finalizar solo service_role/EF (solicitar ya es solo-humana).
-- Frontera publica = EF qr-entrega (habilitado-gated), no el bucket.

revoke execute on function rsuelvo.fn_finalizar_habilitacion_v1(uuid) from authenticated;
