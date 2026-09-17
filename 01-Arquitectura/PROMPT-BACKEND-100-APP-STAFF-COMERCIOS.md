# Auditoría backend para completar Rsuelvo al 100%

> Fecha: 2026-09-17  
> Alcance: aplicación Flutter `rsuelvo`, web `rsuelvo-web/app/src/features` y SQL canónico en `02-Base-de-Datos/sql`.  
> Objetivo: entregar este documento al orquestador para cerrar backend de staff y comercios.

## Resultado ejecutivo

La aplicación tiene cubiertos los flujos principales de ventas, reservas, pagos, logística, créditos, comercios y staff, pero todavía no puede declararse “100% completa” en backend.

Hay cinco bloqueadores de seguridad/funcionalidad que deben resolverse primero:

1. **Permisos de `SUPPORT` demasiado amplios.** `fn_es_admin_comercio` incluye `ROLE_SUPPORT`; por eso políticas de configuración, sucursales, categorías, variantes, usuarios, métodos de pago y canales pueden permitir escrituras de soporte. La matriz define soporte como operativo/lectura.
2. **Inventario con escritura indirecta para cualquier miembro de sucursal.** `inventory_all` es `FOR ALL` y usa `fn_tiene_acceso_sucursal`, por lo que cajero —y potencialmente soporte— puede modificar stock directamente sin movimiento auditado.
3. **Staff global no está alineado con RLS.** La app/web necesitan que `SYSADMIN` y `SUPPORT` consulten comercios, sucursales, configuración y reportes globales, pero `fn_tiene_acceso_comercio` depende principalmente de una vinculación concreta y `fn_es_admin_comercio` no incluye `SYSADMIN`. Deben existir lecturas globales explícitas y limitadas para staff.
4. **Storage de guías sin aislamiento por comercio.** Las políticas actuales de `guias-envios` solo comprueban el bucket, no el primer segmento del path ni el rol. Un usuario autenticado puede intentar leer/escribir objetos de otro comercio.
5. **Backend no reproducible desde el workspace.** No existen `supabase/migrations` ni `supabase/functions` fuente; solo SQL manual y documentación de ejecuciones cloud. Hay que establecer una fuente canónica, migraciones ordenadas y versiones de Edge Functions antes del cierre.

## Qué se verificó y qué no

### Verificado en el código disponible

- La app usa el esquema Supabase `rsuelvo`.
- La app y la web consumen tablas de comercios, usuarios, roles, sucursales, catálogo, inventario, reservas, pedidos, créditos, verificaciones, envíos, auditoría y dispositivos push.
- Las RPC críticas usadas por la app incluyen `fn_alta_comercio`, `fn_cambiar_estado_comercio`, `fn_solicitar_creditos`, `fn_resolver_compra_creditos`, `fn_registrar_guia`, `fn_confirmar_pago`, `fn_rechazar_verificacion`, `fn_actualizar_estado_envio` y `fn_listar_variantes_sucursal`.
- Las Edge Functions usadas por la app son `invitar-usuario-comercio`, `registrar-dispositivo` y `gestionar-variante-sucursal`.
- Los buckets usados por la app son `depositos-creditos`, `guias-envios`, `comprobantes-pago` y `qr-pagos`.
- Las migraciones 58–65 están reflejadas como ejecutadas en la documentación, incluyendo alta pendiente, QR por dueño, créditos y paths de comprobantes. Eso debe confirmarse contra el proyecto remoto.

### No verificable todavía

- Definiciones efectivas desplegadas en el proyecto Supabase remoto.
- Políticas duplicadas o antiguas que hayan quedado activas después de las migraciones.
- Versión real y código fuente desplegado de las tres Edge Functions.
- Estado de buckets, objetos, cron, secretos, proveedor de correo y webhooks en producción.
- Cobertura E2E real con cuentas de cada rol y dos comercios aislados.

El orquestador debe tratar todo lo anterior como una comprobación obligatoria, no como una suposición basada en el monolito SQL.

## P0 — Correcciones obligatorias de seguridad y autorización

### P0.1 Separar roles de administración tenant y staff operativo

Crear helpers con responsabilidades separadas:

- `fn_es_superadmin()` — plataforma completa.
- `fn_es_sysadmin()` — lectura global operativa y configuración global según matriz.
- `fn_es_support()` — lectura global operativa limitada.
- `fn_es_admin_tenant(p_id_comercio)` — únicamente `ROLE_TENANT_ADMIN` y superadmin/service role cuando corresponda.
- `fn_tiene_lectura_staff(p_id_comercio)` — lectura global para sysadmin/support, sin conceder escrituras.
- Mantener helpers específicos para cajero y logística.

Reemplazar `fn_es_admin_comercio` en políticas de escritura. `SUPPORT` no debe poder modificar directamente:

