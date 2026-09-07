# Observaciones y Sugerencias del Usuario — RSUELVO

> **Propósito:** Registro vivo de observaciones, sugerencias y requerimientos del usuario sobre el producto.
> **Fuente de verdad:** [[00-PROMPT-MAESTRO-RSUELVO]] v1.4-FINAL
> **Regla:** Cada observación se evalúa contra decisiones cerradas (D1-D12) y se clasifica antes de implementar.

---

## 📋 Instrucciones de Uso

### Formato por observación

```markdown
### OBS-XXX: [Título corto]
- **Categoría:** Funcional | UX | Regla de Negocio | Seguridad | Técnico | Logística | Monetización | Legal | Futuro
- **Sección afectada:** §X.X / WF-XX / Pantalla X / Tabla/fn_
- **Descripción:** [Qué observas o sugieres]
- **Propuesta de solución:** [Cómo lo resolverías, si tienes idea]
- **Impacto:** 🔴 Alto | 🟡 Medio | 🟢 Bajo
- **Bloquea construcción:** Sí | No
- **Estado:** ⬜ Pendiente | 🔄 En evaluación | ✅ Aceptada | ❌ Rechazada | 📦 P2 (futuro)
- **Resolución:** [Cuando se cierre] Decisión tomada + justificación
```

### Clasificación automática

| Si la observación es... | Se clasifica como... |
|-------------------------|----------------------|
| Corrección de algo existente | 🔧 Bug / Fix |
| Nueva funcionalidad en alcance actual | ✨ Enhacement |
| Funcionalidad fuera de fase actual | 📦 P2 (backlog) |
| Cambio de regla de negocio | ⚖️ Decisión (requiere D-nueva) |
| Mejora visual/UX | 🎨 UX |
| Riesgo de seguridad/fraude | 🔒 Seguridad |

---

## 📝 Observaciones Registradas

---

### OBS-001: Pregunta de confirmación para lista de espera
- **Categoría:** UX / Regla de Negocio
- **Sección afectada:** WF-12 (Lista de Espera) · WF-13 (Notificar Lista) · `fn_agregar_lista_espera` · HU-043/045
- **Descripción:** Cuando un producto está reservado o sin stock, el sistema agrega automáticamente al comprador a la lista de espera sin preguntar. El usuario sugiere incluir una pregunta al comprador para confirmar si desea continuar en la lista o ser removido, permitiendo que los siguientes compradores suban de posición.
- **Flujo actual:**
  ```
  SIN_STOCK → WF-12 agrega automáticamente → WF-13 notifica posición
  ```
- **Flujo propuesto:**
  ```
  SIN_STOCK → Pregunta "¿Deseas entrar a la lista de espera?"
      ├── SÍ → WF-12 agrega → WF-13 notifica posición
      └── NO → No se agrega / Se remueve de la lista
  ```
- **Propuesta de solución:**
  1. Modificar WF-10 para que en la rama `SIN_STOCK` envíe un mensaje preguntando al comprador si desea entrar a la lista de espera (similar al flujo de WF-13 con "Responde SI/NO")
  2. Crear WF-12-V2 o modificar WF-12 para que solo agregue cuando el comprador confirme "SI"
  3. Agregar opción de "NO" / "SALIR" en WF-13 cuando se notifica la oportunidad (actualmente solo procesa "SI")
  4. Crear función `fn_cancelar_lista_espera(id_lista_espera)` o usar `fn_aceptar_lista_espera` con estado `RECHAZADO`
- **Impacto:** 🟡 Medio
- **Bloquea construcción:** No
- **Estado:** 🔄 En evaluación
- **Resolución:** *(pendiente)*
- **Opción seleccionada:** **C** (preguntar al entrar + opción de salir al notificar) — registrada como sugerencia del usuario el 2026-09-06.

#### Análisis de impacto

| Artefacto | Cambio requerido |
|-----------|------------------|
| **WF-10** | Rama `SIN_STOCK` → enviar mensaje de confirmación antes de agregar |
| **WF-12** | Ya no se llama directamente desde WF-10; se invoca solo tras confirmación "SI" del comprador |
| **WF-13** | Agregar rama "NO" / "SALIR" para remover de lista y subir posiciones |
| **WF-14** | Actualmente solo procesa "SI"; podría extenderse para manejar "NO" también |
| **`fn_cancelar_lista_espera`** | Nueva función para marcar como `RECHAZADO` y liberar posición (alternativa: reusar estados existentes) |
| **tbl_lista_espera** | Sin cambios estructurales (el enum ya tiene `RECHAZADO` y `CANCELADO`) |

#### Alternativas

| Opción | Descripción | Pros | Contras |
|--------|-------------|------|---------|
| **A** | Pregunta al entrar a lista (antes de WF-12) | El comprador decide desde el inicio | Un paso más antes de confirmar reserva |
| **B** | Pregunta al notificar oportunidad (WF-13) | El comprador ya sabe su posición | Ya está agregado; remover es más complejo |
| **C** ✅ **SELECCIONADA** | Ambas: preguntar al entrar + opción de salir al notificar | Máxima flexibilidad y control de posiciones | Más complejidad en n8n |

#### 🅰️+C — Detalle de la Opción C (seleccionada)

