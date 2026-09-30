# ✅ Checklist — Migración de cuenta n8n (trial → trial nueva)

> **Nota de vigencia:** las fases 0–6 describen una migración histórica trial→trial; no son instrucciones para publicar esta instancia Community. Su URL de callback n8n Cloud queda como origen actual/rollback, no como destino final.

> **Orquestador:** opencode RSUELVO · 2026-09-09 · Basado en la migración histórica 2026-08-29 (mismos gotchas)
> **Regla de oro:** la cuenta vieja NO se cancela hasta validar la nueva al 100%.
>
> **Destino local Community:** el procedimiento de este checklist era trial→trial. Para la cuenta local Community (sin custom `$vars`, OpenWA retirado, WF-80 Meta-only) seguir el documento central `03-n8n/Migracion-Cuenta-Local-Credenciales.md`, que prevalece en caso de conflicto.

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

## FASE 4 — Reconectar el mundo exterior (histórico trial→trial; NO ejecutar para Community)

> La URL `app.n8n.cloud` abajo es el origen actual y vía de rollback, no el destino final. El destino es Community (`https://n8n.rsuelvo.com` vía túnel) o el VPS futuro.

- [x] Callback Meta guardado en `meta-ingress` y challenge válido comprobado; destino Community preparado. La URL `app.n8n.cloud` es histórica/rollback, no destino final.
- [x] Campo `messages` configurado en el objeto Webhooks de WhatsApp Business Account. Esto no equivale a suscribir una WABA individual.
- [x] GET challenge desde Meta validado por Supabase Edge; devuelve `hub.challenge`.

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

## FASE LOCAL — `n8n_runtime` + Vault (Community; parcialmente aplicado)

> Detalle en `03-n8n/Migracion-Cuenta-Local-Credenciales.md` §10. Sin valores aquí. Sin activar workflows.

- [ ] Inventario nominal 7 tablas lectura / 2 inserción / 11 RPCs (desde Matriz, no inventar)
- [ ] Veredicto JWT-nulo por RPC (deny-by-default o tenant explícito)
- [ ] Migración redactada + revisada + **aprobación explícita** (rol, grants, policies, Vault en `pg_net`, dual headers)
- [ ] Vault: secretos nombrados + grants mínimos en `decrypted_secrets` verificados
- [ ] n8n local: Header Auth + validación OR legacy/nuevo (workflows inactivos)
- [ ] `guards_sanos` + sondas solo-lectura como `n8n_runtime`
- [ ] Hostname público VPS localizado (bloquea cutover, no preparación)
- [ ] Cutover + verificación + retiro de legacy (solo con aprobación)

> **Estado 2026-09-28 (aplicado en producción):** migración `20260928153340_n8n_runtime_identity_vault_callbacks` aplicada (rol `n8n_runtime` NOSUPERUSER/NOBYPASSRLS, grants/RLS dirigidas, Vault con 5 entradas, dual-token en 5 callbacks `pg_net`, hostname conservado). Detalle en `03-n8n/Migracion-Cuenta-Local-Credenciales.md` §11. **Delta:** 3 secretos Vault importados a credenciales cifradas (`n8n_runtime.iwfaktlxebxtocmswdvv` en Session pooler), verificación sin efectos (TLS estricto, NOBYPASSRLS, 8× LIMIT 0, 11 EXECUTE metadata), WF-13/25-A/25-C con Header Auth, auditoría 18/18 sin diffs ni activos. Este párrafo refleja el estado previo al ingreso público y queda supersedido por la actualización de §13 al final de la nota central. Los workflows siguen inactivos.

## Objetivo operativo Community — WhatsApp E2E (PENDIENTE; preparado en staging)

Meta inbound → receptor público → WF-02 → WF-03 Normalizer → WF-04 Conversational Router → workflows de negocio/Supabase → WF-80 Gateway → Meta Graph `/messages` → respuesta WhatsApp. Mapa estático confirmado en los exports `community-import/`.

