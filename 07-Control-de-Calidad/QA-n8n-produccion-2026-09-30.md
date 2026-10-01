# QA de flujos n8n en producción — 2026-09-30

## Alcance y resultado

Se está validando el recorrido WhatsApp de RSUELVO en producción con los tenants de prueba Prueba RSUELVO y Celulares. Los mensajes de salida de las pruebas usan destinatarios sintéticos interceptados por WF-80. La auditoría no registra envíos reales para esos destinatarios.

**Estado: en curso; E2E integral no certificado.** No marcar los flujos como perfectos ni cerrar QA hasta completar entrada SKU, comprobante, aprobación de cajero, callbacks de entrega y lista de espera con ejecución observable.

## Hechos comprobados en esta continuación

- WF-80 (`7V6MIPuGbdx9s0lT`) quedó publicado en versión `8b6c840a-d5fb-4e29-9c2c-64666d9e1a8c`, sin warnings. El modo simulado acepta solo Prueba RSUELVO + `QA_SIM_PRUEBA_01` y Celulares + `QA_SIM_CELULARES_01`. Las parejas sintéticas reservadas se simulan aunque falte `simulation_mode`; el flag con tenant o destinatario incorrecto se rechaza antes del HTTP a Meta.
- Dos ejecuciones del arnés manual inactivo `QA-IAM10-DIRECT-PG-SMOKE` dieron, por auditoría de Supabase, dos `whatsapp_send_simulated` y dos `whatsapp_simulation_rejected` cada una. No hubo `whatsapp_send` para los casos QA.
- La resolución de SKU en Supabase mapea `FERA01` a Prueba RSUELVO y `FEE001` a Celulares. El inventario leído antes de probar era FERA01: 5 disponibles/0 reservados; FEE001: 3/0. La consulta de producción no mostró clientes QA con los teléfonos reservados.
- Se agregó un branch al draft QA inactivo para construir mensajes SKU y llamar al WF-04. El MCP contestó `started` (ID reportado 154), pero `search_workflow_executions` devolvió cero y `get_workflow_execution` no encontró la ejecución. Supabase no mostró clientes/reservas/pedidos creados por ese branch. No contar esta llamada como prueba del router ni atribuir un resultado a sus nodos hijos.
- `prepare-community.sh`, `verify-community-package.py` y `py_compile` pasan en el paquete local: 18 workflows, 391 nodos, 94 Code, 25 Postgres y 40 guardas WF-80. Pasan las matrices sintéticas de WF-80, WF-21, WF-02 y WF-22. `scripts/test_local.sh` previamente terminó con 344 passed; es cobertura local de backend, no E2E n8n.

## Pendientes para cerrar

1. Conseguir observabilidad de ejecuciones manuales/subworkflows y completar SKU → reserva → pedido/QR en Prueba RSUELVO y Celulares; comprobar estado por consultas antes/después y no dejar stock reservado.
2. Recorrer comprobante entrante → archivo/OCR o revisión manual → aprobación por cajero → confirmación WhatsApp. No descargar media desde Meta en un test sintético salvo que el medio de prueba sea válido; usar el comprobante de prueba autorizado con el vínculo tenant/pedido correcto.
3. Probar callbacks de entrega repetidos y cada estado relevante con pedido fixture. El riesgo de deduplicación/outbox documentado en la auditoría sigue requiriendo una ruta durable para fallos ambiguos.
4. Crear un único registro sintético elegible de lista de espera y verificar alta idempotente, aviso al siguiente y cron/callback; confirmar que el aviso sale solo por la pareja sintética. El estado consultado antes de esta ronda no tenía filas `ESPERANDO` activas.
5. Reconciliar auditoría de salida (simulados/rechazados/envíos reales) y registros de negocio tras cada caso; retirar fixtures temporales y verificar inventario neto sin cambios.
6. Repetir lint, verificador de paquete y suites locales tras correcciones; después documentar versiones, evidencias y cualquier riesgo restante.

La bitácora técnica detallada está en `/home/nico/rsuelvo-n8n-local/AUDIT-2026-09-29.md` (sección “Continuación de QA — 2026-09-30 13:07 UTC”).

## Ampliación E2E — 2026-09-30 14:18 UTC

- Mediante el webhook POST de WF-02 con payload Meta sintético completé SKU→reserva→pedido/QR→WF-80 en dos tenants: FERA01→Prueba RSUELVO y FEE001→Celulares. Ambos eventos quedaron `PROCESADO` y cada mensaje saliente fue `simulated`. Repetir la misma WAMID de FERA01 no creó otra reserva/pedido ni otro log de salida.
- Las reservas temporales expiraron: stock final FERA01 5/0 reservado y FEE001 3/0 reservado. Quedan dos pedidos QA `ESPERANDO_PAGO` con cobros QR `GENERADO`, ligados a reservas vencidas. La función de aprobación impide confirmar venta con reserva vencida (`RESERVA_VENCIDA`); no existe RPC de cancelación identificada, así que los pedidos sintéticos se conservan para trazabilidad y no se editaron directamente.
- Una prueba con imagen y `media_id` inválido mostró que la respuesta de error podía salir por WF-80 mientras el evento quedaba `PROCESANDO`. Corregí y publiqué WF-02: `Close Event Error1` usa el item original estable y `Route to WF-03` entrega un item vacío cuando el hijo no devuelve resultados. Una segunda prueba cerró el evento `PROCESADO` con respuesta simulada. WF-02 activa `1eaa683d-fd9f-445a-875c-4380a8b47a79`; WF-80 activa `8b6c840a-d5fb-4e29-9c2c-64666d9e1a8c`; ambas coinciden con el borrador.
- Probé lista de espera de punta a punta: FERI01 sin stock creó una pendiente; `SI` registró `ESPERANDO`; una entrada/restauración neta de inventario QA hizo elegible el grupo; WF-13 notificó y WF-80 registró `simulated`; `NO` dejó el turno `RECHAZADO`. Verifiqué tanto el disparo funcional de pg_net (HTTP 200) como el job programado `rsuelvo_expirar_reservas` cada minuto: el job de las 14:18 notificó el único cliente sintético elegible, pg_net obtuvo HTTP 200 (respuesta 155) y WF-80 auditó `simulated`. Un segundo ciclo durante el turno activo devolvió `notificables=false` y no duplicó el envío. El inventario FERI01 terminó en 0/0 y no quedaron entradas activas de espera.
- Entre los smoke/E2E de la sesión hay 17 logs `whatsapp_send_simulated` y 0 logs `whatsapp_send` para los destinatarios reservados. Dos ejecuciones previas de imagen malformada quedaron cerradas como `ERROR` mediante la RPC oficial; la nueva prueba posterior al arreglo quedó `PROCESADO`.
- Continúan pendientes el comprobante válido→OCR/revisión manual→aprobación de cajero→confirmación al comprador y los callbacks de cada estado de entrega. El arnés n8n sigue sin conservar detalle de ejecuciones, por lo que se verificaron cambios con estados/auditoría Supabase. No marcar el QA general como completo.

El orquestador OpenCode fue contactado en su sesión guardada tres veces; respondió error interno de servidor en los tres intentos. El usuario ya había autorizado documentar, hacer commit y push del vault; al fallar OpenCode, el commit `321ea39` se hizo directamente y se subió a `origin/main`. Esta ampliación todavía requiere su siguiente commit/push.

## Revisión adicional de callback y retención — 2026-09-30

- Los callbacks sintéticos de WF-25C cubrieron `PREPARANDO`, `ASIGNADO`, `EN_RUTA`, `ENTREGADO`, `NO_ENTREGADO` y `guia_registrada` con el fixture de Prueba RSUELVO. Cada evento probado quedó registrado una vez en `tbl_notificaciones_envio`; la repetición de una clave ya usada no creó otra notificación. WF-80 dejó seis logs simulados para el teléfono sintético de Prueba RSUELVO. La búsqueda de auditoría no encontró envíos reales en esa ventana.
- Una serie de llamadas con una combinación de tenant/destinatario sintético incorrecta fue detenida por la guarda previa de WF-80. Las seis ejecuciones integradas terminaron con error en `Log Guard` por violación de FK en `tbl_logs_auditoria`. La fila del tenant consultado sí existe en el proyecto de producción; la causa de la discrepancia queda abierta. No atribuir estos seis intentos a tráfico de clientes ni a envíos Meta.
- El historial de errores de los callbacks conserva headers de autenticación y cuerpos de petición. Se comprobó que WF-25A, WF-25C y WF-13 eran webhooks activos sin políticas explícitas de no-retención. Se actualizaron y publicaron con `saveDataErrorExecution=none` y `saveDataSuccessExecution=none`; la lectura posterior confirmó ambas opciones en los tres workflows activos. Después se ejecutaron callbacks sintéticos manuales de WF-25C; el MCP no conservó sus ejecuciones y se verificó el resultado solo mediante deduplicación y auditoría en Supabase.
- La configuración anterior solo evita guardar datos de nuevas ejecuciones. Los datos ya persistidos siguen en el historial y los secretos de callback requieren rotación/purga por un canal con acceso a credenciales. La actualización no rota credenciales, no borra ejecuciones antiguas ni verifica el plazo de retención global de n8n.
- La suite local del backend en el último registro de esta ronda terminó con 344 pruebas aprobadas. No sustituye el E2E productivo ni certifica OCR/cajero, confirmación de pago o estados de entrega originados por las funciones de base de datos.

**Estado:** QA productivo todavía abierto. El registro FK de rechazos, la rotación/purga de secretos expuestos, el flujo válido de comprobante→cajero→confirmación y la comprobación de los callbacks originados por cambios reales de estado siguen pendientes.

### Revalidación de guía y deduplicación — 2026-09-30 15:04 UTC

- Se detectó que una llamada sintética con tenant/destinatario mezclados había ocupado la clave real `guia_registrada` para el envío fixture. Eliminé solo esa fila, validada por `id_envio`, evento y timestamp exacto, para no suprimir una futura notificación legítima.
- Repetí WF-25C con el tenant y destinatario QA correctos. `tbl_notificaciones_envio` conservó una fila para `guia_registrada`; WF-80 creó un log `whatsapp_send_simulated`. Al repetir exactamente el mismo callback, la fila siguió en una y el log simulado siguió en uno. En la ventana de verificación hubo cero logs `whatsapp_send` reales.
- No se cambió el estado del envío ni se llamó a Meta. La ejecución n8n devolvió `started` sin quedar consultable por el MCP; la evidencia de resultado es el registro de deduplicación y los logs de auditoría en Supabase.

### Guard de ownership del callback — 2026-09-30 15:24 UTC

