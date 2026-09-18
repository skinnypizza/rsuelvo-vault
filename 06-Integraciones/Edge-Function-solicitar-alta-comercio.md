# Edge Function — `solicitar-alta-comercio`

> **Proyecto:** `iwfaktlxebxtocmswdvv` · **Slug:** `solicitar-alta-comercio`
> **Estado:** ✅ DESPLEGADA (pública, `verify_jwt=false`) y **validada E2E**
> (201/200/409/400/422, bandeja superadmin, resolve una vez, anon vacío)
> **Fuente:** `Edge-Function-solicitar-alta-comercio.ts` · deploy vía CLI
> **Contrato web:** `rsuelvo-web/docs/solicitudes-backend.md` (implementado tal cual)

## Contrato
POST sin auth + `Idempotency-Key: <uuid>` + JSON
`{nombre, telefono, tienda, mensaje, plan|null, origen, sitio_web:""}`.
- **201** `{solicitud_id, estado:PENDIENTE}` · **200** reintento idéntico (mismo recibo)
- **409** misma clave otro payload · **400/422** validación/honeypot · **429** rate (3/h teléfono, 10/h IP) · **500** temporal
- CORS: landing acordadas (pages.dev, rsuelvo.com, localhost) + `Idempotency-Key`.
- Tabla `tbl_solicitudes_alta` (RLS niega todo; service_role escribe; superadmin lee).
- Resolución: `fn_resolver_solicitud_alta` (una vez; APROBADA/RECHAZADA+motivo+revisor).
- El alta posterior sigue D17 (staff crea + invite; el form no pide email).

## Lecciones
- Tablas nuevas necesitan GRANTs explícitos (service_role incluido).
- Sintaxis Deno: `Deno.serve(async (req) => {...});` (no `};`).
