# Suite de Aceptación IAM — IAM-0/D

**Fecha de baseline:** 2026-09-21  
**Modo:** solo lectura  
**Producción/BD/cloud:** no modificados  
**Datos reales FEE/FER:** no utilizados  
**Documento solicitado:** no pudo escribirse en `07-Control-de-Calidad/` porque el entorno está montado como solo lectura. Este es el contenido completo propuesto para `Suite-Aceptacion-IAM.md`.

## 1. Evidencia revisada

- `07-Control-de-Calidad/Informe-IAM0-B-Flutter.md`
- `07-Control-de-Calidad/Informe-IAM0-C-Web.md`
- `01-Arquitectura/PROMPT-ORQUESTADOR-IAM-ONBOARDING-USUARIOS.md`, §5
- `01-Arquitectura/PROMPT-IAM0-D-QA.md`
- `00-Index/00-PROMPT-MAESTRO-RSUELVO.md`
- `00-Index/ESTADO-EJECUCION.md`
- `06-Integraciones/Edge-Function-invitar-usuario-comercio.md`
- `06-Integraciones/Edge-Function-invitar-usuario-comercio-v8.ts`
- `02-Base-de-Datos/sql/68_usuarios_staff.sql`
- `02-Base-de-Datos/sql/08_rls.sql`
- `03-n8n/Matriz-Consistencia-WF-BD-HU.md`
- `06-Backlog-HU/03-Correlacion-Wireframes-HU.md`

Rutas de código canónicas encontradas:

- Flutter: `/home/nico/StudioProjects/rsuelvo`
- Web: `/home/nico/StudioProjects/rsuelvo-web`

Los informes B/C aparecen como archivos no rastreados en el árbol actual; no fueron modificados.

---

## 2. Baseline ejecutada

| Componente | Verificación | Resultado |
|---|---|---|
| Flutter | `flutter test` | **NO CONFIRMABLE**: `flutter: command not found` |
| Flutter inventario estático | 25 archivos `*_test.dart`, 112 declaraciones `test`/`testWidgets`/`group` | No equivale a confirmar 278 pruebas verdes |
| Web TypeScript | `npm exec -- tsc -p app/tsconfig.app.json --noEmit` | **VERDE**, exit code 0 |
| Web `permissions.test.ts` y `auth-flows.test.tsx` | Vitest | **BLOQUEADO** por `EROFS`: Vite intenta crear `.vite-temp` |
| SQL/RLS 11 casos | No se encontró suite ejecutable local | **NO EJECUTADA** |
| SQL/RLS histórico | `00-Index/ESTADO-EJECUCION.md` registra 11 casos verdes el 2026-09-18 | Evidencia histórica, no baseline reproducida |
| Producción/cloud | Sin llamadas ni escrituras | **CUMPLIDO** |

### Estado baseline

La baseline no puede declararse completamente verde en este entorno:

- Web TypeScript: verde.
- Web tests: bloqueados por filesystem.
- Flutter: bloqueado por ausencia de Flutter.
- SQL/RLS: solo consta el resultado histórico; no existe el ejecutable de la suite en las rutas revisadas.

---

## 3. Datos fósiles permitidos

Todos los casos deben usar únicamente datos sintéticos:

| Elemento | Valor fósil |
|---|---|
| Comercio A | `00000000-0000-0000-0000-00000000a001` |
| Comercio B | `00000000-0000-0000-0000-00000000b001` |
| Sucursal A1 | `00000000-0000-0000-0000-00000000a101` |
| Sucursal B1 | `00000000-0000-0000-0000-00000000b101` |
| Usuario Admin A | `iam.admin.a@example.test` |
| Usuario Admin B | `iam.admin.b@example.test` |
| Usuario User A | `iam.user.a@example.test` |
| Usuario atacante | `iam.attacker@example.test` |
| Usuario recovery privilegiado | `iam.superadmin@example.test` |
| SKU sintético | `TSTA01` |
| Pedido fósil | `00000000-0000-0000-0000-00000000d001` |
| Motivo auditoría | `IAM0-D-TEST` |