- Se verificó en la función desplegada de estado que el callback incluye `id_envio`, `id_comercio`, `id_pedido`, `phone`, `estado` y `numero_guia`; las funciones reales `fn_registrar_guia`/`fn_set_numero_guia` también incluyen tenant, pedido, teléfono, `numero_guia` y `motivo=guia_registrada`, pero omiten `estado`.
- El grafo anterior insertaba `(id_envio, evento)` antes de comprobar que esos campos pertenecían juntos a una sola fila. Un par mezclado podía ocupar una clave legítima y bloquear un callback posterior.
- Producción recibió dos migraciones versionadas: `20260930151807_private_validate_delivery_callback_before_dedup` crea `rsuelvo_private.fn_registrar_notificacion_envio_validada`; `20260930152316_allow_guide_callbacks_without_state` adapta su rama de guía al payload real. La función fija `search_path` vacío, la posee `postgres` y solo concede `USAGE`/`EXECUTE` a `n8n_runtime`. `anon` y `authenticated` no pueden ejecutarla; `n8n_runtime` aún no tiene lectura directa de `tbl_envios`.
- WF-25C fue actualizado y publicado como `9f94060a-1569-4391-9b95-6c1c9bf46be4`. Su nodo `Dedup Notificación` llama a la función privada y solo da paso al envío cuando vuelve una fila; la deduplicación queda después de validar tenant, pedido, teléfono, estado actual o guía registrada. Siguen activas las opciones de no-retención en ejecuciones nuevas.
- Consultas sintéticas directas contra la función en producción dieron cero filas para: tenant incorrecto con estado permitido, teléfono incorrecto, estado atrasado y guía no registrada con tenant incorrecto. La clave `EN_RUTA` del envío QA continuó en cero. El `PREPARANDO` que ya existía es del 2026-09-29 y se verificó con timestamp; no se atribuye a esta ejecución.
- Se identificó que el envío de prueba consultado corresponde a un teléfono de cliente que **no** es uno de los destinatarios sintéticos reservados. Por seguridad, no se realizó un camino positivo de callback hacia Meta con ese envío. Tampoco hubo filas de envío simulado en la ventana de la verificación. La llamada de ejecución manual de WF-25C devolvió `started`, pero no quedó consultable en el MCP; no prueba el recorrido del grafo ni la identidad de la credencial Postgres.
- La lista de credenciales de n8n solo muestra una credencial Postgres llamada `Postgres account`; la lista no revela el usuario configurado. Confirmar que esa conexión usa `n8n_runtime` sigue abierto antes de aprobar privilegios mínimos. La función RPC privada ya está concedida a ese rol.
- Sigue sin prueba positiva del webhook DB→WF-25C→WF-80 simulado porque producción no tiene un fixture pedido/envío con uno de los teléfonos QA reservados. Preparar ese fixture debe empezar por confirmar los efectos de triggers de auditoría/push y limpiar todos los datos temporales; no mutar la guía ni el teléfono de un cliente real.

**Estado tras esta ronda:** la ruta queda protegida contra cruces de tenant/teléfono y claves de deduplicación falsas a nivel de base de datos. La validación negativa de la función está hecha; no hay evidencia de entrega positiva desde los triggers de producción. Se mantienen pendientes el canary positivo aislado, comprobar la credencial Postgres runtime, completar el pago válido hasta cajero/cliente, revisar los avisos de seguridad de Supabase y resolver rotación/purga de historiales de secretos expuestos.

### Endurecimiento de RPC y vistas — 2026-09-30 15:39 UTC

- Se aplicó en producción la migración `20260930153829_harden_workflow_privilege_rpcs`. La primera invocación falló por una firma mal transcrita de `fn_alta_comercio` y no dejó cambios; la segunda usó literalmente el archivo local y quedó registrada en el ledger.
- Se retiró `EXECUTE` de `anon`/`authenticated` para funciones internas de cron, reserva, créditos, callbacks y triggers. Se confirmó `anon_exec=false` y `auth_exec=false` en `fn_cron_expirar_y_notificar`, `fn_cron_notificar_por_vencer`, `fn_procesar_reservas_vencidas` y `fn_acreditar_creditos`. `service_role` conserva ejecución de las rutas backend.
- Se mantuvieron las RPC de guía y transición de envío para `authenticated`, ahora con autorización por tenant dentro de la función. La lookup de comercio por WhatsApp quedó solo para `service_role`. Las vistas `vw_inventario_disponible` y `vw_lista_espera_activa` usan `security_invoker=true` para respetar permisos/RLS del llamante.
- Los dos jobs cron de producción siguen activos cada minuto como `postgres`: `rsuelvo_expirar_reservas` y `rsuelvo_push_por_vencer`. No ejecuté sus funciones manualmente para no alterar datos de negocio.
- El Security Advisor posterior aún reporta 16 funciones `SECURITY DEFINER` accesibles por `anon`, 50 por `authenticated`, 8 tablas RLS sin políticas, `pg_net` instalado en `public` y protección de contraseñas filtradas deshabilitada. Esos hallazgos requieren inventario por consumidor y corrección gradual; no se revocaron grants en bloque para evitar romper RPC legítimas. La lista completa está en el Advisor de Supabase observado a las 15:39 UTC.

**Estado:** mejora de permisos confirmada, pero no constituye cierre del security review. Pendientes E2E de pago/cajero y callback positivo aislado, identidad real de la credencial Postgres n8n, evaluación de findings restantes, rotación/purga de secretos en historial y preparación/ejecución VPS.

### Cierre de helpers para rol anon — 2026-09-30 15:42 UTC

- La revisión de los 16 hallazgos `anon_security_definer_function_executable` encontró que la app llama `fn_sugerir_codigo` durante el alta sin autenticación. Ese RPC se conserva por compatibilidad. `rg` en Flutter/web no encontró llamadas directas a los otros helpers; los usos restantes detectados son funciones internas y pruebas.
- Se aplicó `20260930154610_revoke_anon_authorization_helpers`: revoca `PUBLIC`/`anon` de los 15 helpers restantes y otorga explícitamente `authenticated`/`service_role` para preservar los permisos que antes heredaban de `PUBLIC`.
- Comprobación de catálogo posterior: los 15 helpers dan `anon_exec=false`, `authenticated_exec=true`, `service_role_exec=true`; `fn_sugerir_codigo` conserva ejecución de `anon`. El Security Advisor pasó de 16 a 1 función marcada para `anon`.
- No se verificaron llamadas HTTP con JWT anónimo/autenticado: esta confirmación es de ACL PostgreSQL y referencias estáticas locales. La prueba funcional de alta sin sesión (`fn_sugerir_codigo`) sigue pendiente.

**Pendiente de seguridad:** quedan 50 funciones `SECURITY DEFINER` expuestas a `authenticated`, que deben revisarse contra el consumidor de cada RPC, y los hallazgos de tablas RLS sin políticas, extensión `pg_net` en `public` y protección de contraseñas filtradas deshabilitada. No se ha aprobado una revocación masiva.

### Canary final WF-80 / SKU y paridad de runtime — 2026-09-30 16:02 UTC

- La credencial Postgres real de n8n quedó confirmada desde el arnés manual como usuario SQL `n8n_runtime`, en la base `postgres`. La misma conexión informó `USAGE` en `rsuelvo_private`, `EXECUTE` en `fn_registrar_notificacion_envio_validada(...)` y sin `SELECT` directo a `rsuelvo.tbl_envios`. Se reemplazó en el arnés la comprobación que intentaba leer `auth.jwt()` (fallaba con `permission denied for schema auth`) por esta comprobación de privilegios mínimos. La retención manual temporal se volvió al valor predeterminado al terminar.
- El arnés QA tenía una aserción inerte: WF-80 sí guardaba la auditoría, pero la rama que devolvía el resultado dependía del nodo Postgres de logging, que no emite filas. WF-80 v`b1cd62a4-7f91-4a9f-8bf8-9579aa787508` ahora devuelve el resultado del guard en paralelo al registro; `Blocked Result` conserva el teléfono sintético. El nodo `Assert Simulated Sends` ya ejecutó y aprobó los cuatro casos: dos pares tenant/destinatario autorizados devolvieron `simulated`, y el tenant/teléfono incorrectos devolvieron `blocked_simulation_forbidden`.
- La repetición SKU encontró que WF-04 preparaba el aviso de error WF-10 usando el nodo de contexto de otra rama (`Attach Commerce`), que no había corrido en el camino universal SKU. WF-04 v`87aace46-0d14-46ea-a1ce-45520d55c43f` usa ahora `Attach Comercio Universal` para ese aviso. Las ocho guardas de notificación de WF-04 y la guarda de aviso QR en WF-10 aceptan `simulated` solamente con `simulated=true` y `errored=false`, preservando el rechazo de cualquier otro estado que no sea `sent` o `blocked_optout`.
- Canary QA root `305` expuso y permitió corregir que la aserción comparaba el teléfono, pero `Blocked Result` no lo devolvía; root `320` confirmó la discrepancia. Root `331` verificó la rama de error simulada sin enviar a Meta; root `348` terminó `success`, WF-80 pasó sus cuatro aserciones y WF-04 devolvió `RESERVA_YA_EXISTENTE` para FERA01/Prueba RSUELVO y FEE001/Celulares. WF-10 quedó publicado en v`ce0e6491-a2c7-42d5-8b29-54370e94b3c6`.
- En la ventana 16:01:30–16:02:00 UTC, la auditoría registró seis `whatsapp_send_simulated`, dos `whatsapp_simulation_rejected` y cero `whatsapp_send` reales. El inventario de las reservas se mantuvo sin incremento por la repetición final; cualquier reserva QA activa temporal queda a cargo del cron minuto a minuto y debe verificarse al vencer.
- `scripts/test_local.sh` terminó después de incluir la nueva migración de ACL: **344 passed**, una advertencia deprecada de Starlette/httpx; sin fallos ni skips.
- La inspección del Advisor confirma que las ocho tablas marcadas RLS sin políticas niegan acceso directo a `anon`; siete niegan también `authenticated`. `tbl_whatsapp_eventos` conserva grants SQL de usuario, pero RLS sin políticas mantiene el default-deny. Las 50 funciones `SECURITY DEFINER` para `authenticated` incluyen varios mutadores con controles internos de identidad/rol/tenant; el Advisor por sí solo no demuestra vulnerabilidad y queda pendiente el inventario de consumidores y pruebas JWT por rol.

**Estado general:** continúa abierto. No se completó comprobante válido → aprobación autenticada de cajero → confirmación al comprador, ni un callback positivo de envío desde trigger de base de datos sobre fixture enlazado a teléfono QA. También siguen pendientes la rotación/purga de secretos históricos, el seguimiento de findings de seguridad restantes, certificación de ejecución n8n/MCP, la provisión de VPS y el canary de expiración/limpieza de las reservas QA activas.

### Limpieza del canary de reserva — 2026-09-30 16:10 UTC

- Esperé los vencimientos normales, sin llamar manualmente a las funciones cron. `rsuelvo_expirar_reservas` y `rsuelvo_push_por_vencer` siguieron activos como `postgres` en intervalos de un minuto.
- Las reservas QA recientes de FERA01/Prueba RSUELVO y FEE001/Celulares quedaron `VENCIDA`; la suma de `stock_reservado` volvió a `0` en ambos inventarios (stock total 5 y 3, respectivamente). No quedan reservas QA activas de ese canary.
- Esto verifica el vencimiento/limpieza del stock para estos fixtures; el cron de aviso de lista de espera tuvo su E2E sintético previo documentado arriba.

### Corrección de aserciones simuladas y repetición SKU — 2026-09-30 16:18 UTC