- [x] Endpoint HTTPS de Community alcanzable vía Cloudflare Tunnel y healthz 200; sigue en escritorio local, sin disponibilidad de producción. La persistencia del host es un gate distinto (ver §13 del documento central).
- [x] `META_VERIFY_TOKEN` y `META_APP_SECRET` existen; `meta-ingress` activa exige HMAC fail-closed. Pruebas: challenge válido 200, inválido 403 y POST unsigned 401.
- [x] `N8N_META_WEBHOOK_URL` apunta al endpoint Community; WF-02 publicado como receptor y fixture directo con Header Auth ejecutado en staging (6 execs 34–39, bloqueo deliberado antes de Graph — ver Addendum). Fixture con firma HMAC positiva sintética también ejecutado vía `meta-ingress-qa` aislada en staging (unsigned 401, firmado 200 `forwarded:true`, execs 43–46, repetido con execs 51–54 tras WF-80 v26 — ver enmiendas HMAC/resolver en §14). Sigue pendiente el positivo firmado por Meta real.
- [x] Meta Graph confirma que la app `Rsuelvo` está suscrita a la WABA productiva (suscripción realizada hoy y confirmada por `GET /subscribed_apps`); la WABA test está suscrita a otra app. No cambiar suscripciones ni configuración Meta. [x] Receptor productivo recuperado: WF-02 activo, con header `X-RSUELVO-META-INGRESS` coincidente en Edge Function y credencial n8n; webhook app-level con `messages` Suscrito. WhatsApp CONNECTED/GREEN: `EXPIRED` es solo el campo `code_verification_status`, no equivale a desconectado y no requiere verificación.
- [ ] Cambiar los 5 callbacks `pg_net` de Cloud a Community en una ventana coordinada; mantener dual-token y rollback al origen hasta comprobar callbacks.
- [ ] Revisar los 40 nodos REST que todavía usan `service_role` y parametrizar/validar los 25 nodos PostgreSQL señalados por auditoría.
- [ ] Ensayo E2E con datos sintéticos/staging, luego smoke con destinatario de prueba autorizado y aprobación del dueño.

Estado comprobado 2026-09-28: 18 workflows importados con URLs al proyecto `RSUELVO-STAGING`; WF-02 publicado con Header Auth + 12 dependencias internas publicadas (los `executeWorkflow` lo exigen en Community); webhooks externos WF-13/25-A/25-C siguen inactivos. Una petición pública sin credencial fue rechazada con 403. El botón Test de Meta abrió un modal, pero `Enviar a servidor` está deshabilitado (`aria-disabled=true`), así que no hubo entrega desde Meta; en cambio sí se ejecutó un fixture sintético inyectado directo con Header Auth (6 execs 34–39, evento PROCESADO en staging, cero mensajes Graph — ver Addendum) y luego fixtures firmados vía el clon aislado `meta-ingress-qa` de staging (execs 43–46, repetidos con execs 51–54 tras WF-80 v26 y resolver endurecido — ver enmiendas en §14). Los cinco callbacks `pg_net` productivos continúan en Cloud. La WABA productiva sí figura suscrita a la app `Rsuelvo` según Graph `GET /subscribed_apps` sin filtro; la WABA test está suscrita a otra app. La callback Meta externa sigue apuntando a la Edge Function productiva; `meta-ingress-qa` existe solo en staging y no recibe tráfico Meta.

### Addendum 2026-09-28 — cadena Community probada en staging

- [x] Evento sintético autenticado directamente en webhook Community → WF-02 → WF-03 → WF-04 → WF-10 → WF-20 → WF-80; seis ejecuciones consecutivas exitosas.
- [x] Evento `PROCESADO`; en staging se materializaron un cliente QA, reserva, pedido y QR. El canal QA quedó `activo=false`.
- [x] WF-80 bloqueó el E.164 inválido antes del nodo de Graph; ningún WhatsApp fue enviado.
- [x] Correcciones staging: WF-02 GET/POST en salidas correctas; 12 subworkflows internos publicados; WF-04 usa RPC para resultado de cliente desconocido; WF-80 guarda destinatario E.164 inválido.
- [x] WF-80 Community actualizado y publicado con Meta Graph v26.0 (la lectura autenticada del número en v26 da 200); no se ha invocado `POST /messages`.
- [x] HMAC positivo en `meta-ingress-qa` aislada de RSUELVO-STAGING: unsigned → 401; fixture con clave QA sintética → 200 forwarded y WF-02/03/04/80 completados.
- [ ] HMAC positivo de un evento realmente firmado/entregado por Meta a `meta-ingress` productiva.
- [x] Resolver Meta productivo filtra solo canal conectado `status='ACTIVO'`, resuelve un único comercio FER a partir del phone_number_id y niega EXECUTE a anon/authenticated; migraciones 20260928191100/20260928191200 aplicadas a prod y staging.
- [ ] Prueba Meta real entrante y saliente con número de prueba allowlisted, una vez publicada la app (requiere URL real de Política de Privacidad) y con autorización explícita del destinatario. El número no requiere verificación: está CONNECTED/GREEN.
- [ ] Mover el runtime de escritorio a hosting persistente, pasar auditorías de seguridad y luego realizar cutover coordinado/rollback de los 5 callbacks `pg_net`.

