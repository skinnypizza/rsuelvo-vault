-- 74_qr_paquetes.sql
-- SuperAdmin asocia un QR a cada paquete; el comerciante lo ve al solicitar
-- segun el paquete elegido. QR plataforma en qr-pagos/paquetes/*.png.

alter table rsuelvo.tbl_paquetes_creditos
  add column if not exists qr_path text;

drop policy if exists paquetes_superadmin_update on rsuelvo.tbl_paquetes_creditos;
create policy paquetes_superadmin_update on rsuelvo.tbl_paquetes_creditos
  for update to authenticated
  using (rsuelvo.fn_es_superadmin())
  with check (rsuelvo.fn_es_superadmin());

drop policy if exists qr_paquetes_public_select on storage.objects;
create policy qr_paquetes_public_select on storage.objects
  for select to authenticated
  using (bucket_id = 'qr-pagos' and name like 'paquetes/%');