- La revisión del código realmente publicado encontró que WF-20 aún rechazaba `simulated` aunque el gateway devolvía `simulated=true` y `errored=false`. Ese rechazo convertía una reserva/QR correctos de QA en ejecución `error` y activaba el aviso que decía no pagar. Corregí y publiqué WF-20 en `b41c0ebb-6e0b-48cf-9478-269977a05c2a`.
- Extendí la misma condición segura a 22 aserciones de WF-02, WF-12, WF-13, WF-14, WF-21, WF-23, WF-24, WF-25A, WF-25B y WF-25C. Se publicaron sin warnings. En todos los casos, `sent`/`blocked_optout` siguen siendo resultados aceptados y ninguna simulación con `errored=true` pasa.
- El arnés QA manual `376` terminó `success`: las cuatro verificaciones WF-80 aprobaron dos pares sintéticos permitidos y rechazaron un tenant y un destinatario incorrectos. El recorrido de SKU probó FERA01/Prueba RSUELVO y FEE001/Celulares y devolvió QR/cobro; los dos destinatarios fueron los teléfonos `QA_SIM_*` reservados, por lo que no se envió WhatsApp real.
- Una consulta SQL de solo lectura, con la identidad `n8n_runtime`, confirmó un pedido y un cobro `GENERADO` por cada reserva sintética después de repetir la entrada SKU. Esto confirma idempotencia del pedido/cobro en esas dos reservas, aunque cada repetición puede volver a enviar la imagen de pago simulada.
- Para obtener esa evidencia se habilitó temporalmente la retención manual del arnés y se restauró a `DEFAULT` tras la ejecución `389`; también se restauró íntegramente la consulta de IAM del nodo. Las ejecuciones simuladas no se confunden con entrega por WhatsApp real.
- Las reservas renovadas vencían a las 16:23 UTC. Aún falta comprobar después de esa hora que el cron las expire y libere stock. Siguen pendientes el comprobante válido → aprobación autenticada del cajero → confirmación al comprador, callback positivo enlazado a un fixture cuyo teléfono sea QA, y los restantes gates de seguridad/rotación indicados arriba.

### Diagnóstico del comprobante ya aprobado — 2026-09-30 16:30 UTC

- La nota de base vincula el comprobante de prueba `1e77d678-cdc7-4f71-a3a8-2ca2972c3b51` con el pedido `5a298814-f4c6-4d66-81d1-7eda9dca4bc7`. La bitácora de auditoría confirma la secuencia: el cajero lo marcó `VALIDO`, completó la verificación y el pedido pasó de `ESPERANDO_PAGO` a `PAGADO` a las 14:10:58 UTC del 29-09. El pedido pasó después a `PREPARANDO` y tiene un envío `PENDIENTE`.
- El workflow WF-25A falló un segundo después del pago: ejecución n8n `86`, nodo `Lookup Pedido`, URL REST construida con base `undefined`. Por ello el webhook no pudo comprobar `PAGADO` ni enviar la confirmación. El grafo activo ya contiene el URL del proyecto explícito, versión `dc894f70-e8d8-484d-ae26-e6d45299a04d`; pruebas n8n con datos pinneados dieron `success` para `PAGADO` (salida WF-80 simulada al par QA) y para `PREPARANDO` (rama no pagada, 200 sin envío). No se abrió una petición a Meta.
- El pedido ya está `PREPARANDO` y su teléfono no pertenece a la lista QA reservada; no reproduje el callback ni forcé la guarda para enviarle a un número de cliente. La prueba demuestra la ruta actual de WF-25A, pero no repara retroactivamente la notificación omitida ni certifica una nueva entrega a comprador. Hace falta un mecanismo seguro de reintento con destinatario de prueba y el estado/contrato correcto.
- Tras el vencimiento normal, consulta de solo lectura confirmó cero reservas activas de los teléfonos QA; los dos SKUs conservan inventario 5/0 y 3/0. Los crons `rsuelvo_expirar_reservas` y `rsuelvo_push_por_vencer` siguen activos cada minuto como `postgres`. Cada tenant de QA conserva cuatro pedidos sintéticos `ESPERANDO_PAGO` y cuatro cobros `GENERADO`, ligados a cuatro reservas `VENCIDA`; se mantienen por trazabilidad, sin edición directa ni ajuste manual del inventario.
- En la repetición validada se contó una fila de pedido y un cobro generado por cada reserva (idempotencia); la salida simulada puede volver a enviar la imagen de pago QA. La retención temporal y la consulta IAM del arnés quedaron restauradas.

**Estado:** corregido y probado el rechazo falso de `simulated` y la aserción de WF-25A con rutas simuladas. No está cerrado el caso real de notificación perdida al aprobar el comprobante. Siguen abiertos el pago/cajero→comprador sintético de extremo a extremo, callback positivo de entrega enlazado a teléfono QA, purga/rotación de credenciales históricas, pruebas JWT del resto de funciones de seguridad y los gates de producción listados arriba.

- La auditoría por teléfono del comprador no tiene ningún registro de `whatsapp_send` entre 14:10:58 y 14:11:30 UTC, justo después de la aprobación; esto concuerda con el error del workflow y confirma que no salió la confirmación por ese intento.

### Pruebas aisladas de captura de entrega — 2026-09-30 16:32 UTC

- Con `test_workflow` y datos pinneados para los nodos de webhook/DB, ejecuté seis rutas de WF-25C: `PREPARANDO`, `ASIGNADO`, `EN_RUTA`, `ENTREGADO`, `NO_ENTREGADO` y `guia_registrada`. Las seis terminaron `success` (IDs 405, 407, 409, 411, 413 y 415); el nodo de deduplicación usó un resultado fijado para no insertar notificaciones reales. WF-80 recibió solo el par sintético reservado y lo simuló.
- En WF-25B probé las rutas con contexto/DB pinneados: menú después del nombre, selección de punto local, selección de transportadora y captura de ciudad. Las cuatro terminaron `success` (IDs 417, 419, 421 y 423); todas las respuestas de WF-80 fueron simuladas. Los nodos RPC/HTTP de prueba no escribieron registros de clientes ni envíos.
- La auditoría del tenant Prueba RSUELVO en 16:29–16:32 UTC agregó 10 `whatsapp_send_simulated`; no apareció `whatsapp_send`. El arnés manual está inactivo y su configuración posterior muestra retención manual en valores `DEFAULT` (sin override).
- Son pruebas de ramas con dependencias externas pinneadas: cubren los mensajes, condiciones y aserciones del grafo sin ejercitar triggers reales ni confirmar escritura/deduplicación de la base en esos casos. El callback positivo con fixture ligado a número QA y la captura con estado de base real siguen pendientes.

### Cierre sintéticos 2026-09-30 — WF-14 positivo y ciclo de vida de QR

- WF-14 positivo en aislamiento: NOTIFICADO+SI → CONVERTIDO_RESERVA, reserva + QR GENERADO, WF-80 simulado, 0 real. WF-12/WF-13 cron dos tenants todo simulado. Cron 18:02 UTC venció la aceptada: reservado a 0, QR EXPIRADO. Harness a 10 nodos base/inactivo/v1. Intervalo: 20 `whatsapp_send_simulated`, 2 rechazados, 0 reales; evidencia por SQL.
- Migración `20260930180547_sync_qr_cobro_lifecycle` (41 QR GENERADO: 12 pagados/downstream, 28 vencidos, 1 cancelado → PAGADO/CANCELADO/EXPIRADO + triggers; ACL sin EXECUTE anon/authenticated/service_role). Local 1/1; `scripts/test_local.sh` 345 tests.
- QA sigue abierto: Auth-JWT cajero para pago/entrega E2E, callback positivo con fixture QA y gates de cutover pendientes. Producción NO lista para cutover.

### Escalamiento de lista de espera por cron — 2026-09-30 18:27 UTC

- Repetí el arnés QA inactivo en Prueba RSUELVO y Celulares. SQL confirma dos pedidos `ESPERANDO_PAGO`, dos reservas activas y QR `GENERADO`, uno por tenant. La bitácora agrupada registró ocho `whatsapp_send_simulated` y dos `whatsapp_simulation_rejected`; cero `whatsapp_send` reales. n8n devolvió la ejecución manual 547 como `started`, pero luego no la retuvo; la evidencia del resultado viene de Supabase.
- Para cubrir al siguiente de la fila, registré `QA_SIM_PRUEBA_02` con `fn_upsert_cliente` y lo agregué mediante `fn_agregar_lista_espera_v2` en posición 2. Amplié temporalmente el guard de simulación WF-80 a ese único destino. A las 18:27 UTC, el cron venció la oferta anterior, `pg_net`→WF-13 respondió HTTP 200, posición 1 pasó a `VENCIDO`, posición 2 a `NOTIFICADO`, y WF-80 registró un envío simulado. Cero mensajes reales.
- Restauré y publiqué el guard original de WF-80; draft y versión activa son `81740576-968f-448b-9bd6-75d0cec21a3c` y `QA_SIM_PRUEBA_02` ya no está permitido. El cron marcó la segunda oferta `VENCIDO` a las 18:38 UTC; no había otra persona pendiente y no generó callback/envío adicional. Los dos pedidos de la corrida 18:15 siguen `ESPERANDO_PAGO`, sus reservas pasaron a `VENCIDA` y sus QR a `EXPIRADO`; stock reservado liberado.
- El usuario eligió un Error Trigger compartido por correo y señaló `ethannic2@gmail.com`. Zoho Mail/Accounts y n8n quedaron autenticados en Chromium. Creé el borrador n8n `RSUELVO — Alertas de errores` (`hnhQW0AM6ana1vO7`) en el proyecto personal: Error Trigger → sanitizador de contexto mínimo → Send Email. Validación de grafo correcta; el sanitizador limita campos y redacta patrones de tokens/contraseñas. El handler permanece inactivo, sin versión publicada y sin enlazar a los 16 workflows porque no existe credencial SMTP utilizable.
- En Zoho Accounts confirmé región/datacenter United States; IMAP figura no disponible para esta cuenta. La documentación oficial distingue SMTP por plan: `smtp.zoho.com` para usuarios personales/organizaciones gratuitas y `smtppro.zoho.com` para organizaciones pagas con dominio propio, ambos con SSL 465 o TLS 587. La generación de contraseña de aplicación no terminó: el endpoint de Zoho respondió HTTP 400 con código `RA102` y no expuso una contraseña; ninguna clave se copió ni guardó. Falta resolver ese rechazo (posible escalación a Zoho Accounts), crear la credencial `Zoho SMTP - RSuELVO Alertas`, probar entrega a `ethannic2@gmail.com`, publicar el handler y recién entonces vincularlo a los flujos activos.
- Auditoría de fallas n8n del 30-09: 26 ejecuciones `error` guardadas; todas manuales o descendientes integrados con `redaction.production=false`. Se originaron en pruebas sintéticas: aserciones previas que trataban `simulated` como fallo, SKU/tenants inválidos, `Attach Commerce` no ejecutado en el grafo anterior, media ID inválido y acceso `auth` negado al usuario PG restringido. No encontré ejecución `production` entre esos errores. Las versiones activas actuales de WF02/WF04/WF10/WF12/WF13/WF14 ya aceptan solo la forma segura de respuesta simulada (`sendStatus=simulated`, `simulated=true`, `errored=false`); WF80 actualiza `Log Guard` con ID de comercio validado o NULL. El grafo de WF04 ya enruta errores sin usar la rama `Attach Commerce` no ejecutada.