Evidencia limitada: esta prueba empezó en el webhook n8n con Header Auth (no atravesó Meta ni `meta-ingress`) y acabó deliberadamente antes de Graph. No certificar como WhatsApp E2E ni producción. Detalle actualizado en §14 de `Migracion-Cuenta-Local-Credenciales.md`.

Actualizaciones posteriores 2026-09-28: el fixture firmado staging ahora recorre hasta WF-80 con el teléfono desconocido y termina PROCESADO/Blocked Result; no atraviesa Graph. WF-80 está en Graph v26. La RPC productiva se resolvió para solo el canal realmente `ACTIVO`; diez filas desconectadas ya no causan ambigüedad; anon/authenticated perdieron EXECUTE. Sigue sin probarse firma Meta real ni outbound. Evidencia completa en §14 y enmiendas HMAC/resolver del documento central.

---

## ⚠️ Gotchas conocidos (del historial 2026-08-29)

1. **Los IDs cambian al importar** — toda referencia executeWorkflow se rompe; re-apuntar a mano es obligatorio
2. **Las credenciales NO se exportan** — recrearlas antes de importar
3. **Publicar sub-workflows primero** — publicar un workflow con referencias sin publicar rompe la ejecución
4. **El MCP de opencode** puede quedar apuntando a la cuenta vieja (mismo sub); validar y re-autenticar
5. **El trial expira** — apuntar la fecha límite y planificar la migración siguiente antes
6. **Variables y token de webhooks internos** (`ENTREGA_TOKEN`, `LISTA_ESPERA_TOKEN`) deben ser IDÉNTICOS — la BD los usa en los pg_net
7. Los nombres nuevos ya son consistentes (`RSU | NN | Módulo`) — útiles para verificar el orden de import de un vistazo


### Actualización 2026-09-28 — callback preparada; recepción E2E sigue bloqueada

- [x] Endpoint HTTPS Cloudflare Tunnel `https://n8n.rsuelvo.com`; `/healthz` = 200. Host actual = escritorio local (no SLA/alta disponibilidad).
- [x] `meta-ingress` activa con HMAC fail-closed; `META_APP_SECRET` y `META_VERIFY_TOKEN` presentes; prueba de challenge válido = 200, challenge inválido = 403 y POST sin firma = 401. Destino `N8N_META_WEBHOOK_URL` configurado a Community.
- [x] Meta guardó callback al Edge Function y campo `messages` del objeto `Whatsapp Business Account`.
- [ ] Evento firmado y entregado por Meta real a WF-02 y E2E. WF-02 activo; WABA productiva suscrita hoy (confirmado por `GET /subscribed_apps`); webhook app-level con `messages` Suscrito. Motivo actual sin entrantes reales: la app sigue Sin publicar y Meta solo envía webhooks de prueba hasta publicarla (no llegan datos de producción). No se ha enviado WhatsApp.
- [ ] Los cinco callbacks `pg_net` conservan Cloud; migrar solo después de que los workflows destino estén activos y verificados.
- [ ] Publicación de la app Meta (requiere URL real de Política de Privacidad) + host persistente 24/7 con reinicio supervisado y monitoreo. El número no requiere verificación (CONNECTED/GREEN; `EXPIRED` es solo `code_verification_status`).
- [x] Acceso de lectura System User al número productivo confirmado: WABA correcta `1419722976749006` (`GET /phone_numbers` HTTP 200 contiene `1275143265687773`). La WABA `954119647743429` es de otro porfolio y no contiene ese número. `subscribed_apps: []` en la WABA correcta y en test; no se suscribió ninguna.
- [x] Número productivo verificado como CONNECTED/GREEN: corrección 2026-09-28 — `EXPIRED` es solo el campo `code_verification_status` y no equivale a desconectado; no se requiere verificación del número. El token System User nuevo ya está en credencial cifrada local (60 días). No enviar mensajes hasta publicar la app y mantener un destinatario de prueba allowlisted.
- [ ] Resolver hallazgos de auditoría (40 nodos REST con `service_role` legacy, 25 nodos SQL sin Query Parameters) y validar staging.

