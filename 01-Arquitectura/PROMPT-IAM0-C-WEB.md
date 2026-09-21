# IAM-0/C — Auditoría Web IAM (solo lectura)

## OBJETIVO
Inventariar auth, capabilities, recovery y operaciones sensibles de la web y determinar qué tiene control server-side/RLS y qué vive solo en frontend. CERO cambios.

## ALCANCE EXACTO
Solo leer e informar. No crear agentes persistentes (no existe `rsuelvo-web` especializado): ejecuta como implementador general React/TypeScript.

## REPOSITORIO
`skinnypizza/rsuelvo-web`, rama `main` (`landing/` + `app/`).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `app/src/auth/permissions.ts` (catálogo `Capability`, `staffRoles`, `can()`), `permissions.test.ts`, `access.ts`, `AuthContext.tsx`, `passwords.ts`, `auth-flows.test.tsx`
- `app/src/data/api.ts` (qué operaciones sensibles → qué RPC/fn_*; cuáles van directo a tablas)
- `app/src/features/UsersPage.tsx`, `SolicitudesPage.tsx`, `CommercesPage.tsx`, `ReportsPage.tsx` (gates por capability vs control real)
- `app/src/auth/permissions.ts` líneas de `highestRole` (¿misma trampa single-context que Flutter?)
- Flujo recovery + `/auth/confirm` (qué verifica, qué no)
- `docs/solicitudes-backend.md` y demás docs de contratos backend

## DEPENDENCIAS
Ninguna (paralelo con A/B/D). Su informe alimenta la convergencia RBAC (IAM-6) y el contrato IAM-1 Web.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Ningún cambio de código en esta fase
- `app/src/auth/permissions.ts` es la referencia de capabilities — no duplicar ni renombrar
- Build/deploy Pages intactos

## CAMBIOS PERMITIDOS
Ninguno en código. Solo el informe.

## CAMBIOS PROHIBIDOS
Editar código, crear `rsuelvo-web.md` u otro agente persistente, inventar sistema de permisos paralelo, tocar backend/Supabase, exponer secretos.

## PRUEBAS REQUERIDAS
`npm run build` o `tsc` de confirmación (solo lectura del estado). Cada capability mapeada a: control server-side (fn_*/RLS) o solo-frontend (marcar RIESGO).

## ENTREGABLES
1) Catálogo capability→acción backend→autoridad real; 2) lista de capabilities solo-frontend (brecha); 3) supuestos de rol/comercio único en web; 4) diferencias contractuales web-vs-Flutter; 5) matriz actual→objetivo.

## DEFINITION OF DONE
Cero cambios funcionales; toda capability clasificada (server vs frontend); brechas señaladas; build sigue verde sin modificaciones.
