# PROMPT CODEX (Astra) — Web: bandeja (handoff) + créditos completar

## Contexto (repo `/home/nico/StudioProjects/rsuelvo-web`)
Dos entregas en una. Reglas: anon+RLS, español, economía, UN commit por entrega,
builds+tests verdes.

## Entrega 1 — Bandeja (doc previo vigente)
Aplicar tal cual `01-Arquitectura/PROMPT-WEB-BANDEJA-SOLICITUDES.md` (Solicitudes,
ficha, aprobar/rechazar, aviso de no-creación).

## Entrega 2 — Créditos completar
Backend LISTO (migs 63/68): `tbl_compras_creditos` (+motivo/revisor),
`fn_solicitar_creditos` (dueño), `fn_resolver_compra_creditos`
(APROBAR/RECHAZAR con `p_motivo`, CANCELAR dueño). `CreditsPage.tsx` ya revisa.
Completar vacíos: motivo y revisor visibles en ficha, comprobante firmado al ver
(`depositos-creditos`), estados (incluida CANCELADA), lista de estados del dueño
(si aplica al rol). Verificar E2E con mocks. Sin inventar contratos.