Está prohibido utilizar comercios, sucursales, SKU, teléfonos, pedidos o credenciales reales de FEE/FER.

Cada ejecución debe limpiar sus fósiles mediante una transacción o fixture reversible. No se deben eliminar datos reales.

---

## 4. Reglas comunes de aceptación

Cada caso debe comprobar:

1. autorización efectiva en backend/RLS, no solo visibilidad de UI;
2. aislamiento por `id_comercio`;
3. ausencia de `password_temporal`, tokens o secretos en respuestas, errores, logs, estados o clipboard;
4. idempotencia ante repetición segura;
5. auditoría en `tbl_logs_auditoria` o SecurityEvent equivalente;
6. concurrencia cuando el caso modifique membresías o recursos;
7. regresión de pedidos, pagos, inventario, créditos y logística cuando aplique;
8. wireframe/HU correspondiente;
9. compatibilidad entre web, Flutter, EF y RPC;
10. respuesta verificable de pass/fail, no inferida por ausencia de error visual.

---

# 5. Casos de aceptación IAM

## IAM-D-001 — Invitación nueva

**HU/WF/contratos:** HU-016–021, `WF#33`, EF v8.

**Precondiciones**

- Admin sintético autorizado para Comercio A.
- Email `iam.nuevo@example.test` inexistente.
- Sucursal A1 activa.
- No usar FEE/FER.

**Pasos**

1. Invocar la EF con rol permitido y sucursal A1.
2. Repetir la consulta de usuarios.
3. Revisar cuerpo HTTP, memoria de cliente, logs y auditoría.
4. Intentar login del invitado mediante el mecanismo seguro definido por IAM-1.

**Resultado esperado**

- Se crea exactamente un usuario y un vínculo.
- El comercio y sucursal corresponden a A/A1.
- La respuesta no contiene contraseña ni secreto.
- Se genera invitación de un solo uso o estado pendiente.
- La operación queda auditada.
- El segundo procesamiento del mismo evento no duplica filas.

**Pass/fail**

- **PASS:** creación única, sin secretos, tenant correcto, auditoría presente.
- **FAIL:** aparece `password_temporal`, se crea más de un vínculo, se omite auditoría o se asigna otro tenant.

---

## IAM-D-002 — Invitación idempotente

**Precondiciones**

- Existe una invitación fósil activa para `iam.nuevo@example.test` en A/A1.
- No existe vínculo duplicado.

**Pasos**

1. Repetir la misma solicitud con la misma clave/correlación.
2. Repetirla con reintento de red simulado.
3. Consultar usuario, vínculos y auditoría.

**Resultado esperado**

- Se devuelve el estado idempotente definido por el contrato.
- No se crea otro usuario, vínculo ni secreto.
- La auditoría identifica el reintento.
- Pedidos, pagos, inventario, créditos y logística permanecen sin cambios.

**Pass/fail**

- **PASS:** una sola identidad y vínculo.
- **FAIL:** duplicación, regeneración de credencial o mutación operativa colateral.

---

## IAM-D-003 — Invitación expirada

**Precondiciones**

- Invitación fósil con fecha de expiración pasada.
- Usuario aún sin sesión establecida.

**Pasos**

1. Intentar aceptar el enlace expirado.
2. Intentar repetirlo.
3. Solicitar una nueva invitación.

**Resultado esperado**

- El enlace expirado es rechazado.
- No se crea sesión ni se establece contraseña.
- El reintento produce el mismo rechazo, sin mutación.
- La nueva invitación tiene nuevo identificador, expiración y auditoría.
- No se revela si existe información sensible adicional.

**Pass/fail**

- **PASS:** rechazo seguro, idempotente y auditado.
- **FAIL:** acceso concedido, token reutilizable o secreto expuesto.

---

## IAM-D-004 — Invitación usada

**Precondiciones**

- Invitación fósil válida ya consumida una vez.

**Pasos**

1. Intentar reutilizar el mismo enlace.
2. Intentar establecer una segunda contraseña.
3. Revisar sesiones y logs.

**Resultado esperado**

