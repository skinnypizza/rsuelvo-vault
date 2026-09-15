-- 60_canal_numero_compartido.sql
-- D16 (numero universal): el numero de WhatsApp es compartido entre comercios
-- (todos usan el 59157005003). El UNIQUE en numero lo impedia: el alta del 2do
-- comercio reventaba con 23505. Se elimina; la desambiguacion vive en M1/M2
-- (fn_resolver_sku_universal + fn_contexto_por_telefono) y fn_identificar_* ya
-- devuelve vacio ante multiples (mig 58). HU-105/106, F8-slice.

alter table rsuelvo.tbl_canal_whatsapp
  drop constraint if exists tbl_canal_whatsapp_numero_key;

drop index if exists rsuelvo.uq_canal_numero_activo;