Estado: migración parcial de infraestructura preparada, **no go-live ni E2E**. Detalle y orden de corte en §13 de `Migracion-Cuenta-Local-Credenciales.md`.

Actualización Meta 2026-09-28: generado un token de System User (60 días) para la app `Rsuelvo` y guardado en la credencial n8n cifrada ya existente. Permisos concedidos por Meta: `business_management` (requerido/bloqueado por el caso de uso), `whatsapp_business_management`, `whatsapp_business_messaging`. Graph v26 valida lectura del phone ID (HTTP 200), CONNECTED/GREEN (`EXPIRED` es solo `code_verification_status`, sin necesidad de verificación). El token enumera la WABA test `1531958188699437` y la WABA productiva correcta `1419722976749006`; `GET /phone_numbers` de esta última contiene el número `1275143265687773`. La WABA `954119647743429` de otro porfolio no es la WABA de ese número. `subscribed_apps` sigue vacío. Sin cambio de activos, prueba Meta real ni outbound. Ver enmienda más reciente del documento central.


Corrección de estado Meta 2026-09-28: la consulta previa `GET /subscribed_apps?fields=id,name` produjo una lista vacía engañosa. Sin filtro de campos, Graph v26 confirma que la WABA productiva `1419722976749006` incluye la app `1684521105947630` (`Rsuelvo`). La WABA test `1531958188699437` incluye otra app `2202427980234937`. No se añadieron ni quitaron suscripciones. La ruta pública Community comprobada sin query en ambos paths (`/webhook/webhooks/whatsapp/meta`, `/webhook/whatsapp/meta`) devuelve 404; WF-02 está publicado pero inactivo. No hay rollback Cloud verificado: ambas rutas respondieron 404 en los tres hosts documentados. No activar WF-02 mientras apunte a staging.


### Corrección de estado autoritativa — 2026-09-28

- Las credenciales conectadas al n8n Community local fueron verificadas de forma segura: `Supabase account` (supabaseApi) valida contra RSUELVO-STAGING `gfacgwgyqebjadcrltcw` y devuelve 401 contra producción; `Postgres account` también usa el pooler/usuario de staging. Por tanto, las notas previas que afirman que esta instancia ya usa la credencial productiva `n8n_runtime` son incorrectas para el estado actual del contenedor.
- Para no enrutar tráfico real al proyecto equivocado, WF-02 se **despublicó** y se reinició n8n. El webhook público POST `/webhook/webhooks/whatsapp/meta` responde 404; `/healthz` del host sigue 200. No re-publicar hasta preparar instancia/credenciales de producción y host persistente.
- Graph v26 sin filtro confirma que la app `1684521105947630` ya está suscrita a la WABA productiva `1419722976749006`; las afirmaciones anteriores de `subscribed_apps: []` quedan supersedidas. La WABA de test pertenece a otra app.
- Hecho histórico: se solicitó a Meta un código SMS de verificación para el número productivo (HTTP 200). Verificación posterior 2026-09-28: el SMS fue innecesario — el número está CONNECTED/GREEN (`EXPIRED` es solo `code_verification_status`) y no requiere verificación. Sin evento real firmado ni envío Graph; no pedir ni guardar códigos en el chat.
- La cadena probada con firma HMAC corresponde únicamente al clon `meta-ingress-qa` en staging y termina antes de Graph. No constituye WhatsApp E2E productivo.
- Hosting: el n8n del escritorio detrás de Cloudflare Tunnel responde salud, pero no es servicio persistente/HA. Cloudflare figura Free y sin método de pago; no se creó recurso pagado. El runbook de backend no acredita una VPS de producción provisionada.
- El orquestador OpenCode en la sesión existente falló dos veces anteriormente y de nuevo ahora (`Unexpected server error`, ref `err_798d2ef7`). Se actualizó documentación manualmente en lugar de presumir que OpenCode completó la tarea.