- El enlace no puede reutilizarse.
- No se modifica nuevamente la credencial.
- No se crean sesiones adicionales.
- El intento queda registrado como evento de seguridad.

**Pass/fail**

- **PASS:** segundo uso rechazado.
- **FAIL:** token reutilizable o cambio de contraseña adicional.

---

## IAM-D-005 — Invitación revocada

**Precondiciones**

- Invitación fósil pendiente para User A.
- Admin revoca la invitación antes de su uso.

**Pasos**

1. Revocar la invitación.
2. Intentar consumir el enlace.
3. Repetir la revocación.

**Resultado esperado**

- El enlace revocado queda inutilizable.
- La repetición de revocación no cambia el estado.
- Se conserva la trazabilidad de creación y revocación.
- No se afecta ningún otro vínculo ni módulo operativo.

**Pass/fail**

- **PASS:** estado revocado, sin login ni secreto.
- **FAIL:** enlace aún usable o revocación cruzada de otra membresía.

---

## IAM-D-006 — Email existente con misma membresía

**Precondiciones**

- Email fósil ya asociado a Comercio A con el mismo rol y sucursal.

**Pasos**

1. Enviar invitación repetida.
2. Consultar usuarios y vínculos.
3. Intentar login con la identidad existente.

**Resultado esperado**

- Se responde de forma idempotente.
- No se crea identidad adicional.
- No se reemplaza ni expone la credencial existente.
- La sesión conserva el contexto correcto.

**Pass/fail**

- **PASS:** una identidad, un vínculo, sin secreto.
- **FAIL:** duplicado, reset no solicitado o reasignación de tenant.

---

## IAM-D-007 — Email existente con otra membresía

**Precondiciones**

- Email fósil asociado a Comercio A.
- Solicitud para agregarlo a Comercio B.

**Pasos**

1. Solicitar nueva membresía desde el actor autorizado.
2. Consultar vínculos.
3. Intentar acceder a A y B por separado.

**Resultado esperado**

- Se agrega únicamente la membresía autorizada.
- La identidad no se duplica.
- La app/web no selecciona automáticamente un tenant por prioridad global.
- Debe existir selección explícita de membresía activa.

**Pass/fail**

- **PASS:** una identidad, dos membresías aisladas y selección explícita.
- **FAIL:** rol global dominante, tenant implícito o acceso cruzado.

---

## IAM-D-008 — Email nuevo

**Precondiciones**

- Email fósil inexistente.
- Actor autorizado.
- Comercio y sucursal válidos.

**Pasos**

1. Crear invitación.
2. Consultar respuesta y auditoría.
3. Completar onboarding.
4. Cerrar sesión y volver a ingresar.

**Resultado esperado**

- Se crea una identidad pendiente o invitación segura.
- Nunca se devuelve contraseña temporal.
- La membresía queda vinculada al tenant solicitado.
- El contexto se reconstruye sin elegir otro comercio.
- No se contaminan filtros ni caches.

**Pass/fail**

- **PASS:** onboarding completo y tenant estable.
- **FAIL:** secreto devuelto, contexto incorrecto o sesión con datos de otro tenant.

---

## IAM-D-009 — Rol no permitido

**Precondiciones**

- Actor autorizado para invitar solo roles permitidos.
- Solicitudes con roles `ROLE_SUPERADMIN`, rol inexistente y rol no permitido.

**Pasos**

1. Enviar cada rol inválido.
2. Repetir cada solicitud.
3. Revisar usuarios, vínculos y auditoría.

**Resultado esperado**

- Cada solicitud es rechazada por backend.
- No basta con ocultar la opción en UI.
- No se crean usuarios ni vínculos.
- El rechazo queda auditado sin incluir secretos.

**Pass/fail**

- **PASS:** rechazo consistente en web, Flutter y EF.
- **FAIL:** un rol inválido llega a persistirse o solo se bloquea visualmente.

---

## IAM-D-010 — Sucursal de otro tenant

**Precondiciones**

- Actor autorizado en Comercio A.
- Se intenta usar Sucursal B1.

**Pasos**

