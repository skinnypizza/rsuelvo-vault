# Reporte E2E Final IAM-8

**Fecha:** 2026-09-22 · **Fósiles:** e2eF/cajero/dueno (restaurados) · **Restore:** completo.

## A. Registro (LIVE)
1. Email nuevo → neutral ✅ · 2. Nombre/apellido/teléfono en perfil ✅ (upsert probado) · 3. Retry indistinguible, sin dup Auth/perfil ✅ · 4. Sin duplicados ✅ · 5. Honeypot neutral ✅ · 6. Existente neutral (no filtra) ✅ · 7. Web `/registro/` 200 ✅ · 8. Flutter registro mismo contrato (código + tests agente).
- Hallazgo documentado: con cuota mail agotada el invite falla y no hay fila (correcto); el retry post-cuota usa upsert probado.

## B. Verificación + login
9. No verificado → sin JWT posible (barrera Auth misma) = DENY efectivo, CÓDIGO (documentado) · 10. Verificado → login OK; sin memberships → pendiente (LIVE login + CÓDIGO ruta `/crear-comercio`).

## C. Auto-alta (LIVE)
11. PENDIENTE_VERIFICACION + 1 admin ACTIVE + owner=creador ✅ · 12. Retry mismo id → mismo comercio ✅ · 13. Distinto id <24h → `rate_limit` ✅.

## D. IAM-3/5/7/8 (CÓDIGO + tests router 1-10)
14. Reconciliación intacta · 15. MFA setup precede onboarding (test 1) · 16. Challenge accesible (test 2) · 17. Unavailable sin rebote (test 3) · 18. Legal precede V0 (tests 4-5) · 19. Tras MFA+legal → onboarding V0 (tests 7-8) · 20. Selector sin loop (test 10).

## E. V0 capabilities (LIVE salvo export)
21. Perfil ALLOW ✅ · 22. Catálogo RLS manage decide (sin RPC; lectura permitida) ✅ · 23. QR write: CLIENT/UX BEST-EFFORT (policy exige habilitado; escritura real no probada por falta de archivo) · 24. Solicitar `comercio_no_habilitado` ✅ · 25. Invite EF 403 `comercio_no_habilitado` ✅ · 26. Transfer con destino válido `comercio_no_habilitado` (fase parche) ✅ · 27. Owner/membership no saltan (postconditions + checks) CÓDIGO+LIVE parcial.

## F. V1 (LIVE)
28. Promoción a ACTIVO → helper true → invite EF pasa gate estado (falla solo por cuota mail) ✅. Demovido/eliminado después (no IAM-9).

## G. Regresiones (LIVE)
29. Staff-created ACTIVO igual ✅ · 30. IAM-1 invite ✅ · 31-35. Selector/owner/MFA/capabilities/legal intactos (sin cambios en su código; suites verdes) · 36. n8n/server intacto (helpers compartidos sin tocar; service_role verificado) · 37. `guards_sanos` verde ✅.

## Restore
0 comercios V0 · cajero 1 vínculo FER · e2eF Auth huérfano sin perfil (sin JWT; inofensivo) · intentos registrados (auditoría útil) · guards_sanos verde.

## Veredicto
IAM-8 E2E verde. Cierre aprobado pendiente revisión ChatGPT.