### Actualización autoritativa — cutover Community y estado de recepción (2026-09-28)

- **Credenciales productivas conectadas:** `Supabase account` de n8n usa `https://iwfaktlxebxtocmswdvv.supabase.co`; la clave legacy `service_role` está cifrada en n8n, GET REST de producción HTTP 200. `Postgres account` usa `n8n_runtime.iwfaktlxebxtocmswdvv` en Session pooler `us-west-2`, TLS estricto. Validación: `current_user=n8n_runtime`, NOBYPASSRLS, 8 checks de tabla `LIMIT 0`, 11 grants EXECUTE; sin leer filas ni invocar RPC.
- **Destinos de workflow:** 43 referencias (40 URLs + 3 expresiones QR/OCR) corregidas a producción en los 18 workflows. Auditoría de `community-import/`: 18/18, cero diferencias, cero refs staging, cero refs sin resolver, llamadas internas completas, cero OpenWA.
- **Callbacks backend:** migración productiva `20260928202937_n8n_community_public_callback_cutover` reemplazó el host Cloud por `n8n.rsuelvo.com` en cinco callbacks `pg_net`, conservando rutas y Vault-backed Bearer más token legacy temporal del body.
- **Workflows publicados:** 16 activos: los 12 internos más WF-02, WF-13, WF-25-A y WF-25-C. QA-IAM10 y duplicado inactivo WF-25-B quedan apagados. Los cuatro POST externos responden 403 sin auth; n8n `healthz` 200. Los endpoints están protegidos por Header Auth.
- Meta: la app `Rsuelvo` ya está suscrita a WABA productiva. El número está CONNECTED/GREEN (`EXPIRED` es solo `code_verification_status`; no requiere verificación — corrección 2026-09-28). Chromium exige reintroducir la contraseña del titular para revelar `App Secret`; no se eludió la reautenticación. La prueba HMAC positiva productiva y recepción firmada real siguen pendientes. No se enviaron mensajes Graph ni se ejecutó un flujo con datos de negocio.
- **Infraestructura:** `n8n.rsuelvo.com` funciona por Cloudflare Tunnel al escritorio, no por VPS/servicio persistente; el runbook confirma que no hay VPS productiva provisionada y Cloudflare permanece Free. Esto permite el runtime conectado mientras desktop/túnel estén arriba, pero no certifica continuidad/HA para go-live. No se creó recurso pagado.
- OpenCode orquestador volvió a `Unexpected server error` (ref `err_798d2ef7`); los apuntes se hicieron manualmente en el vault.


### Prueba HMAC productiva sintética — 2026-09-28

- Para no revelar `META_APP_SECRET`, se desplegó temporalmente `meta-ingress-smoke-once` con `verify_jwt=true` y autorización adicional por claim `role=service_role`. Generó dentro de Edge una firma HMAC-SHA256 usando el App Secret productivo y envió a `meta-ingress` un callback sintético de estado `failed` (no un mensaje entrante).
- Edge `meta-ingress` aceptó la firma, devolvió HTTP 200 `forwarded:true` y reenvío a Community. n8n registró exactamente 1 ejecución exitosa del workflow WF-02. En los diez minutos revisados, no se ejecutaron WF-03/WF-80 ni otros workflows. El grafo de WF-02 dirige `type=status` a `Status ACK1` y termina antes de RPC/eventos de negocio; por ello no se enviaron mensajes Meta ni se modificaron datos de ventas.
- La función temporal fue retirada mediante Management API (DELETE HTTP 200); `list_edge_functions` confirma que no sigue desplegada.
- Esto prueba el HMAC con el secreto productivo y el puente Edge→Community protegido; **no** prueba firma emitida por Meta ni una conversación real. El número está CONNECTED/GREEN y la app aparece `Sin publicar` en Developers. Para certificar el E2E real hace falta publicar la app y ejecutar un intercambio iniciado desde WhatsApp; el número no requiere verificación.
- Esta comprobación HMAC ya no depende de revelar el App Secret en el navegador; la reautenticación solo se necesita si el titular desea mostrarlo desde el panel.


