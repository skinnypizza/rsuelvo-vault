# PROMPT ORQUESTADOR — IAM, ONBOARDING Y CICLO DE VIDA DE USUARIOS RSUELVO

> **Objetivo:** evolucionar el sistema actual de identidad, comercios, personal y permisos de RSUELVO sin reescribir la arquitectura existente ni romper flujos productivos.
>
> **Repositorios canónicos a contrastar:**
> - `skinnypizza/rsuelvo-vault` — arquitectura, SQL, RLS, Edge Functions, backlog, decisiones y estado de ejecución.
> - `skinnypizza/rsuelvo-flutter` — aplicación móvil operativa.
> - `skinnypizza/rsuelvo-web` — aplicación web/staff.
>
> **Principio rector:** reutilizar `tbl_usuarios`, `tbl_comercios`, `tbl_usuario_comercio`, `tbl_roles`, Supabase Auth y RLS. No crear un segundo modelo de identidad o membresías en paralelo.
>
> **Resultado esperado:** pasar del RBAC operativo actual a un IAM progresivo, multi-comercio, auditable y de baja fricción, manteniendo compatibilidad con la operación existente.

---

## 0. REGLAS DE EJECUCIÓN DEL ORQUESTADOR

1. **Leer antes de cambiar**:
   - `00-Index/00-PROMPT-MAESTRO-RSUELVO.md`
   - `00-Index/ESTADO-EJECUCION.md`
   - `02-Base-de-Datos/Rsuelvo_Documentacion_Base_de_Datos.md`
   - `02-Base-de-Datos/Matriz de permisos.md`
   - `06-Integraciones/Edge-Function-invitar-usuario-comercio.md`
   - este documento.
2. Antes de delegar código, verificar el estado real de `main` en los tres repositorios. No trabajar desde supuestos históricos del vault si el código actual difiere.
3. No inventar tablas, columnas, enums, funciones o estados. Toda ampliación de schema debe comenzar como **propuesta de migración** del agente DB y pasar por revisión del orquestador.
4. No realizar acciones destructivas cloud ni cambios incompatibles de schema sin aprobación explícita del usuario.
5. Cada cambio debe preservar RLS y aislamiento tenant. Nunca trasladar autorización crítica al frontend.
6. No reescribir Supabase Auth/RLS por .NET durante este trabajo. Este programa es una evolución incremental del stack existente.
7. No cambiar simultáneamente BD + Edge Function + Flutter + Web sin dividir el trabajo en entregables verificables y secuenciales.
8. Cada lote debe cerrar con QA, regresión y actualización de documentación/estado.
9. Todo secreto, `service_role`, token de invitación o credencial debe permanecer fuera de Flutter/Web y fuera de logs.
10. **Prohibición P0:** al terminar este programa ningún administrador debe poder ver, copiar ni compartir la contraseña de otro usuario.

---

# 1. BASELINE REAL QUE SE DEBE PRESERVAR

## 1.1 Modelo existente válido

RSUELVO ya posee el núcleo correcto:

```text
Supabase Auth
      ↓
tbl_usuarios
      ↓
tbl_usuario_comercio
      ↓
tbl_comercios
      ↓
tbl_roles
```

`tbl_usuario_comercio` debe evolucionar conceptualmente como **BusinessMembership**. No crear una tabla paralela `BusinessMembership` salvo que una auditoría técnica demuestre una razón indispensable.

## 1.2 Aislamiento

Preservar el patrón canónico:

```text
auth.uid()
→ tbl_usuarios.auth_user_id
→ tbl_usuario_comercio
→ id_comercio
→ RLS / fn_* server-side
```

RLS continúa siendo frontera de seguridad. Los checks visuales de Flutter/Web son UX, nunca autorización suficiente.

## 1.3 Roles actuales

Roles canónicos actuales:

- `ROLE_SUPERADMIN`
- `ROLE_SYSADMIN`
- `ROLE_SUPPORT`
- `ROLE_TENANT_ADMIN`
- `ROLE_CASHIER`
- `ROLE_LOGISTICS`

No renumerar ni sustituir roles durante P0. La granularización futura se hará de forma compatible.

## 1.4 Hallazgos actuales que originan este programa

### H-IAM-01 — Invitación insegura por contraseña temporal — **P0 BLOQUEANTE**

La Edge Function `invitar-usuario-comercio` crea una contraseña temporal y la devuelve al cliente. Flutter muestra esa contraseña y permite copiarla. Esto debe desaparecer.

