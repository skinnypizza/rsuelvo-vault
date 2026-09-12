# Auditoría de robustez conversacional — OBS-010

Fecha: 2026-09-12. Cuenta: `rsuelvotest.app.n8n.cloud`. Auditoría de solo lectura de los **16 workflows publicados**. Segunda lectura de versiones completada a las 20:21:48 UTC: ninguna cambió. Borradores y versiones publicadas coincidían en los 16 casos.

**Resultado:** el sistema protege las operaciones mediante RPC, pero todavía no distingue suficientemente entre una respuesta al dato solicitado y conversación incidental. “Gracias” puede sobrescribir el nombre o registrar una ciudad y crear el envío. Post-QR y durante la verificación, el texto ordinario generalmente termina en silencio. Hay una discrepancia concreta entre aceptación y rechazo de “YO”. STOP conserva prioridad en el recorrido normal y el control de salida de WF-80, con límites detallados abajo.

## 1. Alcance y evidencia

Se leyeron nodos, parámetros y conexiones completos mediante `get_workflow_details`; no se ejecutaron workflows ni mensajes de prueba. Se consultaron exclusivamente definiciones de funciones mediante `pg_get_functiondef` en el proyecto Supabase RSUELVO `iwfaktlxebxtocmswdvv`. No se consultaron datos personales ni se invocaron RPC de negocio.

Fuentes documentales: `PROMPT-CODEX-AUDITORIA-ROBUSTEZ.md`, `00-Index/00-PROMPT-MAESTRO-RSUELVO.md`, `Matriz-Consistencia-WF-BD-HU.md` §0, `workflows.md`, `07-Control-de-Calidad/Observaciones-Usuario.md`, backlog de HU y SQL de captura de destino. Ante diferencias históricas, este informe describe el grafo publicado y las definiciones de BD leídas.

Las consecuencias que siguen se deducen del código y del cableado, salvo los casos reales aportados por el dueño. No equivalen a una nueva prueba E2E. Solo se crea este informe; Matriz, workflows, BD y credenciales quedan sin cambios.

### Inventario de los 16 workflows

| WF | ID en rsuelvotest | versionId publicado auditado | Cobertura conversacional |
|---|---|---|---|
| WF-02 | `kXuiHOMTxgR1Lo1O` | `706328cc-d442-40a1-9673-9ee3a183bcdf` | Entrada Meta, extracción del texto, dedup y retorno de mensajes |
| WF-03 | `sxmtEb1j2BlwoYXf` | `73ee48b6-4456-4d18-b2f4-39ce098f77f5` | Normalización de tipo, texto y contexto |
| WF-04 | `0fw2ymvAY1hHoV9M` | `4d4d169c-65d5-4fda-b261-20ddd69295a0` | STOP, SKU, SI/NO, imágenes, entrega y fallback |
| WF-10 | `xFcZMG8Hip0Z6aH5` | `ab3d4121-ad91-4845-939d-0f4ef5472662` | SKU, nombre de perfil, reserva y pregunta de lista |
| WF-12 | `n9VUH43N8i7s9Rn2` | `6d72176e-6be7-490b-b6b5-e72b28e3261d` | Alta atómica y mensajes de resultado; no interpreta texto del comprador |
| WF-13 | `Qnr8SYR8sKGnzYKL` | `27b59091-4c08-4763-9206-0a7883c3b28c` | Emite oportunidad SI/NO; no consume la respuesta |
| WF-14 | `JOT4yRctEcogiYzV` | `71781466-98b6-4e76-a996-2def875f5091` | Interpreta aceptación/rechazo de ambos momentos de lista |
| WF-20 | `1FYWXdVw2swlFYcg` | `c5eb50ca-db68-4c1f-ae0d-8fa671d6cd0b` | Emite QR e instrucciones; no consume chitchat |
| WF-21 | `nJCQI6MfFSjUhywB` | `0eda5aed-a78c-4ee4-a90e-10ec07d0d6fd` | Comprobante, pedido pendiente, errores, ACK y contexto OCR |
| WF-22 | `53xUuvoriN3fqvHD` | `abc18837-a0de-4114-a5cc-7575e06787d1` | Imagen/documento → extracción de datos; validación del resultado OCR |
| WF-23 | `okF8Ayhp5CicRpVU` | `2feb8cd7-0000-4a05-a17e-9c8fa14f6a7c` | Clasificación OCR y mensajes de rechazo/revisión |
| WF-24 | `JU4QtP0vkAC7m3n1` | `a7f28e6b-d169-49e0-b066-d79f4a673ab2` | Resultado de confirmación; sin consumo de texto libre |
| WF-25-A | `gVmvGYVPMlQKWk6z` | `5d24ea2f-d057-4dee-9da3-47a7c8110765` | Solicita nombre tras PAGADO |
| WF-25-B | `9doLr3FSewZofRoN` | `5bcc1c92-62a5-4876-a311-254c9dc150f7` | Nombre, selección de punto y captura de ciudad |
| WF-25-C | `2DzqPBe4xtHIuvHA` | `050cb1a2-6a91-4776-a089-8453faca4c74` | Emite guía/estado; no interpreta respuestas del comprador |
| WF-80 | `7V6MIPuGbdx9s0lT` | `c236c740-b4b0-45d0-b507-810a118235a8` | Opt-out previo al envío, rate-limit y circuit breaker |

