# ✅ Checklist — Migración de cuenta n8n (trial → trial nueva)

> **Orquestador:** opencode RSUELVO · 2026-09-09 · Basado en la migración histórica 2026-08-29 (mismos gotchas)
> **Regla de oro:** la cuenta vieja NO se cancela hasta validar la nueva al 100%.

---

## FASE 0 — Preparación (cuenta VIEJA)

- [ ] Confirmar inventario: **16 workflows activos** (IDs en `03-n8n/Matriz-Consistencia-WF-BD-HU.md` §0)
- [ ] **NO exportar** `[ARCHIVO] RSU | 30 | Expirar Reservas` (archivado, sustituido por pg_cron)
- [ ] Exportar los 16 JSON (UI: cada workflow → ⋯ → Download)
- [ ] Renombrar archivos con orden de importación: `01_80_gateway.json`, `02_22_ocr.json`, `03_24_confirmar.json`, `04_23_verificar.json`, `05_21_comprobante.json`, `06_20_qr.json`, `07_10_reserva.json`, `08_03_normalizer.json`, `09_04_router.json`, `10_02_incoming.json`, `11_12_lista.json`, `12_13_notificar.json`, `13_14_aceptar.json`, `14_25a_solicitar.json`, `15_25b_registrar.json`, `16_25c_notificar.json`
- [ ] Anotar los valores actuales de `$vars` (los necesitarás idénticos):
  - `META_SYSTEM_TOKEN` · `META_VERIFY_TOKEN` · `SUPABASE_PROJECT_URL` · `GEMINI_API_KEY` · `ENTREGA_TOKEN` · `LISTA_ESPERA_TOKEN`
- [ ] Anotar credenciales usadas (nombre/tipo, SIN secretos): `Supabase account` (supabaseApi — service_role key), `Postgres account` (postgres — rol bypassrls a `iwfaktlxebxtocmswdvv`), auth de Gemini si aplica
- [ ] Descargar backup ZIP de la cuenta vieja (Settings → export) como respaldo

## FASE 1 — Cuenta NUEVA (setup base)

- [ ] Crear la cuenta trial nueva
- [ ] Recrear las **6 `$vars`** con los MISMOS valores (Settings → Variables)
- [ ] Recrear credenciales (no se exportan): `Supabase account` (supabaseApi + service_role key del proyecto `iwfaktlxebxtocmswdvv`) y `Postgres account` (host/puerto del pooler + rol bypassrls)
- [ ] Anotar los IDs que asigne n8n a cada workflow importado (tabla nueva para Matriz §0)

## FASE 2 — Import (orden de dependencias, SIN publicar aún)

Importar en este orden y tras cada import:

- [ ] `80` Gateway → `22` OCR → `24` Confirmar → `23` Verificar → `21` Comprobante → `20` QR → `10` Reserva → `03` Normalizer → `04` Router → `02` Incoming → `12` Lista → `13` Notificar → `14` Aceptar → `25-A` → `25-B` → `25-C`

Tras cada import:
- [ ] **Re-referenciar TODOS los nodos executeWorkflow** a los IDs nuevos (los imports rompen las referencias):
  - Todos los `Send/Send X via WF-80` → WF-80 nuevo
  - WF-21: `OCR via WF-22` → WF-22 nuevo; `Call WF-23` → nuevo; (WF-23→WF-24 interno)
  - WF-02: `Route to WF-03` → WF-03 nuevo
  - WF-04: `Dispatch → WF-10/21/14/25-B` → nuevos
  - WF-10: `Call WF-20` → nuevo
  - WF-14: `Call WF-12` → nuevo
- [ ] Reasignar credenciales en cada nodo HTTP/Postgres (los imports las dejan vacías)
- [ ] Verificar que los nombres de `$vars` usados en expresiones coinciden

## FASE 3 — Publicación (sub-workflows primero)

- [ ] Publicar en orden: `80` → `22` → `24` → `23` → `21` → `20` → `10` → `03` → `12` → `13` → `14` → `25-A` → `25-B` → `25-C` → `04` → `02`
- [ ] Regla: nunca publicar un workflow cuyo executeWorkflow apunte a otro sin publicar (n8n falla la resolución)

## FASE 4 — Reconectar el mundo exterior

- [ ] **Meta Developer Portal** → App → WhatsApp → Configuration: cambiar Callback URL a `https://<nueva>.app.n8n.cloud/webhook/webhooks/whatsapp/meta` (verify token sin cambios) + Verify & Save
- [ ] Confirmar suscripción al campo `messages` (Webhooks → Subscription fields)
- [ ] Probar el GET challenge desde el portal (debe responder `hub.challenge`)

## FASE 5 — Validación E2E (humo, misma secuencia del test de reservas)

- [ ] SKU real → reserva + QR único + **evento `PROCESADO`** (valida fix de eventos stuck)
- [ ] Comprobante → OCR Gemini → confirmar → PAGADO + CONSUMO_VENTA −1 + WhatsApp al comprador
- [ ] SIN_STOCK → pregunta SI/NO (Momento 1) → SI → posición #N
- [ ] Notificación de oportunidad 🎯 → SI → QR con Producto/SKU (H-19)
- [ ] Entrega: nombre → menú → opción → foto de guía/código → WhatsApp con imagen (OBS-004)
- [ ] Revisar 0 ejecuciones con error y notificaciones SIN duplicados (dedup Regla 7)

## FASE 6 — Post-migración

- [ ] Re-autenticar el **MCP n8n de opencode** a la cuenta nueva (histórico: la auth UI puede fallar; si pasa, operar por UI manual y registrar IDs aquí)
- [ ] Pasarme los **IDs nuevos** → actualizo Matriz §0
- [ ] Vigilar el trial (días restantes / límite de ejecuciones)
- [ ] Cuenta vieja: cancelar SOLO tras validar el E2E completo

---

## ⚠️ Gotchas conocidos (del historial 2026-08-29)

1. **Los IDs cambian al importar** — toda referencia executeWorkflow se rompe; re-apuntar a mano es obligatorio
2. **Las credenciales NO se exportan** — recrearlas antes de importar
3. **Publicar sub-workflows primero** — publicar un workflow con referencias sin publicar rompe la ejecución
4. **El MCP de opencode** puede quedar apuntando a la cuenta vieja (mismo sub); validar y re-autenticar
5. **El trial expira** — apuntar la fecha límite y planificar la migración siguiente antes
6. **Variables y token de webhooks internos** (`ENTREGA_TOKEN`, `LISTA_ESPERA_TOKEN`) deben ser IDÉNTICOS — la BD los usa en los pg_net
7. Los nombres nuevos ya son consistentes (`RSU | NN | Módulo`) — útiles para verificar el orden de import de un vistazo
