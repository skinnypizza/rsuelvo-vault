-- ============================================================
-- RSUELVO v2 :: 11. STORAGE — BUCKETS Y PATHS
-- ============================================================

set search_path = rsuelvo, public;

insert into storage.buckets(id,name,public)
values ('comprobantes-pago','comprobantes-pago',false),
       ('qr-pagos','qr-pagos',false)
on conflict (id) do nothing;

-- Paths:
--   comprobantes-pago/{id_comercio}/{id_pedido}/{uuid}.{ext}
--   qr-pagos/{id_comercio}/tienda.{ext}
-- Plantilla de política por tenancy (adaptar por bucket):
--
-- create policy "comprobantes_tenant_read" on storage.objects
-- for select to authenticated
-- using (bucket_id='comprobantes-pago'
--   and (storage.foldername(name))[1] in (
--     select uc.id_comercio::text
--     from rsuelvo.tbl_usuario_comercio uc
--     join rsuelvo.tbl_usuarios u on u.id_usuario=uc.id_usuario
--     where u.auth_user_id=auth.uid() and uc.activo));
