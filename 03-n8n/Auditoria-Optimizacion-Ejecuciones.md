# Auditoría de optimización de ejecuciones n8n — RSUELVO

**Fecha:** 2026-09-11, corte aproximado 09:53 America/La_Paz.
**Cuenta verificada:** `rsuelvotest.app.n8n.cloud`. **Alcance:** los 16 workflows canónicos activos de Matriz §0; WF-30 archivado excluido.
**Modalidad:** solo lectura. Se inspeccionaron documentos, exports y JSONs live publicados mediante MCP; se leyeron metadatos y una muestra acotada de ejecuciones existentes. No se ejecutó ningún workflow, webhook, consulta a BD ni cambio remoto. Este informe es el único archivo creado.

> **ADDENDUM DEL ORQUESTADOR (2026-09-11, v1 → v2):**
> - **P1 INVALIDADO.** Proponía pedir CIUDAD+ZONA juntas siguiendo el texto m37 de OBS-005, pero la
>   decisión vigente es **m38: solo ciudad, zona eliminada** (bitácora 2026-09-09 + `fn_procesar_captura_destino`
>   con `destino_zona=NULL` + OBS-005 corregida). Se mantiene solo-ciudad; no reintroducir zona.
> - **Falta m40.** El informe no incorpora el catálogo por sucursal (migración 40, 2026-09-10):
>   `fn_resolver_variante_por_sku(p_id_comercio, p_sku, p_id_sucursal)`, `fn_variante_efectiva`,
>   precios/nombres efectivos ya usados en WF-10/WF-13. Las firmas están en el vault
>   (`02-Base-de-Datos/sql/40_*`, `06_functions.sql`) — no quedan como "pendiente".
>   Igual para `fn_registrar_guia` (archivo 36) y el trío Momento 1 (archivo 35).
> - **Bugs verificados por el orquestador en JSON live** (paquete de intervención separada):
>   WF-24→WF-22 en vez de WF-80, espacio final en IF de WF-24, texto Dirección/Referencia vs OBS-003,
>   `media_url` común vs ruta por comercio en WF-20, precheck de capacidad en WF-12 (anti-Regla 3).
> - Se solicita **v2** del informe con m38+m40 incorporados (ver prompt v2).

## 1. Resumen ejecutivo

