# MCP Servers — Configuración y Reglas de Uso (opencode)

> **Fecha:** 2026-08-24 · **Alcance:** servidores MCP que la IA (opencode) usará para construir RSUELVO.
> **Principio:** todos los servicios son **CLOUD**. Prohibido apuntar al stack local (`127.0.0.1:54321`) para trabajo de proyecto.
> **Fuente de credenciales:** solo variables de entorno / credential manager de n8n. **Nunca** pegar tokens en este vault (Guía Meta §8, HU-136).

## 1. Estado verificado (2026-08-24)

| MCP | Transporte | Destino | Estado | Verificado con |
|-----|-----------|---------|--------|----------------|
| **n8n** | remote HTTP + Bearer JWT | `https://rsuelvo2026.app.n8n.cloud/mcp-server/http` | ✅ **OPERATIVO** | `search_projects` → 1 proyecto personal · `search_workflows` → 3 WFs · `list_credentials` → 2 |
| **Supabase** | remote + OAuth | `https://mcp.supabase.com/mcp` | 🟡 **RECONFIGURADO — requiere login OAuth 1 vez** | Antes apuntaba a `127.0.0.1:54321` (LOCAL, corregido) |
| **meta-devtools** | remote + OAuth | `https://mcp.facebook.com/devtools` | 🟡 **CONFIGURADO — requiere login OAuth 1 vez** (beta Meta) | Endpoint verificado: 405/401 = vivo y pidiendo auth |
| **Meta (mensajería)** | — vía n8n WF-80 | Cloud API (producción) | ⛔ Sin MCP por diseño — D11/D12 | Credencial Meta aún no creada en n8n |

## 2. Supabase

### 2.1 Qué se encontró (por qué se corrigió)
- La config antigua apuntaba a `http://127.0.0.1:54321` = stack **local** de Supabase CLI.
- Ese stack local contiene **25 tablas de una generación anterior del esquema** (familia `tbl_adm_*`, `tbl_cre_*`, `tbl_com_*`, `tbl_cli_*`, `tbl_pag_*`, `tbl_env_*` + genéricas `tiendas/productos/...`), todas vacías. **No es el schema v2** y NO debe usarse como referencia ni como destino del app.

### 2.2 Configuración correcta (aplicada en `~/.config/opencode/opencode.jsonc`)
```json
"supabase": {
  "type": "remote",
  "url": "https://mcp.supabase.com/mcp",
  "enabled": true,
  "oauth": true,
  "timeout": 30000
}
```

### 2.3 Pendiente del usuario (una sola vez)
1. Abrir opencode → ejecutar `/mcp` (o el flujo de autenticación) → completar **OAuth de Supabase** con la cuenta dueña del proyecto.
2. Verificar que el proyecto accesible sea `efsksqrllhenidzqdjsf` (**rsuelvo**, región us-west-2, cloud).
3. Aplicar el schema: ejecutar en orden `02-Base-de-Datos/sql/01…12` (o pedirle a la IA que lo haga vía MCP ya autenticado). Verificación esperada: **32 tablas** en schema `rsuelvo`, 14 enums, 36 funciones.

**Alternativa (sin OAuth):** crear un Personal Access Token en Supabase Dashboard → Account → Access Tokens y configurar el MCP en modo stdio:
```json
"command": ["npx","-y","supabase-mcp@latest","--project-ref","efsksqrllhenidzqdjsf"],
"environment": { "SUPABASE_ACCESS_TOKEN": "<PAT>" }
```
El token NUNCA se pega en el vault ni en Git (HU-136).

### 2.4 Reglas de uso para la IA
- Toda DDL/migración va a un archivo nuevo en `02-Base-de-Datos/sql/` siguiendo la numeración 01…12 (nunca SQL ad-hoc suelto).
- Operaciones críticas SIEMPRE por las `fn_*` existentes; prohibido UPDATE directo de inventario/reservas/créditos/pedidos desde cliente o workflow (Regla de Oro 2).
- Claves: `anon`/publishable → Flutter. `service_role` → solo backend/n8n. Jamás en frontend (HU-136).
- El stack local `54321` está **prohibido** para RSUELVO salvo experimentos desechables; no migrar nada ahí.

## 3. n8n

### 3.1 Verificación realizada
| Check | Resultado |
|---|---|
| Conexión cloud | ✅ `rsuelvo2026.app.n8n.cloud` |
| Proyecto | Personal — Ethan Nicolas Cardenas Luna |
| Workflows existentes | 3: `WF1 - Generar Cobro QR` (activo), `WF2 - Confirmacion y Logistica de Pago` (activo), `Diagnostico Tablas` (inactivo) |
| Credenciales | `openAiApi` (managed, credits gratis) ✅ · `Postgres account` ⚠️ |

### 3.2 Hallazgo importante — workflows LEGACY
`WF1/WF2` fueron creados el 18-19/08 **antes** del diseño canónico del vault. No siguen el esquema `RSU | nn | Módulo` ni llaman a las `fn_*` v2. Además, su credencial Postgres probablemente apunta al stack local.