1. Invocar invitación con `id_sucursal=B1`.
2. Repetir desde Flutter y web.
3. Intentar modificar posteriormente la membresía usando IDs manipulados.

**Resultado esperado**

- La EF/RPC rechaza la asociación.
- No se crea usuario ni vínculo parcial.
- La compensación elimina cualquier recurso transitorio.
- Se registra intento de acceso cruzado.
- No cambia información de B ni de A.

**Pass/fail**

- **PASS:** rechazo server-side y rollback completo.
- **FAIL:** asociación A/B, fila parcial o control únicamente frontend.

---

## IAM-D-011 — Atacante sin permisos

**Precondiciones**

- Usuario sintético sin capacidad de invitar.
- Token inválido, ausente y token de usuario tenant no autorizado.

**Pasos**

1. Invocar la EF sin JWT.
2. Invocar con JWT inválido.
3. Invocar con JWT válido pero sin permiso.
4. Intentar llamar `fn_editar_usuario` y `fn_gestionar_vinculo`.

**Resultado esperado**

- Respuestas 401/403 según corresponda.
- RPC protegidas rechazan al actor.
- No se crean usuarios, vínculos ni cambios.
- Se registra el evento de seguridad cuando corresponda.
- No se revela existencia de cuentas o recursos sensibles.

**Pass/fail**

- **PASS:** ningún bypass usando IDs manipulados.
- **FAIL:** autorización basada solo en UI o acceso con rol incorrecto.

---

## IAM-D-012 — Respuestas sin password

**Precondiciones**

- Todas las rutas de invitación, reintento, error, autorización y recovery disponibles.
- Herramientas de inspección de respuesta y logs.

**Pasos**

1. Ejecutar invitación nueva.
2. Ejecutar invitación idempotente.
3. Provocar errores 400, 401, 403, 409 y 500.
4. Revisar respuestas HTTP, objetos serializados, excepciones, logs, clipboard y almacenamiento local.

**Resultado esperado**

- Ningún campo contiene `password_temporal`, contraseña, token privado o secreto.
- No existe botón Copiar para credenciales.
- Los mensajes no permiten reconstruir secretos.
- El backend sigue siendo la autoridad.

**Pass/fail**

- **PASS:** búsqueda de secretos completamente negativa.
- **FAIL:** cualquier aparición en respuesta, modelo, UI, portapapeles, log o error.

**Hallazgo actual:** el contrato EF v8 y su implementación todavía devuelven `password_temporal` en HTTP 201. Este caso fallaría antes de IAM-1.

---

# 6. Casos multi-comercio y membresías

## IAM-D-013 — Dos roles iguales en dos comercios

**Precondiciones**

- User A tiene `ROLE_TENANT_ADMIN` en A y B.
- A y B tienen sucursales, productos, pedidos y créditos fósiles distintos.

**Pasos**

1. Iniciar sesión.
2. Verificar que se muestran ambas membresías.
3. Seleccionar A y consultar todos los módulos.
4. Cambiar a B y repetir.
5. Manipular manualmente un `id_comercio` de la consulta.

**Resultado esperado**

- La selección es explícita.
- En A solo aparecen datos A; en B solo datos B.
- Un ID manipulado no amplía el acceso.
- Los providers/cache se invalidan al cambiar contexto.
- No se mezclan pedidos, pagos, inventario, créditos ni envíos.
- El cambio queda auditado si el contrato lo exige.

**Pass/fail**

- **PASS:** aislamiento total y selección estable.
- **FAIL:** elección por orden/prioridad, datos mezclados o cache contaminado.

---

## IAM-D-014 — Dos roles distintos en dos comercios

**Precondiciones**

- User A tiene Admin en A y Cashier en B.
- B contiene dos sucursales; el cajero está limitado a B1.

**Pasos**

1. Seleccionar A.
2. Confirmar capacidades de Admin.
3. Seleccionar B.
4. Confirmar capacidades de Cashier y alcance B1.
5. Intentar usar una capacidad de Admin sobre B.

**Resultado esperado**

