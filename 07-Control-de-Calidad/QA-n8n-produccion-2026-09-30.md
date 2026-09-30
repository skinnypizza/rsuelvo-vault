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