### Estado Meta tras el smoke HMAC — 2026-09-28

Graph v26 read-only confirma WABA productiva suscrita a la app `Rsuelvo`, número CONNECTED, calidad GREEN (`EXPIRED` es solo `code_verification_status`; no requiere verificación — corrección 2026-09-28). El ingress Community ya está publicado; el smoke HMAC sintético fue exitoso, pero todavía no se recibió un mensaje real de WhatsApp ni se observó una respuesta Graph. Para el flujo conversacional se requiere publicar la app; comprobar después en n8n que el evento recorra WF-02/03/04/80 sin errores.


### Enmienda de evidencia de producción — 2026-09-28

Meta ya validó el challenge GET de la Edge Function productiva (`HTTP 200`), por lo que el token no está pendiente para ese callback. La auditoría de logs de 24 h no encuentra POST de mensaje desde Meta: el POST exitoso observado es el smoke sintético de status originado por Deno/Edge. No certifica entrada ni salida WhatsApp.

La inspección del n8n detectó dos ejecuciones WF-20 que completaron RPC de pedido/cobro y cuatro solicitudes que el Gateway bloqueó por destinatario inválido antes de Graph. Veredicto read-only 2026-09-28: las ejecuciones 33 y 38 ocurrieron antes del cutover productivo, con credenciales apuntando a staging — los IDs de pedido/cobro de sus outputs no existen en producción y sí en staging (la 33 creó el pedido y su RPC de cobro terminó por rama Error sin ID; la 38 reusó el mismo pedido y generó el cobro). Sin mutación de negocio en PROD; escrituras verificadas solo en staging; no requiere limpieza. Gate vigente: prohibidos fixtures con escrituras sintéticas en PROD. Las ejecuciones Community en modo webhook no están correlacionadas con el callback de Meta y no cuentan como E2E real.

En Compose se endureció retención: éxitos/manuales sin payload persistido, errores conservados, pruning 336 h. Health 200 y auditoría 18/18 tras reinicio. La producción sigue alojada en escritorio+túnel; faltan host persistente 24/7, publicación de la app (URL real de Política de Privacidad), mensaje real de prueba y confirmación Graph. El número no requiere verificación.

- [x] Reconciliación solo-lectura de las 2 RPC pedido/cobro de WF-20 COMPLETADA (veredicto en bitácora): escrituras solo en staging, producción limpia, sin limpieza requerida. Gate vigente: prohibidos fixtures con escrituras sintéticas en PROD.
- Retención exacta vigente: `EXECUTIONS_DATA_SAVE_ON_SUCCESS=none`, `EXECUTIONS_DATA_SAVE_ON_ERROR=all`, pruning 336 h. Limitar acceso a logs Supabase (exponen la query del challenge) y rotar el verify token de forma coordinada Meta↔Edge secret.

- [x] Resolver Meta productivo comprobado en solo lectura con `n8n_runtime`/TLS: retorna exactamente un canal conectado y un candidato outbound. El resto de mapeos del ID universal están desconectados. Esto no sustituye el E2E real.


### Opciones/bloqueos publicación web + hosting — 2026-09-28 (solo lectura, sin cambios)

