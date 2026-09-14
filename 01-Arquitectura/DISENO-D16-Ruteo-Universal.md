# D16 — Ruteo con número universal RSUELVO (DISEÑO v0.1, pendiente aprobación)

> **Estado:** propuesta del orquestador 2026-09-15. Nada implementado.
> **Contexto:** `01-Arquitectura/Numero-Universal-WhatsApp.md` (parte familiar + técnica).
> **Regla del paquete:** SKU global por comercio SE MANTIENE (veredicto 2026-09-12);
> creación de variante por sucursal ya existe y no cambia.

## 1. Cómo resuelve hoy (a reemplazar solo en el resolvedor)

Hoy WF-02/WF-04 resuelven `(comercio, sucursal)` desde el canal (`phone_number_id` →
`fn_identificar_comercio_por_phone_number_id` → `tbl_canal_whatsapp`). Con un solo número
esa señal desaparece. Todo lo demás (máquinas de reserva, pago, lista, entrega, opt-out
por `(comercio, teléfono)`, snapshots con `id_sucursal`, RLS por sucursal) **no cambia**.

## 2. Resolución de comercio (sin canal)

| Entrada | Resolución | Notas |
|---|---|---|
| Texto con SKU válido | `SKU[0:3]` → `codigo_tienda` (UNIQUE global verificado) → comercio. Gratis y exacta | Requiere que el SKU exista; si no, cae a pregunta |
| Link con código (`?text=`) | El código puede traer tienda y/o sucursal (formato §5) | Cero fricción si viene del live |
| STOP | Siempre primero, aun sin comercio (Q3 ya lo deja terminal + auditado) | Sin cambios |
| Resto sin SKU ("hola", SI/NO) | Memoria → pregunta (§3–§4) | Nunca adivinar entre comercios |

## 3. Resolución de sucursal (lo nuevo)

Prioridad estricta, solo dentro del comercio ya resuelto:

1. **Código en el mensaje inicial** (`?text=Hola%20NORTE` del live): tabla nueva
   `tbl_enlace_live (codigo UNIQUE, id_comercio, id_sucursal, activo)` — ver §6.
2. **Memoria**: última sucursal del par `(comercio, teléfono)` (`tbl_clientes.id_sucursal_ultima`,
   ver §6). Se USA si existe; si el mensaje trae SKU de otra sucursal con stock, manda el SKU.
3. **Pregunta**: menú de sucursales del comercio (una vez; luego se recuerda).
4. Buyers con 2+ comercios: la memoria es SIEMPRE por par, nunca global por teléfono (D10).

## 4. Tabla de canales (remodelo mínimo)

`tbl_canal_whatsapp` conserva 1 fila universal Meta (envíos: siempre el mismo
`phone_number_id`; el rate-limit por comercio de WF-80 SIGUE valiendo por `id_comercio`)
+ filas OpenWA de respaldo si aplica. `id_comercio/id_sucursal` dejan de significar
"dueño del número": se documentan como legado o se nulifican en migración (decisión en §8).
`fn_identificar_comercio_por_phone_number_id` se conserva para compatibilidad pero deja de
ser la vía de ruteo (retorna el canal universal).

## 5. Formato del link por live (propuesta, a aprobar §8)

`wa.me/<universal>?text=<CODIGO>` donde `CODIGO` = código de sucursal del live
(ej: `NORTE`, `PAMPAHASI`). El resolvedor: trim/upper del primer token → lookup en
`tbl_enlace_live` (solo activos del comercio si ya hay comercio por SKU, si no global con
desambiguación). Códigos cortos, sin espacios, únicos por comercio (UNIQUE(id_comercio,
codigo); globalmente recomendados distintos para mensajes sin SKU).

## 6. Migraciones previstas (ninguna aplicada)

- **M-A**: `tbl_enlace_live` (codigo, comercio, sucursal, activo, timestamps, triggers
  audit/updated_at, RLS lectura comercio + gestión ADMIN).
- **M-B**: `tbl_clientes.id_sucursal_ultima uuid NULL REFERENCES tbl_sucursales`
  (memoria; se actualiza en cada interacción resuelta; NULL = preguntar).
- **M-C**: remodelo `tbl_canal_whatsapp` (documentar/nulificar dueño por canal) +
  flag `ruteo_universal` en `tbl_comercio_config` (cutover por tenant: 0 = canal clásico,
  1 = universal). Migración de la fila FER existente.
- **M-D**: `fn_resolver_contexto_universal(p_texto, p_telefono)` — implementa §2+§3 en
  una sola RPC atómica (STOP→comercio→sucursal), devuelve `{id_comercio, id_sucursal,
  origen: SKU|ENLACE|MEMORIA|PREGUNTA_PENDIENTE|...}`. WF-02/WF-04 la llaman en vez del
  resolvedor por canal. Reglas 2/3 intactas.

## 7. Riesgos Meta y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Cupo global compartido (tiers por número) | Monitor Usage por comercio (ya medido); P3/P4 reducen raíces; upgrade a Pro antes del 2º tenant real |
| Quality rating compartido (un spammer hunde a todos) | Reglas anti-spam por comercio (decisión §8) + STOP robusto (Q3) + rate-limit vigente |
| Display name "RSUELVO" | Decisión §8 (respaldo vs tienda) |
| Plantillas por cuenta | Estrategia por cuenta: plantillas genéricas con parámetros (decisión §8) |
| Fuga entre tenants | Re-auditoría RLS post-implementación (checklist: resolver nunca devuelve comercio sin evidencia; RPCs exigen id_comercio; tests 2-comercios/2-teléfonos) |

## 8. Decisiones producto pendientes (familia)

- [ ] D8.1 Display name del número.
- [ ] D8.2 Estrategia de plantillas.
- [ ] D8.3 Formato de código por live + quién los asigna.
- [ ] D8.4 Reglas anti-spam por comercio.
- [ ] D8.5 Política de memoria (¿preguntar siempre o confiar?; ¿confirmar al cambiar?).
- [ ] D8.6 Orden de cutover por comercio (FER primero como piloto).

## 9. Secuencia (tras aprobación)

1. Migraciones M-A→M-D (orquestador) + E2E de resolvedor en BD.
2. Rewrite etapa resolvedora WF-02/WF-04 (Claude/Codex) + Matriz.
3. Re-auditoría RLS + E2E 2-comercios + cutover FER (`ruteo_universal=1`).
4. D16 al Maestro. RLS/Reglas sin cambios de fondo.

## Fuera de alcance

SKU por sucursal (descartado 2026-09-12), modo automático (D15), pricing (m40 intacto),
push (sin cambios), app (solo mostrar sucursal resuelta donde aplique, menor).
