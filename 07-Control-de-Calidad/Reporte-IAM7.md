# Reporte QA IAM-7

**Fecha:** 2026-09-22 · **Usuario:** cajero@rsuelvo.test (fósil) · **Restore:** completo.

## E2E live backend (RPC real, sin cambiar clientes)

| # | Punto | Resultado | Evidencia |
|---|---|---|---|
| 1 | 3 obligatorios → bloqueado | PASS | pendientes=3, todos `obligatorio:true` |
| 2 | aceptar uno → quedan 2 | PASS | `aceptado`, pendientes=2 |
| 3 | retry → `ya_aceptado` | PASS | 1 aceptación + 1 AuditLog (apunta a `id_aceptacion`) |
| 4 | aceptar todos → habilitado | PASS | pendientes=[] |
| 5 | versión nueva → gate | PASS | v2 activa → pendientes=[TERMINOS 2.0] |
| 6 | id viejo → obsoleta + refresh | PASS | `version_obsoleta` |
| 7 | opcional no bloquea | CÓDIGO | schema v1 sin docs opcionales (tipo CHECK); clientes filtran por `obligatorio` (verificado en código) |
| 8 | fallo RPC → unavailable | CÓDIGO | catch→`legalStatusUnavailable`/`unavailable` en ambos clientes; backend manda |
| 9 | retry recupera | CÓDIGO | `recargarPerfil`/`refreshMfa` re-consultan; estados resuelven igual que login |
| 10 | logout accesible | CÓDIGO | exento en ambos routers |
| 11 | MFA accesible | CÓDIGO | `/mfa-setup`, `/mfa-challenge` exentos (Flutter); MFA previo al gate legal (Web) |
| 12 | recovery accesible | CÓDIGO | Flutter: `/recuperar`, `/restablecer-contrasena` exentos; Web: rutas fuera de StaffGate |

## DB
Aceptaciones 0→3→0 (restore) · AuditLogs solo en inserción real · seeds v1 activos · versiones fósiles eliminadas · `fn_verificar_guards_sanos()` verde.

## Veredicto
IAM-7 E2E verde. Cierre aprobado pendiente revisión ChatGPT.