WF-30 archivado queda fuera de estos 16.

## 2. Dónde se consume texto como dato

| Punto / nodo | Dato consumido y validación real | Consecuencia / fallback actual | IDs funcionales y BD |
|---|---|---|---|
| WF-02 `Normalize Meta Payload1`; WF-03 `Canonical Message Normalizer` | Extrae `message.text.body`; normalizador acepta string, aplica trim y limita el tipo a una lista. No clasifica intención. WF-02 toma solo `entry[0]`, `changes[0]`, `messages[0]`; si hay un status toma esa rama primero. | Texto vacío sigue vacío. Audio, ubicación y respuestas interactivas no se convierten a respuesta textual. Un mensaje posterior dentro del mismo lote no se recorre. | HU-121/122/123/143; `tbl_whatsapp_eventos`, `fn_registrar_evento_whatsapp` |
| WF-04 `Enrich & Classify` | STOP por igualdad de texto tras trim y mayúsculas: `STOP`, `NO QUIERO`, `NO ME CONTACTEN`. SKU por `^[A-Z0-9]{6}$`. Afirmaciones: SI/SÍ/OK/DALE/YO si tipo text. | No hay clasificador por estado global. “GRACIAS” y “REBAJAME” no son SKU; “SALUDO” sí tiene forma de candidato, aunque luego debe existir en BD. | HU-123/142; `fn_registrar_opt_out`, `tbl_contact_preferences` |
| WF-10 `Validate Input` → `Lookup SKU -> Variante` | Repite regex de 6 caracteres y exige comercio, sucursal y teléfono. RPC resuelve variante por comercio/sucursal. | Una frase de seis caracteres puede hacer lookup, pero no reservar si no corresponde a variante. SKU con prefijo, espacios internos o puntuación no llega como SKU desde WF-04. | HU-037–041; `fn_resolver_variante_por_sku`, `fn_solicitar_reserva`, `tbl_variantes` |
| WF-10 `whatsapp_name` → `PG fn_upsert_cliente` | Nombre tomado de determinadas propiedades de perfil/raw; fallback “Cliente WhatsApp”. Escapa comillas para SQL, pero no verifica que sea un nombre ni que deba reemplazar uno existente. | Dato de perfil es distinto de texto conversacional. La RPC actualiza nombre con un valor no vacío; existe riesgo de reemplazar un nombre ya capturado con un perfil/fallback. La estructura Meta `contacts` no está entre los accesos de este nodo. | HU-077; `fn_upsert_cliente`, `tbl_clientes` |
| WF-14 `Parse Decision` y `Parse Decision 2` | Trim, mayúsculas, quita diacríticos. Solo SI/OK/DALE → ACEPTAR; **todo lo demás → RECHAZAR**. | WF-04 deriva YO como aceptación; WF-14 lo rechaza. “Sí, gracias” no pasa el filtro afirmativo del router. Los textos arbitrarios que lleguen directamente al subworkflow tampoco tienen categoría inválida. | HU-043/046/047; `fn_aceptar_lista_espera`, `fn_rechazar_lista_espera`, `fn_aceptar_pendiente_lista`, `fn_rechazar_pendiente_lista` |
| WF-25-B `¿Selección?` → `Mapear Selección` | Fuera de captura, solo `^[1-9]$` entra como número; luego busca opción en el catálogo actual. | Opción 1–9 inexistente: re-pregunta. “10”, “0”, “2 por favor” o cualquier otro texto entra a `Parse Nombre`, no a opción inválida. Puede saltarse el pedido de nombre enviando directamente una opción válida. | HU-076/077/086; `fn_listar_puntos_entrega`, `tbl_puntos_entrega`, `fn_registrar_entrega` |
| WF-25-B `Parse Nombre` → `Guardar Nombre` | Compacta espacios, separa nombres/apellidos por cantidad de palabras y recorta a 120/60/60 caracteres. No valida intención ni estado “esperando nombre”. | “Gracias”, “rebajame” o una ciudad enviada anticipadamente se guardan como nombre; vuelve a emitir el menú. La RPC confirma ausencia de validación semántica y actualiza `tbl_clientes`. | HU-076/077; `fn_upsert_cliente`, `tbl_clientes` |
| WF-25-B `Procesar Captura` | Pasa texto íntegro a `fn_procesar_captura_destino`. BD rechaza vacío; dígitos son re-selección; otro texto se recorta a 120 y se toma como ciudad. | **“Gracias” se persiste como ciudad y se registra el envío en la misma llamada.** Se elimina la captura. `fn_registrar_entrega` solo exige ciudad no vacía para transporte, además de validar pedido/punto. No existe confirmación de ciudad. | HU-076/086; `tbl_entrega_captura`, `tbl_envios`, `fn_procesar_captura_destino`, `fn_registrar_entrega` |
| WF-22 `Parse OCR` → WF-21 registro | Texto generado por OCR → JSON; quita fences, captura error de parseo. Confianza se convierte a número; campos ausentes reciben defaults. No hay esquema estricto para booleano, fecha, monto, operación ni rango de confianza. | JSON inválido produce `is_payment_receipt:false`, confianza 0 y `parse_error`. El IF técnico de WF-21 revisa `error`/booleano undefined, **no `parse_error`**, por lo que ese error puede tratarse como comprobante ilegible. | HU-059/060/062/064/065/146; `tbl_comprobantes_pago`, `tbl_verificaciones` |
| WF-23 `Decide Verification` | Booleano estrictamente true y umbrales de confianza 0.8/0.5; conserva el objeto de entrada. | No lee chitchat ni acepta “ya pagué” como confirmación. No valida un contrato completo antes de decidir. Rechazo y manual tienen texto y contexto top-level. | HU-060–065; `fn_rechazar_verificacion`, WF-24 `fn_confirmar_pago` |