- Las capacidades se calculan como `(usuario, membership, comercio, rol)`.
- El rol Admin de A no se hereda en B.
- Solo se visualizan y ejecutan acciones permitidas para Cashier/B1.
- RLS rechaza mutaciones fuera de alcance.
- Los módulos operativos permanecen separados.

**Pass/fail**

- **PASS:** capabilities contextualizadas.
- **FAIL:** unión global de roles o escalamiento horizontal.

---

## IAM-D-015 — Cambio repetido de comercio

**Precondiciones**

- Usuario con membresías A y B.
- Filtros fósiles distintos en sucursales, pedidos e inventario.

**Pasos**

1. Cambiar A→B→A→B al menos cinco veces.
2. Abrir dashboard, pedidos, inventario, créditos y logística después de cada cambio.
3. Reiniciar providers o volver a la pantalla inicial.

**Resultado esperado**

- Cada pantalla corresponde al tenant activo.
- Los filtros de sucursal anterior se limpian o validan.
- No aparecen resultados del tenant previo.
- No se producen solicitudes con contexto obsoleto.
- No se duplican auditorías por simple navegación.

**Pass/fail**

- **PASS:** contexto consistente en todos los cambios.
- **FAIL:** datos antiguos, filtros cruzados o requests con tenant stale.

---

## IAM-D-016 — Revocación del comercio seleccionado

**Precondiciones**

- Usuario activo en Comercio A.
- Mantiene también membresía activa en B.
- Se revoca solamente A mediante `fn_gestionar_vinculo`.

**Pasos**

1. Mantener una sesión abierta en A.
2. Revocar el vínculo A desde un actor autorizado.
3. Intentar leer y escribir recursos A con la sesión existente.
4. Cambiar a B.
5. Repetir tras cerrar y reabrir sesión.

**Resultado esperado**

- Acceso a A se corta, incluso con sesión o IDs previamente cargados.
- B sigue funcionando.
- No se revoca la identidad ni la membresía B.
- La UI obliga a seleccionar B o cerrar sesión.
- Auditoría identifica actor, vínculo, comercio y motivo.

**Pass/fail**

- **PASS:** revocación unilateral por comercio.
- **FAIL:** acceso persistente a A o caída innecesaria del acceso a B.

---

## IAM-D-017 — Reinicio de aplicación

**Precondiciones**

- Usuario con membresías A y B.
- Contexto activo B.
- Datos operativos fósiles distintos por tenant.

**Pasos**

1. Seleccionar B.
2. Cerrar la aplicación o destruir el árbol de widgets.
3. Reiniciar y restaurar sesión.
4. Verificar selección y datos.
5. Repetir seleccionando A.

**Resultado esperado**

- El contexto se restaura solo si el diseño lo permite y de forma segura.
- Nunca se selecciona otro tenant por prioridad de rol.
- Si no puede restaurarse con seguridad, se solicita selección explícita.
- No se conservan secretos ni datos sensibles en almacenamiento local.
- Los providers se inicializan con `membershipId`/tenant.

**Pass/fail**

- **PASS:** restart seguro y determinista.
- **FAIL:** tenant incorrecto, cache cruzado o restauración insegura.

---

## IAM-D-018 — Revocación unilateral: User A Admin C1 + Cashier C2

**Precondiciones**

- User A:
  - Admin en Comercio C1.
  - Cashier en Comercio C2, Sucursal C2-1.
- C1 y C2 tienen datos fósiles diferenciados.

**Pasos**

1. Confirmar acceso Admin a C1.
2. Confirmar acceso Cashier únicamente a C2-1.
3. Revocar únicamente el vínculo Cashier de C2.
4. Intentar acceder a C2.
5. Confirmar que C1 sigue operativo como Admin.
6. Revocar después C1 y verificar que ambos accesos terminan.

**Resultado esperado**

- La revocación C2 no afecta C1.
- La revocación C1 posterior no afecta la identidad global hasta que no queden membresías.
- Las funciones operativas respetan el rol contextual.
- La auditoría registra cada revocación separadamente.

**Pass/fail**

- **PASS:** independencia completa de vínculos.
- **FAIL:** revocación global, escalamiento o acceso residual.