- configuración o estado de un comercio;
- sucursales;
- usuarios o vínculos;
- categorías, productos, variantes o métodos de pago;
- canal WhatsApp o QR;
- inventario;
- comprobantes/verificaciones salvo las acciones explícitamente permitidas por la matriz.

Agregar tests que intenten `INSERT`, `UPDATE` y `DELETE` como soporte sobre cada tabla y esperen `42501`/cero filas afectadas.

### P0.2 Endurecer inventario

Separar `SELECT` de mutaciones. El cliente no debe poder actualizar `stock_actual` ni `stock_reservado` directamente.

- Dejar `SELECT` para los roles permitidos por comercio/sucursal.
- Revocar `INSERT/UPDATE/DELETE` directos a `authenticated` o restringirlos solo al administrador tenant, según decisión de negocio.
- Usar una RPC transaccional, por ejemplo `fn_registrar_movimiento_inventario`, para entradas, salidas, ajustes y devoluciones.
- Validar sucursal, variante, cantidad positiva, stock no negativo y tipo de movimiento.
- Registrar siempre usuario, referencia, saldo anterior/posterior y auditoría.
- Mantener las operaciones internas de reservas/ventas con `SECURITY DEFINER` correctamente protegida o service role backend.

La política actual `inventory_all FOR ALL` con `fn_tiene_acceso_sucursal` no cumple este contrato.

### P0.3 Corregir aislamiento de `guias-envios`

Reemplazar las políticas actuales por políticas basadas en:

`guias-envios/{id_comercio}/{id_envio}/{archivo}`

La lectura debe comprobar que el usuario tiene acceso al comercio y que el objeto pertenece a un envío de ese comercio. La escritura/actualización debe limitarse al rol que captura la guía o al flujo backend autorizado. Añadir `DELETE` solo si el producto lo necesita.

Verificar que no existan objetos con paths antiguos fuera de la convención y migrarlos o bloquearlos.

### P0.4 Contrato de lectura global para staff

Implementar políticas o vistas/RPC de lectura segura para que:

- `SUPERADMIN`: vea todos los comercios, estados, usuarios, vínculos, autorizaciones y auditoría global.
- `SYSADMIN`: vea comercios, sucursales, configuración operativa, estados de usuarios/comercios y reportes operativos definidos por la matriz.
- `SUPPORT`: vea comercios, sucursales, estados y créditos operativos permitidos; no auditoría sensible ni datos financieros innecesarios.
- `TENANT_ADMIN`: vea únicamente su comercio y administre su tenant.
- `CASHIER` y `LOGISTICS`: vean únicamente lo necesario de su sucursal/operación.

No exponer más columnas de las necesarias. En particular, evitar entregar `auth_user_id`, secretos, tokens, datos de proveedor o información financiera completa cuando un agregado sea suficiente.

La solución preferida es una vista/RPC de lectura staff con columnas explícitas y filtros por rol, o políticas `SELECT` explícitas; no reutilizar una política de escritura para conseguir lectura.

## P0 — Usuarios, roles y comercios

### Usuarios globales

Completar backend para el CRUD global exclusivo de superadmin:

- listar usuarios y vínculos;
- editar datos de perfil permitidos;
- activar/desactivar;
- desvincular o eliminar vínculo;
- eliminar/desactivar usuario según la política de retención;
- proteger `SUPERADMIN`, evitar auto-desactivación y evitar dejar la plataforma sin superadmin;
- impedir que se creen/asignen `SUPERADMIN`, `CASHIER` o `LOGISTICS` desde un flujo de invitación genérico;
- auditar cada cambio con actor, objetivo, valores anteriores/nuevos y motivo.

El CRUD debe ser RPC/Edge Function con autorización server-side, no una actualización directa de tablas desde el cliente. La web actualmente deja edición/desactivación deshabilitadas y la documentación marca este punto como pendiente.

Completar también invitación de `SYSADMIN` y `SUPPORT`, actualmente deshabilitada/documentada, con idempotencia para usuarios existentes y contrato de correo temporal seguro.

### Invariantes de vínculos

Mantener y probar:

- cajero en una sola asignación activa y una sola sucursal;
- logística con sucursal obligatoria;
- tenant admin con alcance de comercio;
- no asignar vínculo activo a comercio no autorizado/estado incompatible;
- no duplicar vínculo activo equivalente;
- desactivar usuario debe invalidar sus vínculos efectivos.

La restricción de cajero existente debe comprobarse en cloud y ampliarse a todas las combinaciones de rol/sucursal que la matriz exige.

### Alta y estado de comercios

Verificar que solo quede la firma vigente de `fn_alta_comercio` y que no exista overload antiguo. Reforzar:

- nombres y parámetros obligatorios, normalización y límites;
- `p_bonus >= 0`;
- reserva y configuración dentro de rangos válidos;
- correo obligatorio si el alta requiere invitación inmediata;
- staff crea siempre `PENDIENTE_APROBACION`;
- solo superadmin puede crear directamente `ACTIVO`;
- alta, configuración, cuenta de créditos, sucursal y auditoría sean atómicas;
- no crear un canal WhatsApp productivo compartido con el número hardcodeado `59157005003`; definir claramente canal pendiente, onboarding y credenciales por comercio;
- un comercio pendiente/no activo no debe ser identificable por WhatsApp, resolver SKU público ni ejecutar workflows de venta.

Reforzar `fn_cambiar_estado_comercio` con una máquina de estados explícita. No debe aceptar cualquier valor del enum solo porque exista. Definir y probar transiciones permitidas, por ejemplo:

`PENDIENTE_APROBACION -> ACTIVO | CANCELADO`,  
`ACTIVO -> SUSPENDIDO | BLOQUEADO`,  
`SUSPENDIDO -> ACTIVO`,  
sin reactivar estados terminales salvo una operación explícita de superadmin.

Cada transición debe verificar rol, motivo cuando aplique, actualizar auditoría y tener efecto consistente sobre canales, QR, reservas y workflows.

## P1 — Reportes y créditos

### Reportes staff

Crear contratos backend estables para estos reportes, con filtros, paginación, rango de fechas y límites:

- depósitos/compras de créditos;
- créditos comprados, consumidos y saldo agregado;
- estados de comercios;
- estados de usuarios;
- estados de autorizaciones/auditoría para superadmin.

No depender de múltiples consultas directas del cliente para ensamblar reportes sensibles. Reutilizar `reportes_exporter` para CSV/XLSX/PDF, pero la fuente debe aplicar exactamente los mismos permisos que la lectura interactiva.

Correcciones específicas que deben verificarse:

- la política de `tbl_compras_creditos` sí contempla staff en la migración 63, pero cuentas y movimientos todavía dependen de `fn_es_admin_comercio`;
- sysadmin/support deben poder obtener el reporte de créditos+consumo que la matriz les permite, preferiblemente mediante agregados seguros;
- auditoría global para sysadmin debe estar explícitamente permitida si sigue siendo parte de la matriz;
- `tbl_usuarios` y `tbl_comercios` deben ser consultables globalmente por los roles staff autorizados, sin convertirlos en administradores tenant;
- depósitos deben devolver `archivo_path` y permitir signed URL únicamente para quien corresponda;
- rechazos deben persistir motivo y revisor;
- todos los reportes deben ser consistentes ante paginación y no usar `.single()` donde puede haber múltiples vínculos.

### Compras de créditos

Endurecer `fn_solicitar_creditos` y `fn_resolver_compra_creditos`:

- idempotency key o restricción para impedir compras pendientes duplicadas por reintento;
- validar que el path del depósito pertenezca al comercio solicitante y al bucket esperado;
- comprobar explícitamente que existe cuenta antes de aprobar;
- persistir motivo de rechazo;
- bloqueo transaccional al aprobar para no acreditar dos veces;
- auditoría de solicitar, cancelar, aprobar y rechazar;
- límites de paquete, monto y frecuencia configurables;
- políticas de storage para depósito sin `UPDATE/DELETE` arbitrario.

## P1 — Edge Functions e integraciones

Incorporar el código fuente y versionado de estas funciones al repositorio canónico y probarlas con JWT reales:

### `invitar-usuario-comercio`

- solo superadmin o tenant admin según operación;
- invitación de dueño/cajero permitida por política;
- invitación sysadmin/support solo superadmin;
- idempotencia si el usuario ya existe;
- vínculo a comercio/sucursal validado server-side;
- no aceptar `id_rol` arbitrario sin whitelist;
- service role únicamente en backend;
- no devolver secretos ni contraseñas en respuestas normales;
- proveedor de correo/SMTP productivo configurado y con límites controlados.

### `registrar-dispositivo`

- validar usuario autenticado y token FCM;
- upsert idempotente por token/usuario/plataforma;
- desactivar tokens viejos o inválidos;
- no permitir registrar dispositivo de otro usuario;
- RLS y limpieza de tokens comprobadas.

### `gestionar-variante-sucursal`

- validar pertenencia de variante y sucursal al mismo comercio;
- permitir solo tenant admin o cajero cuando la matriz lo permita;
- mantener precio/nombre/activo y stock coherentes;
- evitar que la función y el upsert directo del cliente tengan reglas distintas;
- elegir un único camino canónico y retirar el otro.

## P1 — Storage, QR y comprobantes