**Decisión aplicable (Regla de Oro 2 + matriz WF):** durante F1-F3, **archivar** WF1/WF2/Diagnostico y reconstruir según `workflows.md` (WF-20 Generar QR, WF-23/24 Verificar/Confirmar, WF-40…42 Logística), conectando las RPC v2. No refactorizar in-place: el diseño cambió de raíz.

### 3.3 Credenciales pendientes en n8n
| Credencial | Para qué | Cuándo |
|---|---|---|
| **Meta Cloud API** (System User token — Guía §8-10) | WF-02 Meta Incoming, WF-80 Send | F1/F7 |
| **Supabase service_role** (reemplaza/actualiza `Postgres account`) | Todas las RPC `fn_*` | F0 (tras migrar schema a cloud) |
| OpenAI | WF-22 GPT-4o Vision | ✅ ya existe |
| OpenWA API key | Adaptador legacy/dev (opcional) | Solo dev |

### 3.4 Reglas de uso para la IA
- Un workflow = una responsabilidad (workflows.md §81); nombres `RSU | nn | Módulo`.
- Salidas de WhatsApp SOLO por WF-80 (cola/rate-limit/opt-out) — jamás HTTP directo a Meta/OpenWA desde otros WFs.
- Todo webhook entra primero por idempotencia (`fn_registrar_evento_whatsapp`, HU-143).
- Errores de proveedor ≠ error de negocio (WF-00); backoff 1/2/4/8 s, sin reintentos infinitos.

## 4. Meta

### 4.1 meta-devtools — Developer Tools MCP (OFICIAL de Meta) ✅ configurado

**Qué es:** servidor remoto OFICIAL de Meta (`https://mcp.facebook.com/devtools`, Streamable HTTP, OAuth con cuenta Meta developer). Es **tooling de desarrollo/administración**: NO envía mensajes a clientes.

**Configuración aplicada en `~/.config/opencode/opencode.jsonc`:**
```json
"meta-devtools": {
  "type": "remote",
  "url": "https://mcp.facebook.com/devtools",
  "enabled": true,
  "oauth": true,
  "timeout": 30000
}
```

**Pendiente del usuario (una vez):** abrir opencode → autenticar el servidor → sign-in con la cuenta Meta developer que posee la App/WABA de RSUELVO → otorgar scope sobre las apps. Nota: acceso **beta gradual**; si responde "this app isn't available", la cuenta aún no está habilitada en el rollout.

**Alcance (scopes):**
| Scope | Permite |
|---|---|
| Read | Config de apps, App Review/compliance, uso y salud de API, topics/suscripciones webhook, changelog, búsqueda de docs |
| Manage | Todo lo anterior + **crear/actualizar/borrar suscripciones de webhook** (única escritura) |

**10 herramientas (`devtools_*`):** app_list, app (settings), api_health, api_usage/rate-limits, app_review status, compliance, webhook_topics/list, **webhook_manage**, **webhook_test**, api_changelog + discovery/docs-search.

**Usos concretos en RSUELVO (F1/F7):**
1. Registrar la suscripción webhook de WhatsApp Cloud API apuntando a `https://rsuelvo2026.app.n8n.cloud/webhook/whatsapp/meta` (fields: `messages`) — antes era paso manual del Dashboard.
2. `webhook_test` para disparar payloads de prueba contra WF-02 sin clientes reales.
3. Monitorear rate limits y salud de API (insumo para política §9).
4. Vigilar App Review/compliance (criterios producción §30) y changelog/deprecaciones de Graph API.
5. Buscar documentación oficial in-context.

### 4.2 Mensajería WhatsApp — SIN MCP (D11 se mantiene)

El tráfico de mensajes (enviar/recibir a compradores) sigue **exclusivamente** por **n8n WF-80**: cola, rate-limiting, circuit breaker, opt-out e idempotencia viven ahí y un MCP los saltaría. Los MCP oficiales de Meta hoy no incluyen mensajería de todos modos — si Meta lanza uno, evaluar con la misma regla: solo si respeta WF-80 como único gateway.

### 4.3 Credenciales Meta pendientes en n8n (para mensajería, F1)
System User token (least privilege) según Guía §8-10 → credencial en n8n para WF-02/WF-80. El devtools-mcp **no sustituye** este token: son planos distintos (administración vs mensajería).

## 5. Nota adicional — canal OpenWA (local, dev)

Existe un MCP `openwa` apuntando a `localhost:2785` (servidor local). Es el **adaptador legacy/dev**: válido para pruebas, prohibido en producción (D9/guía §43-44). No mover datos reales por ese canal.

## 6. Higiene de config (recomendación)

`opencode.jsonc` contiene claves en texto plano (Bynara, Stitch, OpenWA). Migrar a variables de entorno `${...}` cuando sea posible y rotar la clave OpenWA si algún día se compartió. Fuera de alcance de este documento, pero alineado con HU-136.
