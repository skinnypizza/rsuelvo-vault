-- 75_solicitud_email.sql
-- La solicitud suma email (opcional, para invitar al aprobar sin pedirlo despues).

alter table rsuelvo.tbl_solicitudes_alta
  add column if not exists email text;