No se captura dirección, zona o teléfono del comprador mediante texto libre en el recorrido actual de WF-25-B: el teléfono viene del canal; el punto viene del catálogo; la ciudad es el único campo de destino libre. Los nombres históricos de algunos nodos, como `Send Pide Zona via WF-80`, no describen el mensaje actual.

## 3. Fallbacks actuales por estado y mensajes cruzados

La prioridad efectiva de WF-04 es: resolver comercio → STOP → imagen/documento → candidato SKU → texto SI/NO y alias → entrega pendiente → noOp de ayuda. **Nombre, ciudad y pedido en verificación no tienen prioridad global propia.** Los estados siguientes describen situaciones de negocio; no suponen una máquina conversacional completa ya implementada.

| Situación | Texto inesperado / fuera de orden | Resultado del grafo actual |
|---|---|---|
| Sin pendiente relevante | “Hola”, “gracias”, “rebajame” | Consulta entrega; si no hay pendiente, `Placeholder → Ayuda / Menú` es noOp. WF-02 no encuentra `message_payload` y cierra success sin responder. No hay menú real. |
| Reserva activa / post-QR | “rebajame”, “gracias”, “ya pagué” | Mismo recorrido anterior si no existe otra entrega pendiente. No cambia precio ni confirma pago; tampoco recuerda enviar comprobante. Un SKU válido puede iniciar/reintentar otra reserva. |
| Verificación en curso | Chitchat textual | WF-23 no recibe este mensaje: entra por WF-04 y normalmente termina en silencio. Si existe un pedido PAGADO sin envío, puede consumirse en WF-25-B. No debe confundirse estado de reserva `PAGO_VALIDANDO` con el valor actual de `tbl_pedidos.estado`. |
| Esperando SI/NO para entrar en lista (Momento 1) | “gracias”, “sí por favor” | No llegan a WF-14. Silencio si no hay entrega; pueden guardarse como nombre/ciudad si la hay. No hay re-pregunta de lista por contexto. SI/OK/DALE aceptan; NO rechaza; YO toma rechazo por discrepancia. |
| Oportunidad NOTIFICADO (Momento 2) | “ok” como simple acuse, “YO”, respuesta tardía | OK acepta y puede crear reserva/QR. YO libera el turno. WF-14 busca oportunidad vigente más reciente por teléfono; sin ella prueba pendiente de alta y finalmente avisa que no hay oportunidades. Una respuesta tardía puede aplicarse a otro pendiente. |
| PAGADO sin envío, sin captura de ciudad | “gracias”, ciudad anticipada, texto no reconocido como opción | `Parse Nombre` guarda el texto y emite menú, incluso si el nombre ya se había dado. No distingue “esperando nombre” de “esperando punto”. |
| Menú de puntos | “9” inexistente / “10” / “2 por favor” | 9 inexistente re-pregunta; 10 y “2 por favor” se guardan como nombre. El catálogo puede tener más de nueve opciones; el parser externo solo admite una cifra. |
| Captura de ciudad activa | “gracias”, “rebajame”, “La Paz”, “2 por favor” | Si WF-04 deriva el texto a entrega, todos son ciudad no vacía para la RPC. Crea envío y cierra captura. Un número puro recibido por esta rama re-selecciona punto; inválido devuelve OPCION_INVALIDA y mensaje de formato. |
| Captura activa + texto con forma de SKU | “TARIJA” / seis letras o dígitos | El candidato SKU se procesa antes de consultar entrega. “Tarija” tiene seis letras: va a WF-10, no a ciudad. Si no existe SKU, intenta error de producto; si coincide con uno, puede reservar. |
| Captura activa + SI/NO/OK | Acuse de la pregunta de ciudad | Se deriva a WF-14 antes de entrega. Puede operar sobre lista u oportunidad concurrente; no confirma ni corrige ciudad. |
| Captura activa + imagen/documento | Foto o comprobante tardío | Va a WF-21 antes de entrega. Si no hay pedido ESPERANDO_PAGO, avisa que no hay pedido pendiente y sugiere SKU, aunque sí pueda existir entrega pendiente. |
| Tras registrar envío / despacho | “gracias” | Sin otra entrega pendiente termina en silencio. Con otro PAGADO sin envío puede convertirse en nombre del siguiente pedido. WF-25-C no consume respuestas. |
| Tipos no atendidos | Audio, ubicación, button/interactive | Fallback noOp en WF-04 salvo que algún campo ya haya activado otra regla. La normalización Meta no extrae respuestas de botones/listas; no hay petición de reenviar como texto. |
| Error RPC / estado no reconocido | Fallo técnico | No existe fallback contextual común. WF-04 tiene errores silenciosos; WF-25-B no tiene ramas de error RPC dedicadas. Los fallbacks de resultado no capturan automáticamente excepciones del nodo anterior. |