Estado objetivo:

```text
Administrador invita
→ backend crea invitación segura
→ destinatario controla su propio canal
→ destinatario acepta
→ crea/vincula su identidad
→ Membership se activa
```

El administrador no conoce ninguna credencial del invitado.

### H-IAM-02 — Flutter reduce múltiples membresías a una sola — **P0/P1**

El `auth_controller.dart` carga varias membresías activas pero selecciona automáticamente una por prioridad de rol. Eso impide operar correctamente escenarios como:

- una persona administra dos comercios;
- una persona trabaja para dos comercios;
- una persona es admin de uno y cajero de otro.

Estado objetivo: identidad única + selector/contexto explícito de comercio/membresía.

### H-IAM-03 — Web y Flutter no usan el mismo nivel conceptual de permisos — **P1**

Web ya dispone de `Capability` (`users.read`, `users.invite`, `users.mutate`, `reports.sensitive`, etc.). Flutter/BD dependen principalmente del rol. No crear dos sistemas divergentes: diseñar una convergencia RBAC compatible, manteniendo RLS como autoridad.

### H-IAM-04 — Recuperación existe, pero no hay lifecycle IAM completo — **P1**

Existen login y recovery, pero falta política integral para:

- pérdida de teléfono/email;
- cambio de email/teléfono primario;
- revocación de sesiones;
- cuenta comprometida;
- step-up authentication;
- recuperación privilegiada de Owner/Admin.

### H-IAM-05 — No existe modelo progresivo formal de verificación del comercio — **P2**

Preparar arquitectura compatible con:

- V0 Persona confirmada
- V1 Comercio básico
- V2 Comercio identificado
- V3 Comercio verificado

No implementar KYC pesado en el MVP.

---

# 2. ESTRATEGIA DE DELEGACIÓN

El orquestador es responsable de dividir el programa. Ningún subagente debe asumir el trabajo completo.

## Carril DB / IAM backend → `rsuelvo-db`

Responsable de:

- auditoría de schema actual;
- propuesta de evolución de `tbl_usuario_comercio`;
- RLS;
- funciones `fn_*`;
- estados de membresía;
- auditoría;
- invitaciones persistentes si fueran necesarias;
- revocación de vínculo;
- SecurityEvent si se aprueba;
- migraciones y rollback.

## Carril Flutter → `rsuelvo-flutter`

Responsable de:

- selector/contexto de membresía;
- aceptación de invitación;
- UX de personal;
- eliminación total de contraseña temporal;
- recuperación/seguridad móvil;
- estados de membresía;
- pruebas de widgets/controladores/repositorios.

No tocar schema directamente desde este agente.

## Carril Web

No existe actualmente un agente `rsuelvo-web` especializado en `.opencode/agent/`. El orquestador debe:

1. delegar implementación web a un implementador general/Codex competente en React/TypeScript;
2. darle rutas exactas del repo `skinnypizza/rsuelvo-web`;
3. exigir que siga `app/src/auth/permissions.ts` y la autoridad server-side existente;
4. no crear un nuevo agente persistente sin aprobación del usuario.

## Carril QA → `rsuelvo-qa`

Responsable de pruebas cruzadas y regresión:

- tenant isolation;
- roles;
- invitaciones;
- membresías múltiples;
- desactivación;
- recuperación;
- exportación/permisos;
- regresión pedidos/pagos/inventario/logística.

## Carril n8n / WhatsApp

`rsuelvo-n8n` y `rsuelvo-whatsapp` solo se involucran si una decisión aprobada requiere notificaciones de invitación/seguridad vía esos canales. No introducir WhatsApp como factor de autenticación sin decisión explícita.

---

# 3. PROGRAMA DE TRABAJO

## FASE IAM-0 — AUDITORÍA Y CONTRATO DE COMPATIBILIDAD

**Prioridad:** P0  
**Responsables:** orquestador + `rsuelvo-db` + `rsuelvo-flutter` + implementador web + `rsuelvo-qa`  
**Objetivo:** fijar baseline antes de modificar.

### Tareas

1. Inventariar schema real cloud de:
   - `tbl_usuarios`
   - `tbl_usuario_comercio`
   - `tbl_roles`
   - `tbl_comercios`
   - `tbl_sucursales`
   - `tbl_logs_auditoria`
2. Inventariar funciones/RPC relacionadas con usuarios y vínculos, especialmente:
   - `fn_editar_usuario`
   - `fn_gestionar_vinculo`
   - helpers de permisos/RLS.