**La principal corrección del modelo de ahorro: una subejecución no equivale a una ejecución consumida del plan.** n8n documenta que las invocaciones mediante Execute Sub-workflow no cuentan para el límite mensual. Por tanto, fusionar WF-03 o reducir llamadas internas puede disminuir latencia y trabajo, pero su ahorro directo de cuota es **0**. El ahorro de cuota se obtiene evitando entradas de producción: mensajes adicionales, callbacks duplicados o despertares vacíos. No se consultó el contrato ni el panel Usage de esta cuenta y no se atribuyen importes monetarios. [Documentación oficial de sub-workflows](https://docs.n8n.io/build/flow-logic/break-workflows-into-smaller-parts).

Convenciones del informe:

- **T:** ejecuciones técnicas de workflows, incluida la raíz y cada invocación de un hijo.
- **Q:** entradas de producción potencialmente computables para cuota; se excluyen los hijos Execute Workflow conforme a la documentación. Requiere conciliación con Usage.
- **S:** POSTs de status de Meta efectivamente recibidos por WF-02. No se presupone uno por mensaje enviado: dependen de estados, agrupación y reintentos.
- **R:** POSTs repetidos del mismo evento de negocio. Un mensaje nuevo del comprador con otro message_id no es automáticamente un duplicado.
- Los conteos son por un ítem y por la rama indicada, salvo fórmulas de lote. Se distingue diseño alcanzable de comportamiento probado; no se certifica una venta automática E2E.

### Top 5 oportunidades por ahorro/riesgo

| Orden | Oportunidad | Ahorro relativo estimado | Evidencia / riesgo |
|---|---|---|---|
| 1 | Corregir la pregunta de destino en WF-25-B para pedir **CIUDAD y ZONA juntas**, preservando OBS-005 | Por conversación que hoy exige un reenvío: **5 T + 1 Q**, más los status evitados de la respuesta adicional. Si el comprador ya responde completo: 0 | Live pide solo ciudad, pero el flujo ya trata el resultado final de captura. Bajo; validar contrato con el orquestador |
| 2 | Hacer efectiva la deduplicación de WF-25-C y cubrir la repetición de WF-25-A | Por callback repetido que hoy envía: **1 T** de WF-80; **0 Q directo** si sigue entrando al webhook, más **S evitados**. Si el emisor evita también el callback: **2 T + 1 Q** por repetición | Bypass comprobado en 25-C; 25-A sin dedup visible. Medio; no perder entrega ante fallo parcial |
| 3 | Filtrar antes de n8n los status/entradas técnicas prescindibles, solo si existe un receptor autorizado con trazabilidad equivalente | Por POST realmente suprimido antes de WF-02: **1 T + 1 Q**. Un IF dentro de WF-02 ahorra **0 Q** | Status ya termina temprano; ejecución 473 lo confirma. Medio/alto por infraestructura y requisitos de status; propuesta condicionada, no desuscribir a ciegas |
| 4 | Evitar despertares vacíos y coalescer notificaciones de WF-13 en el emisor existente | Por despertar vacío evitado: **1 T + 1 Q**. Para K callbacks equivalentes coalescidos en uno: **K−1 T y Q** de raíces; hijos según destinatarios reales | WF-13 es webhook y escanea todos los grupos. No hay ejecuciones retenidas en la búsqueda; frecuencia externa pendiente. Medio/alto por coordinación BD |
| 5 | Corregir contratos/errores de pago WF-21/22/23/24 para evitar reenvíos inducidos por fallos técnicos | Cada comprobante reenviado innecesariamente con pedido: aproximadamente **6 T + 1 Q**, más status; número de casos desconocido. Eliminar OCR accidental de WF-24: **1 T** si se suprime esa llamada; **0 T neto** si se reemplaza por un envío necesario | ID incorrecto confirmado en WF-24 y errores OCR mal tipados. Medio/alto; es primero corrección funcional, no ahorro garantizado |

No sumar estas cifras sin atribución causal: una conversación evitada puede estar incluida en varios hallazgos. No existe evidencia para prometer un porcentaje global mensual.

## 2. Fuentes, jerarquía y cobertura

Se usó el vault **`/home/nico/obsidian/Rsuelvo-CLEAN`**, cuyo PROMPT v1.5 y Matriz §0 contienen la migración 2026-09-09 y D13/D14. La otra copia `Rsuelvo` conserva un PROMPT anterior. Lectura de referencia: [PROMPT MAESTRO](../00-Index/00-PROMPT-MAESTRO-RSUELVO.md), [Matriz](Matriz-Consistencia-WF-BD-HU.md), [workflows](workflows.md), [Checklist](Checklist-Migracion-n8n.md), [OBS-001…005](../07-Control-de-Calidad/Observaciones-Usuario.md), y luego los JSONs de `~/Escritorio/WORKFLOWS EXTRAIDOS FINAL/rsuelvo-workflows/`.

Precedencia: reglas/decisiones del PROMPT para lo normativo; Matriz §0 para IDs; JSON publicado live para lo que está implementado. Las contradicciones se registran aquí sin editar fuentes. La autorización de crear solo este informe prevalece sobre la regla documental general de actualizar matrices.

**16/16 lecturas live satisfactorias:** todos activos, no archivados, `activeVersion.sameAsDraft=true`; versión publicada coincide con el borrador consultado. No se usó el nombre del nodo como prueba de su destino.

| Workflow | ID real rsuelvotest | Versión publicada inspeccionada | Nodos |
|---|---|---|---|
| WF-02 | `kXuiHOMTxgR1Lo1O` | `706328cc-d442-40a1-9673-9ee3a183bcdf` | 18 |
| WF-03 | `sxmtEb1j2BlwoYXf` | `73ee48b6-4456-4d18-b2f4-39ce098f77f5` | 3 |
| WF-04 | `0fw2ymvAY1hHoV9M` | `4d4d169c-65d5-4fda-b261-20ddd69295a0` | 20 |
| WF-10 | `xFcZMG8Hip0Z6aH5` | `9484d2eb-2d95-46d5-8718-066df0c0d221` | 21 |
| WF-12 | `n9VUH43N8i7s9Rn2` | `f5ff4d52-7cff-4f55-bdc4-9199e56f095f` | 13 |
| WF-13 | `Qnr8SYR8sKGnzYKL` | `27b59091-4c08-4763-9206-0a7883c3b28c` | 9 |
| WF-14 | `JOT4yRctEcogiYzV` | `71781466-98b6-4e76-a996-2def875f5091` | 27 |
| WF-20 | `1FYWXdVw2swlFYcg` | `7d66e796-633d-4754-8622-545e92635437` | 9 |
| WF-21 | `nJCQI6MfFSjUhywB` | `f855f389-79c6-454f-810e-647d15c2b0e9` | 34 |
| WF-22 | `53xUuvoriN3fqvHD` | `abc18837-a0de-4114-a5cc-7575e06787d1` | 10 |
| WF-23 | `okF8Ayhp5CicRpVU` | `0a9e1418-ac54-40a6-b462-903d576ab12f` | 10 |
| WF-24 | `JU4QtP0vkAC7m3n1` | `18794c5d-54bd-40e4-ab82-7ab6dbf1884e` | 6 |
| WF-25-A | `gVmvGYVPMlQKWk6z` | `5d24ea2f-d057-4dee-9da3-47a7c8110765` | 9 |
| WF-25-B | `9doLr3FSewZofRoN` | `5bcc1c92-62a5-4876-a311-254c9dc150f7` | 32 |
| WF-25-C | `2DzqPBe4xtHIuvHA` | `014e536d-2281-47df-a01a-6b72375373b7` | 17 |
| WF-80 | `7V6MIPuGbdx9s0lT` | `c236c740-b4b0-45d0-b507-810a118235a8` | 19 |

Los 17 JSONs del directorio principal representan 16 flujos y una segunda copia de WF-25-C; `_BORRAR` se identificó como histórico y no integra los 16. Los exports tienen referencias de la cuenta anterior y varios carecen de id/version internos. Diferencias materiales: WF-22 export tiene 6 nodos frente a 10 live; WF-25-B 31 frente a 32; WF-24 export apuntaba al gateway antiguo, mientras live apunta a WF-22. No importar estos exports como corrección.

### Muestra de ejecuciones existentes

Solo lectura; sin payloads personales en el informe. Búsquedas sin filtro de fecha, máximo 10 resultados por flujo: el count refleja historial disponible, no volumen mensual ni facturación.

| WF | Count devuelto | Muestra relevante |
|---|---:|---|
| 02 | 231 | 473: modo webhook, success, status → ACK sin hijos |
| 13 | 0 | No prueba inactividad del cron externo ni ausencia histórica de llamadas |
| 21 | 9 | 332: integrated, success; `verificacion_automatica=false` **y aun así OCR via WF-22**. 391 figura error, sin análisis detallado de payload |
| 24 | 0 | No existe en esta muestra validación operativa de su rama automática |
| 25-A | 7 | Raíces modo webhook; no se inspeccionaron sus payloads |
| 25-C | 16 | 462 y 466: success; una llamada a WF-80 cada una, dos pasos por ¿Guía? en cada ejecución |

En 462/466 la primera llegada a ¿Guía? viene directamente de Token válido?, con body; la segunda viene de ¿Primera vez?, con solo id_envio. **No se observó doble envío por una misma ejecución en esta muestra.** Sí queda probado el envío antes de la deduplicación. No se afirma que 462 y 466 correspondan al mismo evento.

## 3. Mapa de ejecuciones por escenario

### 3.1 Entradas y ramas comerciales

La cadena base es **B = WF-02 → WF-03 → WF-04 = 3 T, 1 Q**. El único root es WF-02; los otros dos son hijos. Si llegan varios mensajes en un mismo POST, esta fórmula no se multiplica automáticamente: el normalizador actual usa únicamente los índices [0], cuestión separada de integridad.

| Escenario, un mensaje/evento | Cadena y multiplicidad | T | Q directo |
|---|---|---:|---:|
| GET de verificación, token válido o inválido | 02 → challenge/403, sin hijos | 1 | 1, sujeto a Usage |
| POST solo status | 02 → Status ACK | 1 | 1 |
| message_id ya registrado y RPC devuelve nuevo=false | 02 → Duplicate End | 1 | 1 |
| Payload malformado/sin message_id | 02 llega a Register Event; si RPC falla, termina ahí; si admite evento nuevo puede llegar a B | 1–3 | 1 |
| Texto no SKU sin entrega pendiente / tipo sin ruta | B → ayuda noOp; sin mensaje automático visible | 3 | 1 |
| STOP / NO QUIERO / NO ME CONTACTEN | B → fn_registrar_opt_out, sin hijos comerciales ni WF-80 | 3 | 1 |
| SKU válido, RESERVA_CREADA o RESERVA_YA_EXISTENTE | B → 10 → 20 → 80, una llamada por eslabón | 6 | 1 |
| SKU con forma válida pero inexistente | B → 10 → error Set con message_payload; retorno a 02 → 80 | 5 si alcanza el gateway | 1 |
| SIN_STOCK | B → 10; retorno message_payload → 02 llama 80. **No llama 12 todavía** | 5 | 1 |
| SI, Momento 1 con pendiente aceptable | B → 14 → 12 → 80 | 6 | 1 |
| NO Momento 1 / sin oportunidad / ya en lista | B → 14 → 80 | 5 | 1 |
| SI Momento 2, reserva aceptada | B → 14 → 20 → 80 | 6 | 1 |
| NO Momento 2 | B → 14 → 80; dentro de 14 se llama fn_rechazar_lista_espera y fn_notificar_siguiente_lista_espera por HTTP RPC | 5 + efectos externos pendientes | 1 + callbacks externos pendientes |
| Imagen sin pedido pendiente | B → 21 → 80; no OCR | 5 | 1 |
| Imagen con pedido, OCR no legible / operación duplicada / modo manual con ACK | B → 21 → 22 y 21 → 80 | 6 | 1 |
| Texto de nombre/selección/destino/formato inválido con entrega pendiente | B → 25-B → 80, una rama de respuesta | 5 | 1 |
| Callback PAGADO válido | 25-A → 80 | 2 | 1 |
| Callback 25-A token inválido o pedido no PAGADO | 25-A solo | 1 | 1 |
| Callback estado/guía notificable, 25-C live | 25-C → 80 por ruta directa; ruta dedup pierde body | 2 observadas; no prometer doble envío | 1 |
| Repetición estado/guía notificable, 25-C live | La ruta directa sigue permitiendo 25-C → 80 aunque dedup no inserte | 2 potenciales | 1 |
| Token inválido / estado no soportado, 25-C | 25-C sin hijo | 1 | 1 |

Todo lo anterior excluye **S** y reintentos externos: sumarlos como **+S T, +S Q**. Un mensaje inválido no tiene un único costo: un status, un SKU inexistente y un comprobante no legible recorren ramas distintas.

WF-10 bifurca la salida de fn_solicitar_reserva hacia dos IF, pero las condiciones RESERVA_CREADA y RESERVA_YA_EXISTENTE son mutuamente excluyentes. No se atribuyen dos llamadas a WF-20 por esa sola bifurcación. Build Output deja message_payload nulo para reserva; el envío de SIN_STOCK sí lo realiza WF-02.

Las ramas Error: SKU no encontrado y Error: Input inválido sí construyen message_payload, por lo que pueden invocar WF-80 desde 02. No incluyen explícitamente id_comercio en su Set: verificar su conservación en el retorno; una llamada al gateway no garantiza que la respuesta se envíe correctamente. Antes de ese hijo son 4 T; con el hijo, 5 T. No confundir este caso con texto sin forma de SKU, que queda en el router con 3 T.

**NO Momento 2:** el nodo “Notificar Siguiente” es una RPC, no un Execute WF-13. La Matriz describe la notificación al siguiente, pero el grafo live de 14 no contiene llamada a WF-13 ni construcción del aviso al siguiente destinatario. Cualquier pg_net disparado dentro de fn_* queda pendiente: no contar eslabones inexistentes ni certificar que el siguiente recibe su aviso.

### 3.2 Pago automático: camino pretendido y defectos live

Camino pretendido tras comprobante legible y VERIFICACION_INICIADA:

- B → 21 → 22: **5 T acumuladas**.
- ACK de 21 → 80: **+1 T**.
- 21 → 23 → 24 → salida: **+3 T**.
- Si fn_confirmar_pago produce PAGADO y el trigger documentado llama a 25-A → 80: **+2 T, +1 Q**.

Serían **11 T y 2 Q** para la fase comprobante+solicitud de nombre, antes de status. **No es un recorrido automático sano certificado**, por estos defectos:

1. 21 llama a ¿Automático? desde **Build WF-80 Ack**, cuyo Code devuelve solo id_comercio, phone, provider, type y text. Descarta id_verificacion, confidence, amount e is_payment_receipt que necesitaría 23. El ACK debe salir por una rama separada sin reemplazar el contexto de verificación.
2. 23 decide por confianza en Code y conserva mensajes Manual/Reject como Set sin campos configurados. Su contrato de salida a WF-80 no está construido explícitamente.
3. 24 “Send Confirm via WF-80” tiene `workflowId.value=53xUuvoriN3fqvHD`: **WF-22**, no WF-80. La entrada construida es texto de WhatsApp y no media_url.
4. El IF de 24 contiene `leftValue: "={{ $json.resultado }} "`, con espacio final. Su rama falsa trata cualquier resultado como reserva vencida. Se debe verificar el efecto del espacio en la versión instalada y discriminar YA_PROCESADO/error/vencimiento.
5. El texto de 24 pide Dirección/Referencia/Teléfono, incompatible con OBS-003; 25-A ya confirma pago y solicita nombre.

Rechazo/manual automático bien encaminado tendría B+21+22+ACK80+23+respuesta80 = **8 T, 1 Q**. En live puede fallar antes de completar esa ruta por los contratos anteriores. No llamar a esto “venta completa actual”.

### 3.3 Venta completa manual — escenario explícito

Venta directa con stock, sin reintentos, OCR asistente exitoso, cajero confirma en app, luego nombre + selección local y una notificación ENTREGADO:

| Etapa | T | Q |
|---|---:|---:|
| SKU → reserva+QR | 6 | 1 |
| Comprobante manual con OCR asistente y ACK | 6 | 1 |
| Confirmación por app: RPC directa | 0 | 0 |
| Callback PAGADO → 25-A → 80 | 2 | 1 |
| Comprador envía nombre → menú | 5 | 1 |
| Comprador elige punto → confirmación | 5 | 1 |
| Callback ENTREGADO → 25-C → 80 | 2 | 1 |
| **Total hasta entrega, una notificación de estado** | **26** | **6** |

Hasta pago confirmado y solicitud de nombre: **14 T, 3 Q**. Hasta registro de punto local: **24 T, 5 Q**.

Para transporte, añadir un mensaje de destino combinado: **+5 T, +1 Q**. Cada evento adicional de preparación/asignación/ruta/guía añade **+2 T, +1 Q** bajo la ruta notificable actual; no asumir que todos ocurren. Con **m** mensajes de datos de entrega y **c** callbacks notificables de estado/guía, el total manual es:

**T = 14 + 5m + 2c + S; Q = 3 + m + c + S.**

m=2 para nombre y punto local; m=3 si transporte agrega destino combinado. Un formato mal pedido que obliga a corregir añade otra unidad a m. Para venta desde lista, sustituir el SKU inicial por las etapas efectivamente vividas: SIN_STOCK 5/1 + SI inicial 6/1 + aviso 13→80 2/1 (solo si hubo un destinatario) + SI oportunidad 6/1. No atribuir a una única venta todas las notificaciones de un lote.

### 3.4 Cron, lotes y disparadores

**No hay Schedule/Cron ni Loop Over Items en los 16 grafos live.** Hay cuatro entradas webhook: 02, 13, 25-A y 25-C; los demás entran por Execute Workflow Trigger. No proponer bajar “el cron de n8n cada minuto”: WF-30 está fuera del conjunto, sustituido por pg_cron según §0.

Sea K el número de POSTs externos a WF-13 en un tick de pg_cron y N_j los clientes realmente notificados por el callback j:

**T por tick = K + ΣN_j; Q por tick = K**, más status de los envíos. Sin POST a n8n: **0 T, 0 Q**, aunque PostgreSQL ejecute su cron.

WF-13 autentica primero y luego hace un SELECT DISTINCT de **todos** los grupos ESPERANDO, sin limitarse al grupo del payload. Llama la RPC por grupo y solo invoca WF-80 si resultado=CLIENTE_NOTIFICADO. El filtro de resultado ya es temprano respecto al envío. K despertares pueden repetir K veces el barrido global; eso aumenta consultas aunque la guarda atómica evite nuevas notificaciones.

Los Execute Workflow con mode=each aparecen en 04, 13, 14, 25-A/B/C. Para un mensaje el multiplicador sigue siendo 1. **No cambiar a lote hacia WF-80:** Opt-out Check y Build Meta Payload usan .first(), por lo que el grafo no acredita aislamiento por destinatario en una entrada múltiple. Agrupar así podría usar el opt-out o teléfono del primer cliente para otros. El ahorro teórico N−1 T del hijo vale 0 Q y no compensa el riesgo.

## 4. Tabla de los 16 workflows: actual → propuesta → ahorro → riesgo

IDs exactos en §2; cifras locales de invocaciones de cada WF, no volver a sumar los totales de cadena.

| WF / HU de Matriz | Ejecuciones actuales por escenario | Propuesta futura | Ahorro estimado | Riesgo |
|---|---|---|---|---|
| 02 / HU-121,143 | 1 por POST/GET, incluso status/duplicado | Filtro de forma antes de RPC; evaluar supresión de entradas técnicas en origen | Filtro interno 0 Q; supresión externa 1 T/Q por POST | Bajo en forma; alto si se pierden eventos |
| 03 / HU-122 | 1 por mensaje nuevo admitido | Candidato único claro a inline de transformación en 02, conservando contrato | 1 T por mensaje, 0 Q | Bajo/medio; otros callers deben verificarse |
| 04 / HU-123,142 | 1 por mensaje normalizado, STOP incluido | Conservar router y contexto; clasificar forma sin lógica de negocio | 0 Q; hasta 1 T si un formato imposible no llega al router | Medio; preservar SI/NO y texto de entrega |
| 10 / HU-037–041 | 1 por SKU; 20 solo reserva nueva/existente | Mantener RPCs; no reintroducir mensaje duplicado de reserva | 0 adicional demostrado | Medio por stock/concurrencia |
| 12 / HU-043,044 | 1 por SI Momento 1 aceptable | Mantener alta atómica; reducir consultas redundantes según retorno real de RPC | 0 T/Q; menos round trips | Medio |
| 13 / HU-045,049,053 | 1 por callback; N hijos 80 | Despertares útiles, un lote de grupos válidos por callback | K−1 raíces si K→1; 1 raíz por vacío suprimido | Medio/alto; cron/turnos en BD |
| 14 / HU-046–049 | 1 por SI/NO; hijo 12, 20 u 80 según rama | Preservar dos momentos; verificar que RPC siguiente realmente dispara notificación | 0 probado; no eliminar consentimiento | Alto si se altera cola |
| 20 / HU-042,056 | 1 por reserva nueva/existente aceptada | Mantener reutilización por 10 y 14; contrato QR correcto | 0 probado | Alto si se omite cobro/reenvío legítimo |
| 21 / HU-057,058 | 1 por imagen/documento; OCR si hay pedido aun en manual | Separar captura durable, OCR opcional y verificación; preservar contexto de 23 | Hasta 1 T/hijo OCR omitido, 0 Q directo; reenvíos evitados según §1 | Medio/alto |
| 22 / HU-059,146 | 1 por comprobante con pedido; +1 accidental si llega llamada de 24 | Mantener extractor; contrato de error técnico explícito | 1 T por llamada accidental eliminada; cuota directa 0 | Medio/alto |
| 23 / HU-060–064,141 | 1 en rama automática; ningún historial disponible de 24 downstream | Reparar entrada y delegar decisión a fn_*; construir payloads | No cuantificado; evita reenvíos por fallo | Alto por pagos |
| 24 / HU-076,078–081 | 1 al confirmar automático; salida actual llama 22 | Un responsable de notificación, idealmente 25-A event-driven para PAGADO; discriminar resultados | 1 T si se elimina salida redundante; sustituir 22 por 80 da 0 T neto | Alto hasta verificar fn_confirmar_pago |
| 25-A / HU-076 | 1 por callback; +80 si PAGADO incluso repetido | Idempotencia verificable y recuperación de envío; mantener un aviso de nombre | 1 hijo T por repetición frenada; raíz solo si se evita en emisor | Medio |
| 25-B / HU-077,086 | 1 por mensaje de datos, cada corrección vuelve por B | Pedir CIUDAD/ZONA juntas y ejemplo; reutilizar contexto confiable | 5 T/1 Q por corrección evitada; lookup repetido 0 T/Q | Bajo en texto; medio en contexto |
| 25-C / HU-092–094 | 1 por callback; envío no dominado por dedup | Secuenciar token→dedup→recuperar body→tipo→80 | 1 T por callback repetido que deje de enviar; +status evitados | Medio; guía/estados y fallos parciales |
| 80 / HU-124,142,144,145 | 1 por solicitud de envío, incluso opt-out/breaker | **No tocar ni fusionar** en esta optimización | 0 ahorro propio propuesto; menos solicitudes duplicadas upstream | Alto; frontera D9/D11 |

## 5. Hallazgos y propuestas, ordenados por ahorro/riesgo

Las prioridades usan beneficio relativo, certeza y riesgo; sin volumen real no existe ratio numérico defendible. Los IDs WF remiten al inventario live de §2. Pantallas: cuando aplica se usan los números de Matriz (p.ej. 17 para crear envío, 16/30/19 para seguimiento); las transformaciones internas no tienen pantalla asignada.

### P1 — Pregunta completa de destino (WF-25-B; HU-077,086; pantalla 17)

**Evidencia:** Msg Pide Ciudad dice “¿A qué ciudad o población se envía?”; ¿Ciudad capturada? ya compara ENTREGA_REGISTRADA. OBS-005 exige `CIUDAD: X, ZONA: Y`, y el historial documental dice implementada m37. Hay desfase live de texto, no prueba de que la BD siga en dos pasos.

**Tablas/fn:** tbl_entrega_captura, tbl_envios; fn_iniciar_captura_destino, fn_entrega_captura_estado, fn_procesar_captura_destino.

**Pasos futuros:** pedir al orquestador contrato DESTINO/FORMATO_INVALIDO; corregir pregunta inicial y de reinicio con ambos campos y ejemplo; conservar corrección amable; validar acentos, campos faltantes y registro exactamente una vez. No parsear la decisión transaccional en Code. Ahorro condicionado 5 T/1 Q por turno de corrección eliminado, no “1 ejecución por cada venta” indiscriminadamente.

### P2 — Deduplicación efectiva de avisos (WF-25-C/25-A; HU-076,092–094,143; pantallas 16/30/19)

**Evidencia mínima 25-C:** `Token válido?.main[0] → [¿Guía?, Dedup Notificación]`. La primera rama permite enviar antes de la guarda. La consulta dedup devuelve solo id_envio, pero ¿Guía? y Por Estado leen `$json.body`. Además, INSERT ON CONFLICT sin RETURNING rows puede detener la rama antes de ¿Primera vez?; no asumir que Respond 200 Duplicado se alcanza.

**Tablas/fn:** tbl_notificaciones_envio (visible en JSON live; contrato canónico pendiente), tbl_envios, tbl_whatsapp_eventos, tbl_logs_auditoria; fn_actualizar_estado_envio y función de guía vigente pendiente. 25-A consulta pedido PAGADO y envía, sin dedup visible.

**Pasos futuros:** definir con orquestador clave de evento y estados/reintento; hacer que solo una rama autenticada y deduplicada alcance 80; restaurar el body original explícitamente; resolver salida de cero filas y ACK de duplicado; preservar una nueva foto de guía legítima (no bloquearla para siempre por clave id_envio+guia_registrada); verificar fallo entre registro y envío y no marcar entrega como enviada prematuramente. Extender igual garantía a 25-A sin inventar una fn_*.

No basta borrar la arista directa: sin recuperar body podría dejar de notificar. No basta registrar antes de enviar: un fallo posterior podría consumir la marca y perder la notificación. El ahorro es de duplicados reales; no reducir eventos de estado válidos ni imágenes OBS-004.

### P3 — Reducir entradas técnicas en el origen (WF-02; HU-121,143; tbl_whatsapp_eventos / fn_registrar_evento_whatsapp, fn_cerrar_evento_whatsapp)

**Evidencia:** status se descarta antes de registrar evento y de llamar 03. Mensajes duplicados también se cortan antes de 03. Estos dos filtros ya están bien ubicados para evitar hijos, pero el POST ya consumió una raíz. Falta validación visible de firma del POST; Verify Token1 solo protege GET, no autentica POST. No se concluye que no exista protección fuera del workflow.

**Pasos futuros:** medir status/reintentos/entradas malformadas en una ventana representativa; verificar autenticación del receptor existente; mantener entrega de mensajes válidos y trazabilidad de estados necesarios; evaluar un receptor previo solo para autenticación/filtrado técnico, sin mensajería Graph API ni lógica comercial; mantener idempotencia canónica en BD. No asumir que la suscripción Meta permita quitar status manteniendo todos los mensajes. No descartar un payload mixto que incluya mensajes.

Dentro de 02 puede validarse presencia de identidad/formato antes de la RPC y rechazar temprano entradas imposibles. Eso ahorra nodos/posibles hijos, **no la raíz Q**. El normalizador actual prioriza statuses[0] y solo toma entry[0]/changes[0]/messages[0]; procesar todos los eventos válidos puede **aumentar T**, pero evita pérdida. No contabilizar mensajes omitidos como ahorro.

### P4 — Despertares de lista útiles (WF-13; HU-045,049,052,053; pantalla 13/28)

**Tablas/fn:** tbl_lista_espera, tbl_reservas, tbl_inventario; fn_cron_expirar_y_notificar, fn_procesar_reservas_vencidas, fn_notificar_siguiente_lista_espera.

**Pasos futuros:** pedir topología/frecuencia pg_cron→pg_net y payload al orquestador; confirmar quién agrupa; suprimir callbacks vacíos o repetidos en el emisor y limitar grupos al trabajo pertinente, preservando selección atómica, SKIP LOCKED y turno único; validar dos variantes, dos comercios, aceptación, NO y vencimiento. No alargar ventanas de expiración/aceptación para ahorrar. No crear cron n8n nuevo. Si el emisor ya agrupa y solo llama cuando procede, el ahorro es 0.

Un lote aquí significa **una raíz para varios grupos**, conservando una llamada aislada a 80 por destinatario. No implica cambiar WF-80 a batch.

### P5 — Reparar contratos y errores para no inducir reenvíos (WF-21/22/23/24; HU-057–064,065,076,078–081,141,146; pantallas 24/06/07/25/08)

**Tablas/fn:** tbl_comprobantes_pago, tbl_verificaciones, tbl_pedidos, tbl_logs_auditoria; fn_registrar_comprobante, fn_iniciar_verificacion, fn_confirmar_pago, fn_rechazar_verificacion.

Además de §3.2: Parse OCR de 22 convierte una respuesta no parseable en is_payment_receipt=false y parse_error; la guarda “¿Error técnico del OCR?” de 21 solo comprueba is_payment_receipt undefined o error definido. **parse_error puede pasar como comprobante no legible**, provocando rechazo/reenvío pese a ser error técnico. Los HTTP de descarga y Gemini usan continueRegularOutput. Hay fallback manual en 21, pero no cubre inequívocamente ese caso.

**Pasos futuros:** restaurar el contexto completo desde Parse Verification Result hacia 23; validar entrada antes de invocar hijos; tipar fallos de descarga/Storage/Gemini/parseo como técnicos, sin diagnóstico financiero; mantener D5 y revisión manual; confirmar que fn_* decide el resultado financiero y no Code por umbral; eliminar llamada accidental 24→22; elegir un único aviso PAGADO+nombre por 25-A cuando el trigger sea fiable, con manejo explícito de YA_PROCESADO y reserva vencida; probar error técnico, reintento, confirmación concurrente y auditoría.

No proponer inline de Decide Verification como “transformación”: actualmente contiene una decisión de negocio que debe resolverse en fn_* conforme a Reglas 2/3/4. El ahorro de reenvíos es condicionado, no medido.

### P6 — OCR opcional realmente opcional (WF-21/22; HU-057–059,141; D13)

**Evidencia:** 332 prueba modo manual con OCR. Esto puede ser OCR-asistente legítimo bajo D13; **modo manual no significa automáticamente OCR prohibido**. Leer Config ocurre temprano, pero la bifurcación ¿Automático? sucede después del OCR y de fn_iniciar_verificacion. La evaluación SIN_CREDITOS también ocurre después del gasto de OCR.

**Pasos futuros:** distinguir la opción de asistencia OCR de la decisión manual/automática; si el comercio desea modo sin OCR, trasladar captura durable de media fuera de la dependencia exclusiva de 22 y registrar RECIBIDO por el contrato autorizado, preservando revisión humana y D14. En automático, pedir al orquestador un contrato que autorice iniciar verificación antes del servicio externo cuando sea viable; no duplicar consumo de créditos ni bloquear una venta manual por saldo negativo.

Ahorro máximo **1 T, 0 Q por comprobante** que efectivamente deje de invocar 22, además de llamada externa OCR evitada sin estimación monetaria. Mantener OCR asistente si aporta valor; no eliminar Storage al omitir el extractor.

### P7 — Inline pequeño y reutilización (WF-03/02/04; HU-121–123)

03 tiene solo trigger + Canonical Message Normalizer + Execute 04. Es el candidato claro a inline del Code en el llamador, con contrato idéntico provider/message_id/phone/media/raw. **1 T menos por mensaje nuevo; 0 Q.** Conservar 04 como router. Confirmar primero que no haya callers no canónicos/OpenWA dependientes de 03. Por cuota, esta propuesta queda detrás de P1–P5.

No fusionar 20 (pedido+cobro+reenvío QR y dos callers), 12/14 (lista transaccional y consentimiento), 22 (servicio externo y media), 23/24 (pagos), ni 25-A/C (eventos independientes). Ser pequeño no convierte un workflow con efectos comerciales en transformación pura.

### P8 — Contexto y payloads comunes sin otro workflow por mensaje

**WF-04/25-B, HU-123,077,086:** RPC Entrega Pendiente y Resolve Contexto llaman fn_pedido_entrega_pendiente para el mismo paso. Reutilizar contexto en la llamada interna podría evitar un round trip; la escritura debe revalidar estado en fn_*. No usar cache prolongada de estado de pedido.

**WF-10/21/25-B, HU-037–041,057,077:** fn_upsert_cliente aparece en diferentes fases; algunas llamadas actualizan nombre y no son duplicación eliminable. **WF-14** vuelve a resolver provider. Pasar identificadores confiables del contexto puede reducir lookups, sin mezclar tenants ni saltar actualizaciones.

**WF-02/12/13/14/20/21/23/24/25-A/B/C; HU-124 y HU de cada rama:** estandarizar contrato de payload (id_comercio, phone, provider, type, text, media_url) y dueño del envío. Reutilizar formato en Code/Set dentro de los flujos pertinentes; no añadir un subworkflow meramente para construir texto bajo un objetivo de reducir T. 23 tiene constructores vacíos y 24 contrato obsoleto; atender primero esos casos.

Ahorro directo **0 T/Q** para eliminar consultas o uniformar campos. No cachear opt-out ni eliminar lookup del gateway: WF-80 queda fuera de cambios.

## 6. Guardado por workflow

En **los 16 JSONs live**, los tres campos solicitados están **ausentes** del objeto settings. Ausente significa **valor heredado/no explícito**, no false ni none. No se verificaron defaults efectivos de la instancia.

| WF | saveExecutionProgress | saveDataSuccessExecution | saveDataErrorExecution | Política futura candidata |
|---|---|---|---|---|
| 02 | Ausente | Ausente | Ausente | false / none / all, tras asegurar cierres de evento |
| 03 | Ausente | Ausente | Ausente | false / none / all |
| 04 | Ausente | Ausente | Ausente | false / none / all, tras cubrir errores silenciosos |
| 10 | Ausente | Ausente | Ausente | false / none / all, después de verificar auditoría y reintento |
| 12 | Ausente | Ausente | Ausente | false / none / all, mismas condiciones |
| 13 | Ausente | Ausente | Ausente | false / none / all, conservar diagnóstico hasta probar callback |
| 14 | Ausente | Ausente | Ausente | false / none / all, tras validar ambos momentos |
| 20 | Ausente | Ausente | Ausente | false / none / all, validar reentrada pedido/cobro |
| 21 | Ausente | Ausente | Ausente | Mantener éxitos para diagnóstico hasta cerrar P5; luego evaluar none |
| 22 | Ausente | Ausente | Ausente | Igual; no perder diagnóstico OCR/Storage |
| 23 | Ausente | Ausente | Ausente | Igual; actualmente contratos pendientes |
| 24 | Ausente | Ausente | Ausente | Igual; referencia errónea sin prueba E2E |
| 25-A | Ausente | Ausente | Ausente | Evaluar false / none / all tras dedup/recuperación |
| 25-B | Ausente | Ausente | Ausente | Evaluar false / none / all tras OBS-005 |
| 25-C | Ausente | Ausente | Ausente | Mantener diagnóstico hasta P2; luego evaluar false / none / all |
| 80 | Ausente | Ausente | Ausente | **No cambiar** por D9/D11 y alcance de esta propuesta |

Las ternas de política están en orden progreso/éxito/error. **Todas ahorran 0 ejecuciones T y Q**: solo almacenamiento, I/O y posiblemente latencia. Desactivar progreso puede cambiar capacidad de reanudación, por lo que no es una optimización sin consecuencias. [Settings oficiales de n8n](https://docs.n8n.io/build/manage-workflows/configure-workflow-settings).

Prerrequisitos: orquestador confirma cobertura canónica en tbl_logs_auditoria, cierre de tbl_whatsapp_eventos y recuperación idempotente. Guardar errores all inicialmente. Los errores capturados con continueRegularOutput pueden dejar la ejecución en success: quitar éxitos antes de corregir esos contratos ocultaría evidencia. La Regla 9 no se satisface solo porque n8n retenga ejecuciones, y tampoco autoriza quitar trazabilidad técnica sin comprobar su sustituto operativo. No se propone poda histórica ni cambios globales de retención.

## 7. Ramas de error y cascadas

- No hay settings.errorWorkflow explícito ni Error Trigger en los 16. No se observa una cascada automática hacia WF-00; el diseño documental de WF-00 no prueba su instalación.
- 02 tiene separadas las salidas normal y error de Route to WF-03, y ¿Enviar WF-80? evita llamadas cuando no hay message_payload. No repetir como abierto el antiguo hallazgo de cables éxito/error mezclados.
- 04 captura errores de identificación/opt-out y termina en Error silencioso. El padre podría cerrar el evento como exitoso porque no recibió excepción. Hay que propagar un resultado técnico tipado y conservar auditoría, no relanzar toda la venta como política general.
- 20 convierte fallos de sus RPCs en resultado ERROR. 10 no demuestra tratamiento homogéneo del fallo de 20. No eliminar estos caminos para reducir nodos.
- 21/22 confunden ciertos errores de extracción con no legibilidad; §5 P5. 23 puede emitir payloads incompletos; 24 puede disparar otro OCR. Son cascadas de trabajo o reenvío humano evitables, no evidencia de un bucle ilimitado.
- WF-80 tiene retryOnFail=true y maxTries=4 en transportes: hasta cuatro intentos HTTP **dentro de la misma ejecución**, no cuatro workflows. No recortar esos retries ni añadir reintentos de padres para “ahorrar”: ambos requieren conservar D9/D11 y evitar reenviar tras un timeout de resultado incierto.
- 25-A/C responden después del envío; una respuesta tardía/fallida podría inducir reintento del emisor, pero no se midió su política. Adelantar ACK sin persistencia recuperable no es una solución admisible.
- Un fallo tras mutar BD no habilita repetir toda la cadena. El orquestador debe definir punto seguro de reentrada, preservando los cierres/errores de evento y la idempotencia financiera.

## 8. Lista explícita de “no tocar”

1. **WF-80 `7V6MIPuGbdx9s0lT` y D9/D11:** no inline, bypass HTTP/Meta MCP, cambio de cola/rate-limit/breaker, batching de destinatarios ni eliminación de logs. Todas las propuestas de menos envíos actúan en los llamadores; una corrección interna del gateway requeriría otro alcance. HU-124,142,144,145; tbl_contact_preferences/tbl_logs_auditoria.
2. **Opt-out:** registrar STOP antes de dispatch comercial y comprobar fn_cliente_optado en cada envío. No inferir que estar optado permite omitir registro de STOP ni mantener cache de autorización. WF-04/80, HU-142.
3. **Idempotencia:** conservar tbl_whatsapp_eventos y contratos registrar/cerrar; dedup financiera de fn_confirmar_pago y reserva por cliente; no deduplicar por texto o teléfono global. Reparar el bypass 25-C fortalece la regla, no la elimina. WF-02/10/21/24/25-C, HU-041,143.
4. **Regla 9:** no suprimir tbl_logs_auditoria, triggers o logs explícitos de skip/error/envío. No sustituirlos por historial n8n ni por datos estáticos.
5. **Reglas 2/3:** stock, reserva, cupo/turno, pedido, cobro, confirmación, créditos y captura/registro comercial continúan en fn_*. No SELECT→IF→UPDATE ni traslado de umbrales financieros a Code.
6. **OBS-001:** mantener SI/NO en ambos momentos, preferencia de oportunidad frente a pendiente, NO liberando turno y vencimiento configurable. No eliminar un mensaje obligatorio de consentimiento para reducir Q. WF-10/12/13/14, HU-043–049.
7. **OBS-002:** conservar mensaje unificado de reserva+QR y formato de lista/oportunidad, tiempos desde configuración. No sumar como ahorro futuro el mensaje duplicado ya eliminado. WF-10/12/13/20, HU-037–045,056.
8. **OBS-003/004/005:** puntos por sucursal, sin dirección libre/cobro de transporte, foto de guía/código y destino ciudad+zona conjunto; preservar saltos permitidos de estado. WF-25-A/B/C, HU-076,077,086,092–094.
9. **D5/D13/D14:** error técnico no equivale a rechazo financiero; modo manual mantiene confirmación humana; consumo por venta e idempotencia en BD. No bloquear venta manual por saldo negativo ni forzar OCR opcional.
10. **WF-30 archivado/pg_cron:** no reactivar ni recrear expiración n8n, ni reducir garantías temporales o turnos para ahorrar ejecuciones. HU-049,052,053.

## 9. Pendiente de verificar — para el orquestador

**No se requieren JSONs live para empezar:** se leyeron los 16 y se registraron versiones. Sí se requiere relectura antes de implementar, comparación con estas versiones, defaults efectivos y contratos reales. Ninguna firma mostrada por parámetros de un nodo se considera firma validada de BD.

| Pendiente | Evidencia requerida / propósito |
|---|---|
| Cuota y medición | Plan/trial efectivo, regla de Usage para roots/status/retry, ventana temporal representativa y retención. Conciliar raíces webhook vs integrated; no usar count histórico como factura |
| Registro/cierre de eventos | Firma y retornos de fn_registrar_evento_whatsapp/fn_cerrar_evento_whatsapp, tratamiento de payload sin message_id y ERROR/reentrega. Verificar autenticación POST fuera del grafo |
| Disparadores externos | Topología y frecuencia de pg_cron/pg_net para 13/25-A/25-C, URLs rsuelvotest, token/ACK/retries y trabajo vacío. WF-13 sin historial requiere diagnóstico del orquestador, no consulta BD en esta auditoría |
| Lista de espera | Firmas/retornos y guardas de fn_pendiente_lista, fn_aceptar_pendiente_lista, fn_rechazar_pendiente_lista, fn_agregar_lista_espera, fn_aceptar_lista_espera, fn_rechazar_lista_espera, fn_notificar_siguiente_lista_espera y fn_cron_expirar_y_notificar. Confirmar si Notificar Siguiente de 14 realmente dispara aviso |
| Reserva/cobro | Contratos de fn_upsert_cliente, fn_resolver_variante_por_sku, fn_solicitar_reserva, fn_crear_pedido_desde_reserva, fn_generar_cobro; idempotencia, tenancy y retorno reutilizable para evitar SELECTs |
| Pagos/OCR | Firmas/retornos de fn_registrar_comprobante, fn_iniciar_verificacion, fn_confirmar_pago y fn_rechazar_verificacion; YA_PROCESADO/RESERVA_VENCIDA; criterio financiero canónico y créditos manual/automático; persistencia sin OCR |
| Captura destino | Contratos fn_pedido_entrega_pendiente, fn_listar_puntos_entrega, fn_iniciar_captura_destino, fn_entrega_captura_estado, fn_procesar_captura_destino y fn_registrar_entrega; confirmar m37 y ejemplo CIUDAD/ZONA |
| Avisos logísticos | Esquema/clave y semántica de tbl_notificaciones_envio, reenvío tras fallo y actualización de guía; función vigente fn_set_numero_guia/fn_registrar_guia (nombre exacto pendiente); contrato de fn_actualizar_estado_envio |
| Auditoría y errores | Cobertura real de tbl_logs_auditoria y triggers, fallos capturados como success, estado terminal de eventos; no reducir guardado hasta validarlo |
| Otros callers / infraestructura | Consumidores no canónicos de 03 y demás hijos, OpenWA, protecciones externas, workflows de error ajenos a los 16. No se hizo inventario fuera del alcance |
| Verificación futura de grafos | Corregir primero 24→22 y contexto 21→23; P2 debe recuperar body antes de retirar bypass; comprobar .first()/mode=each y aristas de error. No importar exports viejos |
| E2E futuro, no ejecutado | SKU nuevo/reintento, SIN_STOCK+SI/NO ambos momentos, manual/automático, fallo OCR, evento repetido/concurrente, opt-out, dos tenants, retiro/transporte, ciudad/zona incompletas, guía imagen, reintento tras fallo de envío y auditoría |

Otros desajustes observados para revisión funcional, sin sumar ahorros: WF-20 genera cobro con ruta QR por comercio pero construye media_url de envío con ruta común `qr-pagos/tienda.png`; validar el QR correcto por tenant antes de optimizar. WF-12 usa un SELECT de capacidad seguido de IF y luego RPC: confirmar que fn_agregar_lista_espera mantiene la autoridad atómica y que el precheck no decide con datos obsoletos. WF-80 sigue con 20/60s hardcodeado y partes del manejo de error/provider deben revisarse en hardening separado; **no se propone modificarlo aquí**.

## 10. Secuencia futura y criterio de aceptación

1. Reconciliar versiones/contratos y reparar P1/P2/P5 en una intervención autorizada posterior.
2. Medir raíces, hijos, status, repeticiones y errores por ventana; atribuir cada ahorro una sola vez.
3. Evaluar P3/P4 solo con evidencia de volumen y preservación de trazabilidad; mantener lógica de negocio en BD.
4. Considerar P6/P7/P8 y settings por latencia/operación, sin prometer ahorro de cuota que no existe.
5. Actualizar Matriz/OBS y validar escenarios en esa futura implementación. **En esta auditoría solo se crea el informe; no se cambia ningún workflow ni la BD.**
