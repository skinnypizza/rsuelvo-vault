# Auditoría — Guía Meta WhatsApp Business vs Vault

> 📦 **DOCUMENTO HISTÓRICO DE PROCESO** — registra el estado del vault al momento de su emisión. Las resoluciones definitivas están en el [Prompt Maestro](../00-Index/00-PROMPT-MAESTRO-RSUELVO.md) §5 (Decisiones D1-D10). No usar como especificación activa.

> **Fecha:** 2026-08-24 · **Objeto:** `08-Whatsapp Business Guide.md` (76 secciones) contrastado contra [[workflows]], schema SQL **v2.1**, [[01-Backlog-Historias-de-Usuario]] (148 HU), [[Política Técnica de Uso de WhatsApp y OpenWA —RSUELVO]] y [[00-PROMPT-MAESTRO-RSUELVO]].
> **Veredicto:** la guía es **arquitectónicamente consistente** con el vault (separación canal/orquestación/BD, atomicidad, idempotencia, multi-tenant por número, IA que no decide). Se detectaron **5 divergencias** (corregidas en la propia guía o resueltas con parche **SQL v2.1**) y **3 gaps de BD** que la guía asumía implícitamente.

## 1. Consistencias verificadas ✅

| # | Afirmación de la guía | Fuente que la respalda | Estado |
|---|---|---|---|
| C1 | Meta = canal; sin lógica de negocio (§1,3,74) | Prompt Maestro Regla 3 + workflows §3 | ✅ |
| C2 | Comprador sin cuenta; identidad = teléfono (§17,67) | arquitectura + D10 + HU-077 | ✅ |
| C3 | Resolución comercio por configuración interna, nunca input del usuario (§18-19,58) | `tbl_canal_whatsapp` + workflows §15 | ✅ |
| C4 | Reserva atómica vía `fn_solicitar_reserva()` (§21,23,63) | SQL v2 + workflows §20 | ✅ |
| C5 | Lista de espera controlada por PG, nunca SELECT/UPDATE desde n8n (§25) | `fn_agregar_lista_espera` + workflows §24 | ✅ |
| C6 | Re-verificar disponibilidad al aceptar oportunidad (§27) | `fn_aceptar_lista_espera` re-valida estado+expiración+stock | ✅ |
| C7 | QR estático del dueño, sin QR dinámicos (§28) | arquitectura + D-spec 4.3 | ✅ |
| C8 | IA extrae datos; PostgreSQL decide; IA jamás toca stock/créditos/pedidos (§30-32) | Prompt Maestro Regla 4 + workflows §37/72 | ✅ |
| C9 | Créditos atómicos con bloqueo, sin SELECT→IF→UPDATE (§62) | `fn_consumir_creditos` / `fn_iniciar_verificacion` | ✅ |
| C10 | Concurrencia última unidad decidida por BD (§63) | BD §25 + `FOR UPDATE` | ✅ |
| C11 | Deduplicación de eventos/comprobantes (§15,64) | `tbl_whatsapp_eventos` + HU-143 | ✅ |
| C12 | Diferencia MENSAJE_USUARIO vs MENSAJE_NEGOCIO → plantillas fuera de ventana 24h (§36) | política §6-8 + HU-124 | ✅ |
| C13 | Abstracción WhatsAppService con adaptadores Meta/OpenWA (§42-43,76) | workflows §56 (WF-80 único punto de salida) | ✅ |
| D14 | No mezclar proveedores sobre un mismo número (§44) | política §17 "1 WhatsApp = 1 tienda" | ✅ |
| C15 | Los 6 roles canónicos; WhatsApp ≠ interfaz administrativa (§67) | D1 + matriz de permisos | ✅ |
| C16 | Separación META=canal / n8n=orquestación / PG=verdad (§74) | Prompt Maestro §3 | ✅ |
| C17 | Secretos fuera de Git/vault/logs; least privilege System User (§8-10,55-57) | workflows §5 + HU-136 | ✅ |
| C18 | Graph API versionada como config (`META_GRAPH_API_VERSION`) (§75) | workflows §58 | ✅ |

## 2. Divergencias detectadas y CORREGIDAS en la guía