3. Revisar Edge Function `invitar-usuario-comercio` desplegada vs fuente del vault.
4. Flutter: identificar todos los sitios que asumen una sola membresía/comercio actual.
5. Flutter: identificar todo uso de `password_temporal`.
6. Web: inventariar AuthContext, recovery, capabilities, usuarios y operaciones sensibles.
7. Construir una matriz `actual → objetivo → repos afectados`.

### Entregable

`07-Control-de-Calidad/Auditoria-IAM-MultiRepo.md`

### DoD

- cero cambios funcionales;
- inventario validado contra código real y cloud;
- lista de breaking changes potenciales;
- dependencias entre repos identificadas.

---

# FASE IAM-1 — ELIMINAR CONTRASEÑA TEMPORAL DE INVITACIONES

**Prioridad:** P0 BLOQUEANTE  
**Responsables:** `rsuelvo-db` → Flutter/Web → QA

## Objetivo

Reemplazar:

```text
Admin → crear usuario → recibir password_temporal → copiar → compartir
```

por:

```text
Admin → crear invitación
      → destinatario recibe enlace/código de un solo uso
      → destinatario controla su identidad
      → acepta
      → vínculo se activa
```

## Backend/DB

El agente DB debe evaluar la opción más simple compatible con Supabase Auth, preferentemente APIs nativas de invitación/recovery antes de inventar criptografía propia.

Requisitos:

- token/código de un solo uso;
- expiración;
- consumo único;
- asociación inequívoca con comercio + rol + sucursal;
- `invited_by` trazable;
- idempotencia;
- si el email ya corresponde a un User existente, vincular mediante aceptación segura en lugar de devolver 409 como único camino;
- no persistir secretos en claro;
- no registrar tokens en logs;
- compensación ante fallos parciales;
- RLS/server-side authorization.

Si requiere tabla o columnas nuevas: **proponer migración primero** y esperar aprobación antes de cloud.

## Flutter

Eliminar:

- `_PasswordDialog`;
- `passwordTemporal` del modelo;
- botón Copiar credencial;
- textos que instruyen al admin a compartir contraseña.

UX objetivo:

> “Invitación enviada. La persona deberá aceptar el acceso desde su propio correo/canal verificado.”

Mostrar estado:

- Pendiente
- Aceptada
- Vencida
- Revocada

## Web

Si web permite invitación de staff, aplicar el mismo contrato. No mantener dos mecanismos de invitación.

## QA mínimo

- invitación nueva;
- reintento idempotente;
- token expirado;
- token ya usado;
- invitación revocada;
- email de User existente;
- email nuevo;
- rol no permitido;
- sucursal de otro tenant;
- atacante sin permisos;
- confirmación de que ningún response/UI/log contiene password temporal.

---

# FASE IAM-2 — MEMBERSHIP LIFECYCLE

**Prioridad:** P0/P1  
**Responsables:** `rsuelvo-db` → Flutter/Web → QA

## Objetivo

Convertir `tbl_usuario_comercio` en la fuente canónica del ciclo de vida de pertenencia.

No duplicar la entidad.

## Estado conceptual objetivo

Como mínimo poder distinguir:

```text
INVITED
ACTIVE
SUSPENDED
REVOKED
```

Si el schema actual usa `activo bool`, el agente DB debe proponer una migración compatible, no sustituirla abruptamente.

Metadatos deseables, sujetos a revisión de schema:

```text
invited_by
invited_at
accepted_at
disabled_at
disabled_by
revocation_reason
```

## Reglas

- Revocar Membership ≠ borrar User.
- Una persona puede conservar otras membresías activas.
- Historial de operaciones conserva `id_usuario` original.
- Baja invalida el acceso del usuario a ese comercio inmediatamente.
- No hard-delete de vínculos con historial operativo salvo obligación técnica/legal debidamente justificada.

## QA

Caso obligatorio:

```text
User A
├── Comercio 1 ADMIN activo
└── Comercio 2 CASHIER activo

Revocar Comercio 1
→ Comercio 1: denegado
→ Comercio 2: continúa funcionando
→ historial Comercio 1 conserva autoría
```

---

# FASE IAM-3 — MULTI-COMERCIO REAL EN FLUTTER

**Prioridad:** P1  
**Responsable:** `rsuelvo-flutter`  
**Dependencia:** IAM-2 estable

## Problema actual

`auth_controller.dart` ordena membresías por prioridad de rol y toma una como contexto actual.

## Objetivo

Separar:

```text
AuthenticatedUser
Memberships[]
SelectedMembership
SelectedBusiness
SelectedRole
```

## Requisitos UX

- si tiene una sola membresía activa: entrar directamente;
- si tiene varias: restaurar última selección válida o mostrar selector;
- selector accesible desde perfil/header;
- mostrar claramente comercio y rol actuales;
- cambiar comercio debe recargar providers/cache dependientes del tenant;
- no mezclar datos entre comercios durante transición;
- al perder/revocar la membresía seleccionada, expulsar de ese contexto y elegir otra válida o cerrar sesión funcional.

## No hacer

- no seleccionar silenciosamente por “rol más alto” como regla final;
- no persistir datos sensibles de un tenant en cache compartida sin clave por comercio;
- no confiar en `id_comercio` del cliente para autorización.

## Pruebas

- dos comercios, mismo rol;
- dos comercios, roles distintos;
- cambio repetido de comercio;
- revocación del comercio seleccionado;
- app restart y restauración de contexto;
- ninguna consulta muestra datos del tenant anterior.

---

# FASE IAM-4 — OWNER Y OPERACIONES CRÍTICAS

**Prioridad:** P1  
**Responsables:** orquestador + DB + Flutter/Web + QA

## Decisión previa obligatoria

Crear decisión arquitectónica **D-IAM-OWNER**:

> ¿`ROLE_TENANT_ADMIN` seguirá representando al propietario en MVP o se separará Owner de Admin?

No cambiar el catálogo de roles hasta resolver esta decisión.

## Operaciones críticas a proteger

- agregar/quitar administradores;
- cambiar rol privilegiado;
- desactivar propietario/autoridad máxima;
- cambiar email/teléfono principal;
- transferencia de propiedad;
- exportación masiva;
- cierre/suspensión del comercio;
- cambios de configuración de seguridad.

## Controles objetivo

Según riesgo:

- reautenticación;
- MFA/step-up;
- confirmación explícita;
- AuditLog;
- SecurityEvent;
- notificación al propietario/administradores.

No implementar transferencia de propiedad mediante simple `UPDATE id_rol`.

---

# FASE IAM-5 — MFA, SESIONES Y RECUPERACIÓN

**Prioridad:** P1  
**Responsables:** DB/backend/Auth + Flutter/Web + QA

## MVP

MFA obligatorio al menos para cuentas privilegiadas cuando la implementación Supabase seleccionada sea estable:

- propietario/tenant admin;
- superadmin;
- sysadmin.

Evaluar `SUPPORT` según permisos efectivos.

## Sesiones

Crear UX de seguridad para:

- ver sesiones/dispositivos cuando sea viable;
- cerrar otras sesiones;
- revocar acceso después de incidente;
- invalidar sesiones relevantes después de cambios críticos.

## Recovery

Conservar lo ya construido en web, pero completar matriz:

- perdió contraseña;
- perdió email;
- perdió teléfono;
- cuenta privilegiada comprometida;
- recovery con múltiples factores disponibles;
- no permitir que el flujo de recovery sea más débil que la operación que protege.

## Passkeys

**No P0.** Evaluar para Fase 2 después de estabilizar invitaciones, membresías y MFA.

---

# FASE IAM-6 — RBAC + CAPABILITIES SIN DUPLICAR AUTORIDAD

**Prioridad:** P1/P2  
**Responsables:** DB + Web + Flutter + QA

## Situación actual

Web ya contiene capabilities de aplicación. BD/RLS usa roles y helpers. Flutter usa rol para navegación y operaciones.

## Objetivo

Definir un catálogo canónico de permisos funcionales, por ejemplo:

```text
orders.read
orders.create
orders.update
inventory.read
inventory.adjust
payments.read
payments.review
members.read
members.invite
members.manage
reports.read
customers.export
business.configure
business.close
```

Pero la autoridad final debe seguir estando en backend/RLS/fn_*.

## Estrategia

1. mapear capabilities web actuales a acciones reales del backend;
2. definir permisos de negocio faltantes;
3. establecer Role → Permission como documentación/matriz primero;
4. solo crear tablas de permisos dinámicos si hay un caso de producto real que lo justifique;
5. no sobrediseñar ABAC en MVP.

## Entregable

Actualizar `02-Base-de-Datos/Matriz de permisos.md` con CRUD/Approve/Export explícito por rol.

---

# FASE IAM-7 — CONSENTIMIENTO, TÉRMINOS Y PRIVACIDAD

