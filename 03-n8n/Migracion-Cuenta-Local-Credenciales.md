# Migración n8n a cuenta local Community — estado, credenciales pendientes y decisiones

> **Alcance:** documentar la migración ejecutada el 2026-09-26, las credenciales/tokens pendientes de generar o configurar, los riesgos, las pruebas necesarias y la decisión de retirar OpenWA. **No activar workflows. No hacer cambios productivos.**
> Documentos relacionados: `03-n8n/Checklist-Migracion-n8n.md` (procedimiento original trial→trial), `03-n8n/Matriz-Consistencia-WF-BD-HU.md`, `03-n8n/workflows.md`, `02-Base-de-Datos/datos-conexion.md` (plantilla privada, sin valores), `04-OpenWA/Guia Meta WhatsApp Business.md`, `06-Integraciones/Edge-Function-meta-ingress.md`.

## 1. Contexto verificado (lo hecho)

- **Fuente autoritativa:** ZIP exportado en Escritorio (el MCP de n8n fallaba y no servía como fuente).
- **Importados 18 workflows, todos INACTIVOS**, en n8n Community local, con owner ya configurado.
- **Stack:** n8n + task runners `2.40.7`; PostgreSQL local **solo para estado interno de n8n** (no es la BD del producto).
- **Backend destino:** Supabase RSUELVO, ref `iwfaktlxebxtocmswdvv`. Supabase MCP solo verificó metadatos/catálogo en lectura; **ninguna tabla, fila o RPC productiva fue modificada ni ejecutada**.
- Se fijaron **44 usos de `SUPABASE_PROJECT_URL`** al host público confirmado.
- **Health post-upgrade OK.**
- Limpieza de secretos en vault: se redactaron los valores literales que constaban en comentarios de `02-Base-de-Datos/sql/26_cron_notifica_lista_espera.sql` y `30_logistica_entrega_eventos.sql` (se conserva el nombre de cada variable y el aviso de rotación). Los valores funcionales dentro de los cuerpos `pg_net` se dejan intactos a propósito: cambiarlos exige una migración coordinada (ver §5).

## 2. Inventario de secretos y estado actual

| Secreto | Qué es | Estado |
|---|---|---|
| Credencial Supabase REST (`service_role` legacy) | Clave del proyecto RSUELVO para los nodos originales | Cargada cifrada; GET `/rest/v1/` devolvió HTTP 200. Es bypass-RLS y transición temporal. |
| Credencial PostgreSQL (pooler) | Acceso PostgreSQL al proyecto Supabase | Cargada cifrada como `n8n_runtime`, validada por TLS; rol `NOBYPASSRLS` con grants/RLS dirigidas (ver §11). |
| `META_SYSTEM_TOKEN` | Token Meta Cloud API | Cargado cifrado; Graph `/me` y `/me/permissions` respondieron 200 y muestran los scopes de WhatsApp requeridos. No se verificó aún tipo/caducidad ni envío real. |
| `GEMINI_API_KEY` | Clave Google AI Studio para OCR WF-22 (ver §6: contradice `workflows.md` §5.2) | Cargada cifrada; GET del modelo configurado devolvió HTTP 200. No se generó OCR. |
| `META_VERIFY_TOKEN` | Verify token de callback | Rotado y guardado en Supabase Edge Secrets; challenge válido confirmado (ver §13). WF-02 conserva una referencia histórica que no usa Meta al pasar por `meta-ingress`. |
| `LISTA_ESPERA_TOKEN` | Secreto compartido BD→n8n (WF-13) | En Supabase Vault; Header Auth desplegada en WF-13. Cinco callbacks `pg_net` siguen apuntando a Cloud (ver §11/13). |
| `ENTREGA_TOKEN` | Secreto compartido BD→n8n (WF-25 entrega) | En Supabase Vault; Header Auth configurada en WF-25-A/25-C. Cinco callbacks `pg_net` siguen apuntando a Cloud (ver §11/13). |
| `META_APP_SECRET` | App Secret para HMAC `x-hub-signature-256` | Presente en Supabase Edge Secrets; `meta-ingress` activa aplica HMAC fail-closed (ver §13). |
| `N8N_RUNTIME_PASSWORD` | Password aleatorio del rol PG dedicado (ver §10; entregarlo sin mostrarlo, nunca en esta nota ni en chat) | En Vault desde 2026-09-28 (§11); **importado a credenciales cifradas n8n el 2026-09-28** (ver delta al final) |
| `OPENWA_API_KEY` / `OPENWA_BASE_URL` | **RETIRADOS** — ya no usamos OpenWA (ver §7) | No generar ni pedir |

## 3. Decisión: OpenWA retirado, WF-80 Meta-only

- El usuario indicó que **ya no se usa OpenWA**: no se generan ni piden `OPENWA_API_KEY` / `OPENWA_BASE_URL`.
- `03-n8n/workflows.md` §5.4 (OpenWA) y §6 (compatibilidad OpenWA+Meta) quedan históricos y **deben revisarse antes de cualquier implementación**.
- **WF-80 debe quedar Meta-only**: todo envío de mensajes sale exclusivamente por Meta Cloud API vía WF-80 (política D11 intacta). No introducir adaptador OpenWA ni mantener ramas duales.

## 4. Variables `$vars` en Community: plan adoptado

- Las variables personalizadas `$vars` de n8n **no están disponibles en Community** (requieren plan Business/Enterprise self-hosted o Pro/Enterprise Cloud, según docs oficiales de n8n). Los 18 workflows importados referencian `$vars.*` que **no resolverán** en local.
- Plan:
  1. **API tokens** (Supabase, Meta, Gemini) → **credenciales n8n** (cifradas en reposo con la clave de la instancia). Nunca en claro en nodos ni exportaciones.
  2. **Tokens entrantes** (`LISTA_ESPERA_TOKEN`, `ENTREGA_TOKEN`, `META_VERIFY_TOKEN`) → nodo **Crypto (Hash SHA-256, HEX)** sobre el valor recibido + comparación contra el digest esperado. El digest SHA-256 de un token realmente aleatorio de 256 bits puede guardarse como comparación **no secreta** en el workflow; no se afirma que las expressions n8n puedan leer credenciales para comparar. Método sujeto a probar el nodo Crypto en staging; si no resulta viable, queda registrado como pendiente de resolver (ver §9.6). El valor en claro no queda en el flujo ni en exportaciones. Solo tiene sentido con valores de alta entropía y tras revisar el nodo Crypto (ver §9.6).

## 5. Rotación segura (tokens expuestos en comentarios SQL)

- Los valores que constaban en comentarios de las migraciones 26/30 deben considerarse **expuestos**: hay que generar tokens nuevos aleatorios de alta entropía.
- La **fuente de verdad** del valor vigente es doble y debe cambiar de forma coordinada: (a) cuerpo `pg_net` en la BD (requiere migración SQL aplicada con aprobación explícita — **no hacerla ahora**); (b) comparación del digest SHA-256 en el workflow n8n. El digest de un token aleatorio de 256 bits no es el token reutilizable.
- Procedimiento de rotación (cuando se apruebe): generar local (`openssl rand -hex 32`) → aplicar migración que sustituya el literal en el cuerpo de la función → cargar el SHA-256 en n8n → probar webhook en staging/inactivo → recién entonces activar.
- Actualizar triggers/pg_net significa exclusivamente esa migración puntual; no se toca lógica de negocio.

## 5bis. Supabase Vault como fuente cifrada (propuesta, sin aplicar)