### Fallbacks internos que sí existen

- **WF-12:** AGREGADO, YA_EN_LISTA y LISTA_LLENA tienen mensajes; resultado desconocido va a `Msg Error técnico`. Una excepción Postgres no es un resultado del Switch y no queda cubierta por ese fallback.
- **WF-14:** mensajes para oportunidad vencida/no disponible, ausencia de pendiente, alta ya existente y rechazo. No hay estado de decisión inválida. `Resolve Opportunity` ordena por `fecha_notificacion DESC`, por lo que la mitigación histórica de orden ya está presente.
- **WF-21:** sin pedido, ilegible, duplicado, error de registro, SIN_CREDITOS y estado no verificable tienen mensajes; existe rama manual para error técnico OCR. El manejo de `parse_error` no coincide con ese propósito. El ACK manual después de `Start Verification Manual` no discrimina su `resultado` antes de afirmar que el equipo verifica.
- **WF-23:** rechazo informa reenvío; manual informa revisión humana. Contexto de F6 está presente. Los errores de la RPC de rechazo no tienen mensaje alternativo dedicado.
- **WF-24:** PAGO_CONFIRMADO termina y deja avisar a WF-25-A; RESERVA_VENCIDA avisa; YA_PROCESADO y resultado técnico desconocido terminan silenciosamente. No cambia umbrales ni interpreta afirmaciones del comprador.
- **WF-25-A:** valida token y PAGADO antes de pedir nombre. Emite una pregunta, pero no registra un paso específico “nombre solicitado” que permita distinguir respuestas posteriores.
- **WF-25-C:** PREPARANDO, ASIGNADO, EN_RUTA, ENTREGADO y fallback van a 200 silencioso; NO_ENTREGADO avisa; guía antepone SKU si existe. Estos son eventos de negocio, no respuestas al comprador.

### Ambigüedad y concurrencia