**Prioridad:** P1  
**Responsables:** DB + Flutter/Web + revisión legal externa

## Objetivo

Registrar de forma auditable:

```text
UserId
TermsVersion
PrivacyVersion
AcceptedAt
Session/Context
```

Separar consentimientos opcionales (por ejemplo marketing) de aceptaciones necesarias para prestar el servicio.

No solicitar CI, selfie, biometría, domicilio personal o datos tributarios en el registro inicial salvo finalidad justificada.

Toda redacción legal definitiva requiere validación profesional boliviana antes de producción.

---

# FASE IAM-8 — ONBOARDING SELF-SERVICE DE COMERCIO

**Prioridad:** P1/P2  
**Responsables:** Producto/orquestador + DB + Flutter/Web + QA

## Objetivo UX

El pequeño comerciante debe poder llegar a operación básica mediante algo equivalente a:

```text
Teléfono/email
→ verificación
→ nombre
→ nombre comercial
→ rubro
→ comercio básico
→ empezar
```

No exigir inicialmente:

- NIT;
- SEPREC;
- CI escaneado;
- selfie/liveness;
- documentación societaria.

## Decisión pendiente a cerrar

Resolver definitivamente HU-002: self-service vs alta/aprobación por SuperAdmin.

Recomendación de arquitectura:

- self-service crea `Business` en nivel básico/limitado;
- verificaciones adicionales desbloquean capacidades sensibles;
- SuperAdmin interviene por excepción/riesgo, no como cuello de botella universal.

---

# FASE IAM-9 — VERIFICACIÓN PROGRESIVA

**Prioridad:** P2  
**Responsables:** Producto + DB + legal/compliance + QA

No construir KYC bancario indiscriminado.

Modelo objetivo:

| Nivel | Identidad/confianza | Uso |
|---|---|---|
| V0 | medio de contacto confirmado | identidad RSUELVO |
| V1 | comercio básico | operación cotidiana |
| V2 | comercio identificado | capacidades de mayor confianza |
| V3 | comercio verificado | operaciones/volumen/riesgo elevados |

Toda evidencia documental debe obedecer minimización, finalidad y retención definida.

---

# FASE IAM-10 — SECURITY EVENTS Y RESPUESTA

**Prioridad:** P2  
**Responsables:** DB/backend + QA

Separar:

```text
AuditLog = qué cambió en el negocio
SecurityEvent = señal/evento de seguridad
```

Ejemplos SecurityEvent:

- login fallido relevante;
- nuevo factor MFA;
- recovery solicitado;
- cambio de email/teléfono;
- nuevo admin;
- exportación masiva;
- acceso denegado repetido;
- sesión revocada;
- actividad anómala.

No almacenar secretos ni datos completos innecesarios en estos eventos.

---

# 4. ORDEN DE EJECUCIÓN OBLIGATORIO

```text
IAM-0 Auditoría multi-repo
        ↓
IAM-1 Invitación segura
        ↓
IAM-2 Membership lifecycle
        ↓
IAM-3 Multi-comercio Flutter
        ↓
IAM-4 Owner + operaciones críticas
        ↓
IAM-5 MFA / sesiones / recovery
        ↓
IAM-6 RBAC-capabilities
        ↓
IAM-7 Consentimientos
        ↓
IAM-8 Onboarding self-service
        ↓
IAM-9 Verificación progresiva
        ↓
IAM-10 Security Events
```

IAM-7 e IAM-8 pueden diseñarse en paralelo después de IAM-2, pero no desplegarse rompiendo contratos anteriores.

---

# 5. DEFINITION OF DONE GLOBAL

El programa IAM MVP no se considera terminado hasta demostrar:

1. ningún administrador conoce la contraseña de otro usuario;
2. una misma identidad puede pertenecer a múltiples comercios;
3. Flutter permite seleccionar correctamente la membresía activa;
4. revocar un vínculo corta acceso solo al comercio correspondiente;
5. la autoría histórica sobre pedidos/pagos/inventario permanece intacta;
6. RLS impide cross-tenant access incluso manipulando IDs desde cliente;
7. operaciones privilegiadas quedan auditadas;
8. recovery no permite saltarse controles de cuentas privilegiadas;
9. web y Flutter usan contratos de autorización compatibles;
10. pruebas existentes de pedidos, pagos, inventario, créditos y logística continúan verdes;
11. `flutter analyze` sin errores y suite Flutter verde;
12. lint/tests/build web verdes;
13. suite SQL/RLS de aislamiento verde;
14. documentación del vault actualizada;
15. `00-Index/ESTADO-EJECUCION.md` refleja el estado real, no planes no ejecutados.

