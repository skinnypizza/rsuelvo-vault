-- Public onboarding calls solicitar-alta-comercio with its server-side
-- service_role. Direct fn_sugerir_codigo calls come from the authenticated
-- /comercios UI. Keep authenticated and service_role; deny anonymous RPC use.
REVOKE EXECUTE ON FUNCTION rsuelvo.fn_sugerir_codigo(text) FROM anon;