---

# 7. Recovery privilegiado

## IAM-D-019 — Recovery de cuenta privilegiada

**Precondiciones**

- Cuenta sintética SuperAdmin/SysAdmin.
- Enlace PKCE o `token_hash` fósil generado para testing.
- Configuración de expiración y uso único documentada.

**Pasos**

1. Solicitar recovery.
2. Consumir el enlace válido.
3. Cambiar contraseña.
4. Cerrar sesión local.
5. Intentar reutilizar el enlace.
6. Intentar acceder a operaciones privilegiadas.
7. Repetir con enlace expirado, alterado y de tipo incorrecto.

**Resultado esperado**

- El recovery válido permite únicamente cambiar la credencial.
- El token es de uso único y expira.
- No concede capacidades nuevas ni cambia memberships.
- Operaciones privilegiadas siguen requiriendo autorización contextual.
- Los eventos de recovery, cambio de credencial y sesión quedan auditados.
- No se muestran tokens completos ni credenciales.

**Pass/fail**

- **PASS:** recovery limitado, auditado y no escalable.
- **FAIL:** token reusable, bypass de RBAC, cambio de rol o secreto expuesto.

**Brecha actual:** la web verifica PKCE/OTP, pero la autorización privilegiada posterior depende de la carga de acceso; TTL, MFA, revocación real y controles adicionales no están demostrados localmente.

---

# 8. Revocación y RPC de usuarios

## IAM-D-020 — `fn_editar_usuario`

**Precondiciones**

- Usuario fósil no privilegiado.
- Usuario fósil SuperAdmin protegido.
- Actor SuperAdmin y actor no autorizado.

**Pasos**

1. Editar nombre, teléfono y estado con SuperAdmin.
2. Intentar editar SuperAdmin.
3. Intentar editar con actor no autorizado.
4. Repetir la misma edición.
5. Consultar vínculos y auditoría.

**Resultado esperado**

- Solo SuperAdmin/service role autorizado ejecuta la función.
- SuperAdmin protegido no puede editarse por esta vía.
- Desactivar usuario desactiva sus vínculos según contrato.
- La repetición es idempotente.
- Cada mutación crítica queda auditada.

**Pass/fail**

- **PASS:** guards, idempotencia y auditoría correctos.
- **FAIL:** edición por actor no autorizado, protección omitida o auditoría ausente.

---

## IAM-D-021 — `fn_gestionar_vinculo`

**Precondiciones**

- Usuario con vínculos A/B.
- Roles Admin, Cashier, Logistics y SuperAdmin.
- Sucursal válida e inválida.

**Pasos**

1. Crear vínculo válido.
2. Repetir creación.
3. Desactivar vínculo.
4. Repetir desactivación.
5. Intentar crear SuperAdmin.
6. Intentar crear Logistics sin sucursal.
7. Intentar vincular sucursal de otro comercio.
8. Intentar crear segundo Cashier cuando el contrato lo prohíbe.

**Resultado esperado**

- Creación repetida reactiva o responde idempotentemente sin duplicar.
- Desactivación repetida no cambia otros vínculos.
- SuperAdmin protegido.
- Logistics requiere sucursal.
- Sucursal ajena rechazada.
- Restricción de Cashier único respetada.
- Todas las decisiones quedan auditadas.

**Pass/fail**

- **PASS:** invariantes completas.
- **FAIL:** duplicado, cross-tenant, rol protegido asignable o falta de trazabilidad.

---

# 9. Regresión operativa

Cada regresión debe ejecutarse usando tenant fósil A y luego repetirse en B para demostrar aislamiento.

## REG-D-001 — Pedidos y reservas

**Precondiciones**

- SKU `TSTA01`, stock fósil y cliente fósil.
- WF-10/RPC de reserva disponibles.

**Pasos**

1. Crear reserva.
2. Repetir la solicitud.
3. Consultar pedido y reserva.
4. Cambiar de tenant y consultar el mismo ID.
5. Ejecutar expiración fósil si el entorno de pruebas lo permite.

**Resultado esperado**

