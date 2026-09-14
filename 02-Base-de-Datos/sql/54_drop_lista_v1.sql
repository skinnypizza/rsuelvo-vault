-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 54 (2026-09-15)
-- DROP fn_agregar_lista_espera v1 (superseded por v2 desde F5/m41)
-- ============================================================
-- Sin llamadores en BD (verificado pg_depend) ni en n8n (WF-12 usa v2 desde
-- F5, verificado en live). Cuerpo histórico conservado en git. V2 única firma.

-- == FUNCIONES ==
DROP FUNCTION IF EXISTS rsuelvo.fn_agregar_lista_espera(uuid, uuid, uuid, uuid);