1. **Comercio/pedido ambiguo:** `fn_pedido_entrega_pendiente(telefono)` elige el PAGADO sin envío más reciente entre los que coincidan por teléfono, sin argumento comercio. `fn_entrega_captura_estado` y `fn_procesar_captura_destino` también buscan por teléfono; la segunda usa `LIMIT 1` sin el mismo filtro/orden que la primera. WF-04 y WF-25-B resuelven el contexto en llamadas separadas. Con varios pedidos/comercios o cambios entre llamadas, no queda asegurado el mismo destino de la respuesta. HU-076/077/086/123; `tbl_pedidos`, `tbl_entrega_captura`.
2. **Pregunta de lista reemplazada:** `fn_pendiente_lista` hace upsert por `id_cliente`, reemplazando variante/sucursal. SKU A sin stock → SKU B sin stock → SI puede aceptar B cuando el comprador respondía A. Aceptar/rechazar pendiente busca cliente solo por teléfono y `LIMIT 1`; WF-14 prioriza oportunidad NOTIFICADO sobre pendiente de alta. HU-043/046/047; `tbl_lista_pendiente`, `tbl_lista_espera`.
3. **Consumo de pendiente antes del alta:** `fn_aceptar_pendiente_lista` elimina el pendiente y luego WF-14 llama WF-12 en otra operación. Un fallo entre ambas deja sin pregunta reintentable. No es pérdida por chitchat, pero afecta la recuperación conversacional. HU-043/143.
4. **Comprobantes y pedidos múltiples:** WF-21 preselecciona el último ESPERANDO_PAGO; el registro normal no pasa ese `id_pedido` a `fn_registrar_comprobante`, que vuelve a resolver y prioriza reserva ACTIVA. Puede elegir otro pedido. `fn_iniciar_verificacion` bloquea el comprobante y exige RECIBIDO; eso no serializa toda la conversación por cliente. Un reenvío puede volver a poner el comprobante en RECIBIDO en `fn_registrar_comprobante`. HU-057–065.
5. **Dedup no equivale a orden:** WF-02 evita reprocesar el mismo identificador de mensaje, pero dos mensajes distintos, tardíos o simultáneos, siguen siendo dos entradas válidas. El grafo no vincula respuesta con la pregunta original ni con una revisión de contexto. HU-123/143.

## 4. STOP y opt-out: qué permanece protegido

**Recorrido canónico comprobado:** WF-02 procesa evento nuevo → WF-03 conserva texto/teléfono → WF-04 normaliza y resuelve comercio → `Opt-out request?` true → `RPC Registrar Opt-out` → noOp terminal. No continúa hacia SKU, SI/NO, nombre, ciudad ni comprobante. Se reconocen mayúsculas/minúsculas y espacios exteriores de las tres frases canónicas.

`fn_registrar_opt_out` persiste `opted_out=true` por `(id_comercio, telefono_whatsapp)` con upsert. WF-80 comienza por `Opt-out Check` (`0dbd750f-db6b-4d15-af63-efe265ab741f`) → `Opted-out?`; true registra `whatsapp_optout_skip` y termina antes del guard y del proveedor. `fn_cliente_optado` consulta exactamente comercio/teléfono. Todos los envíos a Meta/OpenWA encontrados en los 16 grafos pasan por WF-80; las únicas llamadas HTTP de mensajería están dentro de él. D9/D11 permanecen presentes.

**Límites que no permiten afirmar protección absoluta de cualquier variante de STOP:**

- `STOP!`, `por favor no me contacten` o espacios internos distintos no coinciden con igualdad exacta. Pueden seguir hacia captura de datos. Las tres frases exigidas sí coinciden; ampliar variantes requiere política explícita, sin convertir NO de una oportunidad en opt-out.
- WF-02 no itera todos los mensajes del lote. Un STOP en una posición posterior podría no llegar al router. Los captions de media tampoco se extraen como texto, por lo que STOP escrito solo allí no se reconoce.
- STOP exige `commerce_resolved=true` en el IF. Si no se puede construir resolver, termina silenciosamente. Si la RPC retorna sin comercio, el IF false deja continuar el routing: no debe permitirse consumir esa entrada como dato. Un error de registro lleva al error silencioso y no acredita persistencia del opt-out.
- Los subworkflows de captura no implementan STOP por sí mismos; dependen del ingreso por WF-04. Un futuro caller directo debe preservar esa precondición.
- `fn_cliente_optado` devuelve false si no hay coincidencia, incluido comercio nulo. Todo mensaje nuevo debe conservar `id_comercio`, `phone`, `provider` top-level; el antecedente #508 sigue siendo relevante. El opt-out no cancela reservas/pedidos ni necesariamente detiene operaciones ya iniciadas: su alcance comprobado es la salida y el consumo del comando STOP en el router.
- Una solicitud que ya superó el chequeo de opt-out puede estar en vuelo cuando entra STOP; no se probó concurrencia ni se garantiza retirada de un envío ya iniciado.

**Condición para cualquier intervención futura:** mantener STOP antes de cada clasificador/captura, no crear un ACK que eluda WF-80, no reactivar contactos como efecto de un saludo y no modificar el interior de WF-80 en este paquete. HU-142/143; Reglas 2/3/9; D9/D11.