- Confirmar que todos los buckets sean privados.
- `qr-pagos`: permitir lectura/escritura solo al dueño del comercio y superadmin; mantener path `id_comercio/tienda.ext`; probar reemplazo del objeto y lectura de otro tenant.
- `depositos-creditos`: permitir insert al admin del comercio en su propio path y lectura staff autorizada; no permitir leer depósitos de otro comercio.
- `comprobantes-pago`: verificar path, lectura por roles, signed URL con expiración y ausencia de objetos huérfanos.
- `guias-envios`: aplicar el aislamiento P0.3.
- Revisar `INSERT/SELECT/UPDATE/DELETE` efectivos en `storage.objects`, no solo el nombre de las policies.
- Confirmar MIME, tamaño máximo, extensiones y retención de archivos.

## P1 — Seguridad Supabase y despliegue

El orquestador debe:

- crear proyecto Supabase CLI real con migraciones numeradas idempotentes;
- separar migraciones de esquema, RLS, funciones, storage y datos semilla;
- incluir fuente de Edge Functions y manifest de versiones desplegadas;
- comparar `pg_get_functiondef`, `pg_policies`, grants, buckets y extensiones del cloud con el repositorio;
- revisar overloads antiguos de RPC y eliminarlos cuando cambie el contrato;
- revisar todas las funciones `SECURITY DEFINER`: `search_path` fijo, objetos calificados, validación de `auth.uid()`/rol y ausencia de bypass accidental;
- revocar `EXECUTE` de `PUBLIC`/`anon` para funciones privilegiadas y concederlo solo a los roles necesarios;
- confirmar que `service_role` nunca aparezca en Flutter/web ni en variables públicas;
- ejecutar Supabase Database Linter y Security Advisors, corrigiendo todo hallazgo crítico/alto;
- crear backup y procedimiento de rollback antes de aplicar migraciones productivas.

La migración 61 corrigió una detección insegura de service role en el SQL documentado; debe comprobarse que la definición final desplegada sea realmente la corregida y que ningún usuario autenticado pueda hacerse pasar por service role.

## Matriz mínima de aceptación E2E

Usar dos comercios A/B, un usuario por rol, una sucursal por comercio y un usuario con múltiples vínculos. Ejecutar con JWT reales y comprobar tanto respuesta como ausencia de filas.

| Caso | Esperado |
|---|---|
| anon lista usuarios/comercios o lee storage | denegado/vacío |
| tenant admin A lee/escribe A | permitido según módulo |
| tenant admin A lee B | denegado/vacío |
| support lee reportes operativos globales | permitido solo columnas/módulos definidos |
| support modifica catálogo/config/usuarios/inventario | denegado |
| sysadmin lee comercios/config/reportes permitidos | permitido, sin mutación tenant |
| superadmin CRUD global | permitido, con protecciones y auditoría |
| cajero actualiza stock directo | denegado; debe usar flujo autorizado |
| logística modifica catálogo/créditos | denegado |
| tenant A lee/escribe objeto de storage B | denegado |
| doble aprobación de crédito | una sola acreditación |
| doble alta/invitación por reintento | operación idempotente |
| comercio pendiente recibe WhatsApp/venta | denegado |
| transición de estado inválida | denegada con código estable |
| usuario con múltiples comercios | resultados correctos, sin `.single()` implícito |

## Definition of Done backend

No cerrar esta fase hasta tener:

1. migraciones y Edge Functions en fuente canónica;
2. diff cloud/repositorio documentado y sin funciones/policies antiguas;
3. P0 corregidos;
4. CRUD global de usuarios y sus gates terminado;
5. reportes staff interactivos y exportables con permisos iguales;
6. storage aislado por tenant y signed URLs probadas;
7. tests SQL/RLS/E2E con mocks y usuarios reales por rol;
8. `supabase db lint`, Security Advisors y `flutter analyze`/tests limpios;
9. rollback/backups documentados;
10. evidencia de cada caso de la matriz, incluyendo errores esperados.

## Archivos que sustentan esta auditoría

- `02-Base-de-Datos/sql/06_functions.sql`
- `02-Base-de-Datos/sql/08_rls.sql`
- `02-Base-de-Datos/sql/11_storage.sql`
- `02-Base-de-Datos/sql/40_variante_sucursal_overrides.sql`
- `02-Base-de-Datos/sql/58_alta_superadmin.sql`
- `02-Base-de-Datos/sql/61_fix_fn_es_service_role.sql`
- `02-Base-de-Datos/sql/62_pendiente_aprobacion_qr_dueno.sql`
- `02-Base-de-Datos/sql/63_creditos_clientes.sql`
- `02-Base-de-Datos/sql/64_comprobantes_path.sql`
- `02-Base-de-Datos/sql/65_registrar_path.sql`
- `02-Base-de-Datos/Matriz de permisos.md`
- `02-Base-de-Datos/ESTADO-EJECUCION.md`
- `rsuelvo/lib/core/supabase_client.dart`
- `rsuelvo/lib/features/**/data/*_repository.dart`
- `rsuelvo-web/app/src/features/**`