### Revalidación sintética actual — 2026-09-30 19:11 UTC

- Corrí el harness inactivo `QA-IAM10-DIRECT-PG-SMOKE` en su versión `4dbe13be-9065-4975-8d90-4fe0804d5d2a`; n8n devolvió ejecución `569 started`, pero el registro se perdió al consultarlo. Supabase sirve como evidencia persistida: un pedido `ESPERANDO_PAGO`, una reserva `ACTIVA` y un QR `GENERADO` para cada uno de los tenants Prueba RSUELVO y Celulares; una entrada de espera `NOTIFICADO` por tenant.
- La bitácora agrupada mostró ocho `whatsapp_send_simulated` (cuatro por tenant) y dos `whatsapp_simulation_rejected` (tenant no permitido y destino no reservado). En esa ventana no hubo `whatsapp_send` real. Las reservas vencerán a las 19:21:34 y 19:21:36 UTC; aún falta verificar liberación, estado del QR y el comportamiento del siguiente cliente.

- Reconsulta a las 19:22 UTC: ambas reservas pasaron a `VENCIDA` en el ciclo de cron de las 19:22:00. El stock reservado quedó en cero (Prueba RSUELVO: stock 5/reservado 0; Celulares: stock 3/reservado 0) y ambos QR pasaron a `EXPIRADO`. La lista no produjo callback adicional porque en esta corrida solo se creó una entrada notificable por tenant y no quedó otro cliente en cola.
- Revisé autorización del cajero en producción: `fn_confirmar_pago` solo puede ejecutarse por `authenticated`/`service_role` (no `anon`) y usa `fn_puede_verificar(id_comercio)`. Sus helpers consultan `auth.uid()`, membresía activa, comercio coincidente y rol `ROLE_TENANT_ADMIN` o `ROLE_TENANT_CASHIER`; `service_role` conserva el bypass de backend. Esta evidencia confirma el aislamiento tenant del camino de autorización a nivel de función, pero no reemplaza una prueba de extremo a extremo con sesión JWT de cajero.
- Al reanudar Chromium, Zoho Accounts sigue en seguridad/contraseñas de aplicación y Mail en ajustes SMTP de `contacto@rsuelvo.com`; el intento anterior de app-password fue rechazado con `RA102`, y la página muestra el aviso de confirmar identidad. El tab de n8n inicialmente conservaba la página de WF-80, pero abrir `/home/credentials/create` redirigió a `/signin`; MCP confirmó cero credenciales llamadas “Zoho SMTP”. El usuario informó que inició sesión, pero el estado actual aún no la acredita. No publicar/enlazar el handler hasta tener sesión efectiva, guardar SMTP y validar entrega real de la alerta.
- Intenté enviar esta actualización a la sesión OpenCode `RSUELVO: n8n Supabase Flutter`; OpenCode respondió con error interno (`err_29773a73`). Esta nota QA y el cierre directo en el vault quedan como registro de la corrida, commit `624e9d9` ya publicado.
- La web de producción `https://rsuelvo.com/app/login/` está abierta en Chromium y presenta el formulario de acceso; no hay sesión de cajero ahí. Aprobación/idempotencia del comprobante con JWT real sigue pendiente hasta autenticación de una cuenta QA de cajero.
- Sigue pendiente aprobación de pago con JWT de cajero, comprobante/OCR/Storage/provider E2E, durable inbox/outbox, alertas de operación, paridad completa y provisión VPS. Producción NO lista para cutover.

### Gate review, permisos e índices — 2026-09-30 19:47 UTC

- Probé el límite `anon` por PostgREST: `fn_confirmar_pago` respondió HTTP 401/SQLSTATE `42501` (sin ejecutar la función) y los `SELECT` directos a `tbl_pedidos`, `tbl_comprobantes_pago` y `tbl_envios` también fueron rechazados con 401. El ID usado para la prueba de pago era nulo sintético; no se modificaron filas. El RPC público de onboarding `fn_sugerir_codigo('ZZQ')` sí respondió 200 y devolvió cinco códigos con formato válido; es de solo lectura y su exposición corresponde al alta pública.
- Los ocho objetos señalados por el Advisor como RLS sin políticas (siete en `rsuelvo`, uno en `rsuelvo_private`) tienen RLS activo y no conceden SELECT/INSERT a `anon` ni `authenticated`. Se confirma denegación por privilegios, sin depender solo del RLS.
- Encontré que `fn_checks_verificacion_v1(uuid)` permitía ejecución directa a cualquier `authenticated`, sin filtrar `p_id_comercio`; la app usa en cambio `fn_estado_verificacion_comercio`, que valida superadmin/admin del comercio, y sus otros llamadores SQL son funciones `SECURITY DEFINER`. Apliqué `20260930194131_restrict_verification_check_helper`: `anon_exec=false`, `auth_exec=false`, `service_role_exec=true`, `owner_exec=true`; la RPC de estado y la de solicitud de habilitación conservan `authenticated EXECUTE`. El Security Advisor bajó de 50 a 49 funciones `SECURITY DEFINER` accesibles por `authenticated`; siguen en revisión las otras 49.
- `pg_stat_statements` mostraba lecturas de pedidos filtradas por comercio y ordenadas por `created_at` (167 llamadas, 18.3 ms promedio), lecturas de verificaciones (298 llamadas de lista; 40 detalles, 13.5 ms promedio) y carga de detalles de pedido por `id_pedido`. Añadí `idx_pedidos_comercio_created_at`, `idx_pedido_detalles_id_pedido` e `idx_verificaciones_comercio_estado` en `20260930194408_add_hot_path_read_indexes`. El Advisor de FKs bajó de 55 a 53. La base aún tiene menos de 50 filas por tabla en estos paths, así que esto valida patrones y presencia de índices, no rendimiento bajo carga; el Advisor reporta 9 índices no usados ahora, incluidos los tres nuevos, antes de que acumulen tráfico.
- También corregí las seis políticas RLS marcadas `auth_rls_initplan`: `users_select`, `users_update_self` y las cuatro políticas de dispositivos push ahora envuelven `auth.uid()` como `(select auth.uid())`, preservando los predicados. El Advisor ya no reporta `auth_rls_initplan`; migración `20260930194730_initplan_rls_auth_uid`. Inspeccioné las seis expresiones de `pg_policies` posteriores y todas conservan su filtro de identidad.
- Reconcilié de nuevo el ledger: producción 93 versiones; directorio local 42 migraciones; solo 10 versiones coinciden, 83 del ledger faltan localmente y 32 archivos locales no están aplicados en producción. El checkout backend sigue sin commit ni remoto. Las tres migraciones nuevas están copiadas en el workspace local con los nombres/versiones devueltos por Supabase, pero el historial completo y una cadena reproducible siguen sin resolverse.
- Verificación local: backend 345/345 con Python local y 345/345 en el contenedor Python 3.12 tras reconstruir `test`. La imagen vieja omitía siete módulos y dio 337; se reconstruyó y repetí la suite completa. Web: 95 pruebas unitarias y 19 de Playwright pasaron; typecheck terminó sin errores; `npm run build` compiló, con aviso del bundle principal de 1,065.95 kB (319.39 kB gzip). Ninguna de estas pruebas sustituye autenticación real o prueba de carga.
- Continúan sin cierre: confirmación de pago con JWT de cajero y estado cero para denegación entre tenants; E2E actual de comprobante/OCR/Storage; callback positivo de entrega sobre fixture con teléfono QA; durable inbox/outbox; alertas n8n entregadas; ejercicio de carga/concurrencia; reconciliación completa de migraciones; VPS y plan probado de rollback/cutover.

### Revisión de sesión Zoho/n8n y configuración — 2026-09-30 19:53 UTC

- Chromium muestra Zoho Mail autenticado en la cuenta operativa y su página de ajustes SMTP. Zoho Accounts todavía bloquea “Contraseñas de aplicaciones” con una solicitud de confirmar identidad. No se generó ni expuso ninguna contraseña de aplicación.
- n8n sigue redirigiendo a `/signin` y presenta el formulario de acceso. El MCP de n8n falló temporalmente con error interno al consultar credenciales; no pude verificar desde el MCP si hubo cambios en la cuenta. El handler compartido sigue sin publicar/enlazar y no hay prueba de entrega SMTP; las alertas continúan como gate abierto.
- `docker compose config --quiet` terminó correctamente. `compose.yaml` y `.env.example` ya no declaran claves OPENWA; el backend conserva código/configuración opcional heredada, pero la consulta de producción anterior encontró 11 canales activos y todos usan Meta. No se encontraron referencias OPENWA en los archivos de configuración de Compose revisados.

### Alcance Meta-only del backend candidato — 2026-09-30 20:01 UTC

- Reconsulté producción: la base responde y `rsuelvo.tbl_canal_whatsapp` tiene 11 canales `META` activos; `rsuelvo_private.backend_outbox` aún no existe. No apliqué cambios remotos.
- Retiré del backend candidato el adaptador/configuración OpenWA y su camino de despacho. Los futuros SQL de outbox limitan el proveedor a `META`; una migración local posterior `0004_meta_only_whatsapp.sql` conserva inmutable la migración base ya aplicada localmente y acota cuatro constraints de inbox/outbox/attempts. El test de contrato SQL pasó y el ledger local registra 0004.
- Suite backend completa: 340/340 Python 3.14 local y 340/340 Python 3.12 en Docker después de reconstruir la imagen. Ruff lint pasó. El `ruff format --check` de todo el repo sigue señalando dos archivos preexistentes no tocados; los archivos editados están formateados.
- La decisión Meta-only aún no queda cerrada en producción: Chromium sigue mostrando n8n en `/signin` y Zoho Accounts solicita confirmar identidad. El flujo n8n publicado requiere inspección autenticada antes de retirar/confirmar su rama heredada. El backend candidato permanece sin repositorio canónico/remoto y sus colas no están desplegadas.

### Hardening de `SECURITY DEFINER` y estado alertas email — 2026-09-30

- Cerré en producción el vector de escalación por *temporary-table shadowing*: 114 funciones `SECURITY DEFINER` en `public`, `rsuelvo` y `rsuelvo_private` tienen ahora `search_path` fijado explícitamente y `pg_temp` al final. La migración aplicada es `20260930202722_harden_security_definer_search_paths` y su archivo fuente quedó en `supabase/migrations/20260930202722_harden_security_definer_search_paths.sql` del workspace backend; también se aplicó antes `20260930201732_restrict_iniciar_verificacion_execute`.
- Repetí la prueba adversarial con rol `authenticated`, JWT sintético y tablas temporales con las mismas filas de un `ROLE_SUPERADMIN` falso. `rsuelvo.fn_es_superadmin()` devolvió `false`; la transacción se revirtió. La consulta de catálogo confirmó `missing_pg_temp=0`, total `114`. La RPC `public.fn_iniciar_verificacion(uuid,text,boolean)` conserva `EXECUTE` para `service_role`, sin `EXECUTE` para `anon` ni `authenticated`.
- Chromium ya muestra una sesión autenticada de n8n en la pantalla `Credentials`, y sesiones abiertas de Zoho Mail (ajustes SMTP) y Zoho Accounts (contraseñas específicas de aplicación). El dashboard n8n mostraba 41 ejecuciones de producción y 2 fallidas (4.9%) al inspeccionarlo. No pude listar/gestionar credenciales/workflows mediante el MCP: `list_credentials` y `search_workflows` continúan respondiendo `-32603 Internal error`; el CDP local solo sirve para lectura UI dentro de la sesión.
- No se generó contraseña de aplicación ni se guardó credencial SMTP. Zoho Accounts aún exige confirmar la identidad antes de generar la contraseña; Zoho Mail no revela la contraseña guardada. Por eso no hay prueba de entrega de alerta y el workflow compartido de errores no está configurado/verificado. Pendiente para continuar: completar confirmación de identidad en Zoho Accounts, generar contraseña específica de aplicación y guardarla directamente en la credencial SMTP de n8n (sin anotarla en vault ni mostrarla); después probar envío al destinatario de alertas y vincular el workflow compartido dejando los workflows productivos inactivos durante la preparación.
- Se mantiene abierto el gate general de producción: estas correcciones SQL están desplegadas y el exploit quedó cubierto por prueba sintética; permanecen pendientes los E2E positivos autenticados, el correo de alertas y las demás verificaciones listadas en este informe.