## 5. Propuestas priorizadas: punto → riesgo → propuesta

Orden por daño potencial y beneficio. **Quick-win** significa alcance pequeño, no autorización para implementarlo ni garantía de que una simple lista de palabras resuelva el problema. Toda validación que cambie/persista negocio debe quedar en RPC transaccional y auditada. Los nombres de categorías siguientes son propuestas, no funciones/tablas nuevas existentes.

### Quick-wins

| Prioridad / ID | Punto | Riesgo | Propuesta concreta | IDs |
|---|---|---|---|---|
| P0 · Q1 | Captura de ciudad y nombre | Acuse/regateo termina persistido; ciudad puede crear envío inmediatamente. | Antes de escribir, reconocer un conjunto pequeño de acuses/saludos/regateo y devolver una re-pregunta contextual sin consumir captura ni modificar cliente. Validar vacío, longitud y formato; no truncar silenciosamente como sustituto de validación. Aplicar defensa en las RPC afectadas. Una regex de letras no distingue “gracias” de una ciudad; no presentar esta mitigación como validación geográfica completa. | WF-25-B `Procesar Captura` / `Parse Nombre`; HU-076/077/086; `fn_procesar_captura_destino`, `fn_upsert_cliente` |
| P0 · Q2 | WF-04 aceptación → WF-14 decisión | YO libera turno aunque el router lo marcó afirmativo; cualquier texto directo es rechazo. | Unificar vocabulario de entrada. Tres resultados: aceptar, rechazar explícito, no reconocido. Solo NO canónico rechaza; entrada no reconocida conserva pendiente y re-pregunta. Revisar si OK/DALE deben seguir siendo decisiones o simples acuses. | WF-04 `Enrich & Classify`; WF-14 `Parse Decision` / `Parse Decision 2`; HU-043/046/047; funciones de lista |
| P0 · Q3 | STOP sin comercio / variantes | Comando puede perderse o consumirse como dato. | Mantener la rama terminal de STOP aun cuando no se pueda resolver/persistir: reportar fallo técnico por el canal operativo existente, sin avanzar captura. Definir variantes adicionales conservadoras; jamás reclasificar NO como STOP. Conservar la consulta de WF-80 sin cambios internos. | WF-04 `Opt-out request?`; HU-142; `fn_registrar_opt_out`, `tbl_contact_preferences` |
| P1 · Q4 | Menú de puntos | “10” o “2 por favor” se guarda como nombre; captura fuera de orden. | Cuando se espera selección, validar entero completo y pertenencia al catálogo; toda entrada no válida reenvía opciones. Separar ese paso del nombre es prerequisito para una solución completa. Admitir más de nueve opciones si el catálogo las devuelve. | WF-25-B `¿Selección?`, `Mapear Selección`; HU-076/086; `fn_listar_puntos_entrega` |
| P1 · Q5 | Fallback de texto / tipos no atendidos | Silencio parece fallo; favorece reenvíos repetidos. | Reemplazar el noOp de ayuda por una respuesta breve con contrato completo de salida. Sin contexto fiable, no afirmar “estamos verificando”; ofrecer una instrucción neutral. En nombre/ciudad, acuse breve más la pregunta pendiente. Evitar un mensaje adicional por cada palabra repetida. | WF-04 `Placeholder → Ayuda / Menú`; WF-02 `Prepare WF-80 Input1`; HU-123/124; WF-80 como única salida |
| P1 · Q6 | Error de parseo OCR | Fallo técnico comunicado como comprobante inválido. | Validar esquema y tipos del resultado, propagar error técnico explícito y hacer que WF-21 lo reconozca; conservar revisión humana cuando corresponda. No cambiar umbrales ni convertir afirmaciones del comprador en evidencia de pago. | WF-22 `Parse OCR`; WF-21 `¿Error técnico del OCR?`; HU-059/064/065/146; `tbl_verificaciones` |
| P1 · Q7 | Fallback de SKU inválido | Mensaje construido puede no llegar por pérdida del contexto de envío. | Verificar/preservar comercio, teléfono y proveedor top-level en todos los errores retornados a WF-02. `Error: SKU no encontrado` e `Error: Input inválido` no asignan comercio explícitamente; tratarlo como riesgo de contrato hasta probar retorno E2E. No tocar WF-80. | WF-10 errores; WF-02 `Prepare WF-80 Input1`; HU-039/123/142; antecedente #508 |
| P2 · Q8 | Nombre de perfil y nombre ya confirmado | Una nueva reserva puede reemplazar el nombre útil con perfil/fallback. | No sobrescribir un nombre capturado por el comprador con “Cliente WhatsApp” o perfil incidental; definir precedencia en `fn_upsert_cliente` o contrato de llamada. No bloquear nombres legítimos de una sola palabra por regla arbitraria. | WF-10 `PG fn_upsert_cliente`, WF-25-B `Guardar Nombre`; HU-077; `tbl_clientes` |