- Reserva y pedido se crean una sola vez.
- Reintento devuelve estado idempotente.
- No se puede leer ni mutar desde otro tenant.
- La expiración libera stock una sola vez.
- Auditoría de reserva, pedido y expiración presente.

**Pass/fail**

- **PASS:** atomicidad, idempotencia, aislamiento y auditoría.
- **FAIL:** duplicado, stock inconsistente o lectura cruzada.

---

## REG-D-002 — Pagos y comprobantes

**Precondiciones**

- Pedido fósil `ESPERANDO_PAGO`.
- Comprobante sintético sin datos reales.

**Pasos**

1. Registrar comprobante.
2. Repetir el registro.
3. Confirmar pago.
4. Repetir confirmación.
5. Intentar confirmar pedido con reserva vencida.
6. Consultar desde otro tenant.

**Resultado esperado**

- Comprobante idempotente.
- Confirmación única.
- Pedido pasa a `PAGADO` una sola vez.
- Movimiento de inventario y crédito se genera una sola vez.
- Reserva vencida es rechazada.
- Auditoría completa.
- No se exponen documentos de otro comercio.

**Pass/fail**

- **PASS:** `YA_PROCESADO`/equivalente, atomicidad y RLS.
- **FAIL:** doble venta, doble consumo de crédito o confirmación vencida.

---

## REG-D-003 — Inventario y variantes

**Precondiciones**

- Producto y variante fósiles en A y B.
- Sucursal A1 y B1.

**Pasos**

1. Crear o editar variante dentro del tenant.
2. Registrar entrada y ajuste.
3. Repetir el ajuste con la misma correlación.
4. Intentar usar IDs de B desde A.
5. Verificar stock tras reserva y liberación.

**Resultado esperado**

- Solo roles permitidos mutan inventario.
- Las operaciones son atómicas y auditadas.
- Repetición no duplica movimiento.
- El stock queda consistente.
- No se permite acceso cross-tenant ni cross-sucursal.

**Pass/fail**

- **PASS:** stock correcto y tenant aislado.
- **FAIL:** ajuste duplicado, rol incorrecto o contaminación de stock.

---

## REG-D-004 — Créditos

**Precondiciones**

- Cuenta de créditos fósil por tenant.
- Pedido fósil confirmable y pedido rechazable.

**Pasos**

1. Confirmar una venta.
2. Repetir confirmación.
3. Rechazar otro comprobante.
4. Consultar ledger desde A y B.
5. Intentar aprobar/resolver con rol no autorizado.

**Resultado esperado**

- Confirmación consume exactamente lo definido por D14.
- Reintento no consume nuevamente.
- Rechazo no consume.
- El saldo puede quedar negativo solo cuando el contrato lo permite.
- Ledger y usuario actor quedan auditados.
- RLS impide ver movimientos ajenos.

**Pass/fail**

- **PASS:** ledger consistente, idempotente y aislado.
- **FAIL:** doble consumo, consumo en rechazo o acceso cruzado.

---

## REG-D-005 — Logística

**Precondiciones**

- Pedido fósil pagado.
- Sucursal, repartidor y envío sintéticos.

**Pasos**

1. Crear envío.
2. Asignar repartidor de la sucursal correcta.
3. Intentar asignar repartidor de otra sucursal/tenant.
4. Avanzar estados válidos.
5. Repetir el mismo cambio.
6. Intentar una transición inválida.
7. Registrar entrega fósil.

**Resultado esperado**

- Solo se permite alcance correcto de sucursal.
- Estados siguen la máquina canónica.
- Repetición es idempotente.
- Transición inválida es rechazada.
- Evidencia de entrega y auditoría se vinculan al tenant correcto.
- No se envían mensajes duplicados por reintento.

**Pass/fail**

- **PASS:** aislamiento, máquina de estados, idempotencia y auditoría.
- **FAIL:** asignación cruzada, transición inválida aceptada o duplicado.

---

## REG-D-006 — Regresión de sesión sobre módulos operativos

**Precondiciones**

- Usuario con membresías A/B.
- Datos fósiles en pedidos, pagos, inventario, créditos y logística.