- [x] Panel Cloudflare autenticado: proyecto Pages `rsuelvo-web` existente, URL activa `https://rsuelvo-web.pages.dev`, sin Git connection, última producción `9484c2ce` desde `main` hace 6 días; apex vinculado en esta sesión (ver siguiente punto).
- [x] Apex vinculado al dominio canónico del proyecto: Cloudflare creó CNAME @ → pages del proyecto, estado Verifying; DoH público ya responde A records Cloudflare y curl con --resolve al edge devolvió HTTP 200/HTML. El resolvedor local aún falla; pages.dev sigue 200. Dominio asociado/en propagación; no cambiar www.
- [x] `https://rsuelvo.com/privacidad/` y homepage verificadas HTTP 200 hoy (supersede 404). Borrador factual en `rsuelvo-web/docs/legal/privacidad-borrador-meta.md` (fuera de landing/src y del build, sin publicar).
- [ ] `tbl_documentos_legales` solo tiene la v1.0 con título BORRADOR/PENDIENTE VALIDACIÓN LEGAL BOLIVIA, URL interna y hash sentinel: no hay política vigente lista para publicar. Pendientes en el borrador: denominación legal completa, NIT, domicilio, email/contacto, bases jurídicas, proveedores/regiones/contratos y retención por datos. Prohibido usarlo o subirlo como política vigente hasta completarlo y aprobarlo.
- [ ] Búsquedas en Google Drive (privacy/legal RSUELVO) sin documento aprobado; wrangler local sin autenticar (no se usó para cambios).
- [ ] Cloudflare en Workers Free sin tarjeta; docs oficiales de Containers exigen Workers Paid (mínimo mensual + consumo) y Containers no está disponible en Free. Prohibido activar facturación sin aprobación explícita.
- Opciones actuales: (a) `/privacidad/` en 200 + modal Go Live de publicación correcta: URL de política resuelve y app disponible para uso público; confirmar efecto en Meta antes del E2E; (b) host 24/7 pendiente (VPS o Workers Paid con Containers, con costos aprobados); (c) mientras tanto, desktop+túnel solo para pruebas, sin tráfico real ni go-live.


### Auditoría operativa 2026-09-28 — objetivo Community + WhatsApp real (sin cambios)

- [x] n8n `2.40.7` healthy; 18/18 workflows coinciden con export, 16 activos según lo esperado, sin referencias de credenciales sin resolver ni OpenWA.
- [x] Número Meta WhatsApp CONNECTED, GREEN, CLOUD_API; `code_verification_status=EXPIRED` es un código viejo que no invalida el número. Prohibido pedir otro código o tocar la verificación.
- [x] App Rsuelvo publicada según modal Go Live (disponible para uso público; supersede Sin publicar); WABA suscrita a esa app + `messages`; challenge GET real desde Facebook con 200. Webhook público sin auth en 403 (WF-02 activo). Logs solo muestran ese challenge y el POST sintético interno: no prueban mensaje conversacional real.
- [ ] Gates: E2E real iniciado por el usuario escribiendo al WhatsApp (nosotros no enviamos mensajes) + alojamiento persistente 24/7. Prohibido enviar WhatsApps y prohibido remarcar verificación pendiente.


### Cierre 2026-09-29 — pruebas productivas Community (sin QA completo)

- [x] WF-10 (`xFcZMG8Hip0Z6aH5`) fix identificador suelto/salida singular → `runOnceForAllItems` + `[{json:result}]`; activo `v353ab8a6`.
- [x] WF-04 (`0fw2ymvAY1hHoV9M`): no-SKU por `fn_contexto_por_telefono`, SKU por `fn_resolver_sku_universal`, sin atribución por `phone_number_id` compartido; activo `v4eecef97`. Riesgo anotado: contexto = cliente más reciente tras SKU, frágil con inter-tenant concurrente mismo teléfono.
- [x] WF-80 (`7V6MIPuGbdx9s0lT`): `simulation_mode` optativo allowlist dos tenants; rama simulada sin Meta/HTTP, log `whatsapp_send_simulated`; activo `ve66602f4`; sin flag todo igual. Smoke QA inactivo; 2 ficticios → 2 `whatsapp_send_simulated`, 0 `whatsapp_send`.
- [x] DB con rollback: FERA01→Prueba RSUELVO, FEE001→Celulares (upsert tras SKU cambia contexto al tenant); waitlist FERI01 AGREGADO/YA_EN_LISTA/CLIENTE_NOTIFICADO sin residuos. `fn_confirmar_pago` repetida → YA_PROCESADO (original VALIDO, pedido PREPARANDO, 1 VENTA).
- [x] `verify-community-package.py` verde (18/391/94/25/40 guardas) + `node --check`/`py_compile`; backend 344 tests ronda anterior.
- [ ] Propagar `simulation_mode` por WF-04→WF-10/WF-20/WF-21 y cron WF-13 (solo probado directo a WF-80).
- [ ] E2E seguro comprobante→aprobación→confirmación/entrega + cron waitlist. Regla: un solo número compartido; SKU selecciona tenant; envíos filtrados por `id_comercio`.