### Rediseño / cambios coordinados

| Prioridad / ID | Punto | Riesgo | Propuesta concreta | IDs |
|---|---|---|---|---|
| P0 · R1 | Contexto resuelto solo por teléfono | Respuesta aplicada a otro comercio/pedido/captura. | Contexto explícito por comercio + cliente + entidad pendiente; misma entidad entre lectura y escritura. Validar/consumir atómicamente con revisión vigente y resultado de conflicto. Las RPC actuales de solo teléfono necesitan evolucionar; no resolverlo con SELECT→IF→UPDATE en n8n. | WF-04/14/21/25-B; HU-043/046/057/076/086/123; `tbl_lista_pendiente`, `tbl_lista_espera`, `tbl_pedidos`, `tbl_entrega_captura` |
| P1 · R2 | Prioridad global por forma de mensaje | “Tarija” se interpreta como SKU; OK/NO se desvía de entrega; foto no tiene contexto. | Tras STOP, resolver en BD el paso esperado y las acciones permitidas. Distinguir respuesta al paso de intención de nueva compra, ayuda o consulta. Ante múltiples pendientes, pedir elección explícita. Estados/contrato nuevos requieren diseño y migración; no inventar funciones en workflows. | WF-04 `Route by Message Type`; HU-123/076; `fn_pedido_entrega_pendiente`, `fn_entrega_captura_estado` |
| P1 · R3 | Persistencia inmediata de ciudad | Texto plausible pero incorrecto crea envío definitivo. | Capturar candidato, mostrar “¿Enviar a …?” y confirmar antes de `fn_registrar_entrega`, o usar catálogo de destinos con alternativa humana para poblaciones no listadas. La confirmación SI/NO debe estar vinculada a ese paso, no competir con WF-14. | WF-25-A/B; HU-076/086; `tbl_entrega_captura`, `tbl_envios` |
| P1 · R4 | Lista y respuestas tardías | SKU nuevo reemplaza pregunta anterior; SI genérico actúa sobre entidad equivocada. | Vincular respuesta a oportunidad/pregunta, conservar identidad y vigencia; IDs de botones o referencia explícita si se adopta interacción estructurada. Integrar consumo de pendiente + alta de lista en una transacción o mecanismo de reintento inequívoco. | WF-10/12/13/14; HU-043–049/143; `fn_pendiente_lista`, `fn_aceptar_pendiente_lista`, `fn_agregar_lista_espera_v2` |
| P1 · R5 | Post-QR y verificación | No hay fallback contextual fiable y pueden existir pedidos simultáneos. | Exponer estado real de pago/pedido desde BD y responder sin modificarlo: esperando comprobante, revisión en curso, reenvío permitido o vencido. Vincular comprobante al pedido seleccionado; no inferir estado solo por el último mensaje enviado. | WF-04/20/21/23/24; HU-057–065/123; `tbl_reservas`, `tbl_pedidos`, `tbl_comprobantes_pago`, `tbl_verificaciones` |
| P1 · R6 | Normalización por primer mensaje | Lotes, interactivas y mensajes cruzados incompletamente representados; STOP posterior se pierde. | Normalizar cada mensaje del lote con su identificador, conservar referencia de respuesta si existe y pasar cada uno por dedup. Definir serialización/validación de revisión por conversación; el dedup de ID no asegura orden. Decidir soporte de botones/listas antes de proponerlos como solución UX. | WF-02/03/04; HU-121/122/123/142/143; `tbl_whatsapp_eventos` |
| P2 · R7 | Recuperación y trazabilidad | Una re-pregunta puede perderse por error de salida; no hay clasificación común de fallos. | Resultado de negocio separado de resultado de envío; registrar entidad, estado observado e intención reconocida con datos mínimos. Reintentar notificación sin repetir mutaciones. Mantener guards de WF-80; no agregar un emisor alternativo. | WF-02/12/14/21/25-B; HU-126/127/143; `tbl_logs_auditoria`; Reglas 2/3/9 y D9/D11 |

### Hallazgos adyacentes que afectan el ruido conversacional

