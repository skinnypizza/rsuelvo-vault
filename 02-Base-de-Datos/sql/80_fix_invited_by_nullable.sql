-- 80_fix_invited_by_nullable.sql
-- IAM-1 parche revision ChatGPT: invited_by nullable (auditoria historica
-- preservada con ON DELETE SET NULL). No reescribe mig 79.

alter table rsuelvo.tbl_invitaciones alter column invited_by drop not null;
