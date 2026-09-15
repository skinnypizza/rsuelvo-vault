-- 59_rls_superadmin_qr.sql
-- F8-slice: el panel (superadmin) debe poder subir/leer/actualizar el QR del comercio
-- en el bucket qr-pagos. Lecturas de tablas ya cubiertas (fn_tiene_acceso_comercio y
-- fn_es_admin_comercio incluyen superadmin). PostgREST: policies sobre storage.objects
-- aplican al upload via API con JWT de superadmin (TO authenticated).

-- Limpieza idempotente
drop policy if exists qr_pagos_superadmin_select on storage.objects;
drop policy if exists qr_pagos_superadmin_insert on storage.objects;
drop policy if exists qr_pagos_superadmin_update on storage.objects;

create policy qr_pagos_superadmin_select on storage.objects
  for select to authenticated
  using (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin());

create policy qr_pagos_superadmin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin());

create policy qr_pagos_superadmin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin())
  with check (bucket_id = 'qr-pagos' and rsuelvo.fn_es_superadmin());