### Supabase advisors posteriores al hardening — 2026-09-30

- Tras la migración, el catálogo confirma `114/114` funciones `SECURITY DEFINER` con `pg_catalog` primero y `pg_temp` último, sin configuraciones implícitas.
- Advisor SECURITY se actualizó a las 20:31 UTC. Conserva 49 avisos de `SECURITY DEFINER` ejecutables por `authenticated`: requieren revisión función por función de identidad, rol, tenant y consumidor, y no equivalen automáticamente a una vulnerabilidad. Mantiene 8 tablas con RLS sin políticas; ya se había confirmado que niegan acceso directo por grants y default-deny. `fn_sugerir_codigo(text)` sigue accesible a `anon` deliberadamente: el onboarding público lo consume en `rsuelvo-web/app/src/data/api.ts` y no realiza escrituras. `pg_net` en `public` aparece como warning de extensión pendiente de revisar. Advisor PERFORMANCE reporta políticas permisivas duplicadas; evaluar consolidación sin alterar semántica multirol.

### Prueba de autorización con contexto JWT controlado — 2026-09-30

- Una primera llamada SQL de diagnóstico omitió el JSON `request.jwt.claims`; en ese contexto la herramienta ejecuta como `postgres`, y los helpers de servicio responden como operación privilegiada. Descarté ese resultado y repetí el ensayo con `SET LOCAL ROLE authenticated` y un JWT sintético completo (`sub` sintético, `role=authenticated`).
- Con rol efectivo confirmado `authenticated`, `auth.uid()` devolvió el subject sintético, `fn_es_service_role()` fue `false`, y `fn_puede_verificar`, `fn_es_owner` y `fn_tiene_acceso_sucursal` devolvieron `false` para IDs ajenos/inexistentes.
- Repetí el shadowing adversarial creando tres tablas temporales con un vínculo falso `ROLE_SUPERADMIN`; con el mismo JWT y rol `authenticated`, `fn_es_superadmin()` devolvió `false`. La transacción terminó en rollback y no modificó tablas persistentes.

### Proveedor correcto para alertas automáticas — 2026-09-30