---

# 6. MATRIZ DE DELEGACIÓN RESUMIDA

| Lote | Responsable primario | Apoyo | No debe hacer |
|---|---|---|---|
| IAM-0 | Orquestador | todos + QA | cambiar producción |
| IAM-1 backend | rsuelvo-db | QA | UI Flutter/Web |
| IAM-1 Flutter | rsuelvo-flutter | QA | schema directo |
| IAM-1 Web | implementador web/Codex | QA | inventar auth paralelo |
| IAM-2 | rsuelvo-db | Flutter/Web/QA | hard-delete histórico |
| IAM-3 | rsuelvo-flutter | QA | relajar RLS |
| IAM-4 | Orquestador + DB | Flutter/Web/QA | asumir Owner=Admin sin decisión |
| IAM-5 | DB/Auth | Flutter/Web/QA | MFA casero |
| IAM-6 | Orquestador + DB | Flutter/Web/QA | duplicar permisos solo frontend |
| IAM-7 | DB + Producto | Flutter/Web + legal | redactar obligación legal como hecho no validado |
| IAM-8 | Producto/orquestador | DB/Flutter/Web/QA | KYC pesado al inicio |
| IAM-9 | Producto/Compliance | DB/QA | biometría por defecto |
| IAM-10 | DB/Security | QA | loggear secretos |

---

# 7. FORMATO OBLIGATORIO DE CADA DELEGACIÓN

Toda tarea enviada a un subagente debe incluir:

```text
OBJETIVO
ALCANCE EXACTO
REPOSITORIO
ARCHIVOS/RUTAS CANÓNICAS A REVISAR
DEPENDENCIAS
CONTRATOS QUE NO SE PUEDEN ROMPER
CAMBIOS PERMITIDOS
CAMBIOS PROHIBIDOS
PRUEBAS REQUERIDAS
ENTREGABLES
DEFINITION OF DONE
```

No delegar instrucciones vagas como “mejorar seguridad” o “hacer onboarding”.

---

# 8. PRIMERA ORDEN QUE DEBE EJECUTAR EL ORQUESTADOR

Ejecutar **IAM-0 exclusivamente**.

No comenzar migraciones ni refactors todavía.

Delegar en paralelo auditorías de solo lectura:

### A — DB

A `rsuelvo-db`:

> Audita el modelo IAM real cloud y las fuentes SQL canónicas. Devuelve el estado exacto de `tbl_usuarios`, `tbl_usuario_comercio`, roles, funciones de gestión de vínculos, auditoría y RLS. Identifica qué campos ya existen de lifecycle y qué migraciones mínimas serían necesarias para IAM-1/IAM-2. No cambies cloud ni archivos productivos.

### B — Flutter

A `rsuelvo-flutter`:

> Audita todas las dependencias de autenticación, selección de membresía/comercio, invitación, gestión de personal, cambio de contraseña y perfil. Localiza cada uso de `password_temporal` y cada supuesto de “un comercio actual”. Entrega mapa archivo→comportamiento→riesgo→cambio propuesto. No modifiques código.

### C — Web

A implementador web/Codex:

> Audita `app/src/auth`, usuarios, capabilities, recovery y operaciones críticas. Determina qué capacidades están solo en frontend y cuáles tienen control server-side/RLS. Localiza supuestos de roles/comercios y diferencias contractuales con Flutter. No modifiques código.

### D — QA

A `rsuelvo-qa`:

> Diseña la suite de aceptación IAM que deberá ejecutarse después de IAM-1/IAM-3: aislamiento, invitaciones, usuarios existentes, multi-comercio, baja, recovery y regresión de módulos operativos. No cambies producción.

### Integración del orquestador

Con los cuatro informes:

1. crear `07-Control-de-Calidad/Auditoria-IAM-MultiRepo.md`;
2. consolidar discrepancias;
3. proponer el contrato IAM-1;
4. señalar migraciones necesarias;
5. presentar al usuario el lote exacto a implementar antes de tocar producción.

---

# 9. CRITERIO DE PRODUCTO

Toda decisión debe preservar este equilibrio:

```text
baja fricción
+ inclusión del pequeño comerciante
+ seguridad
+ trazabilidad
```

No convertir RSUELVO en un onboarding bancario. La seguridad debe aumentar con el riesgo, no con la mera existencia de una cuenta.