**Momento 1 — Cuando el producto NO tiene stock (entrada a lista):**
```
SIN_STOCK → WF-10 pregunta "¿Quieres que te avisemos cuando haya stock? Responde SI/NO"
    ├── SI → WF-12 agrega a la lista (posición N) → "Estás en la posición #N"
    └── NO → No se agrega nada → fin
```
**Propósito:** Evitar "lista de espera basura". Solo entran interesados reales.

**Momento 2 — Cuando llega su turno (notificación de oportunidad):**
```
WF-13 notifica "¡Ya hay stock! Tienes 2 minutos. Responde SI/NO"
    ├── SI  → WF-14 reserva (sale de lista) → QR de pago
    ├── NO  → Se marca RECHAZADO → siguiente sube de posición → WF-13 notifica
    └── (no responde) → VENCIDO al vencer ventana → siguiente sube de posición
```
**Propósito:** Aquí se produce el **desplazamiento de posiciones**. Si alguien dice NO o deja vencer su turno, el siguiente comprador sube automáticamente.

**Ejemplo real:**
```
1) 3 personas piden el mismo producto agotado:
   - Ana: "SI" → posición #1
   - Beto: "SI" → posición #2
   - Carlos: "NO" → no entra (sin Momento 1, estaría en #3)

2) Llega stock: WF-13 notifica a Ana (pos #1) → Ana: "NO" → RECHAZADO → turno liberado

3) Beto sube de #2 → #1 → WF-13 lo notifica automáticamente → "SI" → reserva → QR
```

**Cambios en n8n:**
| Workflow | Cambio |
|----------|--------|
| **WF-10** | Rama `SIN_STOCK` → pregunta SI/NO (Momento 1), no agregar directo |
| **WF-12** | Solo se invoca si el comprador responde "SI" |
| **WF-04** | Reconocer "NO"/"SALIR" como declinación, no como texto libre |
| **WF-13** | Confirmar desplazamiento (siguiente sube) vía `fn_notificar_siguiente_lista_espera` + `VENCIDO` |
| **WF-14** | Rama "NO" → `RECHAZADO` → WF-13 notifica al siguiente |

**BD:** sin cambios estructurales (enum ya tiene `RECHAZADO`/`VENCIDO`/`CANCELADO`; `fn_notificar_siguiente_lista_espera` usa `SKIP LOCKED`).

> **Estado implementación (2026-09-07):** **Momento 2 ✅ implementado, publicado y VALIDADO E2E** (T-A: NO → RECHAZADO + desplazamiento automático; T-B: SI → RESERVA_CREADA → QR → PAGADO, con D14 en vivo). **Momento 1 ⬜ pendiente** (WF-10 rama `SIN_STOCK` → pregunta SI/NO; WF-12 solo si responde "SI"). **Hallazgos del test → H-16/H-17/H-18 resueltos por migración 32** (turno único por cliente: imposible acumular 2 ofertas; turnos expirados pasan a VENCIDO; el cron no re-notifica grupos con turno en vuelo). Hardening pendiente en WF-14: `ORDER BY fecha_notificacion DESC`.

---

## 📊 Resumen de Estado

| Estado | Cantidad |
|--------|----------|
| ⬜ Pendientes | 0 |
| 🔄 En evaluación | 1 |
| ✅ Aceptadas | 0 |
| ❌ Rechazadas | 0 |
| 📦 P2 (futuro) | 0 |

---

## 📎 Referencias

- **PROMPT MAESTRO:** `00-Index/00-PROMPT-MAESTRO-RSUELVO.md`
- **Decisiones cerradas:** §5 del PROMPT MAESTRO (D1-D14)
- **Backlog HU:** `06-Backlog-HU/01-Backlog-Historias-de-Usuario.md`
- **Matriz WF-BD-HU:** `03-n8n/Matriz-Consistencia-WF-BD-HU.md`
- **Bitácora de avance:** `00-Index/ESTADO-EJECUCION.md`
- **WF-12 (Lista de Espera):** `03-n8n/workflows.md` §23-25
- **WF-13 (Notificar Lista):** `03-n8n/workflows.md` §26-28
- **WF-14 (Aceptar Oportunidad):** `03-n8n/workflows.md` §29

---

## 🔄 Historial de Cambios

| Fecha | Observación | Acción |
|-------|-------------|--------|
| 2026-09-06 | — | Archivo creado |
| 2026-09-06 | OBS-001 | Registrada — pregunta confirmación lista de espera |
| 2026-09-06 | OBS-001 | Opción C seleccionada — preguntar al entrar + opción de salir al notificar (registrada como sugerencia) |
| 2026-09-07 | OBS-001 | Momento 2 implementado en n8n (WF-04 `qLyBczowLOcnNXe5` y WF-14 `MLgnwfXbg7HnWVHC` publicados; usa `fn_rechazar_lista_espera` m31). Pendiente: Momento 1 (WF-10/WF-12) + tests T-A/T-B |
| 2026-09-07 | OBS-001 | **T-A/T-B VALIDADOS E2E** (NO→RECHAZADO+desplazamiento / SI→reserva→QR→PAGADO). Hallazgos H-16/H-17/H-18 → resueltos con migración 32 (turno único por cliente) |