- Para que los tokens internos usados por triggers `pg_net` no vivan como literales en cuerpos SQL, se propone **Supabase Vault** ([doc oficial](https://supabase.com/docs/guides/database/vault)) como fuente de verdad cifrada: secretos con nombre único (`vault.create_secret`), lectura solo vía vista `vault.decrypted_secrets`, con **permisos mínimos** (revocar acceso por defecto y conceder `SELECT` únicamente a los roles/funciones que disparan los webhooks).
- Migración coordinada pendiente (con aprobación explícita, fuera de este pase): crear secretos → cambiar cuerpos `pg_net` a leer de Vault → rotar valores → actualizar hashes n8n. **No se aplica nada aquí ni se edita SQL ejecutable.**
- Nota: cambia el modelo de actualización (ya no es “editar un literal”), pero mantiene la regla de coordinación BD+n8n.

## 6. Contradicción GEMINI_API_KEY vs arquitectura OpenAI

- `workflows.md` §5.2 documenta credencial OpenAI/GPT-4o, pero la implementación real de WF-22 usa **Google Gemini** (Matriz Aud-H-14: “extractor real Google Gemini”; Checklist E2E “OCR Gemini”; PROPUESTA-Verificacion-Hibrida con modelo `gemini-3.6-flash`; bitácora F3).
- **Acción:** generar `GEMINI_API_KEY` en Google AI Studio (no una key OpenAI) y corregir `workflows.md` §5.2 en una revisión documental separada (no se cambia en este pase).

## 7. Riesgos

1. **Privilegios runtime**: PostgreSQL usa el rol `postgres` (`rolbypassrls=true`) y REST usa `service_role` legacy. Ambos son demasiado amplios como identidad final de producción; definir sustitutos de privilegio mínimo y probarlos.
2. **Tokens legacy en cuerpos `pg_net`**: siguen siendo los valores vigentes en producción hasta la rotación coordinada.
3. **Trial/cloud vs local**: la guía original era trial→trial; el destino real es Community local (sin `$vars`, con PG propio). No seguir FASE 4/5 del checklist al pie de la letra sin adaptar.
4. **MCP n8n**: puede seguir apuntando a la cuenta vieja; re-autenticar antes de operar (Checklist FASE 6).
5. **`datos-conexion.md` es privado y git-ignored**; recarga la nota en Obsidian antes de llenarla para ver los últimos cambios.

## 8. Pruebas necesarias (todo inactivo, sin tráfico real)

1. `fn_verificar_guards_sanos()` en Supabase (solo lectura).
2. Importación: 18 workflows presentes e inactivos, owner configurado, `2.40.7` en n8n + runners.
3. Credenciales recreadas (nombres/tipos, sin exponer valores) + Crypto SHA-256 de prueba (hash conocido, comparar).
4. Webhooks internos con token de prueba en staging: WF-13 y WF-25 responden 401/403 ante token incorrecto y procesan ante hash correcto (sin activar).
5. Meta GET challenge contra endpoint de staging con `META_VERIFY_TOKEN` de prueba.
6. E2E completo solo tras rotación coordinada + aprobación explícita (Checklist FASE 5 adaptada).
7. Vault (si se adopta §5bis): secretos con nombre único creados; `decrypted_secrets` legible solo por roles mínimos (verificar grants); triggers leen de Vault.

## 10. Rol `n8n_runtime` + Vault + rotación dual — PREPARADO, nada aplicado (ver §11 para lo ya ejecutado en producción)

> Todo lo de esta sección era diseño previo a la aplicación. El estado real post-aplicación está en §11; lo no listado allí sigue PREPARADO.

> Todo lo de esta sección era el diseño previo a la aplicación del 2026-09-28. El estado real post-aplicación está en §11; lo no listado allí sigue PREPARADO. No activar workflows. No cambiar endpoints externos.

### 10.1 Rol dedicado (spec aprobada por Nico)
- Rol `n8n_runtime`: `LOGIN NOSUPERUSER NOBYPASSRLS`, password aleatorio de alta entropía generado localmente.
- Hoy n8n usa `postgres/BYPASSRLS` (Checklist FASE 1): **todo lo que dependa del bypass se romperá al cambiar**, por eso las políticas dirigidas van primero.
- Grants mínimos: `CONNECT` a la BD, `USAGE` en schema `rsuelvo`, `SELECT` en 7 tablas (allowlist nominal pendiente de inventario), `INSERT` en 2 tablas, `EXECUTE` en 11 RPCs. Nada más. Sin writes fuera de esas tablas, sin DDL, sin `SET ROLE`.

### 10.2 RLS dirigidas + frontera explícita cross-tenant
- Nuevas policies `... TO n8n_runtime` **solo** en esas tablas. No tocar policies existentes.
- **Frontera de confianza (explícita):** la lectura de esos 7 recursos es transversal a comercios **por diseño**, porque los consumidores son workflows de sistema (lista/entrega/notificaciones), no usuarios tenant. Aceptable únicamente porque: (a) el llamante es backend server-side confiable, no un JWT de usuario; (b) alcance cerrado a tablas/operaciones nombradas; (c) sin SELECT amplio; (d) trazabilidad en logs existentes. Toda tabla nueva requiere entrada explícita en la allowlist.
- Sutileza crítica: las funciones `SECURITY DEFINER` ejecutan como owner y los cuerpos `pg_net` corren en contexto BD — las policies dirigidas gobiernan el acceso **directo** de `n8n_runtime` (nodos PostgREST/Postgres), no los internos del definer.
- **Riesgo JWT-nulo:** por conexión PG directa, `auth.jwt()` es NULL; cualquier RPC de las 11 que derive tenancy de `auth.uid()` **no atribuirá**. Gate obligatorio: veredicto por RPC (deny-by-default sin JWT, o parámetro tenant explícito desde llamante confiable) antes de conceder `EXECUTE`. Ver lección P0 (`fn_es_service_role`, mig 76/87).

### 10.3 Vault como fuente de verdad (aprobado, sin aplicar)
- Secretos nombrados para: token legacy (transición), token nuevo Bearer, password de `n8n_runtime`.
- Permisos mínimos: revocar por defecto en `vault.decrypted_secrets`; conceder `SELECT` solo a los roles/funciones que disparan `pg_net`. Verificar la ruta owner/definer **antes** de aplicar ([doc oficial](https://supabase.com/docs/guides/database/vault)).
- Entrega del password **sin mostrarlo**: el owner lo genera → `vault.create_secret` → lo lee una vez en sesión supervisada → lo pega **directo** en la UI de n8n Credentials. Nunca en chat, nota privada ni vault. Pendiente definir quién/cuándo.

### 10.4 Rotación dual compatible (transición)
- Hoy: `pg_net` llama al hostname viejo de n8n Cloud con token legacy en el body.
- Transición: conservar token legacy en body (leído de Vault) **+ agregar** `Authorization: Bearer <nuevo>` (de Vault). En n8n local, credenciales **Header Auth** + validación con lógica **OR** (hash legacy **o** hash nuevo) en nodos Crypto. Esto exige editar nodos de validación (workflows inactivos; edición pendiente, no desde este documento).
- **No eliminar ni revocar el legacy** hasta: hostname público de VPS existente → `pg_net` apuntado al VPS → cutover verificado → recién entonces quitar legacy (migración + nodos en AND/nuevo-solo).
- **Jamás apuntar `pg_net` a localhost**: `pg_net` ejecuta desde la red de Supabase Cloud; localhost sería el propio host de la BD. El VPS debe tener hostname/IP **pública** primero (aún no localizado: bloquea el cutover, no la preparación).

### 10.5 Secuencia, validación sin side effects, rollback/cutover, gates
- Secuencia: (1) inventario nominal 7/2/11 desde Matriz + auditoría de nodos (fuente, no invención); (2) veredicto JWT-nulo por RPC; (3) redactar migración (rol+grants+policies, Vault en cuerpos `pg_net`, dual headers); (4) revisión + **aprobación explícita**; (5) aplicar en ventana acordada; (6) Header Auth + validación OR en n8n (inactivo); (7) `guards_sanos` + sondas solo-lectura como `n8n_runtime`; (8) cutover de URLs; (9) verificación; (10) retiro de legacy.
- Validación sin side effects: todo en lectura o en inactivo; negativas 401/403; cero efectos de negocio; cero activaciones.
- Rollback: hoy no hay nada que revertir. Post-apply, la migración debe llevar su reversa guionada (drop policies/grants/rol; restaurar literales `pg_net`). Rollback de cutover solo viable si la cuenta vieja sigue viva (riesgo trial — ver §7).
- Gates: aprobación explícita del dueño; validación en staging o todo-inactivo; hostname VPS; capacidad trial/VPS; MCP re-autenticado; sin tráfico productivo durante el cambio.

### 10.6 Tabla PREPARADO vs APLICADO (estado al 2026-09-28; detalle en §11)
| Elemento | Estado |
|---|---|
| Rol `n8n_runtime`, grants, policies dirigidas | **YA APLICADO** (migración `20260928153340`, §11) |
| Secretos Vault (legacy/nuevo/password) | **YA APLICADO** (5 entradas nombradas, §11; sin valores aquí) |
| Dual-token en `pg_net` + Bearer | **YA APLICADO** (5 callbacks, hostname conservado) |
| Header Auth n8n + validación OR | **YA APLICADO parcial**: WF-13, WF-25-A, WF-25-C con Header Auth (auditoría 18/18, cero diffs, cero activos); queda 1 referencia `META_VERIFY_TOKEN` |
| `META_VERIFY_TOKEN` última referencia | PENDIENTE (no bloquea lo ya importado) |
| Hostname público VPS | PENDIENTE (bloquea cutover, no preparación) |
| Importar password/tokens a credenciales cifradas | **YA APLICADO 2026-09-28** (3 secretos Vault; ver delta al final) |
| **Solo documentos/health de lectura** | **APLICADO antes** (nada productivo tocado salvo la migración aprobada) |

## 11. Ejecución real en producción — YA APLICADO 2026-09-28

> Migración: `supabase/migrations/20260928153340_n8n_runtime_identity_vault_callbacks.sql` del repo `/home/nico/StudioProjects/BACKEND RSUELVO`. Aquí solo el estado verificable; el SQL nominal vive en ese archivo. Sin valores de secretos en este documento.

- **Aplicación exitosa.** El primer intento se revirtió completo al detectar formato distinto del delimitador de `pg_get_functiondef`; la migración corregida sí quedó aplicada.
- **Rol `n8n_runtime`:** `LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE`, `CONNECTION LIMIT 30`.
- **Grants directos:** `SELECT` en 7 tablas de negocio observadas; `INSERT` en `tbl_notificaciones_envio` y `tbl_logs_auditoria`; `SELECT` solo sobre `tbl_notificaciones_envio.id_envio` para `RETURNING`; `EXECUTE` en exactamente 11 funciones observadas; **10 políticas RLS dirigidas al rol**. (Nominal en el archivo de migración; no se listan tablas/funciones aquí para no duplicar fuente.)
- **5 callbacks `pg_net` actualizados:** ya no hay literales en las funciones; los tokens legacy del body se leen de Vault (compatibilidad) y cada callback incluye `Authorization: Bearer` con token nuevo también de Vault. **El hostname Cloud existente se conserva intencionalmente; ningún URL cambió.**
- **Vault (nombres, sin valores):** `rsuelvo_n8n_legacy_waitlist_body_token`, `rsuelvo_n8n_legacy_delivery_body_token`, `rsuelvo_n8n_waitlist_callback_token`, `rsuelvo_n8n_delivery_callback_token`, `rsuelvo_n8n_runtime_password`.
- **JWT-nulo RESUELTO para estas 11 RPC:** están `SECURITY DEFINER` propiedad de `postgres` y la guardia `fn_es_service_role()` (service si `auth.jwt` role es `service_role`; con JWT nulo acepta `current_user` postgres/service_role) se conserva dentro de ellas tras revisión. **Límite explícito conservado:** es una identidad backend transversal — puede leer 7 tablas completas y ejecutar estas 11 capacidades para cualquier comercio. La clave vive solo en el runtime privado de n8n; jamás en frontend/PostgREST.
- **Advisors post-migración:** `rls_enabled_no_policy` bajó 9→8 porque `tbl_notificaciones_envio` ya tiene políticas dirigidas; el resto de hallazgos relevantes son preexistentes (definer views, funciones `SECURITY DEFINER` expuestas, etc.). No se amplió nada en esta migración.
- **Pendiente (bloquea cutover/activación):** host persistente todavía no contratado; recepción E2E y auditoría n8n no certificadas. Los cinco callbacks `pg_net` conservan Cloud/dual-auth como rollback; los 18 workflows siguen INACTIVOS. El endpoint entrante Meta ya apunta a Community por `meta-ingress` (ver §13).

## 9. Guía por secreto (resumen operativo, sin valores)

### 9.1 Supabase REST (`SUPABASE_PROJECT_URL` + clave server)
- **Qué es / quién emite:** URL pública del proyecto (`https://<ref>.supabase.co`) y clave server-side; las emite Supabase al crear el proyecto. Portal: Dashboard → **Connect** (diálogo con URL y claves) o **Project Settings → API Keys** (pestaña Legacy para `anon`/`service_role`; pestaña nueva para `sb_publishable_*`/`sb_secret_*`). Fuente: [API keys](https://supabase.com/docs/guides/getting-started/api-keys), [migración a nuevas keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys).
- **Compatibilidad en pausa (importante):** las claves opacas nuevas `sb_secret_*` viajan en el header **`apikey`** y **nunca deben enviarse en `Authorization: Bearer`**. El credential `supabaseApi` built-in de nuestro n8n `2.40.7` envía la misma “Secret Key” en **ambos headers**, por lo que es incompatible con `sb_secret_*`. **Recomendación en pausa:** no cargar `sb_secret_*` en ese credential hasta (i) elegir HTTP genérico con `apikey` y probarlo en staging, o (ii) seleccionar explícitamente el JWT legacy `service_role` como temporal con máxima precaución (BYPASSRLS, alcance máximo, solo server-side, jamás frontend; deprecación anunciada fines 2026). Decisión pendiente, sin activar nada.
- **Dónde cargarlo (cuando se decida):** credencial n8n recreada por workflow (los imports la dejan vacía); `SUPABASE_PROJECT_URL` como host en cada credencial/nodo.

### 9.2 PostgreSQL Supabase (pooler)
- **Qué es / quién emite:** cadena del pooler Supavisor para conexiones persistentes. Portal: Dashboard → **Connect** (sección pooler): modo **SESSION = host `aws-[INDEX]-[REGION].pooler.supabase.com`, puerto `5432`**, usuario `postgres.<ref>`; contraseña la definida al crear el proyecto (Database settings); SSL `require` con CA del dashboard. El modo **transaction (`6543`) NO conviene para n8n persistente ni prepared statements**. Nunca registrar el password dentro de un DSN en docs. Fuente: [Connect to your database](https://supabase.com/docs/guides/database/connecting-to-postgres).
- **Dónde cargarlo:** credencial `Postgres account` por nodo (host/puerto/usuario/rol/base SSL). PG local del stack NO es este: solo estado interno de n8n.

### 9.3 Meta (`META_SYSTEM_TOKEN`, `META_APP_SECRET`)
- **System User token (proveedor):** Meta Business Settings → Users → System users → Add (Admin) → Assign assets (app + WABA) → Generate token con `whatsapp_business_messaging` (+ `business_management`, `whatsapp_business_management` según guía oficial). Se muestra una sola vez. Fuente: [Access Tokens Guide](https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens), [Get Started](https://developers.facebook.com/documentation/business-messaging/whatsapp/get-started).
- **App Secret (condicional según arquitectura):** App Dashboard → Settings → Basic → App Secret; se usa para HMAC `X-Hub-Signature-256` ([docs webhooks Meta](https://developers.secure.facebook.com/documentation/business-messaging/whatsapp/webhooks/create-webhook-endpoint)). `meta-ingress` valida HMAC de forma obligatoria desde la versión fail-closed desplegada; requiere mantenerse en Supabase Edge Secrets, no en n8n.
- **Dónde cargarlo:** `META_SYSTEM_TOKEN` en credencial n8n (header `Authorization: Bearer`) usada solo por WF-80 y nodos Meta; `META_APP_SECRET` **solo** a Supabase Edge Secrets si `meta-ingress` se conserva — no hace falta en ninguna credencial n8n normal.

### 9.4 Gemini (`GEMINI_API_KEY`, proveedor)
- **Qué es / quién emite:** clave de Google AI Studio (`aistudio.google.com` → API keys, atada a un Google Cloud project; con restricciones). **Nunca en cliente.** Fuente: [Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key), [quickstart](https://ai.google.dev/gemini-api/docs/quickstart).
- **Dónde cargarlo:** credencial del nodo HTTP/IA de WF-22. Pendiente: corregir `workflows.md` §5.2 (dice OpenAI).

### 9.5 Verify/internos (generados localmente, no por portal)
- `META_VERIFY_TOKEN`: cadena aleatoria local (`openssl rand -hex 32`); se pega en Meta App Dashboard → WhatsApp → Configuration → Verify token ([docs](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/create-webhook-endpoint)); en n8n solo su SHA-256.
- `LISTA_ESPERA_TOKEN` / `ENTREGA_TOKEN`: aleatorios locales de alta entropía; **no los emite ningún portal**. Activación = migración BD coordinada (§5) + SHA-256 en n8n. Tras adoptar Vault (§5bis), la fuente pasa a secretos nombrados.

## Actualización local — 2026-09-28

- n8n Community `2.40.7`, runners y Postgres interno están sanos; `/healthz` responde OK. El editor escucha solo en `127.0.0.1:5678`.
- Los 18 workflows esperados están importados y permanecen **inactivos**. Las 37/37 llamadas `Execute Workflow` resuelven; no quedan referencias OpenWA.
- `META_SYSTEM_TOKEN` y `GEMINI_API_KEY` están guardados como dos credenciales HTTP cifradas de n8n y asignados a WF-22/WF-80. Las comprobaciones GET documentadas abajo pasaron. Los secretos no aparecen en exports; no guardarlos ni copiarlos en esta nota.
- Verificación HTTP de solo lectura desde el contenedor n8n (2026-09-28): Meta Graph `/me` y `/me/permissions` respondieron 200; están concedidos `whatsapp_business_management` y `whatsapp_business_messaging`. Gemini `GET /v1beta/models/gemini-3.5-flash-lite` respondió 200 usando exactamente el header configurado. No se envió mensaje ni se generó OCR; no certifica todavía una llamada de producción ni que la app esté publicada.
- En Meta for Developers la app `Rsuelvo` aparece en modo **En desarrollo**. El portfolio empresarial abierto no muestra aplicaciones ni usuarios del sistema; aunque el token actual es válido y tiene los scopes requeridos, confirmar que su tipo/caducidad sea apto y revisar publicación/portfolio antes de producción.
- Pendientes: `META_VERIFY_TOKEN` (1 referencia), `LISTA_ESPERA_TOKEN` (1) y `ENTREGA_TOKEN` (2). OpenWA está retirado.
- La credencial REST de Supabase quedó cifrada en n8n con el `service_role` legacy que el nodo built-in admite. Un `GET /rest/v1/` respondió HTTP 200/OpenAPI; no se leyeron filas ni se hicieron escrituras. La `service_role` puede saltarse RLS y Supabase indica soporte legacy hasta fines de 2026; planear adaptación de las 40 referencias para enviar la nueva `sb_secret_*` solo como `apikey` antes de ese plazo.
- La exportación autoritativa del contenedor confirma 18/18 workflows por ID, sin diferencias en nodos ni conexiones respecto a `community-import/`; los 18 están inactivos. Las 40 referencias `supabaseApi` y las 25 referencias Postgres resuelven.
- No se hicieron escrituras de negocio ni cambios de esquema en Supabase. Se cargó la credencial Postgres sin rotar el password, y el pooler respondió a `select 1`. Mantener los workflows inactivos hasta terminar adaptación de tokens entrantes, revisar SQL y probar cada contrato en staging.
- Auditoría local n8n señala 25 nodos SQL sin Query Parameters y 92 nodos integrados marcados por categoría de riesgo. Revisarlos antes de activar, usando staging/datos sintéticos.
- El MCP de n8n todavía falla con `-32603`; la fuente operativa de workflows es el ZIP exportado y preparado en el host.
- Chromium se conectó por CDP local y las sesiones de Supabase/Meta están autenticadas. En Supabase se confirmó el proyecto productivo `RSUELVO` (`iwfaktlxebxtocmswdvv`) y el pooler de sesión. La credencial `Postgres account` quedó cifrada en n8n con el password vigente, que se retiró de la nota privada tras importarlo.
- No pulsar **Reset database password** sin coordinar el cambio con los otros clientes productivos: Supabase no vuelve a mostrar el password actual y resetearlo puede interrumpir conexiones.
- El panel Legacy API Keys sí permite revelar la clave `service_role`; se copió directamente al credential cifrado de n8n con ID/nombre que esperan los 40 nodos. No se escribió al vault ni a exports. `sb_secret_*` sigue siendo la migración futura: los 40 nodos deben usar únicamente `apikey` antes de que termine soporte legacy en 2026.
- JWT Keys muestra una signing key ECC actual y una legacy HS256 previa. No se modificó ni rotó la firma JWT del proyecto.
- `configure-postgres-credential.py` importó la credencial PostgreSQL cifrada. `audit-local-state.py` confirma 18/18 workflows iguales, 40 referencias REST y 25 referencias Postgres resueltas; quedan cuatro referencias a tres tokens entrantes.
- Prueba desde el propio contenedor n8n: export temporal cifrado en directorio efímero, conexión con el driver Node PostgreSQL incluido en n8n, consulta de solo lectura correcta, TLS cifrado y verificación de certificado activa. Se añadió la CA raíz de Supabase por `NODE_EXTRA_CA_CERTS` en Compose.
- Gate de producción detectado por catálogo (solo lectura): la credencial actual usa el rol gestionado `postgres` (`rolsuper=false`, `rolbypassrls=true`); nueve tablas de acceso directo tienen RLS habilitado y las 11 funciones usadas directamente por los workflows son `SECURITY DEFINER`. No dejar la credencial actual como identidad final de runtime. Definir rol y privilegios mínimos y validar en staging antes de cambiarlo; no se hicieron GRANTs ni cambios de función.

## Delta importación n8n + verificación sin efectos — 2026-09-28

- Los 3 secretos no públicos de Vault (password runtime + 2 callback tokens) importados directo a credenciales cifradas de la instancia local. PostgreSQL credential con usuario `n8n_runtime.iwfaktlxebxtocmswdvv` (Session pooler).
- Verificación sin efectos de negocio: TLS con validación estricta, `current_user=n8n_runtime`, NOBYPASSRLS, 8× `SELECT LIMIT 0`, metadata de 11 ACL `EXECUTE`; sin filas leídas ni funciones invocadas.
- WF-13, WF-25-A, WF-25-C con credencial HTTP Header Auth. Auditoría local final: 18/18 IDs, cero diffs contra community-import, cero activos, 37/37 llamadas internas, cero OpenWA, cero credenciales sin resolver; `supabaseApi=40`, `postgres=25`, `httpHeaderAuth=6`. Queda solo `META_VERIFY_TOKEN` (1 referencia).
- Gate JWT verificado: 11 RPC `SECURITY DEFINER` propiedad postgres; `fn_es_service_role()` admite `current_user=postgres` con `auth.jwt` nulo. Se mantiene la confianza transversal anotada en §11: clave solo en runtime privado n8n, jamás frontend/PostgREST.
- Sin activaciones; `pg_net` conserva hostname Cloud con legacy + Bearer hasta cutover verificado.

## 12. Objetivo operativo WhatsApp end-to-end — PENDIENTE

**Objetivo vigente:** dejar operativos en Community los flujos como lo hacían en Cloud: Meta inbound → n8n → Supabase → Meta outbound. No se ha activado ningún workflow ni enviado un WhatsApp real.

### Ruta confirmada en los JSON exportados

`WF-02 WhatsApp Meta Incoming` recibe el GET/POST en `/webhook/webhooks/whatsapp/meta`; procesa challenge GET (`META_VERIFY_TOKEN` aún pendiente en WF-02), registra/deduplica eventos y llama a `WF-03 Normalizer` → `WF-04 Conversational Router` → workflows de negocio. Las respuestas de texto/plantilla/media pasan por `WF-80 WhatsApp Gateway`, que en Community se actualizó de Meta Graph API v21.0 a **v26.0** (vigente el 2026-09-28) en `/v26.0/{phone_number_id}/messages`. La llamada `GET` de solo lectura al número de prueba en v26 respondió HTTP 200; WF-80 ya está publicado con v26, pero aún no se ha ejecutado la llamada de envío.

### Ingress público ya existente

Supabase lista `meta-ingress` como ACTIVE v4, `verify_jwt=false`. Su código implementa challenge GET y reenvío POST hacia `N8N_META_WEBHOOK_URL`, cuyo default es el n8n Cloud anterior. Un GET de prueba con token deliberadamente inválido devolvió 403: se confirma endpoint accesible y rechazo, **no** que los secretos reales estén completos ni que el challenge válido pase.

Gate de seguridad: la función solo valida `X-Hub-Signature-256` cuando `META_APP_SECRET` no está vacío; si falta, acepta POST sin HMAC. No cortar Meta hacia este ingress hasta confirmar secretos por el canal privado de configuración y desplegar/validar una variante fail-closed. El destino debe ser una URL pública HTTPS que Supabase pueda alcanzar (actual: `N8N_META_WEBHOOK_URL` → Community vía túnel, ver §13). No apuntar `N8N_META_WEBHOOK_URL` a localhost.

### Gates para producción

1. Hospedar Community en un endpoint público TLS con proxy, URL webhook correcta, restricciones de red y salud/observabilidad. Hostname actual: `https://n8n.rsuelvo.com` por túnel a escritorio (ver §13; sin alta disponibilidad). El hostname propio del VPS sigue pendiente.
2. `meta-ingress` ya conserva el verify token en Supabase Secrets y el challenge correcto fue validado. WF-02 no valida GET de Meta bajo esta arquitectura; no activar su trigger hasta cerrar staging/E2E.
3. HMAC fail-closed y destino Community están configurados; challenge y rechazo de POST sin firma pasaron. Falta firma positiva y fixture sin PII hacia WF-02 activo en staging.
4. Confirmar app Meta Live, WABA/`phone_number_id`, asociación, permisos y vigencia del token. Estado observado previamente: app en Development; token Graph respondía 200, pero tipo/caducidad y WABA no estaban verificados.
5. Mover los cinco callbacks `pg_net` de lista/entrega desde Cloud a Community solo en ventana coordinada después de activar y comprobar los workflows destino. Actualmente conservan Cloud + dual auth en Vault.
6. Revisar los 40 nodos Supabase REST que usan `service_role` y los 25 nodos PostgreSQL señalados por falta de Query Parameters. No activar en producción antes de resolver riesgos aplicables.
7. Certificar en staging con fixtures/datos sintéticos. Existe proyecto `RSUELVO-STAGING` activo, pero el inventario MCP mostró cero Edge Functions y no se ha hecho una prueba E2E de WhatsApp allí.
8. Hacer smoke primero con destinatario de prueba autorizado y ventana de cutover/rollback; habilitar subworkflows y WF-02 gradualmente. No realizar un envío real sin autorización explícita para esa prueba.

**Estado 2026-09-28:** endpoints externos sin cambio; cinco callbacks aún en Cloud; 18/18 Community inactivos. El GET inválido al ingress es la única sonda hecha aquí; no hubo POST, ejecución n8n, RPC ni mensaje enviado.

### Evidencia Meta añadida (lectura, 2026-09-28)

- Meta for Developers app `Rsuelvo` observada en modo Development. El formulario de Webhooks de la app muestra el campo de URL de callback vacío; no se guardó ni cambió.
- Token leído desde la credencial cifrada Meta, sin imprimirlo: Graph `/me`, `/me/permissions`, listado de WABA y números contestaron 200. Permisos concedidos observados: `business_management`, `whatsapp_business_management`, `whatsapp_business_messaging`, `public_profile`.
- Se enumeraron dos WABA: uno de pruebas y `Rsuelvo`. `/{WABA-ID}/subscribed_apps` devolvió cero apps para ambos. El número de pruebas aparece `GREEN` pero `NOT_VERIFIED`; el número `Rsuelvo` aparece `GREEN` con `code_verification_status=EXPIRED`. No se hizo POST de suscripción, verificación ni envío.
- Logs agregados Supabase 24h para `meta-ingress`: solo el GET inválido de esta revisión devolvió 403; no aparecen llamadas Meta entrantes durante la ventana. Esto concuerda con el callback vacío, pero no demuestra configuración histórica de n8n Cloud.
- Por tanto, antes de probar tráfico entrante real se necesita (corrección 2026-09-28: el número está CONNECTED/GREEN y no requiere verificación; `EXPIRED` es solo `code_verification_status`): establecer URL pública; configurar callback y campo `messages`; asociar/suscribir WABA a la app si el flujo de producción lo requiere; publicar la app según requisitos de Meta. Cambios externos siguen pendientes hasta que el endpoint de destino esté listo.


## 13. Estado de infraestructura y callback Meta — 2026-09-28 (parcial, sin E2E)

- El hostname `https://n8n.rsuelvo.com` se sirve por Cloudflare Tunnel `rsuelvo-n8n-community` hacia el servicio Compose local. `/healthz` público y TLS validan (HTTP 200); el editor responde con su login. **Este Docker corre en un ordenador de escritorio**, no en un host de producción administrado: depende de alimentación, red y arranque del equipo. No se considera alta disponibilidad ni producción robusta.
- La Edge Function productiva `meta-ingress` está activa con código fail-closed. Valida HMAC como requisito fail-closed (`META_APP_SECRET` ausente → 503; firma ausente/incorrecta → 401), responde solo al challenge con `META_VERIFY_TOKEN` correcto y reenvía eventos a `N8N_META_WEBHOOK_URL`. Se configuró este destino a `https://n8n.rsuelvo.com/webhook/webhooks/whatsapp/meta`. La rotación del verify token se efectuó por Supabase Secrets; el challenge con valor correcto respondió exactamente el challenge (HTTP 200). No se registran valores secretos en Obsidian.
- Meta Developer aceptó/guardó la callback `https://iwfaktlxebxtocmswdvv.supabase.co/functions/v1/meta-ingress`; el objeto `Whatsapp Business Account` muestra el campo `messages` suscrito. Esto configura la callback de la aplicación, **pero no suscribe ninguna WABA**. Se confirmó que la WABA de pruebas (`Test WhatsApp Business Account`) y la WABA `Rsuelvo` no tenían apps suscritas antes del cambio. No se ha ejecutado el POST Graph `/{WABA}/subscribed_apps`.
- Seguridad/alcance comprobados: callback inválido GET → 403; challenge válido → 200; POST de fixture sin HMAC → 401; GET público de n8n al webhook → 404 mientras WF-02 está inactivo. El evento firmado positivo todavía no se ha probado ni se ha recibido evento de WhatsApp.
- **Sin cutover de ejecución:** 18/18 workflows continúan inactivos; los cinco callbacks `pg_net` mantienen el hostname Cloud para preservar el flujo existente; ninguna WABA fue suscrita; no se enviaron mensajes. No activar ni suscribir hasta tener un receptor operativo.
- Meta App sigue en Development. Lecturas históricas: número de prueba `NOT_VERIFIED`; número productivo con `code_verification_status=EXPIRED` (corrección 2026-09-28: CONNECTED/GREEN, sin necesidad de verificación). Confirmar el recipient de prueba antes de validar mensajería.

### Gates pendientes para E2E
1. Mover el Compose a un VPS/host siempre activo con reinicio supervisado, backups, actualizaciones y monitoreo; validar tunnel tras reboot. El endpoint público actual demuestra conectividad, no disponibilidad de producción.
2. Completar revisión de seguridad n8n; particularmente 40 nodos REST con `service_role` legacy y 25 nodos SQL sin parámetros detectados en la auditoría. No activar workflows con las observaciones abiertas sin criterio de mitigación.
3. En staging con secretos de prueba y datos sintéticos: probar callback firmado y entrega al webhook, disparar WF-02 con fixture, comprobar normalización/routing/idempotencia/Supabase, y salida Graph solo a número explícitamente allowlisted. El staging no tiene aún Edge Functions y n8n-imported workflows no están certificados E2E.
4. Acordar ventana y dueño del corte. En orden: respaldar estado actual; validar subworkflows y WF-80 aislados; publicar/activar dependencias internas; activar WF-02; confirmar evento firmado y escritura de negocio; solo entonces suscribir WABA de prueba y validar ida/vuelta; actualizar cinco `pg_net` a Community tras comprobar callbacks y rollback; pasar a producción únicamente con app publicada (URL real de Política de Privacidad). (Corrección 2026-09-28: el número no requiere verificación.)
5. No mover `pg_net` ni suscribir WABA mientras los endpoints n8n respondan 404. Si el host local se apaga, Supabase/Meta no podrán entregar a n8n; cloudflared no sustituye alojamiento persistente.


## 14. Prueba de configuración Community sobre staging — 2026-09-28 (sin E2E)

- PostgreSQL `n8n_runtime` conecta a RSUELVO-STAGING mediante TLS. Verificación directa: lectura de `rsuelvo.tbl_canal_whatsapp` permitida; lectura de `rsuelvo.tbl_logs_auditoria` denegada.
- Se preparó una API key dedicada solo a staging y se importaron 18 workflows con referencias Supabase reescritas al proyecto staging. La importación reemplazó las credenciales Supabase/Postgres locales por las de staging. No usar ese n8n local como producción mientras permanezca así.
- WF-02 apunta a staging, usa Header Auth con `X-RSUELVO-META-INGRESS` y escucha POST explícitamente. (Superseded: al inicio era el único publicado; tras la enmienda sintética hay 12 dependencias internas publicadas y solo WF-13/25-A/25-C siguen inactivos.) La URL pública rechaza una petición POST sin credencial con 403. Las referencias al project id de producción se eliminaron de los JSON importados.
- La prueba Meta del campo `messages` abrió el modal de muestra, pero el botón final `Enviar a servidor` estaba deshabilitado (`aria-disabled=true`). No hubo petición al callback, ejecución de n8n, escritura en staging ni envío WhatsApp. Esta es una prueba negativa de autenticación más preparación de configuración, **no una E2E positiva**.
- El callback público de Meta sigue siendo `meta-ingress` productivo y su destino configurado es el endpoint Community que ahora usa configuración de staging. No hay WABA suscritas según la revisión previa; no debe suscribirse una ni aceptar tráfico de negocio mientras el receptor apunte a staging. Los cinco `pg_net` productivos aún apuntan a Cloud.
- Para continuar: ~~habilitar una vía de fixture positivo Meta (resolver el botón Test deshabilitado o crear ingress aislado en staging)~~ HECHO en staging vía `meta-ingress-qa` (ver enmienda HMAC; el botón Test de Meta sigue deshabilitado y no se usó); inspeccionar ejecuciones/RPCs; completar pruebas de WF-03/04/80 en staging. La prueba outbound debe limitarse a un número de prueba allowlisted y requiere aprobación del dueño. Antes de go-live, restaurar/introducir credenciales productivas con control, publicar en host siempre activo y hacer corte coordinado de `pg_net` con rollback. App Meta sigue en Development (motivo actual sin datos de producción: solo webhooks de prueba); el número está CONNECTED/GREEN — `EXPIRED` es solo `code_verification_status` y no bloquea recepción (corrección 2026-09-28).

### Enmienda 2026-09-28 — procesamiento funcional sintético en Community/staging

Esta evidencia posterior supersede en §14 las frases que afirmaban que no hubo ejecución ni escrituras. No equivale a WhatsApp E2E con Meta ni a go-live.

- n8n Community 2.40.7 ejecutó el evento sintético `wamid.codex.qa.f052511b9ca348b7a5ded1ead20a1653` a través de WF-02 → WF-03 → WF-04 → WF-10 → WF-20 → WF-80. Se observaron seis ejecuciones consecutivas exitosas (IDs locales 34–39); WF-80 terminó en `Blocked Result` deliberadamente.
- Consulta de staging confirmó el evento `PROCESADO`, un cliente QA con teléfono inválido `0000000000`, una reserva, un pedido y un QR asociado. `tbl_canal_whatsapp.activo=false` quedó confirmado. El teléfono QA no es un destinatario y se usa para que la guarda impida la llamada a Meta Graph.
- WF-02 requiere el método GET/POST explícito y el mapeo GET → Verify Token / POST → Acknowledge POST. Los workflows internos llamados por `executeWorkflow` deben estar publicados en esta versión de Community; se publicaron 12 dependencias internas. Los webhooks externos WF-13, WF-25-A y WF-25-C siguen inactivos.
- En staging, WF-04 ahora resuelve clientes por RPC `fn_resolver_cliente_id_para_router`; la función aditiva equivalente también está en migración versionada aplicada a producción. El RPC devuelve una fila con id nulo cuando no encuentra al cliente, evitando que la búsqueda PostgREST de cero filas detenga la ruta genérica.
- Se concedió ACL de `service_role` solo en RSUELVO-STAGING para alinear el uso PostgREST de los exports; la concesión está documentada fuera de las migraciones productivas en `supabase/staging/20260928_service_role_acl_parity.sql`. No trasladar esa paridad de privilegios como un grant amplio de producción.
- WF-80 en staging valida el teléfono E.164 normalizado antes de Graph; el destino inválido se registra y retorna como bloqueado. En la ejecución se comprobó que el nodo `Send via Meta Graph API` no corrió: **cero mensajes salieron**.
- La primera prueba (§14 base) inyectó directamente al webhook de n8n con Header Auth; no atravesó Meta ni HMAC. La enmienda siguiente añade HMAC positivo con una Edge clon independiente en staging. Ninguna prueba llamó Graph, recibió un evento real de Meta, actualizó callbacks pg_net ni validó la continuidad del host.
- Estado real en la prueba base: cadena sintética directa hasta el guard del gateway. El HMAC aislado de staging y su puente Edge→Community, con el canal activado temporalmente, se validan en la enmienda siguiente. Aún faltan la firma/callback real de Meta, outbound Graph a un número test allowlisted, y alojamiento persistente antes de producción. App Meta está Development; número de producción CONNECTED/GREEN (`EXPIRED` es solo `code_verification_status` — corrección 2026-09-28); cinco callbacks productivos conservan destino Cloud y ninguna WABA está suscrita.

### Enmienda 2026-09-28 — firma HMAC positiva en ingress aislado de staging

- Se desplegó en RSUELVO-STAGING un clon temporal `meta-ingress-qa` del código Edge productivo v9 (mismo SHA-256 de artefacto, `e5bdcac16268a200f8be23e5a1994d4aee8c5cb1aae1fd145c505f9188f0ead7`) y tres secrets **de staging solamente**: clave HMAC aleatoria QA, el Header Auth que usa WF-02 y el callback HTTPS Community. No se copió ni se leyó el `META_APP_SECRET` productivo. La callback Meta externa sigue apuntando a su Edge Function productiva, no a `meta-ingress-qa`.
- Evidencia Edge: un POST unsigned recibió 401; un fixture WhatsApp sintético con firma SHA-256 correcta recibió 200 `forwarded:true`. n8n creó ejecuciones 43–46 para WF-02/03/04/80; todas terminaron success. El registro quedó `PROCESADO` en `tbl_whatsapp_eventos`.
- El canal de Meta QA de staging se activó solo durante esta corrida para que WF-04 resolviera el comercio; el `phone` QA siguió siendo `0000000000`, y WF-80 llegó a `Blocked Result` antes de `Send via Meta Graph API`. Luego se restauró `activo=false`, `status='DESCONECTADO'`. No hubo llamada Graph ni mensaje real.
- Una primera firma válida, con ese canal todavía inactivo, se detuvo en WF-04 sin resolver comercio; el evento sintético se cerró como `ERROR` anotando la causa. La segunda corrida valida el caso con canal activo en staging.
- Esto prueba la implementación HMAC fail-closed y el puente Edge→Community en un ingress de prueba, **no** que Meta firme el payload con la clave real, ni que el callback productivo/WABA esté entregando. Sigue pendiente el test positivo firmado por Meta (o verificar el secreto mediante reautenticación), número allowlisted para outbound real (el número no requiere verificación: CONNECTED/GREEN — corrección 2026-09-28) y outbound real. La reautenticación de la pestaña Meta aún solicita la contraseña del titular; no se eludió ni se guardó su contraseña.

### Enmienda 2026-09-28 — resolver productivo y Graph v26 validados en staging

- Meta Graph `/v26.0/{phone_number_id}` respondió HTTP 200 en lectura para el número de producción: `quality_rating=GREEN`, `code_verification_status=EXPIRED`. Para el número test respondió HTTP 200 con `NOT_VERIFIED`. No se hizo llamada `POST /messages`.
- Hallazgo que impedía tráfico de producción: había 11 filas Meta con el mismo production `phone_number_id`; una tenía `status='ACTIVO'` y diez `status='DESCONECTADO'`, todas con `activo=true`. La RPC anterior contaba los diez desconectados como candidatos y devolvía cero filas por ambigüedad, dejando el mensaje atascado en WF-04.
- Migración productiva aditiva `20260928191100_fn_identificar_comercio_por_phone_number_id_status.sql` actualiza `fn_identificar_comercio_por_phone_number_id` para filtrar `provider='META'`, `activo=true`, `status='ACTIVO'`, comercio `ACTIVO`, y devolver resultado solo si existe una coincidencia única. El resultado probado para el ID productivo es comercio `FER` (`Prueba RSUELVO`). La corrección **no modifica las diez filas desconectadas**.
- Migración `20260928191200_restrict_meta_phone_resolver_execute.sql` revoca EXECUTE a `PUBLIC`, `anon` y `authenticated`; conserva `service_role` y `n8n_runtime`. Verificado: service_role y runtime pueden ejecutar; anon/authenticated, no.
- Las mismas dos migraciones se aplicaron a staging. Tras la actualización del workflow WF-80 a Graph v26 y reinicio de Community, fixture HMAC sintético a `meta-ingress-qa` → WF-02/03/04/80 (ejecuciones 51–54), evento `PROCESADO`, final `Blocked Result`. WF-04 completó la rama de ayuda para teléfono QA desconocido; WF-80 no ejecutó Graph. El canal staging se puso temporalmente `activo=true,status='ACTIVO'` y se restauró a `activo=false,status='DESCONECTADO'`.
- El callback real de Meta todavía no se probó positivamente. El diálogo Meta sigue pidiendo reautenticación al titular para mostrar el App Secret; la app está Sin publicar (motivo actual sin datos de producción: solo webhooks de prueba). El número está CONNECTED/GREEN y no requiere verificación (corrección 2026-09-28). No hay outbound real ni go-live.

### Enmienda 2026-09-28 — System User token Meta y separación de porfolios

- Desde el porfolio propietario de la app (`1205606568449109`) se generó un token de System User `Employee` para la app `Rsuelvo`, expiración 60 días (renovar antes del 2026-11-27). Meta requirió `business_management` (opción obligatoria/deshabilitada para quitar) junto con `whatsapp_business_management` y `whatsapp_business_messaging`. El token sustituyó el valor de la credencial cifrada n8n existente `RSUELVO Meta System Token`; no se registró en esta nota ni en logs.
- Verificación Graph v26 de solo lectura con esa credencial: `GET /1275143265687773` respondió 200 (verified name `Rsuelvo`, quality `GREEN`), pero `code_verification_status=EXPIRED`. `GET /1419722976749006?fields=id,name` y `/1419722976749006/phone_numbers` responden 200; la lista incluye el número productivo. No se llamó `POST /messages`.
- La WABA productiva correcta es `1419722976749006`, propiedad del porfolio de la app `1205606568449109`. La WABA test `1531958188699437` incluye el número de test `1253039534563144`. La WABA `954119647743429` de otro porfolio no contiene este número y su lectura devuelve code 100/subcode 33; no es el activo productivo de esta integración. `GET /1419722976749006/subscribed_apps` sin filtro confirma que la app `1684521105947630` ya está suscrita; la WABA test `1531958188699437` está suscrita a otra app (`2202427980234937`). La consulta previa con `fields=id,name` ocultó el objeto anidado y no sirve para verificar.
- No se cambió propiedad/permiso de activos, callbacks ni suscripciones. Community `/webhook/webhooks/whatsapp/meta` y `/webhook/whatsapp/meta` devuelven 404 en la URL pública consultada; WF-02 está publicado pero inactivo. No activar mientras apunte a staging. Los hosts Cloud históricos consultados también devuelven 404, por lo que no hay rollback HTTP verificado. Próximo gate: establecer un receptor de producción seguro/persistente, recibir evento firmado real y hacer E2E controlada. (El número no requiere verificación: CONNECTED/GREEN — corrección 2026-09-28.) App sigue en Development; 5 callbacks `pg_net` aún en Cloud y n8n Community apunta a staging. Sin tráfico real, outbound, ni go-live.


### Corrección 2026-09-28 — suscripción existente y endpoint actualmente 404

La consulta Graph correcta no especifica `fields`: `GET /1419722976749006/subscribed_apps` devuelve app `1684521105947630` (`Rsuelvo`). La WABA test `1531958188699437` devuelve la app `2202427980234937` (otra app). Un intento anterior con `fields=id,name` dio `data:[]` por el formato anidado y fue una lectura engañosa; no se modificó ninguna suscripción. La URL pública Community probada con GET sin query retorna 404 porque WF-02 está inactivo. Se observaron también 404 en los dos paths históricos en los tres hostnames n8n Cloud documentados; no se presume operativo el rollback. Como los workflows locales aún apuntan a staging, mantenerlos inactivos y no exponer tráfico de producción hasta disponer de receptor persistente correctamente configurado. Nota histórica: el campo `code_verification_status` seguía `EXPIRED` (corrección 2026-09-28: CONNECTED/GREEN, sin necesidad de verificación).


## Enmienda autoritativa 2026-09-28 — estado live Community y barrera de seguridad

Esta enmienda reemplaza afirmaciones anteriores de esta nota que indiquen que la instancia n8n Community activa ya utiliza credenciales de producción, que WF-02 permanece publicado, o que la WABA productiva no tiene app suscrita.

- Inspección segura del almacenamiento cifrado activo en n8n: la credencial `Supabase account` apunta al host staging `gfacgwgyqebjadcrltcw.supabase.co` (GET REST 200 allí; 401 en producción `iwfaktlxebxtocmswdvv.supabase.co`). La credencial `Postgres account` apunta a pooler/user de staging `gfacgwgyqebjadcrltcw`. El rol de producción `n8n_runtime` y su secreto Vault fueron preparados/aplicados previamente, pero **no son** la identidad de `Postgres account` activa en esta instancia. No se imprimieron claves ni contraseñas.
- WF-02 fue despublicado el 2026-09-28 y n8n reiniciado. El POST público al webhook Community ahora responde 404; healthz sigue 200. Se hizo para evitar que el endpoint Meta productivo escriba accidentalmente en staging. Los workflows de negocio externos WF-13/WF-25-A/WF-25-C continúan inactivos; 12 workflows internos permanecen publicados como dependencias de `executeWorkflow`.
- La aplicación Meta `1684521105947630` ya está suscrita a la WABA productiva `1419722976749006` (Graph v26 `GET /subscribed_apps` sin filtro). El resultado previo vacío con `fields=id,name` era engañoso y queda supersedido.
- Hecho histórico: se solicitó `request_code` por SMS para el número productivo (HTTP 200); el estado observado después permanecía `EXPIRED`. Verificación posterior 2026-09-28: el SMS fue innecesario — el número está CONNECTED/GREEN (`EXPIRED` es solo `code_verification_status`) y no requiere verificación; no pedir ni guardar códigos. No se envió mensaje outbound ni se confirmó inbound real.
- Evidencia existente: fixture sintético firmado con HMAC QA en el Edge `meta-ingress-qa` de staging recorrió WF-02/03/04/80 y terminó antes de Graph. Esto no verifica firma real de Meta ni WhatsApp E2E productivo.
- La instancia corre en escritorio vía Cloudflare Tunnel. La cuenta Cloudflare está en plan Free, sin método de pago; el runbook backend no acredita host VPS contratado/provisionado. No hay actualmente receptor de producción durable certificado. Los callbacks `pg_net` productivos se cambiaron antes a dual-auth/Community, pero la ruta entrante se mantiene cerrada hasta resolver este gate.
- Se intentó documentar esta transición desde la sesión OpenCode orquestadora `ses_f16da631affeR20xWIHtBQBdPE` en Rsuelvo-CLEAN; la llamada vuelve a `Unexpected server error` (ref `err_798d2ef7`). Este apunte se aplicó manualmente; no se atribuye el cambio a OpenCode.


## Estado autoritativo tras el cutover Community — 2026-09-28

Esta sección supersede las notas anteriores que reportaban credenciales activas en staging, workflows apagados o callbacks aún dirigidos a Cloud.

- `Supabase account` del n8n Community ahora apunta a producción `iwfaktlxebxtocmswdvv`; se cargó directamente desde Chromium autenticado la legacy `service_role`, comprobada con GET REST 200 y guardada solo en el almacén cifrado n8n. No incluir el valor en notas. Esta clave bypass-RLS sigue siendo una compatibilidad temporal de privilegio alto para los 40 nodos REST.
- `Postgres account` ahora está realmente en producción con `n8n_runtime.iwfaktlxebxtocmswdvv`, pooler Session `aws-0-us-west-2`, TLS con CA estricta. Comprobado `current_user`, `NOBYPASSRLS`, 8 permisos de lectura sin filas y 11 EXECUTE ACL.
- Se actualizaron 43 referencias a proyecto Supabase en los 18 workflows (40 URLs + 3 expresiones de URL para QR/OCR). `community-import/` se sincronizó con los nodos/conexiones vigentes y queda inactivo por defecto. Auditoría actual verde: 0 diferencias de nodo/conexión, 0 staging refs, 0 credenciales sin resolver, 0 llamadas internas faltantes, 0 OpenWA.
- Nueva migración versionada y aplicada: `supabase/migrations/20260928202937_n8n_community_public_callback_cutover.sql`. Los cinco callbacks `pg_net` apuntan a `https://n8n.rsuelvo.com`, con paths originales, header Bearer desde Vault y body legacy temporal conservados. Post-migración, las cinco funciones reportan host `n8n.rsuelvo.com` y tokens correctos por Vault.
- Publicados 16 workflows: 12 dependencias internas y webhooks WF-02, WF-13, WF-25-A, WF-25-C. QA-IAM10 y duplicado inactivo 25-B permanecen apagados. POST público a cada endpoint sin autenticación recibe 403; salud pública n8n 200. No se ejecutó ningún POST autenticado de negocio.
- Meta: `Rsuelvo` ya está suscrita a la WABA productiva correcta. El canal está CONNECTED/GREEN (`EXPIRED` es solo `code_verification_status`; no requiere verificación — corrección 2026-09-28). Para mostrar `App Secret`, Meta solicita reintroducir la contraseña del titular en la pestaña Chromium actualmente abierta; no pegar contraseña/código en el chat. Sin evento real firmado ni outbound Graph.
- Alojamiento actual: desktop + Cloudflare Tunnel (TLS y endpoint sano); no existe VPS productiva aprovisionada y Cloudflare sigue plan Free. El túnel público opera mientras la computadora y conexión están disponibles, pero no proporciona continuidad de producción.
- OpenCode no respondió después de varios intentos, último `Unexpected server error` ref `err_798d2ef7`; el registro se actualizó manualmente.


### Prueba HMAC productiva sintética — 2026-09-28

- Para no revelar `META_APP_SECRET`, se desplegó temporalmente `meta-ingress-smoke-once` con `verify_jwt=true` y autorización adicional por claim `role=service_role`. Generó dentro de Edge una firma HMAC-SHA256 usando el App Secret productivo y envió a `meta-ingress` un callback sintético de estado `failed` (no un mensaje entrante).
- Edge `meta-ingress` aceptó la firma, devolvió HTTP 200 `forwarded:true` y reenvío a Community. n8n registró exactamente 1 ejecución exitosa del workflow WF-02. En los diez minutos revisados, no se ejecutaron WF-03/WF-80 ni otros workflows. El grafo de WF-02 dirige `type=status` a `Status ACK1` y termina antes de RPC/eventos de negocio; por ello no se enviaron mensajes Meta ni se modificaron datos de ventas.
- La función temporal fue retirada mediante Management API (DELETE HTTP 200); `list_edge_functions` confirma que no sigue desplegada.
- Esto prueba el HMAC con el secreto productivo y el puente Edge→Community protegido; **no** prueba firma emitida por Meta ni una conversación real. El canal sigue CONNECTED/GREEN y la app aparece `Sin publicar` en Developers. Para el E2E real hace falta publicar la app (URL real de Política de Privacidad) y ejecutar un intercambio iniciado desde WhatsApp; el número no requiere verificación.
- Esta comprobación HMAC ya no depende de revelar el App Secret en el navegador; la reautenticación solo se necesita si el titular desea mostrarlo desde el panel.


### Estado Meta tras el smoke HMAC — 2026-09-28

Graph v26 read-only confirma WABA productiva suscrita a la app `Rsuelvo`, número productivo CONNECTED, calidad GREEN (`EXPIRED` es solo `code_verification_status`). El ingress Community ya está publicado; el smoke HMAC sintético fue exitoso, pero todavía no se recibió un mensaje real de WhatsApp ni se observó una respuesta Graph. Motivo actual: la app sigue Sin publicar y Meta solo entrega webhooks de prueba hasta publicarla. Para el flujo conversacional se requiere URL real de Política de Privacidad + publicación; comprobar después en n8n que el evento recorra WF-02/03/04/80 sin errores.


### Auditoría posterior 2026-09-28 — retención, ventana 24h y reconciliación read-only

- n8n Community `2.40.7` vía Tunnel al escritorio contra producción: 18/18 sincronizados, 16 publicados, health pública 200. El GET de verificación Meta a `meta-ingress` respondió 200 desde origen facebookplatform. En 24h no hubo POST conversacional de Meta; el único POST 200 fue el smoke sintético Deno/Edge de estado.
- Las ejecuciones webhook históricas 29–54 no correlacionan con el callback Meta: 2 WF-20 cerraron RPC de pedido/cobro — veredicto read-only 2026-09-28: ejecuciones 33 y 38 pre-cutover contra staging (IDs ausentes en producción, presentes en staging; la 33 creó el pedido con cobro en rama Error sin ID; la 38 reusó el pedido y generó el cobro); sin mutación en PROD, sin limpieza requerida. 4 WF-80 se bloquearon antes de Graph por destinatario inválido. Prohibido borrar o limpiar datos; gate vigente: prohibidos fixtures con escrituras sintéticas en PROD.
- Reconciliación solo-lectura COMPLETADA (procedimiento y veredicto en bitácora): SELECT por ventana temporal en pedidos/cobros, cruce con eventos WhatsApp y auditoría, verificación de constraints; sin UPDATE/DELETE.
- Retención tras reinicio: `EXECUTIONS_DATA_SAVE_ON_SUCCESS=none`, `EXECUTIONS_DATA_SAVE_ON_ERROR=all`, sin progreso ni payloads manuales, pruning 336 h. Los logs Supabase contienen la query del challenge: acceso limitado y rotación coordinada del verify token Meta↔Edge secret.
- Pendiente: URL real de Política de Privacidad + publicación de la app, conversación WhatsApp real, Graph outbound confirmado y host persistente 24/7. Sin E2E ni go-live.


### Auditoría operativa 2026-09-28 — estado verificado y bloqueos (sin cambios)

- Objetivo vigente: workflows Community conectados a Supabase y WhatsApp real. n8n `2.40.7` healthy; 18/18 coinciden con export, 16 activos según lo esperado, sin credenciales sin resolver ni OpenWA.
- Número Meta WhatsApp CONNECTED, GREEN, CLOUD_API; `code_verification_status=EXPIRED` es un código viejo que no invalida el número — prohibido pedir otro código o tocar la verificación. Una sola app Rsuelvo (En desarrollo/Sin publicar); WABA suscrita + `messages`; challenge GET real desde Facebook con 200.
- Logs actuales (challenge real + POST sintético interno) no prueban mensaje conversacional real. Publicar exige URL de política de privacidad; la página legal sigue BORRADOR pendiente de validación legal Bolivia y las rutas públicas devuelven 404. Hosting en desktop+Tunnel, sin 24/7.
- Bloqueos: política legal pública aprobada + publicación de app Meta + alojamiento persistente. Prohibido enviar WhatsApps. Sin E2E ni go-live.


### Auditoría 2026-09-28 — provider estático, filas WF-80 y restart (sin cambios)

- Revisión estática del camino WF-02→WF-03→WF-04: WF-02 emite provider `META`, WF-03 lo normaliza a `meta` conservando `phone_number_id`, WF-04 compara provider con `meta`; sin mismatch de mayúsculas en el flujo activo y ningún workflow modificado.
- Filas de ejecuciones WF-80 39, 46, 50 y 54 en modo integrated con status success: sin evidencia de llamadas Graph desde conversaciones reales.
- Restart `unless-stopped` en contenedores n8n, cloudflared, task-runners y PostgreSQL; host de escritorio sin disponibilidad durante suspensión/apagado.
- Bloqueos vigentes: privacidad pública aprobada/app Meta Live, evento conversacional E2E sin enviar WhatsApps sintéticos y hosting persistente. Sin tocar número, app, Supabase ni workflows.


### Estado autoritativo 2026-09-28 — app publicada, privacidad viva, E2E lo inicia el usuario (sin cambios)

- WhatsApp CONNECTED/GREEN; `code_verification_status=EXPIRED` es código viejo: prohibido remarcar verificación pendiente o pedir códigos.
- Meta Go Live muestra modal de publicación correcta / disponible para uso público de la app Rsuelvo (supersede "Sin publicar" y "solo webhooks de prueba").
- `rsuelvo.com/privacidad/` y homepage en HTTP 200 (supersede rutas 404); `healthz` en 200; webhook público sin auth en 403 con WF-02 activo (supersede 404).
- n8n local: ejecuciones 43–55; la webhook 55 de WF-02 es el smoke firmado Deno/Edge de las 20:53:34 UTC, no conversación real; posteriores a las 15:15 locales solo QA integrada. Supabase prod: challenge Facebook 200 + POST smoke estado 200; sin inbound conversacional Meta ni envío Graph real.
- Contenedores en escritorio vía Cloudflare Tunnel, sin continuidad ante suspensión/apagado.
- Gate pendiente: el E2E real debe iniciarlo el usuario escribiendo al WhatsApp (nosotros no enviamos mensajes) + alojamiento persistente VPS/servicio 24/7. Workflows activos conservados; sin tocar verificación del número; sin secretos en notas.


### Cierre 2026-09-29 — fixes productivos + simulation_mode (sin QA completo, sin cambios)

- WF-10 (`xFcZMG8Hip0Z6aH5`) activo `v353ab8a6` con fix de identificador suelto/salida singular (`runOnceForAllItems`, `[{json:result}]`). WF-04 (`0fw2ymvAY1hHoV9M`) activo `v4eecef97`: no-SKU por `fn_contexto_por_telefono`, SKU por `fn_resolver_sku_universal`, sin atribución por `phone_number_id` compartido; contexto = cliente más reciente tras SKU (riesgo inter-tenant concurrente mismo teléfono). WF-80 (`7V6MIPuGbdx9s0lT`) activo `ve66602f4` con `simulation_mode` optativo allowlist dos tenants; rama simulada sin Meta/HTTP con log `whatsapp_send_simulated`; sin flag, envíos normales intactos.
- Smoke QA (`6XoIAD3JIOt1KlaN`) inactivo; 2 destinatarios ficticios → 2 `whatsapp_send_simulated`, 0 `whatsapp_send`. Rollback DB verificado (reserva/waitlist por tenant, `fn_confirmar_pago` idempotente YA_PROCESADO). Paquete verificado 18/391/94/25/40 guardas + checks verdes + backend 344 tests.
- Límite: `simulation_mode` no propagado (WF-04→WF-10/WF-20/WF-21, cron WF-13). Pendientes: E2E seguro comprobante→aprobación→confirmación/entrega y cron waitlist. Un solo número compartido: SKU selecciona tenant, envíos filtrados por `id_comercio`.


### Avance QA 2026-09-30 — rechazo simulado y blindaje externo (incompleto, sin cambios)

- Suite backend 344 passed (warning deprecado Starlette/httpx); paquete 18/391/94/25/40 guardas + `py_compile` OK. 16 RSU activos versionados (`activeVersionId=versionId`, `sameAsDraft`); WF-25-B inactivo fuera de MCP.
- Smoke QA inactivo: 2 `whatsapp_send_simulated` allowlisted + 0 `whatsapp_send`; tercer tenant no-allowlisted → `whatsapp_simulation_rejected` (`blocked_simulation_forbidden`); evidencia en logs (n8n no expone ejecución/detalle). Solo cambió el draft del harness; productivos intactos.
- Sin ESPERANDO en lista (2 CONVERTIDO_RESERVA): sin cron notificable. 32 llamadas a WF-80 con Code validador; WF-02/03 bloquean `simulation_mode` externo: solo el QA interno lo crea.
- Pendientes: propagar flag por rutas, simulación cron waitlist, observabilidad. No es E2E funcional.


### Avance producción 2026-09-30 — sintéticos por tenant, NO apto cutover (sin cambios)

- Supabase prod ACTIVE_HEALTHY; n8n healthz/readiness 200. Migración `20260930164650`: sin SELECT/INSERT anon/authenticated en `tbl_whatsapp_eventos`; `service_role` conserva. Repo BACKEND local sin commits/remote: prohibido db push sin reconciliar historia.
- QA abierto en `07-Control-de-Calidad/QA-n8n-produccion-2026-09-30.md`: WF-80 `8b6c840a` con pares sintéticos exactos (2 simulados + 2 rechazados por corrida, 0 envíos); SKU E2E no comprobado. WF-04 orden+reserva por tenant sin duplicados; cron minuto a minuto liberando vencidas; WF-12/WF-13 en simulación; RPCs de lista solo `service_role`/`n8n_runtime`.
- WF-14 positivo pendiente: ciclo aislado 17:36 UTC en monitoreo (vence ~17:46:27); evidencia por DB; cero mensajes reales. Auditoría 16 activos sin `errorWorkflow` compartido y `retryOnFail` parcial; política pendiente de respuesta del usuario. SECURITY DEFINER verificados con guardas rol/tenant.
- Conclusión: NO apto para cutover. Pendientes: VPS DigitalOcean (CEO), repo canónico con remoto + historia reproducible, inbox/outbox + callbacks estado/replay, sin `pg_net` en transacciones, E2E cajero con Auth, almacenamiento/proveedor, paridad y alertas n8n. Python a STAGING. Sin tocar secretos ni workflows.


### Cierre sintéticos 2026-09-30 — WF-14 positivo, ciclo QR (NO apto cutover, sin cambios)

- WF-14 positivo en aislamiento (NOTIFICADO+SI → CONVERTIDO_RESERVA, reserva + QR GENERADO, WF-80 simulado, 0 real); WF-12/WF-13 cron dos tenants todo simulado; cron 18:02 UTC venció aceptada (reservado a 0, QR EXPIRADO). Harness restaurado 10 nodos/inactivo/v1. Intervalo: 20 simulados, 2 rechazados, 0 reales; evidencia por SQL.
- Migración `20260930180547_sync_qr_cobro_lifecycle`: 41 QR GENERADO (12 pagados/downstream, 28 vencidos, 1 cancelado) → PAGADO/CANCELADO/EXPIRADO + triggers; ACL sin EXECUTE anon/authenticated/service_role. Local 1/1; backend 345 tests.
- Producción NO lista para cutover. Pendientes: VPS (CEO), repo BACKEND sin remote/historia sin reconciliar (no db push), inbox/outbox + replay/status, sin `pg_net` en transacciones, Auth-JWT cajero pago/entrega E2E, receipt OCR/Storage/proveedor, paridad + política errores/retries (usuario). Python a STAGING. Sin tocar secretos ni workflows activos.


### Cierre QA 2026-09-30 — escalamiento cron + WF-80 restaurado (NO apto cutover, sin cambios)

- Arnés 18:15 UTC dos tenants (exec 547 no retenida; evidencia SQL): 2 reservas/QR simulados. Cron escaló pos1 VENCIDO → pos2 NOTIFICADO vía pg_net 200: 1 `whatsapp_send_simulated`, 0 reales.
- Guard `QA_SIM_PRUEBA_02` retirado; WF-80 restaurado/publicado `v81740576`. Detalle en `07-Control-de-Calidad/QA-n8n-produccion-2026-09-30.md` (QA abierto).
- Error Trigger compartido elegido por el usuario; faltan email destino + credencial SMTP (n8n sin disponibles): no crear handler incompleto. Sin tocar secretos ni workflows activos.


### Cierre posterior 2026-09-30 18:38 UTC — oferta vencida, trigger en espera (sin cambios)

- Cron 18:38 UTC: `QA_SIM_PRUEBA_02` NOTIFICADO→VENCIDO sin siguiente → sin callback/envío. Reservas 18:15 VENCIDA, QR EXPIRADO, stock liberado. WF-80 en `81740576` sin guard temporal.
- Error Trigger compartido por correo a ethannic2@gmail.com (elección usuario): Zoho en signin, sin credencial SMTP; esperar login manual, sin crear app password/credential aún. Sin tocar secretos ni workflows activos.
