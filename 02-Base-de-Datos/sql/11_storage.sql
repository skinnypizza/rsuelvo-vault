-- ============================================================
-- RSUELVO :: STORAGE (BUCKETS Y POLÍTICAS)
-- Archivo 11/12 del schema separado
-- Ejecutar en orden. Idempotente. Esquema: rsuelvo
-- ============================================================

set search_path = rsuelvo, public;

-- Buckets privados (idempotente). El monolito dejaba esto solo como comentario.
insert into storage.buckets(id,name,public)
values ('comprobantes-pago','comprobantes-pago',false),
       ('qr-pagos','qr-pagos',false)
on conflict (id) do nothing;

-- Path recomendado: {bucket}/{id_comercio}/{id_pedido|tienda}/{uuid}.{ext}
-- Las políticas de Storage deben validar tenancy por prefijo de carpeta. Ejemplo:
--
-- create policy "comprobantes_tenant" on storage.objects
-- for select to authenticated
-- using (bucket_id='comprobantes-pago'
--   and (storage.foldername(name))[1] in (
--     select id_comercio::text from rsuelvo.tbl_usuario_comercio uc
--     join rsuelvo.tbl_usuarios u on u.id_usuario=uc.id_usuario
--     where u.auth_user_id=auth.uid() and uc.activo));
