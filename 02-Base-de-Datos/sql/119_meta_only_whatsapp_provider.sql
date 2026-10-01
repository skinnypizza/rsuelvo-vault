-- OpenWA was retired. Every active WhatsApp workflow uses the single shared Meta number.
-- Abort safely if legacy provider rows are present; preserve records for explicit review.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM rsuelvo.tbl_canal_whatsapp WHERE provider <> 'META') THEN
    RAISE EXCEPTION 'tbl_canal_whatsapp contains a non-Meta provider; review rows before migration';
  END IF;
  IF EXISTS (SELECT 1 FROM rsuelvo.tbl_whatsapp_eventos WHERE provider <> 'META') THEN
    RAISE EXCEPTION 'tbl_whatsapp_eventos contains a non-Meta provider; review rows before migration';
  END IF;
END
$$;

ALTER TABLE rsuelvo.tbl_canal_whatsapp
  ALTER COLUMN provider SET DEFAULT 'META';
ALTER TABLE rsuelvo.tbl_canal_whatsapp
  DROP CONSTRAINT IF EXISTS tbl_canal_whatsapp_provider_check,
  DROP CONSTRAINT IF EXISTS tbl_canal_whatsapp_provider_meta_only_check;
ALTER TABLE rsuelvo.tbl_canal_whatsapp
  ADD CONSTRAINT tbl_canal_whatsapp_provider_meta_only_check CHECK (provider = 'META');

ALTER TABLE rsuelvo.tbl_whatsapp_eventos
  ALTER COLUMN provider SET DEFAULT 'META';
ALTER TABLE rsuelvo.tbl_whatsapp_eventos
  DROP CONSTRAINT IF EXISTS tbl_whatsapp_eventos_provider_check,
  DROP CONSTRAINT IF EXISTS tbl_whatsapp_eventos_provider_meta_only_check;
ALTER TABLE rsuelvo.tbl_whatsapp_eventos
  ADD CONSTRAINT tbl_whatsapp_eventos_provider_meta_only_check CHECK (provider = 'META');

COMMENT ON TABLE rsuelvo.tbl_canal_whatsapp IS
  'Canal de transporte WhatsApp Meta compartido por comercios; el comercio se resuelve por SKU y contexto. OpenWA retirado.';
COMMENT ON TABLE rsuelvo.tbl_whatsapp_eventos IS
  'Eventos entrantes del webhook WhatsApp Meta. OpenWA retirado.';
