# Auditoría de optimización de ejecuciones n8n — V3

**Cuenta:** `rsuelvotest.app.n8n.cloud`. **Corte del historial:** 2026-09-14 12:09:47 America/La_Paz (16:09:47 UTC). **Alcance:** los 16 canónicos de Matriz §0, releídos live. Solo lectura de n8n, documentación, SQL local e historial existente; ninguna consulta a la BD, ejecución de prueba ni modificación operativa. Este informe es el único archivo creado; v1/v2 permanecen intactas.

## 1. Resumen ejecutivo y top 5 vigente

**El ahorro de cuota está en evitar entradas a n8n y rondas innecesarias del comprador. Reducir nodos, RPCs o subworkflows no reduce por sí mismo la cuota.** Se verificaron **12 versiones distintas de v2 y 4 iguales**. Los atajos de lista, silencios logísticos, ayuda/R5, filtros Q y reparaciones F1–F6 ya forman parte del baseline; no se venden como trabajo pendiente.

La ventana fresca tiene **413 ejecuciones técnicas (T): 220 raíces y 193 subejecuciones**. Se clasificaron las **220 raíces**: WF-02 recibió **159 status y 41 mensajes admitidos**, y la única corrida de WF-13 tuvo trabajo (**0 vacíos/1 corrida**). Las últimas 24 horas tienen **76 T y 39 raíces**; de estas, **27 son status de Meta** y **2 callbacks de estados logísticos silenciosos**. Esas dos clases representan **29/39 raíces (74,4%)** y constituyen un **techo de entradas candidatas**, no ahorro aprobado ni proyección mensual. El filtro de status externo requiere comprobar primero qué eventos pueden descartarse. El panel contractual Usage no está expuesto por el conector: las raíces observadas son el indicador de Q utilizado aquí, no una lectura de facturación.

Ranking cualitativo por ahorro observado, alcance y riesgo; no hay ratio monetario inventado:

| Orden / propuesta | Acción futura contra el diseño actual | Ahorro relativo y evidencia | Riesgo / certeza |
|---|---|---|---|
| 1 · P3 | Evitar antes de n8n los POST exclusivamente técnicos de status que se declaren prescindibles | **1 T/1 Q por POST realmente evitado**. Últimas 24 h: techo **27 T/27 Q**, 69,2% de las 39 raíces. El filtro interno ya existe y no ahorra Q | Medio/alto: autenticidad, errores de entrega y lotes mixtos; viabilidad de filtrado externo pendiente |
| 2 · V3-A | Dejar de emitir callbacks WhatsApp para PREPARANDO/ASIGNADO/EN_RUTA/ENTREGADO ya silenciosos | **1 T/1 Q por callback evitado**, sin tocar guía ni NO_ENTREGADO. Últimas 24 h: **2 T/2 Q** candidatos; el envío de guía permanece | Bajo/medio si el orquestador limita el cambio al emisor WhatsApp; conservar auditoría y push |
| 3 · P2 | Dedup efectivo y recuperación de notificaciones en 25-C/25-A | Repetición notificable detenida dentro de n8n: **1 T/0 Q** por hijo 80 evitado; detenida antes del webhook: **2 T/1 Q**. **No se probaron replays repetidos en los payloads examinados** | Medio: bypass live probado, ahorro recurrente no medido; no perder avisos tras fallo parcial |
| 4 · P4 | Evitar callbacks vacíos/coincidentes de 13 si se confirman | **1 T/1 Q por vacío**; K despertares equivalentes→1: **K−1 T y K−1 Q** manteniendo destinatarios. **0 vacíos entre 1 raíz de 13** en toda la ventana; 0 llamadas en últimas 24 h | Medio/alto por turnos, concurrencia y correlación por sucursal; no justificar rediseño por volumen supuesto |
| 5 · V3-B | Reducir rondas correctivas residuales con instrucciones contextualizadas, preservando Q1–Q8/R5 | Cada mensaje posterior realmente evitado: **1 Q** y la cadena asociada (**4 T** ayuda/R5; **5 T** captura; **6 T** reenvío de comprobante manual). **0 ahorro incremental demostrado**; requiere medir conversaciones | Medio: no eliminar consentimiento, STOP, pregunta de ciudad ni reenvío legítimo |

No sumar P3 con status hipotéticamente evitados por P2/V3-B sobre la misma entrada. Tampoco sumar P2 y V3-A sobre el mismo callback. El ahorro en guardado, P7 y P8 se informa aparte: **0 Q directo**. Si solo se prioriza cuota demostrable, concentrar el estudio siguiente en P3/V3-A; las otras tres conservan condiciones de medición.

## 2. Fuentes, método y baseline de versiones

Fuentes documentales: [spec V3](PROMPT-CODEX-AUDITORIA-OPTIMIZACION-V3.md), [Matriz §0](Matriz-Consistencia-WF-BD-HU.md), [Maestro v1.7](../00-Index/00-PROMPT-MAESTRO-RSUELVO.md), [bitácora 09-11/12/14/15](../00-Index/ESTADO-EJECUCION.md), [v1/v2](Auditoria-Optimizacion-Ejecuciones.md), [robustez y addendum Q](Auditoria-Robustez-Conversacional.md), [OBS-001–010](../07-Control-de-Calidad/Observaciones-Usuario.md), SQL local 31/34/35/36/40, **41–56** y definiciones finales de [06_functions.sql](../02-Base-de-Datos/sql/06_functions.sql). Los exports históricos no sustituyen esta relectura live.

**Fechas:** el vault incluye entradas rotuladas 2026-09-15, posteriores al reloj de esta auditoría. Se usan como decisiones documentadas solicitadas por el usuario, no como ejecuciones observadas en una fecha futura. La ventana de medición termina el 14. Algunas casillas de OBS/Matriz mantienen estados históricos; para versión/conexiones manda la lectura live.