| ID | Divergencia | Corrección aplicada |
|----|-------------|---------------------|
| **M1** | Ruta webhook `POST /webhooks/meta/whatsapp` ≠ canónica | Cambiada a `POST /webhooks/whatsapp/meta` (workflows WF-02) |
| **M2** | Contrato de normalización con claves propias (`customer_phone`, `message_type`, provider en MAYÚSCULAS §47) — existían 3 variantes en el vault | Unificado al contrato canónico de workflows.md §7 (+extras opcionales `phone_number_id`, `media_id`) |
| **M3** | Numeración paralela WF01-WF13 (§45) chocaba con WF-00…WF-80 | Nota canónica añadida: son *adaptadores Meta* con mapeo 1-a-1 a la numeración oficial (ver §4 abajo) |
| **M4** | Estados de comprobante inventados (`EN_PROCESAMIENTO`, `VERIFICADO`) | Sustituidos por enums de BD: `PROCESANDO`, `VALIDO`, `INVALIDO/RECHAZADO` |
| **M5** | Máquina conversacional §50 con nombres propios (`ESPERANDO_ENVIO`, `VERIFICANDO`) | Mapeada a los estados canónicos de workflows.md §16 |

## 3. Gaps de BD asumidos por la guía → parche SQL v2.1

| ID | La guía asume… | Parche aplicado al schema v2 |
|----|----------------|------------------------------|
| **N1** | Registro de eventos con `phone_number_id`, `customer_phone` y estado de procesamiento granular (§16) | `tbl_whatsapp_eventos`: + columnas `phone_number_id`, `customer_phone`; `procesado boolean` sustituido por `processing_status CHECK IN ('RECIBIDO','PROCESANDO','PROCESADO','ERROR')` + índice parcial; `fn_registrar_evento_whatsapp` v2 (permite reprocesar intentos fallidos) + nueva `fn_cerrar_evento_whatsapp` |
| **N2** | Resolver comercio por **Phone Number ID** (§18,58) | `tbl_canal_whatsapp.provider_phone_number_id text unique` + `fn_identificar_comercio_por_phone_number_id(p_pnid)` |
| **N3** | Catálogo interno template_code→name/language/params (§38) | Nueva tabla `tbl_plantillas_whatsapp` + seed de las 8 plantillas (RESERVA_EXPIRADA…ENVIO_NO_ENTREGADO) + RLS (select all / manage superadmin) |

## 4. Equivalencia de workflows (guía §45 ↔ numeración canónica)

| Guía (adaptador Meta) | Canónico vault | Dominio |
|---|---|---|
| WF01_META_WEBHOOK | WF-02 | Ingesta Meta |
| WF02_META_NORMALIZE | WF-03 | Normalizador |
| WF03_META_ROUTER | WF-04 | Router |
| WF04_SKU / WF05_RESERVA | WF-10 / WF-11 | Venta |
| WF06_LISTA_ESPERA | WF-12/13/14 | Lista de espera |
| WF07_PAGO / WF08_COMPROBANTE_IA | WF-20…24 | Pagos e IA |
| WF09_ENVIO | WF-40/41/42 | Logística |
| WF10_META_SEND | WF-80 | Salida única |
| WF11_META_MEDIA | parte de WF-21 | Media download |
| WF12_META_ERROR | WF-00 | Errores |
| WF13_META_RETRY | política §13 | Backoff |

## 5. Cobertura de HU por la guía

La guía implementa el flujo completo del comprador: **HU-037–042** (SKU/reserva/QR), **HU-056–065** (comprobante/OCR/validación/reintento), **HU-076–081** (envío/pedido), **HU-120–126** (infraestructura WhatsApp) y soporta **142–145** (opt-out vía §36+política; dedupe §15; retry clasificado §52). Sin HU huérfanas nuevas; sin HU contradichas.

**Referencias menores:** §71 usa "fn_crear_pedido" como abreviatura de `fn_crear_pedido_desde_reserva()`; §31 lista las funciones correctas. Opt-out no se menciona explícitamente en la guía — queda cubierto por política §16/HU-142 y check pre-envío en WF-80 (`fn_cliente_optado`).

## 6. Conclusión

Tras las correcciones M1-M5 y el parche N1-N3, **guía ↔ workflows ↔ BD v2.1 ↔ HU quedan al 100%**: ningún nombre, estado, ruta ni contrato en disputa. La guía pasa a ser la referencia oficial de integración Meta y complementa (no reemplaza) la Política de OpenWA.