- Confirmé la política oficial vigente de Zoho Mail: prohíbe correo automatizado y transaccional, incluso OTP/activación. Por ello NO usar contraseña de aplicación de `contacto@rsuelvo.com` ni SMTP Zoho Mail para alertas n8n o Auth. La política recomienda Zoho CPaaS (ZeptoMail): [Zoho Mail Usage Policy](https://www.zoho.com/mail/help/usage-policy.html).
- El portal `cpaas.zoho.com` sí está autenticado en Chromium y presenta onboarding sin organización: solicita nombre de organización y aceptación de sus términos. No envié el formulario, acepté términos ni contraté plan. Para configurar producción falta que el titular complete esa aceptación/onboarding y verifique un remitente propio (preferentemente `noreply@rsuelvo.com`) en la consola CPaaS.
- Tras habilitar el agente SMTP de CPaaS, guardar su usuario/token únicamente en credenciales de n8n/Supabase, nunca en el vault. Zoho CPaaS documenta `smtp.zeptomail.com`, puerto 465/SSL o 587/TLS, usuario `emailapikey` (o la dirección From permitida) y contraseña del agente: [SMTP Zoho CPaaS](https://help.zoho.com/portal/en/kb/zoho-cpaas/faqs/sending-emails/articles/how-to-configure-smtp). Para Auth, Supabase recomienda SMTP personalizado en producción y también lista ZeptoMail: [Supabase Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).
- n8n ya muestra sesión iniciada y vista Credentials, pero sus herramientas MCP siguen devolviendo `-32603 Internal error`. Aún no existe/confirmé SMTP CPaaS, ni envié prueba al destino autorizado `ethannic2@gmail.com`; tampoco configuré ni asocié el handler de error.

### Revalidación de políticas RLS y estado de sesión n8n — 2026-09-30

- Las ocho tablas que el Advisor marca con RLS sin políticas niegan actualmente `SELECT` e `INSERT` directos a `anon` y `authenticated`; permanecen aisladas por falta de grants además del default-deny de RLS.
- Chromium alcanzó a mostrar el dashboard n8n y el workflow `RSUELVO — Alertas de errores`, pero al consultar su recurso de workflow, n8n respondió con `sessionExpired=true` y redirigió a `/signin`. Por lo tanto, el listado visible y la indicación de estado del editor no se aceptan como prueba de que la versión actual del handler esté publicada, activa o enlazada. El usuario había iniciado sesión; el servidor volvió a expirar/rechazar esa sesión antes de poder verificar el workflow por API. MCP sigue devolviendo `-32603`.
- El portal Zoho CPaaS sí muestra la identidad iniciada y presenta el onboarding de organización con aceptación de términos; quedó sin aceptar/crear y sin comprar un plan. No usar Zoho Mail SMTP automatizado.

### Gate de build/test de app completo — 2026-09-30

- Backend candidate (`scripts/test_local.sh`): 340/340 pasando en Python 3.14 + Postgres/Redis local. El servicio de test Docker volvió a pasar 340/340 con Python 3.12. Solo quedó un warning conocido de deprecación Starlette/httpx.
- Web candidate: 95/95 unitarias, 19/19 Playwright sobre preview local, `npm run typecheck` pasó landing y app, y `npm run build` compiló ambos workspaces. Vite advierte que el bundle principal de la app pesa 1,065.95 kB sin comprimir (319.39 kB gzip); seguimiento de optimización de carga aún pendiente.
- Flutter: 381/381 pruebas pasaron con Flutter 3.47.0; `flutter analyze` terminó sin observaciones.
- Estos resultados verifican código local/candidato y no sustituyen pruebas de producción contra JWT real, Meta/WhatsApp, SMTP, ni un despliegue canary.

### Recuento actual de migraciones — 2026-09-30

- Recalculé contra el ledger de producción: Supabase lista 95 versiones; el directorio local `supabase/migrations` contiene 44. Coinciden exactamente 12 versiones; 83 de producción no están representadas localmente y 32 archivos locales no existen con esa versión en el ledger de producción. Parte de los 32 corresponde a colas/outbox backend todavía no desplegadas; otros nombres/fechas divergentes requieren reconciliación semántica.
- Sigue prohibido ejecutar `supabase db push` desde este checkout hasta reconstruir/reconciliar una historia aplicable. Las migraciones desplegadas manualmente por MCP sí están espejadas con las dos versiones exactas `20260930201732` y `20260930202722`.

### Estado actual de Zoho CPaaS y control de secretos — 2026-09-30

- Zoho CPaaS ya tiene creada la organización RSUELVO. La consola muestra `rsuelvo.com` verificado y los registros DKIM + CNAME de rebotes como verificados; todavía no añadí `noreply@rsuelvo.com` al allowlist ni generé credencial SMTP. El único Agent visible (`agent_1`) está cerrado.
- La consola exige la “Validación del cliente” (KYC) para habilitar la funcionalidad completa; el flujo indica hasta 2 días laborables de revisión y correo de prueba solamente mientras se aprueba. Abrí el formulario y comprobé que comienza preguntando “Organization website” (1 de 4). No ingresé ni envié información legal, no acepté un plan pagado y no toqué DNS; el formulario queda en manos del titular.
- Un escaneo heurístico de archivos actuales e historial disponible en vault/web/Flutter/backend no encontró JWT privilegiados, claves privadas PEM ni patrones de tokens de proveedor en Git. El único JWT encontrado en el source móvil tiene `role=anon` y `iss=supabase` (clave pública de cliente; no service role). En backend, `.env` está ignorado y no rastreado por Git; sus conexiones DB apuntan a localhost/staging y la clave nombrada STAGING decodifica con `role=service_role`. No imprimí ningún valor. Esto es una comprobación heurística, no una certificación con escáner especializado.
- El tab de n8n permanece redirigido a `/signin?sessionExpired=true`, y el MCP sigue con `-32603`; el handler compartido no puede certificarse publicado, enlazado ni capaz de entregar correo. El checkout candidate actualizó el gate de corte con los recuentos de migración actuales (95 prod / 44 local / 12 coincidentes).

### Limpieza de estado QA tras canaries — verificado 2026-09-30

- Consulté producción en solo lectura después de los canaries previos. Para los tenants Prueba RSUELVO (`FER`) y Celulares (`FEE`), hay `0` reservas `ACTIVA`/`PAGO_VALIDANDO` y `stock_reservado=0` en ambos. Esto confirma que no quedó inventario retenido por las pruebas; no cambié pedidos ni reservas históricas.

### Protección de la extracción local de esquema — 2026-09-30

- Revisé `/home/nico/rsuelvo-schema-extraction`: no es un repositorio Git y no tiene remotes; `.pgpass`, escaneo/mapas y snapshot SQL eran archivos locales con permisos `0600` y no rastreados. El `.env` también era no rastreado y su directorio privado, pero tenía modo `0644`; lo ajusté a `0600`. Amplié el `.gitignore` del directorio para `.pgpass` y los artefactos de escaneo/snapshot, por defensa ante una futura inicialización Git. No imprimí ni copié credenciales.

### Inspección SMTP de Zoho CPaaS — 2026-09-30

- El panel de configuración de `agent_1` muestra los valores públicos de conexión SMTP: host `smtp.zeptomail.com`, TLS/SSL por puerto 587/465 y usuario `emailapikey`. Existe una contraseña SMTP previamente generada, pero el panel la muestra enmascarada; también muestra una API key enmascarada. No revelé, regeneré ni copié ninguna de ellas.
- El agente todavía figura cerrado y el banner KYC sigue en “Completar”. La credencial del proveedor no equivale a una credencial SMTP guardada en n8n: el n8n de producción continúa en `/signin?sessionExpired=true`, su MCP devuelve `-32603`, y no hay prueba de conexión/entrega. Próximo paso de titular: terminar KYC y reautenticar n8n; después verificar estado/alcance del agente, crear o rotar credencial si procede, y guardarla en n8n sin registrarla en archivos ni chats.

### Alerta compartida: estado tras reautenticación reportada — 2026-09-30 21:02 UTC

- El usuario informó que ya inició sesión en n8n. La integración MCP de n8n ahora responde: `list_credentials` devolvió 7 credenciales y ninguna es SMTP; `search_workflows` y `get_workflow_details` funcionan.
- El handler `RSUELVO — Alertas de errores` (`hnhQW0AM6ana1vO7`) tiene 3 nodos conectados (`Error Trigger` → `Sanitize alert context` → `Send production error alert`) y el correo destino `ethannic2@gmail.com`. Sigue `active=false`, `activeVersionId=null`, `triggerCount=0`; el nodo de email no tiene credencial asignada. No se publicó ni enlazó a los workflows productivos y no se envió correo.
- En la pestaña Chromium de depuración disponible, recargar n8n aún termina en `/signin?...&sessionExpired=true` y cuerpo vacío. Esto puede ser otra sesión/perfil que la que el usuario acaba de autenticar; el MCP sí quedó operativo y no se usaron cookies ni credenciales del usuario. Hace falta completar la credencial SMTP dentro de n8n y confirmar el acceso UI si se requiere gestionarla allí.
- CPaaS ofrece SMTP `smtp.zeptomail.com`, puerto 587 TLS o 465 SSL y usuario `emailapikey`; secreto/API key enmascarados. El agente continúa cerrado y KYC en “Completar”; no copiar/rotar secretos hasta tener claro estado de habilitación.
- Siguiente secuencia: habilitación del agente/KYC CPaaS por el titular; guardar credencial SMTP en n8n sin incluir secreto en vault; prueba de envío a `ethannic2@gmail.com`; publicar handler; asignar `settings.errorWorkflow` a los workflows previstos; provocar un fallo sintético controlado y confirmar recepción. Mantener workflows de negocio sin cambios durante la configuración.

### Auditoría actual de notificaciones y avance del handler — 2026-09-30 21:10 UTC

- El MCP de n8n permitió auditar 16 workflows de negocio activos. Los 16 tienen `settings.errorWorkflow` sin configurar; el handler común aún no tiene versión publicada, por lo que no hay alertas centrales enlazadas.
- Revisé las ramas de error declaradas por nodo: todos los `continueErrorOutput` encontrados en WF-02, WF-04, WF-10, WF-14, WF-20, WF-21 y WF-80 tienen una salida de error conectada a un nodo de manejo/respuesta; no cambié su comportamiento. Hay `retryOnFail` solo en WF-21 `Start Verification`, WF-22 `HTTP Request` y WF-80 `Send via Meta Graph API`. No se añadieron reintentos globales: RPCs y mutaciones requieren evaluar idempotencia por operación.
- Ajusté el borrador `hnhQW0AM6ana1vO7`: remitente `fromEmail` ahora `noreply@rsuelvo.com`, que es la dirección registrada en CPaaS; destinatario sigue `ethannic2@gmail.com`. Mejoré `Sanitize alert context` para redactar Bearer, JWT, claves/tokens/contraseñas/cookies y parámetros sensibles de URL; también elimina emails y teléfonos del texto del error.
- `validate_node_config` aceptó el nodo Code v2 y casos sintéticos locales comprobaron JWT, credenciales, Bearer, email/teléfono y error normal. n8n aceptó la actualización con `validationWarnings=[]`. El handler continúa `active=false`, `activeVersionId=null`; `Send production error alert` sigue sin credencial SMTP. No se ejecutó el flujo ni se envió correo.
- Chromium CPaaS muestra `agent_1` cerrado y el aviso “Su cuenta se revisará en breve”; por tanto está bajo revisión y no habilitado para envíos. Las credenciales siguen enmascaradas. Chromium n8n accesible continúa en `sessionExpired`; MCP sí sirve para inspección/edición del draft, pero sus herramientas disponibles no crean credenciales.
- **Pendiente operativo:** esperar habilitación de CPaaS y guardar SMTP como credencial de n8n. Después validar entrega desde el remitente permitido, publicar el handler, enlazar los 16 workflows activos con `settings.errorWorkflow` y confirmar recepción de un fallo sintético de producción controlado. No declarar listas las alertas hasta completar esa evidencia.


### Reconciliación y estado comprobado — 2026-09-30 21:37 UTC

- Chromium CDP está autenticado en el editor del workflow `hnhQW0AM6ana1vO7` y el MCP de n8n responde. La sesión permite inspeccionar el editor/credenciales. n8n tiene 7 credenciales, ninguna SMTP. El handler conserva 3 nodos, no está publicado (`activeVersionId=null`) ni activo. No se envió alerta desde n8n.
- Volví a consultar los 16 workflows productivos activos: los 16 siguen sin `settings.errorWorkflow`. Por tanto no publiqué ni conecté un manejador sin credencial de entrega verificada.
- El tab de CPaaS autenticado indica `agent_1` cerrado. Host SMTP `smtp.zeptomail.com`, TLS 587/SSL 465 y usuario `emailapikey`; contraseña y API key enmascaradas. No regeneré la contraseña porque el mismo agente se usa para SMTP de Supabase y rotarla puede interrumpir su entrega actual.
- La nota de correo registra una prueba SMTP separada mediante Supabase Auth: invitación QA entregada a `ethannic2+qa20260930smtp@gmail.com`, enlace confirmado y usuario pudo iniciar sesión. Esto verifica ese recorrido de onboarding; no valida el SMTP de n8n ni la recepción de alertas. El CPaaS continúa mostrando el agente cerrado/revisión.
- **Bloqueo preciso:** para terminar alertas n8n hace falta provisionar o recuperar una credencial SMTP válida sin interrumpir Supabase. Después se puede guardar en Credentials, enviar correo de prueba, publicar el handler, enlazar los 16 workflows y confirmar un evento sintético.

### Hardening MFA en Supabase producción — 2026-09-30

- Apliqué la migración `20260930213037_harden_email_mfa_search_path` después de que el usuario autorizara cambios en producción. Fija `search_path = pg_catalog, pg_temp` en cinco funciones `SECURITY DEFINER` del módulo email MFA. La verificación posterior encontró 119 funciones `SECURITY DEFINER` en los esquemas API `public`, `rsuelvo` y `rsuelvo_private`; las 119 empiezan con `pg_catalog` y terminan con `pg_temp` (cero excepciones).
- El Advisor aún señala dos tablas RLS sin políticas en `rsuelvo_private`; inspección de ACL confirma que `anon`, `authenticated` y `service_role` no tienen SELECT. Se mantienen inaccesibles por grants; no añadí permisos ni políticas. `pg_net` sigue en `public`; moverlo requiere revisar los callbacks/cron que dependen de su schema.
- `fn_sugerir_codigo(text)` sigue ejecutable por `anon` y `authenticated`; el cuerpo solo normaliza una base y devuelve sugerencias disponibles, sin datos de clientes. Mantenerlo público es necesario para sugerencias durante alta anónima, sujeto a validación de producto y rate limiting. Advisor también lista 52 funciones `SECURITY DEFINER` ejecutables por authenticated; requieren revisión de contrato/identidad por función, no revocación masiva.
- Ledger Supabase: 97 versiones remotas; directorio candidato contiene 47 SQL; 13 versiones coinciden exactamente por nombre/versión (84 remotas sin archivo local y 34 archivos locales fuera del ledger). `db push` sigue bloqueado hasta reconciliar historia y comprobar replay.


### Plantillas de correo Auth en español — 2026-09-30 21:45 UTC

En el dashboard Auth de producción se guardaron las plantillas **Invite user** y **Confirm sign up** en español. Se comprobó persistencia recargando ambas rutas. Se conservaron `{{ .ConfirmationURL }}` y enlaces de acción. No se mandó un mensaje nuevo tras el cambio, así que falta validar visualmente el correo renderizado/entregado con el texto nuevo.


### Reconciliación posterior — 2026-09-30 21:48 UTC

- Se actualizó en producción la plantilla Auth `Invite user` y `Confirm sign up` al español; ambas persistieron al recargar. Aún falta recibir una nueva invitación/confirmación renderizada después del cambio.
- Apareció la bitácora [[QA-MFA-Correo-2026-09-30]]: documenta implementación de step-up MFA por correo para roles administrativos, envío/validación real con cuenta QA, replay rechazado, revocación de sesión y controles. El E2E con inicio de sesión real de SuperAdmin queda pendiente del titular en web/móvil. Las plantillas actuales están en español.
- Conteo actualizado contra producción: ledger remoto 99; local 48; 13 coincidencias exactas por versión, 86 versiones remotas no presentes con ese timestamp en local y 35 archivos locales fuera del ledger. Cuatro archivos locales recientes guardan timestamps distintos a los nombres de entrada remotos (`email_second_factor`, `enforce_email_mfa_rpc_and_storage`, `email_mfa_catalog_guard`); no ejecutar `db push` ni reparar ledger automáticamente.
- Confirmé de nuevo 119 funciones SECURITY DEFINER de `public`, `rsuelvo`, `rsuelvo_private`; las 119 tienen `search_path` empezando por `pg_catalog` y terminando en `pg_temp`. La migración 30213928 y 30214210 están al final del ledger de producción y acompañan el despliegue MFA ya descrito.


### Advisor Auth: contraseña filtrada — 2026-09-30 21:50 UTC

El Advisor de seguridad en producción incluye `auth_leaked_password_protection`. En el dashboard, la organización/proyecto figura FREE y el ajuste Prevent use of leaked passwords aparece DISABLED sin control editable. La documentación oficial de Supabase indica que este control requiere Pro o superior: https://supabase.com/docs/guides/auth/password-security. No cambié el plan ni se generó un gasto. Registrar la habilitación tras decidir el plan de lanzamiento.


### Harness sintético 19:22 UTC + `fn_confirmar_pago` + SMTP bloqueado — 2026-09-30

- El harness sintético QA-IAM10 creó una orden/reserva/QR por tenant (Prueba RSUELVO y Celulares); envíos WhatsApp solo simulados: ocho `whatsapp_send_simulated`, cero `whatsapp_send` real. El cron venció ambas reservas, liberó stock reservado (ambos en 0) y cambió ambos QR a EXPIRADO. Sin siguiente cliente en lista para callback. Workflows de prueba conservados inactivos; sin cambios de producción.
- Revisión `fn_confirmar_pago` y helpers: `authenticated` solo confirma si `auth.uid()` tiene membresía activa del mismo comercio con rol admin o cashier; `anon` sin EXECUTE; `service_role` para backend.
- SMTP de alertas bloqueado: app-password Zoho falló con RA102; handler n8n `hnhQW0AM6ana1vO7` inactivo/no publicado/no enlazado. Pendiente: credencial SMTP válida sin romper SMTP Supabase/Edge, publicar handler, enlazar 16 activos y confirmar evento sintético.


### Python/VPS candidato — verificación local — 2026-09-30 21:58 UTC

- Checkout candidato `BACKEND RSUELVO`: suite completa existente pasó **340/340** en Python 3.14 con `scripts/test_local.sh` y **340/340** en Docker Python 3.12. `ruff check .`, `ruff format --check .` (112 archivos), y `docker compose config -q` pasan. El formato de dos pruebas antiguas se corrigió antes de la segunda corrida Docker.
- API levantada solo en Docker local con las funciones de ingreso/envío deshabilitadas por default; `/health/live` y `/health/ready` contestaron 200 y el healthcheck llegó a healthy. El API se detuvo al terminar la verificación. `.env` está 0600 y el script apunta solo a `127.0.0.1:54329`; sin llamada a staging/producción ni envío de proveedor.
- Una advertencia queda en ambas suites: Starlette depreca `fastapi.testclient` basado en `httpx`. Es del cliente de test, no del servidor de producción.
- Esto no cierra paridad ni cutover: faltan RPC/Auth JWT real, Meta/OCR/Storage, migraciones reconciliadas y VPS. Los workers permanecen apagados; esta suite sintética no prueba flujos reales de WhatsApp ni proveedores.


### Refresh autenticado de WF80 / versión Meta — 2026-09-30 22:05 UTC

- El MCP autenticado devolvió WF80 (`7V6MIPuGbdx9s0lT`) activo con `activeVersionId=81740576-968f-448b-9bd6-75d0cec21a3c`. Su único nodo HTTP de envío llama a `https://graph.facebook.com/v26.0/{phone_number_id}/messages`; no hay nodo OpenWA en el grafo activo. Esta lectura actualiza los datos históricos v21.0/OpenWA del corte 2026-09-25. No modifiqué n8n ni envié mensajes.
- El backend Python candidato quedó alineado a Meta-only/v26.0 en configuración, Compose, fixtures y paridad. Suite local Python 3.14: 340/340; suite Docker Python 3.12: 340/340; Ruff lint/formato y `docker compose config -q` pasan. Mocks sintéticos; ningún llamado a Meta.
- Meta publica Graph v26.0 desde 2026-07-29 con expiración TBD; su tabla marca v21.0 hasta 2027-01-21. El proyecto queda en versión activa v26.0. [Meta Graph API versions](https://developers.facebook.com/docs/graph-api/changelog/versions/).


### Incidente SMTP 2026-09-30 — contraseña expuesta, nada publicado (solo vault)

- Codex confirmó Chromium n8n autenticado (URL del workflow del handler) y MCP oficial `mcp__n8n` operativo; `codex_apps/n8n` falla -32603. Handler revisado: borrador 3 nodos, inactivo, no publicado, sin `errorWorkflow` asignado en los 16 workflows activos.
- Error operativo: la contraseña SMTP apareció accidentalmente en una salida interna de diagnóstico — tratarla como comprometida; nunca reescribirla ni incluirla en Git/vault (esta nota no contiene ningún valor secreto).
- Contraseña secundaria más corta generada en Zoho CPaaS pero NO copiada/instalada/probada; `agent_1` sigue cerrado.
- n8n muestra una credencial nueva guardada pero SIN validar: no conectarla ni publicar nada todavía. El form indica puerto 465 con SSL/TLS apagado → la config aún requiere corrección a 587+STARTTLS o 465+SSL.
- Supabase Auth conserva SMTP `smtp.zeptomail.com`, `noreply@rsuelvo.com`, usuario `emailapikey`, puerto 587 (secreto no visible en UI). Una Edge Function en versión 3 (nombre no precisado en el reporte) lee secreto; UI Secrets de Edge Functions muestra `PUSH_WEBHOOK_SECRET` como personalizado visible; confirmado 2026-09-30 que `RSUELVO_SMTP_PASSWORD` SÍ existe en Edge Function Secrets (solo el nombre registrado; el valor jamás se copió).
- Siguiente: rotar con credencial fuerte y coordinar Auth, email-mfa, n8n; verificar entrega. Nada publicado ni conectado.
- Corrección post-commit: la credencial SMTP genérica quedó guardada con host `smtp.zeptomail.com` y puerto 587; la pestaña Connection muestra tested successfully (solo conectividad/auth SMTP, no envío/entrega). Sigue usando la contraseña anterior expuesta: no se cambió ni se pegó la secundaria. Aparece como `SMTP account` en el MCP, sin asignar al nodo; handler inactivo, sin publicar ni conectar. Rotar antes de cualquier uso.


### Continuación de QA n8n — 2026-09-30 22:30 UTC

- Revisión de ejecuciones fallidas desde el 29/09: 34 registros, 32 `manual`/`integrated` sintéticos y 2 `webhook`. Los dos webhooks son antiguos: #110 de lista de espera (gateway respondió `sendStatus=sent`, `errored=false`; luego falló `Assert Delivery Result 1` con `Invalid output format`) y #86 de solicitud de entrega (`Lookup Pedido` recibió URL `undefined`). El nodo Lookup Pedido de la versión activa actual ya construye el host de Supabase correcto; no hay éxito posterior para confirmarlo. La versión activa de WF13 también es posterior al #110, por lo que falta repetir el caso con un destinatario QA que no contacte a clientes reales.
- En #110 los datos históricos de ejecución incluían dos secretos de callback: un bearer HTTP y un token legado en el body. Ambos se tratan como comprometidos; ningún valor se conserva en esta nota. Corresponden a la credencial n8n `RSUELVO n8n Waitlist Callback` / entrada Vault `rsuelvo_n8n_waitlist_callback_token` y a `rsuelvo_n8n_legacy_waitlist_body_token`. No rotados: coordinar el cambio de los valores Vault y de la credencial n8n/consumidores para evitar que el cron quede con credenciales desparejadas.
- Los errores `Invalid output format` #125-127 y validaciones de `simulated` #317-360 son anteriores a actualizaciones de los flujos afectados del 30/09. Los nodos actuales reconstruyen los items tras subworkflow y permiten una simulación marcada como segura, pero no se ejecutó una repetición completa posterior al cambio; no marcarlos como resueltos sin esa comprobación.
- Error #471 pertenece al workflow inactivo `QA-IAM10-DIRECT-PG-SMOKE`: su assertion `Assert Waitlist Acceptance` exige que la salida final de WF14 incluya datos de pedido y cobro, pero WF14 termina propagando el resultado simulado del gateway WF80. Es un desacuerdo entre contrato del harness y salida final del flujo, no evidencia de rechazo de WF14. Corregir el harness para comprobar el registro de pedido/cobro con consultas read-only separadas de la rama de envío; no repetirlo antes de revisar/limpiar cualquier registro sintético que haya dejado.
- Errores #219-224 de `Log Guard` ocurrieron en ejecuciones integradas de prueba. La FK verificada apunta a `rsuelvo.tbl_comercios(id_comercio) ON DELETE SET NULL`; la causa concreta aún no está aislada. No se modificó la escritura de auditoría.
- El canal SMTP aún está pendiente de rotación segura y entrega real; handler sin publicar/sin enlaces y workflows activos no alterados por esta sesión.


### Rotación callback waitlist verificada — 2026-09-30 23:35 UTC

- Roté los dos valores expuestos: `rsuelvo_n8n_waitlist_callback_token` y `rsuelvo_n8n_legacy_waitlist_body_token`. La comparación SHA-256 en SQL confirmó igualdad con los valores nuevos sin devolverlos. La función `fn_cron_expirar_y_notificar` lee ambos valores de Vault en runtime y ya no conserva el token legado inline.
- Actualicé la credencial n8n `RSUELVO n8n Waitlist Callback`; el valor de Header Auth debe incluir el prefijo literal `Bearer ` porque la cabecera entrante lo envía así. El primer intento sin ese prefijo obtuvo 403; guardé el valor con el formato exacto y el POST controlado al webhook devolvió 200 `Workflow was started`.
- Antes de disparar el webhook confirmé cero grupos en espera y cero inventario con destinatarios elegibles; no se enviaron WhatsApps. El MCP no mostró la ejecución de prueba en su búsqueda posterior, por lo que el HTTP 200 confirma aceptación/autenticación, pero falta revisar el registro de ejecución en la UI n8n.
- Pausé el job `rsuelvo_expirar_reservas` solo durante la rotación y lo reactivé con su cron `* * * * *`. Verificación posterior: `active=true`; 20/20 ejecuciones recientes de pg_cron aparecen `succeeded`, última a las 23:34 UTC.
- La rotación de callback está cerrada a nivel Vault + credencial. La SMTP es independiente y continúa pendiente.


### Rotación SMTP Zoho coordinada — 2026-09-30 23:56 UTC

- Se generó una nueva Send Mail API key adicional en CPaaS sin revocar la anterior. No persistir el secreto en archivos ni chats.
- n8n SMTP actualizada y conexión autenticada con éxito (prueba de conexión, no entrega). Supabase Auth SMTP actualizada; SMTP personalizado continúa habilitado. `RSUELVO_SMTP_PASSWORD` reemplazado en Edge Secrets; digest distinto y confirmación de guardado visibles.
- Falta enviar y recibir un correo real posterior a la rotación. No revocar aún la API key anterior ni publicar/enlazar el Error Trigger compartido. `RSUELVO — Alertas de errores` permanece sin publicar, sin asignar; los 16 flujos activos siguen sin errorWorkflow.
- MCP n8n devolvió error interno al consultar búsqueda/credenciales. La sesión Chromium sí permitió guardar la rotación. Reintentar verificación MCP/UI, correo real y luego continuar activación controlada.


### Reanudación de alertas — sesión n8n no autenticada — 2026-10-01 00:02 UTC

- Tras completar la rotación SMTP coordinada, la pestaña Chromium de n8n redirigió a `/signin`. El formulario aparece sin usuario ni contraseña guardados; al enfocar y pulsar “Sign in” con campos vacíos no se autenticó. Las llamadas REST responden 401 y el MCP n8n devuelve `Internal error` en búsqueda y lista de credenciales.
- La credencial SMTP nueva sí fue guardada antes de expirar la sesión y pasó “Connection tested successfully”. Auth SMTP y Edge secret también quedaron actualizados. No se ha probado todavía un correo real con la clave nueva.
- Por seguridad operativa, el workflow `RSUELVO — Alertas de errores` permanece sin publicar y los 16 flujos no se enlazaron. La clave CPaaS anterior sigue activa hasta entregar y verificar un correo con la nueva.
- Se intentó informar al orquestador OpenCode en la sesión previa desde el backend, pero el servidor respondió `Unexpected server error` (ref `err_b6e1a047`). El detalle está versionado en el vault, commit `ee70e3f`; repetir aviso al orquestador cuando su sesión responda.


### Envío SMTP y activación del Error Trigger compartido — 2026-10-01 00:20 UTC

- Prueba SMTP real, desde un endpoint QA temporal publicado solo para una llamada, ejecutada por `pg_net` en Supabase producción. `net._http_response` request 203 devolvió HTTP 200; Zoho SMTP informó `accepted=[ethannic2@gmail.com]`, `rejected=[]`, respuesta `250 Message received`, `messageId` emitido y sin timeout. Esto prueba aceptación por el servidor SMTP del correo de prueba; no acredita apertura/visualización en Gmail. El endpoint QA se despublicó inmediatamente.
- Publicado `RSUELVO — Alertas de errores` con su nodo SMTP conectado a `SMTP account`, sanitización del error y remitente `noreply@rsuelvo.com`. Descripción actual indica el destinatario autorizado.
- Falla sintética de producción ejecutada desde webhook temporal con `errorWorkflow` apuntando al handler publicado. Ejecución n8n #596 registra el error intencional esperado; respuesta webhook HTTP 500, sin timeout. El workflow de prueba se despublicó inmediatamente. La búsqueda MCP no mostró una ejecución separada del handler ni permite confirmar desde aquí que el correo de alerta apareció en Gmail; confirmar recepción con el titular.
- Enlazados y publicados los 16 workflows de negocio activos con `settings.errorWorkflow = hnhQW0AM6ana1vO7`. Verificación posterior: 16/16 activos, todos con enlace al handler y `versionId == activeVersionId`. Handler también activo. QA SMTP manual y ambos endpoints temporales están despublicados.
- Queda pendiente confirmar que el titular recibió el mensaje de prueba y el mensaje de alerta, verificar entrega SMTP de `email-mfa`/Auth tras rotación y revocar la clave API SMTP Zoho anterior solo después de validar todos los consumidores.
- El cron Supabase `rsuelvo_expirar_reservas` sigue activo cada minuto; SQL en producción mostró `active=true`.


### Verificación con Stop And Error oficial — 2026-10-01 00:30 UTC

- Repetí el disparo con el nodo oficial n8n `Stop And Error`, recomendado para provocar una falla que active el Error Workflow. El webhook de QA respondió HTTP 500 y la ejecución #598 terminó `error`; el error registrado tiene `shouldReport=true`. La QA estaba publicada con `settings.errorWorkflow=hnhQW0AM6ana1vO7` y el handler central estaba activo.
- Aun así, la búsqueda de ejecuciones no muestra una ejecución del handler `hnhQW0AM6ana1vO7`. El SMTP directo ya tuvo aceptación 250, pero el envío de alerta desde Error Trigger no está confirmado. Ambos workflows de falla QA y los endpoints aleatorios quedaron despublicados; no repetir la falla hasta resolver por qué n8n no registra/arranca el Error Workflow o confirmar en el buzón.

### Reprueba publicada de Error Trigger — 2026-10-01 00:47 UTC

- La sesión n8n ya respondió por MCP. Al revisar el QA anterior vi que, pese a su ajuste `errorWorkflow`, estaba sin versión publicada (`active=false`, `activeVersionId=null`); por eso #598 no probaba una versión de producción publicada.
- Publiqué temporalmente `QA Stop and Error Alert Test` y confirmé `active=true`, versión `4a29744b-e1a4-4435-a8c0-a60d995a3e8f`, `settings.errorWorkflow=hnhQW0AM6ana1vO7`; el handler también estaba publicado y activo. Disparé una sola falla controlada: ejecución #600, modo `webhook`, estado `error`, `shouldReport=true`.
- La búsqueda de ejecuciones del handler sigue sin mostrar hijo/ejecución de alerta, incluso después de esa prueba publicada. Despubliqué la QA temporal al terminar (`active=false`, `activeVersionId=null`). La causa de que el Error Trigger compartido no arranque sigue abierta; no afirmar que los emails de fallo funcionan hasta ver la ejecución del handler o confirmar el mensaje en el buzón.
- Revalidé por MCP los workflows productivos: 16/16 flujos de negocio siguen activos, publicados y apuntan a `hnhQW0AM6ana1vO7`; el propio handler está activo/publicado. El canal SMTP directo tuvo aceptación Zoho `250` en la prueba #203, pero no sustituye esta prueba de Error Trigger.
- Pendiente: revisar el log/ejecución desde la UI de n8n y el inbox `ethannic2@gmail.com`, diagnosticar el disparo del Error Trigger con la evidencia de #600, validar entrega Auth/email-mfa tras la rotación y solo entonces retirar la clave CPaaS anterior. Los 21 pedidos QA expirados continúan como datos de auditoría; no se editaron.

### Disparo real con pg_net — 2026-10-01 00:52 UTC

- Publiqué nuevamente la QA `QA Stop and Error Alert Test` solo para un disparo HTTP real desde Supabase producción, no desde el ejecutor MCP. Antes de disparar confirmé `active=true`, versión activa `4a29744b-e1a4-4435-a8c0-a60d995a3e8f` y `settings.errorWorkflow=hnhQW0AM6ana1vO7`.
- `pg_net` request 206 al webhook QA recibió HTTP 500 (`Error in workflow`), esperado por `Stop And Error`. n8n registró ejecución #602, modo `webhook`, estado `error`, `shouldReport=true`. La búsqueda no encuentra ejecución del handler. Esto reproduce el fallo por el camino automático real y confirma que la alerta sigue sin funcionar/verificarse pese a las versiones publicadas.
- Despubliqué de inmediato la QA (`active=false`, `activeVersionId=null`). El handler sigue activo; los 16 workflows productivos siguen activos/publicados y enlazados a él. Próximo paso: revisar el log/ejecución en la UI autenticada de n8n para hallar rechazo de encolado/subworkflow; no hacer más fallas sintéticas hasta ese diagnóstico. Sin cambios a órdenes, pagos, reservas ni inventario.

### Lectura de errores recientes del historial n8n — 2026-10-01

- Revisé las últimas 43 ejecuciones `error` visibles en n8n. Los nuevos fallos #315–#360 vienen de la QA multi-tenant: `WF-80` devuelve `sendStatus=simulated`, y varios nodos de aserción elevan `WF-80 did not confirm delivery: simulated`; esos errores no significan que Meta haya rechazado mensajes reales ni deben contarse como entregas fallidas. `shouldReport=false` en algunas de esas excepciones de código.
- El #315 sí reveló un defecto real en el camino de error de WF-04: `Build Error Notice 1` referenciaba el nodo antiguo `Attach Commerce`, que no existía tras renombrarlo. La versión actual publicada `87aace46-0d14-46ea-a1ce-45520d55c43f` ya referencia `Attach Comercio Universal` en los campos de tenant/teléfono/proveedor. Revisé además que el flujo actual sigue activo y `versionId == activeVersionId`. No repetí el E2E porque ese harness inserta pedidos/reservas en producción; la corrección queda pendiente de una comprobación aislada sin nuevas escrituras.
- La falla real de QA #602 (webhook externo vía Supabase `pg_net`, `shouldReport=true`) sigue sin una ejecución asociada del handler; la QA fue retirada. Ese es el gate principal de alertas centralizadas.

### Corrección del contexto del correo de error — 2026-10-01 01:00 UTC

- La documentación oficial de n8n define `execution.error`, `execution.lastNodeExecuted` y, para fallos de activación, `trigger.error`/`trigger.node`. El sanitizador del handler leía `source.error` y `source.lastNodeExecuted` solamente; por tanto, aun si se ejecutaba, el correo mostraría `No disponible` para el detalle y último nodo.
- Corregí `Sanitize alert context` para leer ambas formas del payload (ejecución y activación), conservando la redacción de secretos, email/teléfonos y límites de longitud. Validación de configuración Code v2 pasó. Publiqué el cambio: handler `hnhQW0AM6ana1vO7`, activa/publicada con `versionId == activeVersionId == c8dba68d-f12c-4cb5-9240-fa3ebcb43bd5`; la credencial SMTP sigue asignada.
- La ruta de Error Trigger continúa sin verificación funcional: #602 por pg_net tuvo `shouldReport=true`, pero n8n no creó ejecución del handler. Esta corrección mejora el contenido de la futura alerta, no soluciona el disparo. No se generó otra falla ni se tocó ningún dato transaccional.

### Revalidación estática de errores previos — 2026-10-01 01:00 UTC

- Los errores históricos #86 (`undefined/rest/v1` en WF25-A), #110 (`Invalid output format` al recibir el resultado simulado de WF80) y #219–#224 (fallo FK al auditar tenant no existente en WF80) ocurrieron antes de las revisiones actuales de producción.
- Revisé el código/configuración actuales activos/publicados: WF25-A v`dc894f70-e8d8-484d-ae26-e6d45299a04d` construye la URL con el project ref Supabase vigente y conserva credencial `supabaseApi`; WF13 v`c1a4ef09-002d-4f3b-9401-63bffde87291` admite `simulated=true, errored=false`; WF80 v`81740576-968f-448b-9bd6-75d0cec21a3c` solo persiste `id_comercio` si existe en `rsuelvo.tbl_comercios`, y la columna de auditoría acepta NULL.
- `validate_node_config` pasó para `Lookup Pedido`, `Assert Delivery Result 1` y `Log Guard`. Esto verifica el esquema de los nodos y la versión publicada, no reemplaza una ejecución E2E actual. No repetí las rutas con escrituras en producción; falta diseñar una prueba aislada/idempotente antes de esa comprobación.
- Comprobé además el sanitizador actualizado ejecutando el JS guardado con un payload representativo: tomó `execution.error.message` y `execution.lastNodeExecuted`, y convirtió `token=sentinel`, email y teléfono de prueba a valores redactados. No envió correo ni usó datos reales.
- No pude abrir la UI de n8n con el perfil Chromium del usuario en este runtime: Chromium aborta al arrancar con `setsockopt: Operation not permitted` de Crashpad, incluso desactivando Crashpad. MCP n8n sigue disponible, pero no expone logs de instancia; para cerrar el diagnóstico del evento #602 hace falta acceso a logs desde la UI/runtime de n8n.

### Cron real de lista de espera en dos tenants — 2026-10-01 01:12 UTC

- El estado previo de la cola era cero `ESPERANDO`/`NOTIFICADO`; cada fixture estaba asociado al tenant, variante y sucursal correctos. Verifiqué que los dos clientes tienen contacto `QA_SIM` (sin revelar teléfonos), que no había entradas activas para esas variantes, que quedaba stock y que no se reservaría inventario por la notificación.
- Inserté una entrada sintética por tenant con `fn_agregar_lista_espera_v2`; ambas devolvieron `AGREGADO`, posición 1. El cron activo `rsuelvo_expirar_reservas` corrió a las 01:12:00 UTC con estado `succeeded`; a las 01:12:04 ambas entradas ya estaban en `NOTIFICADO`, con sus TTL configurados (2 y 10 min), sin reserva generada.
- El gateway escribió exactamente dos eventos de auditoría `whatsapp_send_simulated` (uno por tenant) a las 01:12:06. Ningún mensaje salió a Meta/WhatsApp y `stock_reservado` no fue cambiado por esta fase. Esto prueba cron → WF13 → gateway en modo simulado para dos tenants/clientes; no prueba la entrega Meta real.
- Las dos entradas QA se conservarán para observar su vencimiento natural por cron (01:14 y 01:22 UTC). No hay usuarios reales esperando en esas variantes según la lectura previa; no ejecutar otra prueba hasta que expiren.

### Expiración natural y guard MFA — 2026-10-01 01:18 UTC

- El turno QA de Celulares expiró a las 01:14 y pasó a `VENCIDO`; a las 01:17 el cron seguía `succeeded`. El turno QA de Prueba RSUELVO permanece `NOTIFICADO` hasta 01:22 por su TTL de 10 minutos; aún no se cerró ese tramo.
- Ejecuté `tests/sql/email_mfa_access.sql` contra Supabase producción. Pasó todas las aserciones (administrador AAL1 bloqueado, bootstrap permitido, RPC/escritura protegidos, challenge validado y escritura permitida tras MFA) y terminó con `ROLLBACK`. Consulté después y quedaron cero usuarios, perfiles, comercios o challenges de prueba.
- Revisé la alerta RLS de `email_mfa_*`: esas políticas son `RESTRICTIVE`, no amplían la lectura por OR; se combinan como guardas con las políticas permisivas de acceso por tenant. No hice cambios RLS.