- **WF-25-C dedup tiene bypass en el grafo leído:** `Token válido?` conecta simultáneamente a `¿Guía?` y `Dedup Notificación`; `¿Primera vez?` también conecta a `¿Guía?`. Existe un recorrido de envío que no depende del resultado de dedup. La tabla puede deduplicar su INSERT sin bloquear ese recorrido. Proponer revisión separada del cableado (HU-092–094/143, `tbl_notificaciones_envio`); no se alteró ni se probó despacho. Esto no invalida que PREPARANDO esté silenciado, pero impide afirmar dedup efectivo solo por la existencia del nodo.
- **WF-13 mensaje usa `.first()` para algunos campos del grupo/notificación y datos del item para otros.** Con varios grupos, revisar correspondencia de comercio, producto y destinatario antes de introducir respuestas vinculadas a una oferta. No se reprodujo mezcla de mensajes; es un riesgo estático (HU-045/142, `Build Message Payload`, `tbl_lista_espera`).
- **WF-14 `Resolve Provider` selecciona un canal activo sin filtrar comercio.** Debe revisarse junto al contexto multi-comercio; los nuevos acuses no deben copiar este patrón (HU-123/124/142, `tbl_canal_whatsapp`).

## 6. Casos propuestos para validación posterior — no ejecutados

| Caso | Criterio de aceptación propuesto |
|---|---|
| Post-QR: “gracias”, “rebajame”, “ya pagué” | Acuse/instrucción según estado; precio, reserva y pago no cambian por texto. |
| Verificación automática y manual: chitchat + reenvío | Mensaje coherente con estado real; no crea otra verificación por chitchat ni confirma por afirmación. Reenvío enlazado al pedido correcto. |
| Nombre: “gracias”, vacío, nombre de una palabra, nombre compuesto | Acuse no se guarda; nombre legítimo conserva integridad; menú no vuelve a sobrescribir nombre. |
| Ciudad: “gracias”, “rebajame”, “Tarija”, “La Paz”, “2 por favor” | Conversación incidental no crea envío; Tarija no dispara reserva; ambigüedad re-pregunta; ciudad confirmada persiste. |
| Punto: 0, 9 inexistente, 10 existente, número tardío | Solo opción válida del menú vigente cambia destino; entrada inválida no se guarda como nombre. |
| SI/NO: SI, SÍ, NO, YO, OK, “sí, gracias”, otra frase | Vocabulario acordado consistente entre router y WF-14; solo rechazo explícito libera turno; ambigüedad conserva pendiente. |
| SKU A → SKU B → SI; oportunidad y entrega simultáneas | No acepta una pregunta diferente por accidente; referencia/entidad explícita. |
| Mismo teléfono en dos comercios / dos pedidos | Una respuesta solo afecta el comercio y pedido elegido; lectura y mutación usan la misma identidad. |
| STOP, NO QUIERO, NO ME CONTACTEN en cada paso | Preferencia persistida; el comando no llega a captura; todo envío posterior pasa por WF-80 y se suprime. Fallo de resolución no convierte STOP en nombre/ciudad. |
| Lote con STOP en segundo lugar; duplicado de mismo ID | Todos los mensajes se evalúan una vez; duplicado no repite negocio; comprobar orden/concurrencia sin prometer cancelar un envío ya en vuelo. |
| Error OCR de formato vs imagen que no es comprobante | Error técnico y rechazo de contenido se comunican por ramas distintas; D5 permite reenvío cuando corresponda. |
| Repetición de webhook de guía | Una sola notificación; ruta de envío condicionada efectivamente por dedup. |

Antes de implementar, acordar el vocabulario afirmativo y la política de acuses. La secuencia recomendada es mitigar escritura de chitchat y rechazo implícito, preservar STOP, y luego resolver identidad/paso conversacional en BD. El estado de implementación al momento de cerrar la auditoría se actualiza en el addendum siguiente.

## Addendum — Quick-wins publicados 2026-09-12

Se publicaron Q1/Q2/Q4/Q7 sin migraciones y sin cambios a STOP, opt-out ni WF-80.

### Q2: sets finales de decisión de lista

| Resultado | Texto canónico normalizado | Efecto |
|---|---|---|
| ACEPTAR | SI, SÍ, OK, DALE, YO | Conserva los flujos de aceptación existentes. |
| RECHAZAR | Solo NO | Conserva las RPC existentes de rechazo/liberación. |
| CONSERVAR | Cualquier otro texto o tipo no textual | No muta pendiente ni turno; re-pregunta el contexto vigente. |

WF-04 expone list_decision, is_acceptance e is_rejection. WF-14 aplica las tres decisiones tanto a oportunidad NOTIFICADO como a pregunta de lista pendiente; las rutas de rechazo solo reciben RECHAZAR.