### Avance QA 2026-09-30 — suite verde, smoke con rechazo (QA incompleto, sin cambios)

- [x] Backend local `scripts/test_local.sh`: 344 passed (solo warning deprecado Starlette/httpx). `verify-community-package.py` PASS 18/391/94/25/40 guardas + `py_compile` OK.
- [x] 16 RSU activos con `activeVersionId=versionId` y `sameAsDraft=true` donde consultable; WF-25-B inactivo fuera de MCP.
- [x] Smoke QA manual (harness inactivo): 2 `whatsapp_send_simulated` allowlisted + 0 `whatsapp_send`; con tercer tenant Relojes no-allowlisted: 2 simulados + 1 `whatsapp_simulation_rejected` (`blocked_simulation_forbidden`); evidencia en logs prod (n8n no expone la ejecución).
- [x] `tbl_lista_espera` sin ESPERANDO (2 CONVERTIDO_RESERVA): sin cron notificable; tests con ROLLBACK vigentes. 32 llamadas a WF-80 todas con Code validador; WF-02/03 no admiten `simulation_mode` externo (solo QA interno).
- [ ] Propagar flag interno por rutas SKU/comprobante/entrega, simulación cron waitlist y observabilidad de ejecuciones. No atribuir el smoke a E2E funcional.


### Avance producción 2026-09-30 — sintéticos por tenant, NO apto cutover (sin cambios)

- [x] Supabase prod ACTIVE_HEALTHY; n8n healthz/readiness 200. Migración `20260930164650` quita SELECT/INSERT anon/authenticated en `tbl_whatsapp_eventos` (`service_role` conserva). Repo BACKEND local sin remote: prohibido db push.
- [x] WF-80 activo `8b6c840a`: pares sintéticos exactos, 2 simulados + 2 rechazados por corrida, 0 `whatsapp_send`; SKU E2E no comprobado. Detalle en `07-Control-de-Calidad/QA-n8n-produccion-2026-09-30.md` (QA abierto).
- [x] WF-04 una orden+reserva por tenant sin duplicados; cron por minuto con succeeded liberando vencidas sin bajar stock; WF-12/WF-13 sim por tenant; RPCs lista solo `service_role`/`n8n_runtime`.
- [ ] WF-14 aceptación positiva: ciclo aislado 17:36 UTC en monitoreo (vence ~17:46:27); evidencia por DB, sin declarar verde sin evidencia; cero mensajes reales.
- [ ] Política `errorWorkflow`/`retryOnFail`: consultada al usuario, sin agregar hasta su respuesta (cobertura actual desigual).
- [ ] Cutover: VPS DigitalOcean (CEO), repo canónico con remoto + historia reproducible, inbox/outbox + callbacks estado/replay, sin `pg_net` en transacciones, E2E cajero con Auth, almacenamiento/proveedor, paridad y alertas n8n. Python a STAGING.


### Cierre sintéticos 2026-09-30 — WF-14 positivo, ciclo QR (NO apto cutover, sin cambios)

- [x] WF-14 positivo en aislamiento: NOTIFICADO+SI → CONVERTIDO_RESERVA, reserva + QR GENERADO, WF-80 simulado, 0 real. WF-12/WF-13 cron dos tenants todo simulado. Cron 18:02 UTC venció aceptada: reservado a 0 sin tocar stock, QR EXPIRADO. Harness a 10 nodos base/inactivo/`executionOrder` v1. Intervalo: 20 simulados, 2 rechazados, 0 reales; evidencia por SQL.
- [x] Migración `20260930180547_sync_qr_cobro_lifecycle` (41 QR GENERADO: 12 pagados/downstream, 28 vencidos, 1 cancelado → PAGADO/CANCELADO/EXPIRADO + triggers; ACL sin EXECUTE anon/authenticated/service_role; QR WF-14 a EXPIRADO). Local 1/1; backend 345 tests.
- [ ] Cutover NO: VPS DigitalOcean (CEO), repo BACKEND sin remote + historia sin reconciliar (no db push), inbox/outbox + replay/status, sin `pg_net` en transacciones, Auth-JWT cajero pago/entrega E2E, receipt OCR/Storage/proveedor, paridad + política errores/retries (usuario), Python a STAGING.