**T** cuenta instancias de workflow: raíces y subejecuciones. **Q** cuenta las raíces de producción bajo la disciplina pedida. Los hijos ejecutados mediante Execute Workflow no cuentan al límite mensual, según [documentación oficial n8n](https://docs.n8n.io/build/flow-logic/break-workflows-into-smaller-parts). Un nodo SQL, HTTP o Code adicional es **0 T/0 Q**. Un retry del nodo tampoco crea por sí solo otro workflow; un POST externo repetido sí crea otra raíz. Una llamada a 80 no acredita entrega: puede terminar por opt-out, guardas o contexto vacío.

Q1–Q8 son etiquetas de la auditoría de robustez, distintas de Q (cuota).

Los 16 JSONs live se obtuvieron con detalle completo. En todos: `active=true`, `versionId=activeVersionId` y `activeVersion.sameAsDraft=true`. Se consultó además el diff estructural histórico de los 12 workflows con versión distinta: **10 diffs disponibles**; n8n no encontró las versiones v2 de **23 y 24** (posible retención). Para esos dos se compara el live con la tabla/descripción v2 y la bitácora. En los otros cuatro la versión no cambió. Nodos incluye notas/noOp, por lo que su variación no mide T.

| Workflow | ID real rsuelvotest | Versión v2 → versión live V3 | Nodos | Diferencia material |
|---|---|---|---:|---|
| WF-02 | `kXuiHOMTxgR1Lo1O` | `706328cc-d442-40a1-9673-9ee3a183bcdf` → `2acdd177-ce2c-40ac-a24a-c0dd0dc65785` | 18→18 | Ayuda Q5 y supresión del fallback tras reserva ya atendida; status y dedup siguen antes de 03. |
| WF-03 | `sxmtEb1j2BlwoYXf` | `73ee48b6-4456-4d18-b2f4-39ce098f77f5` → `73ee48b6-4456-4d18-b2f4-39ce098f77f5` | 3→3 | Sin cambio: normalización y llamada a 04. |
| WF-04 | `0fw2ymvAY1hHoV9M` | `4d4d169c-65d5-4fda-b261-20ddd69295a0` → `e834ba1e-017f-4f7b-b132-735268af0cb9` | 20→35 | STOP ampliado/terminal, ayuda/R5 y M1/M2; +15 nodos internos, sin nuevo hijo. |
| WF-10 | `xFcZMG8Hip0Z6aH5` | `9484d2eb-2d95-46d5-8718-066df0c0d221` → `5249d844-eaed-47de-b5c0-be48c85b00f0` | 21→25 | Atajos ya_en_lista/lista_llena, título y contexto de errores Q7; m40 ya estaba. |
| WF-12 | `n9VUH43N8i7s9Rn2` | `f5ff4d52-7cff-4f55-bdc4-9199e56f095f` → `6d72176e-6be7-490b-b6b5-e72b28e3261d` | 13→9 | F5 cerrado: alta atómica v2 y Switch; 13→9 nodos no reduce ejecuciones. |
| WF-13 | `Qnr8SYR8sKGnzYKL` | `27b59091-4c08-4763-9206-0a7883c3b28c` → `27b59091-4c08-4763-9206-0a7883c3b28c` | 9→9 | Sin cambio contra v2: precios efectivos ya presentes; conserva .first() en construcción. |
| WF-14 | `JOT4yRctEcogiYzV` | `71781466-98b6-4e76-a996-2def875f5091` → `6d1527eb-3b38-435a-822f-38eeaab9d258` | 27→31 | Tres decisiones Q2 en ambos momentos: aceptar/rechazar/conservar. |
| WF-20 | `1FYWXdVw2swlFYcg` | `7d66e796-633d-4754-8622-545e92635437` → `79184aa1-79de-4fc7-bb40-d283588c08be` | 9→10 | QR por comercio y título con nombre comercial; conserva pedido/cobro/80. |
| WF-21 | `nJCQI6MfFSjUhywB` | `f855f389-79c6-454f-810e-647d15c2b0e9` → `fcb8c235-f080-4b92-864a-ac736b2010d8` | 34→35 | Contexto F6 hacia 23 y error técnico OCR/Q6 hacia revisión manual. |
| WF-22 | `53xUuvoriN3fqvHD` | `abc18837-a0de-4114-a5cc-7575e06787d1` → `35027f27-f3e9-43f4-91b0-5b8dbd7b0921` | 10→10 | Validación de esquema y parse_error explícito; conserva descarga y Storage. |
| WF-23 | `okF8Ayhp5CicRpVU` | `0a9e1418-ac54-40a6-b462-903d576ab12f` → `2feb8cd7-0000-4a05-a17e-9c8fa14f6a7c` | 10→10 | Contexto F6 y contenido Reject/Manual; misma cantidad de nodos. |
| WF-24 | `JU4QtP0vkAC7m3n1` | `18794c5d-54bd-40e4-ab82-7ab6dbf1884e` → `a7f28e6b-d169-49e0-b066-d79f4a673ab2` | 6→9 | F1–F3 cerrados: confirmado termina sin envío; vencida conserva salida; ya procesado/error silenciosos. |
| WF-25-A | `gVmvGYVPMlQKWk6z` | `5d24ea2f-d057-4dee-9da3-47a7c8110765` → `5d24ea2f-d057-4dee-9da3-47a7c8110765` | 9→9 | Sin cambio: callback PAGADO y solicitud de nombre vía 80. |
| WF-25-B | `9doLr3FSewZofRoN` | `5bcc1c92-62a5-4876-a311-254c9dc150f7` → `81fe4c93-41a0-4026-8401-77c2735b82ed` | 32→35 | Q1/Q4 y origen de nombre CONFIRMADO; ciudad única m38 conservada. |
| WF-25-C | `2DzqPBe4xtHIuvHA` | `014e536d-2281-47df-a01a-6b72375373b7` → `050cb1a2-6a91-4776-a089-8453faca4c74` | 17→17 | Cuatro estados silenciosos y SKU en guía; bypass de dedup aún presente. |
| WF-80 | `7V6MIPuGbdx9s0lT` | `c236c740-b4b0-45d0-b507-810a118235a8` → `c236c740-b4b0-45d0-b507-810a118235a8` | 19→19 | Sin cambio; frontera D9/D11 intacta. |

**WF-13 no cambió de versión respecto de v2**: la adaptación de precios efectivos m40 ya estaba incluida. WF-03, WF-25-A y WF-80 tampoco cambiaron. La versión actual de 20 supera la abreviada de F4 que aún aparece en Matriz; 04 incorpora M1/M2 aunque parte de su etiqueta conserve la fecha de Q/R5.

## 3. Usage fresco: historial observado y límites

Búsqueda global por fechas, tres páginas de **200 + 200 + 13**, deduplicadas por execution ID: **413 registros únicos**, todos de los 16 canónicos; no se sustituyó esto por el count histórico sin fecha de v2. Ventana **2026-09-11 00:00:00 → 2026-09-14 12:09:47 La Paz** (84 h 9 min 47 s), equivalente a `2026-09-11T04:00:00Z` → `2026-09-14T16:09:47Z`. La subventana de 24 h empieza `2026-09-13T16:09:47Z`.

| WF | T ventana | Raíces webhook | Hijos integrated | Estado error | Últimas 24 h: T / raíces |
|---|---:|---:|---:|---:|---:|
| WF-02 | 200 | 200 | 0 | 0 | 35 / 35 |
| WF-03 | 41 | 0 | 41 | 1 | 8 / 0 |
| WF-04 | 41 | 0 | 41 | 1 | 8 / 0 |
| WF-10 | 16 | 0 | 16 | 0 | 3 / 0 |
| WF-12 | 2 | 0 | 2 | 0 | 0 / 0 |
| WF-13 | 1 | 1 | 0 | 0 | 0 / 0 |
| WF-14 | 4 | 0 | 4 | 0 | 0 / 0 |
| WF-20 | 10 | 0 | 10 | 0 | 3 / 0 |
| WF-21 | 6 | 0 | 6 | 1 | 1 / 0 |
| WF-22 | 6 | 0 | 6 | 0 | 1 / 0 |
| WF-23 | 2 | 0 | 2 | 1 | 0 / 0 |
| WF-24 | 0 | 0 | 0 | 0 | 0 / 0 |
| WF-25-A | 3 | 3 | 0 | 0 | 1 / 1 |
| WF-25-B | 8 | 0 | 8 | 0 | 3 / 0 |
| WF-25-C | 16 | 16 | 0 | 1 | 3 / 3 |
| WF-80 | 57 | 0 | 57 | 0 | 10 / 0 |
| **Total** | **413** | **220** | **193** | **5** | **76 / 39** |

Raíces por entrada: **02=200 (90,9%)**, **13=1 (0,5%)**, **25-A=3 (1,4%)**, **25-C=16 (7,3%)**; redondeos independientes. No hay raíz Schedule, modo retry ni manual en los registros devueltos. Esto no acredita ausencia de ejecuciones purgadas/no guardadas, ni la configuración de retención o el consumo contractual del mes.

### Clasificación de las raíces y errores

**Cobertura final:** **220/220 raíces** con detalle y **5/5 ejecuciones con estado error** inspeccionadas. Hubo HTTP 429 temporal; tras esperar se completaron las lecturas. Se seleccionaron nodos y se limitó a un ítem cuando bastaba para clasificar; #550 se leyó sin truncar para contar grupos/destinatarios. No se copiaron payloads personales al informe.

- **WF-02:** **200/200** entradas: **159 status** (53 sent, 52 delivered, 53 read, **1 failed**), **41 admitidas hacia 03**, **0 descartes Duplicate End** y **0 otras**. Los status son **79,5% de las entradas de 02 y 72,3% de las 220 raíces**; failed es evidencia de que no corresponde descartar todo status sin decidir qué observabilidad preservar. Las **35/35 raíces de 02 de las últimas 24 h** sí se clasificaron: **27 status y 8 admitidas**, sin duplicados. Evidencia: #887 status; #882 ayuda/R5 llega a 80; #874/#866/#812 retornan cobro y no agregan un segundo envío en 02.
- **STOP:** #792 recorre 02→03→04, devuelve salida vacía y no llama a 80 desde 02. Es evidencia de un caso; las siete variantes se verificaron estáticamente, no mediante pruebas nuevas.
- **WF-13:** una ejecución, **#550**, success: **1 grupo**, **1 CLIENTE_NOTIFICADO** y **1 subejecución de 80**, salida success=true. **0 vacíos/1 callback** y **2 T/1 Q** observados para esa cadena. Se midió trabajo/llamada al gateway, no entrega física al comprador. Últimas 24 h: **0 llamadas/0 vacíos observados**.
- **WF-25-A:** 3/3 callbacks llegan a 80 (#619/#709/#830), con **3 id_pedido distintos**; no repetición de pedido en esta muestra.
- **WF-25-C:** **16/16** bodies y recorridos examinados: **4 PREPARANDO, 6 ENTREGADO y 6 guia_registrada**. **0 claves repetidas (id_envio, motivo/estado)** y **0 bodies idénticos**. Los 10 callbacks de estado serían silenciosos bajo el grafo actual; no se adjudica a todos silencio histórico porque hubo cambios durante la ventana. No confundir guía + ENTREGADO del mismo envío con un replay: son eventos distintos. No se observó doble llamada a 80 dentro de un mismo callback examinado.
- **Versiones mezcladas en la ventana:** #730 PREPARANDO y #678 ENTREGADO aún enviaron con versiones anteriores; no representan el grafo actual. En últimas 24 h, #859 PREPARANDO y #860 ENTREGADO son silenciosos; #861 guía llama a 80. **Silencioso cuesta 1 T/1 Q, no “gratis”**. La bitácora usa esa palabra para ausencia de aviso; no corresponde trasladarla a cuota.
- **Errores:** 408 success y 5 error. #572 (03), #573 (04), #574 (21) y #576 (23) propagan la cascada F6 documentada; raíz #571 figura success pero termina en **Close Event Error1**. Los detalles frescos de #574/#576 muestran que se intentó resolver `fn_rechazar_verificacion(p_resultado)`, sin `p_id_verificacion`; 03/04 fallaron al ejecutar su hijo. Es el incidente previo al fix de contexto, no una firma desconocida ni un fallo comprobado de la versión actual. #667 (25-C) sí expone error de FK en `tbl_notificaciones_envio` **después de alcanzar Send Guia via WF-80**: prueba concreta de que el envío no está dominado por dedup. No afirmar entrega física por ese dato. Son cinco registros de error, no cinco raíces fallidas ni cinco incidentes independientes.
- **Reintentos:** las cabeceras no contienen ejecuciones con modo retry y las 220 raíces examinadas no tienen vínculos retryOf/retrySuccessId. No se midieron intentos HTTP dentro de nodos ni reintentos de transporte pg_net/Meta. Un nuevo mensaje del comprador tiene otro ID y no es un retry n8n. La tasa de replay pg_net sigue sin demostrarse con esta muestra; no asignar toda repetición de estado a la red.
- **24 h recientes:** 76/76 success y 0 errores de cabecera. No equivale a 76 operaciones de negocio exitosas ni 10 entregas WhatsApp acreditadas por los 10 hijos de 80.

**Usage contractual pendiente:** obtener del panel, para esta misma ventana/ciclo, total que consume plan, retención y descartes. No hay acceso de lectura al panel de billing/Usage entre las herramientas expuestas. Se entregan ejecuciones relativas, sin dinero y sin proyección de producción desde una cuenta de pruebas.

## 4. Cadenas actuales por escenario

Definir **B = WF-02→WF-03→WF-04 = 3 T/1 Q** para un mensaje nuevo admitido. S = POSTs de status efectivamente recibidos asociados al escenario: añadir **S T/S Q**, sin asumir uno, dos o tres status por envío. Un lote HTTP no equivale automáticamente a varios B: 02 sigue normalizando los índices iniciales; no explotar esa limitación para “ahorrar”.

| Escenario | Cadena actual, una invocación por eslabón salvo indicación | T | Q |
|---|---|---:|---:|
| GET challenge/token incorrecto; POST solo status; mensaje duplicado detenido | 02 solamente | 1 | 1 raíz del modelo |
| Entrada sin formato/identidad utilizable | 02; si admite y normaliza, llega a B; eventual ayuda depende de contexto de salida | 1–4 | 1 |
| Texto de ayuda o R5 sin captura/lista prioritaria | B; lecturas dentro de 04; retorno→02→80 | 4 | 1 |
| STOP reconocido, persistido o terminal por fallo de resolución | B; no dispatch comercial ni ACK de salida añadido | 3 | 1 |
| SKU, reserva creada o existente | B→10→20→80; 02 no añade otra ayuda | 6 | 1 |
| SKU inexistente con contexto válido para responder | B→10; payload devuelto→02→80 | 5 | 1 |
| SIN_STOCK nuevo con cupo | B→10; pendiente y pregunta→02→80; **sin 12 todavía** | 5 | 1 |
| SIN_STOCK ya_en_lista o lista_llena | B→10; respuesta directa→02→80; **sin pendiente ni ronda SI** | 5 | 1 |
| SI/YO/OK/DALE, Momento 1 con pendiente aceptable | B→14→12→80 | 6 | 1 |
| NO Momento 1; ya en lista al aceptar; conservar cuando alcanza 14 | B→14→80 | 5 | 1 |
| SI Momento 2, oportunidad aceptada y reserva | B→14→20→80 | 6 | 1 |
| NO Momento 2 | B→14→80; rechazar y notificar siguiente son RPCs internas | 5 | 1 |
| Comprobante sin pedido pendiente | B→21→80; sin 22 | 5 | 1 |
| Comprobante con pedido, manual con ACK, ilegible o error técnico con derivación manual | B→21→22 y 21→80 | 6 | 1 |
| Automático, rechazo o revisión manual tras ACK | B→21→22; ACK→80; 21→23→80 | 8 | 1 |
| Automático confirmado, 24 sin envío propio + callback PAGADO | B→21→22; ACK→80; 21→23→24; **otra raíz** 25-A→80 | 10 | 2 |
| Nombre, punto, ciudad o re-pregunta Q1/Q4 con entrega pendiente | B→25-B→80 | 5 | 1 |
| Callback PAGADO válido; token inválido/pedido no PAGADO | 25-A→80; o 25-A solo | 2; 1 | 1 |
| Callback PREPARANDO/ASIGNADO/EN_RUTA/ENTREGADO/fallback | 25-C termina sin 80 | 1 | 1 |
| Callback guía o NO_ENTREGADO notificable | 25-C→80; bypass permite alcanzar envío antes de dedup | 2 en recorrido ordinario | 1 |
| WF-13 sin destinatarios / con N llamadas a 80 | 13 solo / 13→N×80 | 1 / 1+N | 1 |

Conteos ordinarios con contexto válido; un error puede cortar antes y una ejecución excepcional/replay requiere sus propios eslabones. Todos los hijos de 80 cuentan aunque finalmente salten el envío. El automático se documenta para completar el grafo: **D15 mantiene lanzamiento manual** y no se lo presenta como tráfico actual dominante ni se habilitó para medir.

### Ahorros ya incorporados y efectos de las ramas nuevas

- **Atajo ya_en_lista (m42):** antes, pregunta 5/1 + SI rechazado como YA_EN_LISTA por 14, 5/1; ahora respuesta directa 5/1. Diferencia **5 T/1 Q** si ese SI se habría enviado. **Lista llena (m43/OBS-006):** antes pregunta 5/1 + SI→14→12→80, 6/1; ahora 5/1: **6 T/1 Q**. Si el comprador no habría respondido, **0 Q ahorrado**. No aplicar esos números a todos los SKU ni sumarlos como propuesta nueva.
- **Silencios OBS-007/008:** por estado, 25-C→80 (2/1) pasa a 25-C (1/1): **−1 T/0 Q directo**, más los status de ese aviso que efectivamente desaparezcan. Una menor cantidad de “gracias/¿qué hago?” posteriores podría ahorrar raíces, pero no se atribuye sin medir. V3-A es el paso incremental: quitar también el callback silencioso antes de n8n.
- **Q3 STOP:** siete frases exactas normalizadas: STOP, NO QUIERO, NO ME CONTACTEN, NO ME CONTACTE, NO ME ESCRIBAN, NO ME ESCRIBAS, NO MOLESTAR. Se resuelve/persiste opt-out y se termina antes del dispatch/captura; si falla resolución o persistencia, rama terminal de error. **NO solo sigue siendo rechazo de lista, no STOP.** Las lecturas de identificación previas no generan T/Q adicionales.
- **Q2:** 14 aplica ACEPTAR/RECHAZAR/CONSERVAR en ambos momentos. CONSERVAR no libera turno ni consume pendiente; re-pregunta. 04 sigue despachando a 14 afirmativos y NO; no todos los textos arbitrarios llegan a la tercera rama de 14. No contar una llamada a 12 en CONSERVAR.
- **Q1/Q4/Q8:** 25-B filtra acuses/saludos/regateo reconocidos antes de guardar nombre/ciudad, re-pregunta según captura, valida entero completo y pertenencia al menú; entrada que empieza por dígito pero no es selección válida vuelve al menú. Guarda nombre con `p_origen_nombre:'CONFIRMADO'`. Esto evita escrituras incorrectas; el mensaje recibido sigue costando **5/1** cuando recorre captura. Los filtros son acotados, no validación geográfica completa ni clasificador universal.
- **Q5/Q7 y R5:** ayuda y errores conservan contexto de envío; consulta `fn_estado_pago_cliente(p_id_comercio,p_id_cliente)` solo lee. m52/53 restringen verificación/comprobante al contexto activo. “Ya pagué” no confirma, no crea cobro ni equivale a comprobante. **4/1** para esa rama, independientemente del número de SELECT/RPCs.
- **M1/M2 universal (m56/D16), distintos de los Momentos 1/2 de lista:** M1 intenta resolver SKU→comercio/sucursal, con fallback al canal; 10 conserva resolver efectivo por sucursal. M2 consulta teléfono y **adjunta `contexto_universal`** sobre Attach Commerce, sin reemplazar decisiones/IDs del routing actual. No afirmar que ya existe memoria o una nueva selección multicomercio. Ambos añaden nodos dentro de 04: **0 T/0 Q incremental**.
- **Q6/F6:** 22 valida salida y propaga parse_error; 21 separa error técnico de recibo inválido y conserva contexto hacia 23. Las reparaciones ya publicadas no son ahorro futuro. **Manual aún invoca 22 con pedido**: la rama `¿Automático?` está después del OCR/ACK. `active=true` de los workflows es distinto del modo comercial D15.

**NO Momento 2:** la llamada a `fn_notificar_siguiente_lista_espera` dentro de 14 no es una llamada a 13 y su definición final no envía pg_net. No inventar ese eslabón. La entrega del aviso al siguiente cliente y su correlación quedan como seguimiento funcional preexistente, sin ahorro atribuido.

### Venta completa manual, con etapas explícitas

SKU+QR **6/1** + comprobante/ACK **6/1** + confirmación directa desde app **0/0** + callback PAGADO→25-A→80 **2/1** = **14 T/3 Q**. Añadir **5 T/1 Q por mensaje de datos**: nombre y punto local (m=2), o nombre/punto/ciudad transporte (m=3). La pregunta verificada es **“¿A qué ciudad o población se envía?”**; no se solicita zona.

Con **c_s** callbacks silenciosos y **c_n** notificables (guía o NO_ENTREGADO), la fórmula vigente es:

**T = 14 + 5m + c_s + 2c_n + S; Q = 3 + m + c_s + c_n + S.**

| Venta ilustrativa sin status/reintentos | T | Q | Cambio incremental si se evitan callbacks silenciosos |
|---|---:|---:|---|
| Local: nombre+punto y un callback ENTREGADO, sin guía | 25 | 6 | 1 T/1 Q |
| Transporte hasta registrar ciudad, antes de callbacks logísticos | 29 | 6 | Ninguno todavía |
| Transporte anterior + un PREPARANDO + guía + ENTREGADO | 33 | 9 | 2 T/2 Q; guía queda intacta |

Guía puede generar **dos raíces**: aviso `guia_registrada` y cambio ENTREGADO por m48/49. El cierre en SQL no es una ejecución n8n. No asumir que todas las ventas atraviesan todos los estados. Para compra desde lista sustituir el SKU inicial por las etapas vividas: pregunta 5/1 + SI de alta 6/1 + aviso 13→80 2/1 (un destinatario) + SI de oportunidad 6/1. En un lote de avisos compartir la raíz 13, no imputarla completa a cada venta.

### Crons y lotes

**Ninguno de los 16 tiene Schedule/Cron, Loop Over Items ni Error Trigger.** WF-30 permanece fuera del conjunto, archivado; no recrear polling en n8n.

- [12_cron.sql](../02-Base-de-Datos/sql/12_cron.sql) y m26/m32: `rsuelvo_expirar_reservas` ejecuta `fn_cron_expirar_y_notificar` en PostgreSQL cada minuto. El job en sí cuesta **0 T/0 Q**. Solo si su POST llega a 13 aparece una raíz. Con K callbacks y N_j hijos de 80 por callback: **T=K+ΣN_j; Q=K**, más status. Sin callback, 0/0.
- [m47](../02-Base-de-Datos/sql/47_push_eventos_v1.sql): `rsuelvo_push_por_vencer`→`fn_cron_notificar_por_vencer`→`fn_push_evento`→Edge Function `notificar-reserva-sucursal`→FCM. Banda de vencimiento **60–120 segundos**, límite local 50 por pasada. **No llama a n8n ni WF-13: 0 T/0 Q siempre para esta ruta**. Ni ticks vacíos ni push enviados deben inflar “vacíos WF-13”. Tampoco convertir 1.440 ticks/día en supuestas ejecuciones de n8n.
- Los pg_net de pago/estado/guía sí tienen como destino webhooks n8n: **contar únicamente el workflow receptor**, sin añadir otra ejecución por el trigger, RPC, petición pg_net o push paralelo.

13 ya recibe un despertar global y busca todos los grupos ESPERANDO. m32 filtra stock y turno activo del grupo en el emisor; no equivale a garantía de destinatario al llegar: hay carreras y exclusión de cliente con otro turno. Consultar G grupos dentro de 13 aumenta RPCs, **no G raíces**. Solo los N hijos de 80 aumentan T. Reducir G sin reducir callbacks es **0 Q**.

Antes de cualquier coalescencia, revisar `.first()` en Build Message Payload de 13: comercio/nombre/precio/minutos deben corresponder al mismo ítem/sucursal. **No convertir 80 a lote** para ahorrar N−1 hijos: sus guardas usan primeros ítems, comprometiendo opt-out/identidad por destinatario. El supuesto ahorro sería solo T.

## 5. Tabla por workflow: baseline → propuesta → ahorro → riesgo

Las cantidades de esta tabla son **invocaciones locales de cada workflow**, no totales de cadena para volver a sumar. IDs exactos y versiones en §2; HU tomadas de Matriz, conservando ceros iniciales.

| WF / HU | Ejecuciones actuales por escenario | Propuesta vigente | Ahorro incremental | Riesgo |
|---|---|---|---|---|
| 02 / HU-121,143 | 1 raíz por entrada, incluso status/duplicado | P3; validación temprana de forma sin perder mensajes del lote | 1 T/1 Q por POST evitado externamente; filtro interno 0 Q | Medio/alto |
| 03 / HU-122 | 1 hijo por mensaje nuevo admitido; llama a 04 | P7 opcional: inline solo transformación y enlace directo a 04 | 1 T/mensaje, **0 Q**; 41 hijos observados como techo técnico | Bajo/medio: contrato y otros callers |
| 04 / HU-123,142 | 1 hijo por mensaje normalizado; M1/M2/R5 no añaden hijos | Conservar Q3/D16/R5; P8 contexto sin modificar semántica | 0 T/0 Q por ahorrar lookups; V3-B solo si evita otra entrada | Medio/alto por identidad |
| 10 / HU-037–041,043 | 1 por SKU; 20 si reserva, sin 12 en atajos | Atajos implementados; conservar m40/m42/m43/m55/m56 | 0 nuevo; ahorro de ronda ya incluido en §4 | Alto si se mueve decisión de stock/cupo a Code |
| 12 / HU-043,044 | 1 hijo en SI Momento 1 aceptable | Mantener v2 atómica m41; v1 eliminada m54 | 0 nuevo; 4 nodos menos no son 4 ejecuciones | Alto si vuelve precheck |
| 13 / HU-045,049,053 | 1 raíz por callback; N hijos 80 | P4 condicionado y correlación efectiva por ítem | 1 T/1 Q por vacío externo evitado; K−1 por coalescencia segura | Medio/alto |
| 14 / HU-043,046–049 | 1 por decisión; hijo 12,20 u 80 según rama | Q2 implementado; conservar consentimiento y turno | 0 nuevo demostrado | Alto por lista |
| 20 / HU-042,056 | 1 hijo por reserva nueva/existente u oportunidad aceptada | Mantener QR de comercio, título y snapshot; reutilización por 10/14 | 0 nuevo | Alto si se suprime reenvío legítimo |
| 21 / HU-057,058,146 | 1 por media; 22 con pedido aun en manual | P5 implementada; P6 opcional para OCR manual | Hasta 1 T por 22 omitido, **0 Q**, si Storage queda cubierto | Medio/alto |
| 22 / HU-059,146 | 1 hijo por comprobante con pedido; no decide venta | Mantener parser Q6; separar OCR de captura durable solo si se diseña P6 | Nodos/API omitidos 0 T/0 Q; omitir hijo completo 1 T/0 Q | Medio/alto |
| 23 / HU-060–064,141 | 1 hijo solo en rama automática; 2 en historial de pruebas | F6 cerrado; conservar contrato y D15 | 0 nuevo; no activar automático para ahorrar | Alto por pagos |
| 24 / HU-076,078–081 | 1 al confirmar automático; 0 en ventana; confirmado sin 80 propio | F1–F3 cerrados; 25-A único emisor | 0 nuevo; intervención funcional excluida | Alto |
| 25-A / HU-076 | 1 raíz por PAGADO; +80 si válido | P2 dedup/recuperación de repetidos, sin quitar aviso único | 1 T/0 Q si detiene hijo repetido; 2 T/1 Q si evita raíz notificable | Medio |
| 25-B / HU-077,086 | 1 hijo por nombre/punto/ciudad/corrección | P1 descartada; V3-B y P8 solo contexto/instrucciones | P1 0/0; cada ronda correctiva evitada 5 T/1 Q | Medio; Q/m38 son invariantes |
| 25-C / HU-092–094,143 | 1 raíz siempre; +80 solo guía/NO_ENTREGADO en grafo actual | V3-A y P2; recuperar body tras dedup | 1 T/1 Q por callback silencioso externo evitado; repetidos según P2 | Medio |
| 80 / HU-124,142,144,145 | 1 hijo por intento; 57 observados, no 57 entregas acreditadas | **No tocar**; reducir solicitudes prescindibles aguas arriba | 0 ahorro propio propuesto | Alto: D9/D11 y opt-out |

## 6. Estado de P1–P8 y pasos futuros

| ID histórico | Estado V3 | Evidencia y alcance actual |
|---|---|---|
| **P1** | **Descartada** | Reintroducir ciudad+zona contradice m38. 25-B `81fe4c93` pregunta solo ciudad/población. 0/0 incremental; nombre residual “Send Pide Zona” no prueba captura de zona |
| **P2** | **Vigente** | 25-C `050cb1a2` mantiene dos salidas de Token válido?: directa a ¿Guía? y a Dedup; 25-A `5d24ea2f` sigue sin dedup de aviso. Silencios implementados superan la parte de ruido por estados, pero no cierran idempotencia |
| **P3** | **Vigente** | 02 `2acdd177` filtra status dentro de la raíz; falta evaluar prevención externa. Beneficio directo condicionado y medible |
| **P4** | **Vigente, condicionada a medición** | 13 `27b59091` sigue con webhook global; m32 ya evita muchos vacíos. No hay Schedule n8n para reducir. Única raíz examinada: 1 destinatario, 0 vacíos |
| **P5** | **Implementada en su núcleo; superada como reparación pendiente** | 21 `fcb8c235`, 22 `35027f27`, 23 `2feb8cd7`: F6/Q6 contexto y parse_error. Reenvíos residuales son medición de V3-B, no repetir intervención F |
| **P6** | **Vigente, beneficio técnico** | 21 llama a 22 antes de ¿Automático?; 22 conserva descarga/Storage/URL firmada. D15 vuelve pertinente omitir OCR opcional, pero **0 Q directo** |
| **P7** | **Vigente, baja prioridad de cuota** | 03 `73ee48b6`: normalización pequeña más llamada a 04. Inline evita 1 hijo, **0 Q** |
| **P8** | **Vigente con alcance reducido por cambios ya hechos** | R5/M2/Q7/Q8 y m40 ya resuelven parte del contexto. Duplican lecturas entrega 04/25-B y construcción de payloads, sin ahorro directo T/Q |

### Secuencia propuesta para el orquestador, sin implementar aquí

1. **P3 — WF-02 (`kXuiHOMTxgR1Lo1O`), HU-121/143; `tbl_whatsapp_eventos`, `fn_registrar_evento_whatsapp`, `fn_cerrar_evento_whatsapp`.** Verificar cuáles status necesita operación y qué mecanismo soportado puede filtrarlos antes de crear la raíz. Diseñar un ingreso que autentique y preserve todo mensaje comercial/STOP de payloads mixtos; registrar lo requerido por Regla 9. Comparar POSTs recibidos/reenviados y Usage en ventanas iguales. No cambiar la suscripción de mensajes suponiendo que permite aislar status; no está verificado. Si todos los status deben conservarse en n8n, **descartar ahorro Q de P3**, sin ocultarlos solo para reducir métricas.

2. **V3-A — WF-25-C (`2DzqPBe4xtHIuvHA`), HU-092–094/127; `tbl_envios`, `tbl_env_seguimiento_estados`, `tbl_logs_auditoria`; `fn_notifica_envio_estado` m30 y `fn_registrar_guia` m49.** El orquestador prepara una futura migración para omitir únicamente el POST WhatsApp de los cuatro estados ya silenciosos. Preservar mutación/seguimiento/auditoría, triggers push m47 y callback guia_registrada con SKU. Mantener NO_ENTREGADO. Evaluar si `tbl_notificaciones_envio` necesita mantener la marca de eventos silenciosos en BD. Validación futura: cierre de guía conserva aviso único, historial y push; cae solo el número de raíces silenciosas. No borrar ni cancelar datos logísticos para producir el ahorro.

3. **P2 — WF-25-C + WF-25-A (`gVmvGYVPMlQKWk6z`), HU-076/092–094/143; `tbl_notificaciones_envio`, `tbl_pedidos`, `tbl_logs_auditoria`.** Diseñar dedup transaccional y recuperable en `fn_*` (contrato nuevo aún por definir, no inventado como existente). Un único camino token→decisión dedup→contexto original→tipo→80. Actualmente el INSERT devuelve solo id_envio y la ruta directa conserva body: no basta borrar una conexión sin restaurar el contrato. Distinguir evento ya entregado de intento que falló después de marcarlo; una marca previa sin recuperación puede perder el aviso. Para 25-A usar identidad de transición PAGADO, no teléfono global. Validación futura con replays y fallo parcial, sin reejecutar pagos. No prometer “exactamente una entrega” si el proveedor no da garantía idempotente.

4. **P4 — WF-13 (`Qnr8SYR8sKGnzYKL`), HU-045/049/053; `tbl_lista_espera`, `tbl_inventario`; `fn_cron_expirar_y_notificar` y `fn_notificar_siguiente_lista_espera`.** Ampliar la ventana de producción: #550 ya está verificada con un grupo y un destinatario, sin vacío. Medir callbacks, grupos, candidatos, destinatarios y carreras. Solo con vacíos/repetidos relevantes, proponer elegibilidad más precisa/coalescencia en BD con recuperación, turno único y expiración intactos. Antes de agrupar, corregir correlación de ítems de 13 en intervención funcional específica; usar valores efectivos de cada sucursal. No subir arbitrariamente el intervalo de expiración ni sustituir reglas por un IF de stock.

5. **V3-B — WF-02/04/10/14/21/25-B, HU-039/043–049/057–065/076/077/086/123; `tbl_whatsapp_eventos`, `tbl_lista_pendiente`, `tbl_entrega_captura`, `tbl_verificaciones`; RPCs de captura/lista y `fn_estado_pago_cliente`.** Medir re-preguntas y mensajes correctivos por contexto, separados de nuevas compras y consentimiento. Ajustar una instrucción/acuse contextual solo donde haya confusión residual demostrada, sin añadir una respuesta por cada fragmento del mensaje. Comparar rondas por venta y no solo envíos. Q1–Q8, R5, atajos y pregunta m38 **ya implementados no se vuelven a presupuestar**.

6. **P6/P7/P8 — mejoras técnicas secundarias.** P6 (21/22; HU-057–059/146): preservar descarga, Storage, URL, registro de comprobante, congelamiento m44, revisión humana y auditoría al omitir OCR manual; si se deja 22 ejecutándose solo para subir archivo, ahorro T=0. P7 (02/03/04; HU-121–123): comprobar callers y contrato multiítem; conservar normalización y enlace a 04 en el llamador. P8 (04/10/13/20/25-B; HU-037–045/056/077/086/123): reutilizar contexto dentro de la invocación sin cache de opt-out/precio ni autoridad comercial stale. No crear un subworkflow diminuto por cada lookup: añade T sin reducir Q.

**F1–F5:** intervención cerrada según bitácora y versiones actuales de 24/20/12. No se re-auditan como cinco ahorros ni se reabre la carga de QR ya tratada. F6 también fue cerrado; #574/#576 son evidencia histórica del incidente, no prueba de un bug presente en la versión V3.

## 7. Guardado, duplicación y ramas de error

En **cada uno de los 16** JSONs los settings explícitos son `executionOrder:v1`, `binaryMode:separate`, `availableInMCP:true`. **No están declarados** `saveExecutionProgress`, `saveDataSuccessExecution` ni `saveDataErrorExecution`: **heredados/no determinados** para los 16, no “true” o “false” inferidos del historial.

| Workflows | Progress / Success / Error observados | Propuesta futura de guardado | T/Q |
|---|---|---|---|
| 02,03,04,10,12,13,14,20,21,22,23,24,25-A,25-B,25-C,80 | Ausente / ausente / ausente en todos | Obtener defaults efectivos antes de afirmar ahorro de almacenamiento | 0/0 |
| 03,04 y luego 02/13/25-C estabilizados | Igual | Evaluar progress=false y success=none con una estrategia de diagnóstico/medición previa; al ser por workflow puede ocultar también éxitos comerciales útiles | 0/0 |
| 10,12,14,20,21,22,23,24,25-A/B | Igual | Conservar visibilidad mientras se verifican retornos, binarios y recuperación; minimizar éxito solo después | 0/0 |
| Todos salvo 80 | Igual | Mantener error=all en la propuesta inicial y validar Regla 9; no borrar registros históricos | 0/0 |
| 80 | Igual | **No cambiar settings ni interior en este paquete** | 0/0 |

Guardar menos reduce datos/latencia potenciales; no devuelve cuota consumida. Las opciones y su relación con recuperación se describen en [settings oficiales](https://docs.n8n.io/build/manage-workflows/configure-workflow-settings). Antes de desactivar guardado de éxito, tener en cuenta #571: un workflow success puede contener fallo capturado. Los logs canónicos no se sustituyen por el historial de n8n, pero tampoco se certificó desde BD que hoy cubran todos los diagnósticos. No declarar ahorro de bytes sin tamaños/retención.

**Duplicación:** 04 y 25-B consultan entrega pendiente; 04/M1 y 10 resuelven variante; varios Builds repiten contrato top-level para 80. Son candidatos a reutilización limitada, **0 T/0 Q por consulta eliminada**. Mantener revalidación transaccional al mutar y separar comercio/sucursal/precio efectivo. Que M1 traiga precio no autoriza recalcular o sustituir snapshot del pedido.

**Errores/cascadas:** ningún JSON tiene `settings.errorWorkflow` explícito ni Error Trigger entre los 16. No se verificó configuración externa; no inventar WF-00 ejecutándose por cada error. 21 reintenta `fn_iniciar_verificacion` hasta 4 intentos/1 s; 22 tiene retry en el HTTP OCR; 80 tiene retry Meta/OpenWA hasta 4/2 s. Son intentos internos, **0 Q adicional** mientras no se reingrese al workflow. Mantener D9/D11 y recuperación. El coste extra de un reenvío del comprador nace de otra raíz; el de un error propagado no convierte cada hijo fallido en cuota.

## 8. No tocar

1. **WF-80 `7V6MIPuGbdx9s0lT` — D9/D11; HU-124/142/144/145.** Única salida, cola/rate-limit/breaker y consulta `fn_cliente_optado` por envío. Sin inline, lotes, emisor alternativo, cache de opt-out ni cambios de settings.
2. **Opt-out e idempotencia — WF-02/04/80; HU-121/142/143.** Conservar `tbl_contact_preferences`, `fn_registrar_opt_out`, `tbl_whatsapp_eventos` y contratos de registrar/cerrar. STOP precede captura/dispatch; fallo de resolución no habilita tratarlo como nombre/ciudad. No deduplicar mensajes distintos por texto o teléfono. Resolver P2 debe reforzar estas garantías.
3. **Reglas 2/3/9 — HU-127–131, stock/pagos/listas.** Decisiones/mutaciones en `fn_*`, auditoría en `tbl_logs_auditoria` y triggers. No pasar decisiones a Code, suprimir logs ni cambiar BD en esta auditoría.
4. **m40 y m55/m56/D16 — WF-04/10/13/20; HU-037–045/056/123.** Resolver con comercio+SKU+sucursal, `fn_variante_efectiva`, overrides `tbl_variante_sucursal` y snapshot `tbl_pedido_detalles`. No mezclar precio global, primera fila o sucursal distinta. Mantener generación sin O y tolerancia legacy O→0; no reabrir links/memoria/remodelo de canal descartados por D16.
5. **OBS-001/006 y m41–43/54 — WF-10/12/13/14; HU-043–049/053.** Consentimiento de nuevos con cupo, prioridad ya_en_lista antes de lista_llena, turnos/expiración, tres decisiones Q2 y alta atómica v2. No recuperar fn_agregar_lista_espera v1.
6. **OBS-002/003/004/005 — WF-20/25-A/B/C; HU-042/056/076/077/086/092–094.** QR unificado por comercio, nombre, puntos por sucursal, ciudad única libre sin zona ni costo de transporte añadido, guía/foto/código. No suprimir una pregunta obligatoria para bajar Q.
7. **D5/D13/D14/D15 y m44 — WF-21–24/25-A; HU-057–065/076/078–081/141/146.** Humano confirma en lanzamiento; crédito de venta en transacción; comprobante protege reserva PAGO_VALIDANDO sin revivir vencidas; rechazo permite reenvío. 25-A es único aviso de confirmación. No habilitar automático ni tocar umbrales para medir/optimizar.
8. **Silencios OBS-007/008, SKU OBS-009 y Q1–Q8/R5 OBS-010.** No reactivar mensajes retirados, quitar guardas conversacionales ni volver a afirmar pago por texto. Preservar m48/49 y guarda de pedido impago.
9. **Expiración PostgreSQL y push m45–47.** No recrear WF-30, degradar vigencias ni trasladar FCM/por-vencer a n8n. V3-A solo trata callbacks WhatsApp prescindibles; auditoría y push siguen independientes.

## 9. Contratos locales ya verificados y pendientes reales

**No volver a pedir como “firmas desconocidas” lo disponible en SQL local.** Se leyó el orden final de redefiniciones, no solo la primera coincidencia de 06:

| Contrato / migraciones | Firma o cambio confirmado en archivos | Consecuencia para la auditoría |
|---|---|---|
| Lista/captura m31/34/35/38 | `fn_pendiente_lista(uuid,uuid,uuid,uuid)`; `fn_aceptar_pendiente_lista(text)`; `fn_rechazar_pendiente_lista(text)`; `fn_iniciar_captura_destino(uuid,uuid)`; `fn_entrega_captura_estado(text)`; `fn_procesar_captura_destino(text,text)` | Dos momentos; ciudad única; no pedir esas firmas al orquestador |
| Catálogo m40 | `fn_resolver_variante_por_sku(p_id_comercio uuid,p_sku text,p_id_sucursal uuid DEFAULT NULL)`; `fn_variante_efectiva(p_id_variante uuid,p_id_sucursal uuid)`→TABLE(nombre,precio,activo); `fn_listar_variantes_sucursal(uuid)`; snapshot efectivo en `fn_crear_pedido_desde_reserva(uuid)` | Enviar sucursal; no compartir precio global/primer grupo. Valores globales retornados por aceptar pendiente no son fuente de precio efectivo |
| m41–43 y m54 | `fn_agregar_lista_espera_v2(p_id_comercio uuid,p_id_sucursal uuid,p_id_variante uuid,p_id_cliente uuid)`→jsonb; `fn_solicitar_reserva` añade flags ya_en_lista/lista_llena; m54 elimina v1 | Alta atómica y atajos ya implementados, no nuevas RPCs pendientes |
| m44 | `fn_registrar_comprobante` conserva contrato y añade congelamiento ACTIVA→PAGO_VALIDANDO | Cambio dentro de la transacción: 0 T/0 Q |
| m45–47 | Dispositivos; trigger reserva; dispatcher `fn_push_evento(text,jsonb)`; `fn_cron_notificar_por_vencer()`→integer | Push/Edge Function/FCM fuera de n8n; 0/0 |
| Guía m36→48→49 | `fn_registrar_guia(p_id_envio uuid,p_numero_guia text DEFAULT NULL,p_guia_foto_url text DEFAULT NULL)`→jsonb; cierre de envío/pedido con guarda y SKU snapshot en payload | Firma resuelta; guía + transición pueden despertar 25-C por separado |
| m50 | `fn_upsert_cliente` pasa a 8 argumentos con `p_origen_nombre text DEFAULT 'PERFIL'`; sobrecarga de 7 eliminada | 25-B usa CONFIRMADO; perfil no debe sustituir nombre confirmado |
| m51→52→53 | `fn_estado_pago_cliente(p_id_comercio uuid,p_id_cliente uuid)`→jsonb, STABLE; verificación y comprobante acotados a contexto activo | R5 solo lee; no cobrar ni confirmar por texto |
| m55 | Generación SKU base35 sin O; decoder tolera O→0 | No confundir número de migración con la antigua colisión “54 SKU” |
| m56 | `fn_resolver_sku_universal(p_sku text)`; `fn_contexto_por_telefono(p_telefono text)`, ambas jsonb/STABLE | M1 resuelve; M2 se adjunta en live; nodos internos 0/0 |

**Pendientes de verificar, con responsable/uso:**

- **Orquestador / Usage:** lectura del panel contractual y defaults/retención de n8n para conciliar raíces con consumo del plan; volumen representativo fuera de pruebas. No falta dinero para expresar los escenarios relativos.
- **Histórico n8n:** solo faltan los snapshots v2 de 23 (`0a9e1418-ac54-40a6-b462-903d576ab12f`) y 24 (`18794c5d-54bd-40e4-ab82-7ab6dbf1884e`) para un diff estructural exacto: el endpoint informó versión no encontrada, posiblemente por retención. Buscar export histórico si se requiere. **No falta ninguno de los 16 JSONs live ni la clasificación de las 220 raíces**; el 429 temporal quedó resuelto.
- **Orquestador / evidencia operativa BD (fuera de esta auditoría):** configuración desplegada de crons y transporte, correlación de requests pg_net con execution IDs y política real de reintentos; correspondencia entre emisor m30/m32/m49 y despliegue. Las firmas locales están resueltas; no se certificó igualdad con catálogo cloud porque se prohibió tocar BD.
- **P3:** posibilidad de suprimir solo status elegibles antes de n8n, sin perder mensajes de lotes ni observabilidad requerida. Sin esa verificación el techo no es ahorro realizable.
- **P2/P4:** replays, vacíos y recuperación tras fallo de envío; medir antes de diseñar garantías. Para 13, revisar correlación m40 por ítem antes de lotes. No inferir duplicados pg_net por dos eventos distintos del mismo envío.
- **V3-B/P6/P8:** rondas correctivas, envío real frente a success, necesidad de OCR manual y contrato de captura durable; contexto multicomercio y aviso al siguiente en NO Momento 2 son seguimientos funcionales, no ahorros contabilizados.
- **Validación futura:** casos de replay/STOP/lote mixto, guía+ENTREGADO, error parcial de envío, dos sucursales con precios diferentes y consentimiento de lista. No se ejecutaron pruebas nuevas: producirían mensajes/mutaciones prohibidos por el alcance.

## 10. Cambios respecto de v2

- Relectura de los **16 live**, inventario completo y **12 versiones renovadas**; se distingue WF-13 efectivo ya presente de cambios posteriores.
- Cadenas recalculadas para atajos, silencios, Q1–Q8/R5, universal M1/M2 y confirmación con 25-A único emisor; fórmula de venta separa callbacks silenciosos/notificables.
- Historial fresco y paginado: 413 cabeceras, 220 raíces clasificadas y 5 errores inspeccionados; 0 vacíos de 13 y 0 replays de callbacks en la muestra. Cifras de v1/v2 no se presentan como Usage actual.
- Estado explícito P1–P8. P1 permanece descartada; P5 núcleo implementado; F1–F6 cerrados y excluidos de ahorro futuro.
- m41–56 incorporadas; por-vencer/push excluidos de T/Q. Settings y menos RPCs se clasifican como almacenamiento/latencia, nunca cuota.
- Top 5 limitado al diseño vigente; V3-A identifica la diferencia entre **silenciar dentro** y **evitar una raíz**.

**Resultado:** informe para priorizar una intervención posterior; ninguna propuesta de este documento fue aplicada.