**Pasos**

1. Abrir cada módulo en A.
2. Cambiar a B sin cerrar sesión.
3. Volver a abrir cada módulo.
4. Cerrar sesión.
5. Confirmar que no quedan datos protegidos visibles.
6. Iniciar nuevamente y seleccionar explícitamente tenant.

**Resultado esperado**

- Cada módulo consulta el tenant activo.
- Logout limpia usuario, membresía activa, filtros y providers.
- No aparecen datos de la sesión anterior.
- No se realizan mutaciones con contexto anterior.
- La app no depende de `selected.first` ni de prioridad global.

**Pass/fail**

- **PASS:** sesión y módulos consistentemente aislados.
- **FAIL:** datos residuales, mutación stale o acceso tras logout.

---

# 10. Cobertura del DoD global

| Criterio | Cobertura |
|---:|---|
| 1. Ningún administrador conoce contraseña ajena | IAM-D-001, 002, 012. Actualmente fallaría por `password_temporal` en EF v8 |
| 2. Una identidad en múltiples comercios | IAM-D-007, 013, 014 |
| 3. Selección correcta de membresía Flutter | IAM-D-013, 015, 017 |
| 4. Revocación solo del comercio correspondiente | IAM-D-016, 018, 021 |
| 5. Autoría histórica operativa | REG-D-001 a REG-D-006 |
| 6. RLS contra IDs manipulados | IAM-D-010, 011, 013, 014; REG-D-001 a REG-D-005 |
| 7. Operaciones privilegiadas auditadas | IAM-D-005, 011, 019, 020, 021; todas las regresiones |
| 8. Recovery sin bypass privilegiado | IAM-D-019 |
| 9. Contratos web/Flutter compatibles | IAM-D-001, 009, 012, 019, 020, 021 |
| 10. Regresión pedidos/pagos/inventario/créditos/logística | REG-D-001 a REG-D-006 |
| 11. `flutter analyze` y suite Flutter | Baseline requerida; no confirmable por `flutter` ausente |
| 12. Lint/tests/build web | TypeScript verde; Vitest bloqueado por `EROFS`; build no ejecutado para no intentar escribir artefactos |
| 13. Suite SQL/RLS de aislamiento | Baseline histórica de 11 casos; ejecución local no encontrada |
| 14. Documentación del vault | Este documento propuesto; escritura bloqueada por filesystem |
| 15. Estado real reflejado en ejecución | Registrar explícitamente baseline parcial y bloqueos; no declarar verde sin evidencia |

---

# 11. Hallazgos que bloquean la aceptación

1. La EF v8 devuelve `password_temporal` en respuestas 201.
2. El contrato documenta explícitamente mostrar y copiar esa contraseña.
3. La implementación Flutter conserva `password_temporal` en modelos y UI.
4. Flutter elige membresía mediante prioridad global y `selected.first`.
5. La web agrega roles y comercios globalmente y usa `highestRole`.
6. No hay evidencia local de una suite SQL/RLS ejecutable de 11 casos.
7. Flutter no pudo ejecutarse porque el binario no está instalado.
8. Los tests web no pudieron iniciar porque Vite necesita escribir `.vite-temp`.
9. Recovery web valida el formato del enlace, pero TTL, MFA, revocación y controles privilegiados dependen de configuración externa no verificable aquí.
10. La aceptación multi-comercio no puede declararse verde mientras no exista selección explícita y contexto tenant-keyed en Flutter y web.

---

# 12. Resultado final IAM-0/D

**Suite diseñada:** sí.  
**Casos solicitados cubiertos:** sí.  
**Reglas de idempotencia y auditoría incorporadas:** sí.  
**Regresión explícita por pedidos, pagos, inventario, créditos y logística:** sí.  
**Cobertura de los 15 criterios DoD:** sí.  
**Baseline completamente verde:** no confirmable en este entorno.  
**Cambios en producción:** ninguno.  
**Cambios en código, BD o tests:** ninguno.  
**Archivo `Suite-Aceptacion-IAM.md` creado:** no; bloqueado por filesystem solo lectura.
