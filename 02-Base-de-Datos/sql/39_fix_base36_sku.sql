-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 39 (2026-09-10)
-- FIX SKU BASE36 — el trigger decodificaba base36 como HEX
-- ============================================================
-- Síntoma: "G is not a valid hexadecimal digit" al crear variantes cuyo
-- sufijo contenía G-Z; y aun con A-F el máximo era incorrecto (hex ≠ base36),
-- pudiendo repetir/saltar el contador de SKUs.
-- Fix: helper fn_base36_a_int() y uso en el cálculo de máximo del trigger.
-- La GENERACIÓN (encode) ya era base36 correcta (loop con chars 0-9A-Z).
-- Validado: FERK02 tras K01 · FERZ9A tras FERZ99 (letras >F sin error).

CREATE OR REPLACE FUNCTION rsuelvo.fn_base36_a_int(p_texto text)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'rsuelvo', 'public'
AS $function$
DECLARE
  v text := upper(coalesce(p_texto,''));
  i int;
  c text;
  v_valor int := 0;
BEGIN
  IF v = '' THEN RETURN NULL; END IF;
  FOR i IN 1..length(v) LOOP
    c := substr(v, i, 1);
    IF c ~ '[0-9]' THEN
      v_valor := v_valor * 36 + (ascii(c) - 48);
    ELSIF c ~ '[A-Z]' THEN
      v_valor := v_valor * 36 + (ascii(c) - 55);
    ELSE
      RETURN NULL;
    END IF;
  END LOOP;
  RETURN v_valor;
END;
$function$;

comment on function rsuelvo.fn_base36_a_int(text) is 'Convierte un sufijo SKU base36 (A-Z0-9) a entero. Usado por fn_resolver_variante_tenant_sku.';

-- Nota: el cuerpo completo actualizado de fn_resolver_variante_tenant_sku()
-- está en 06_functions.sql y en _monolito_…_v2.sql (misma definición aplicada a cloud).
