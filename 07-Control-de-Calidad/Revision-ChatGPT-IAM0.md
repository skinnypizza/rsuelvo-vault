# Revisión independiente ChatGPT — IAM-0

**Fecha:** 2026-09-21  
**Alcance revisado:** `Auditoria-IAM-MultiRepo.md`, informes A/B/C, `Suite-Aceptacion-IAM.md` y Edge Function v8 actual.  
**Resultado:** **APROBACIÓN CONDICIONADA**. IAM-0 está suficientemente bien ejecutado para preparar IAM-1, pero deben cerrarse los puntos C-01 a C-04 antes de desplegar IAM-1 en producción.

---

## 1. Lo que queda validado

1. **H-IAM-01 confirmado.** La EF v8 crea una contraseña temporal y la devuelve como `password_temporal`; Flutter la muestra y copia. Debe eliminarse completamente.
2. **H-IAM-02 confirmado.** Flutter colapsa múltiples vínculos a una sola membresía mediante prioridad de rol; no existe selección explícita de comercio.
3. **Modelo base correcto.** `tbl_usuario_comercio` ya soporta múltiples vínculos y debe evolucionar como fuente canónica de Membership; no se justifica crear una segunda entidad paralela.
4. **Lifecycle insuficiente.** Hoy `activo bool` no expresa INVITED/ACTIVE/SUSPENDED/REVOKED ni actor/motivo/fechas.
5. **Suite IAM-D es adecuada como base de aceptación.** Cubre invitación nueva, idempotencia, expiración, reutilización, revocación, usuario existente, cross-tenant, atacante sin permisos y ausencia de secretos.
6. **Separación de lotes es correcta.** No conviene mezclar IAM-1 con selector multi-comercio, MFA o rediseño completo de permisos.

---

# 2. Condiciones que deben cerrarse antes de IAM-1 productivo

## C-01 — No fijar todavía `inviteUserByEmail + tbl_invitaciones(token_hash)` como diseño definitivo

El informe DB propone preferir `auth.admin.inviteUserByEmail` y simultáneamente mantener una fila propia con `token_hash`.

Eso debe tratarse como **alternativa a validar**, no como contrato cerrado.

Razón:

- el mecanismo nativo de Supabase puede gestionar el token/expiración fuera de `rsuelvo`;
- el backend de RSUELVO necesita transportar contexto adicional: comercio, rol, sucursal, invitador y estado de aceptación;
- para usuarios ya existentes, el flujo no es equivalente al de un usuario nuevo;
- no debe terminar existiendo un “token Supabase” más un segundo token propio innecesariamente.

### Acción requerida

Antes de codificar IAM-1, producir una decisión corta:

`01-Arquitectura/D-IAM-INVITACIONES.md`

Comparar al menos:

**Opción A — Supabase invite/generateLink como token de identidad + invitación RSUELVO por estado/contexto**  
**Opción B — Usuario existente autenticado acepta una invitación RSUELVO mediante identificador opaco propio**  
**Opción C — mecanismo unificado alternativo si Supabase permite resolver ambos sin duplicar secretos**

Elegir el flujo con menor cantidad de secretos y menor lógica criptográfica propia.

**Regla:** nunca almacenar token de aceptación en claro.

---

## C-02 — La unicidad `UNIQUE(email, id_comercio)` propuesta es demasiado rígida

Una constraint permanente `UNIQUE(email,id_comercio)` impediría conservar correctamente historial de invitaciones sucesivas para el mismo usuario/comercio después de expiración, revocación o cambios de rol/sucursal.

### Acción requerida

Modelar idempotencia sobre **invitaciones activas**, no sobre todo el historial.

Ejemplos aceptables:

- índice único parcial para invitación `PENDING` vigente;
- clave de idempotencia explícita;
- lookup transaccional de una invitación pendiente equivalente.

El historial de invitaciones revocadas/expiradas/consumidas debe poder conservarse.

---

## C-03 — “Web highestRole = misma trampa que Flutter” necesita decisión arquitectónica

En Flutter el defecto sí es directo porque la app es tenant-operativa y `idComercio` elegido afecta pedidos, inventario, pagos y logística.

En web, antes de calificar `highestRole` como el mismo defecto, hay que definir si `rsuelvo-web` es:

1. backoffice staff global de RSUELVO, o
2. cliente multi-tenant que además opera por comercio.

Si es backoffice global, agregar roles staff globales puede ser intencional y no requiere selector de comercio de la misma manera que Flutter.

### Acción requerida

Agregar decisión:

`D-IAM-WEB-SCOPE` — **Staff global vs contexto tenant**.

Hasta resolverla, H-IAM-03-Web debe clasificarse como **riesgo arquitectónico por confirmar**, no como defecto equivalente probado.

---

## C-04 — N-1/N-6 no pueden quedar como P0/P2 definitivos sin verificar RLS/Storage cloud

El informe Web identifica:

- escritura directa de QR/paquetes;
- reportes sensibles filtrados en frontend.

Eso es una señal válida, pero la severidad depende de las policies RLS/Storage reales.

Una escritura directa desde cliente **no es por sí sola una vulnerabilidad** si RLS/Storage policies implementan exactamente el control requerido.

### Acción requerida

Antes de cerrar IAM-0 como verificación integral, DB/QA debe auditar en cloud de solo lectura:

- policies de `tbl_paquetes_creditos`;
- policies del bucket/path de QR de paquetes;
- policies de tablas usadas por `reports.sensitive`;
- permisos efectivos por `ROLE_SUPERADMIN`, `ROLE_SYSADMIN`, `ROLE_SUPPORT`.

Después:

- si backend permite bypass → mantener/elevar severidad;
- si RLS/Storage bloquea correctamente → reclasificar como deuda de consistencia/arquitectura, no vulnerabilidad P0.

Esto no necesita bloquear el desarrollo local de IAM-1, pero sí debe resolverse antes de declarar IAM-0 completamente cerrado.

---

# 3. Ajustes recomendados a IAM-1

## Backend

IAM-1 debe resolver exclusivamente:

1. desaparición de `password_temporal`;
2. invitación/aceptación de un solo uso;
3. usuario nuevo;
4. usuario existente;
5. asociación segura comercio/rol/sucursal;
6. expiración/revocación/idempotencia;
7. auditoría;
8. compensación ante fallos parciales.

No introducir todavía:

- selector multi-comercio;
- MFA;
- Owner nuevo;
- permission engine dinámico;
- SecurityEvent completo.

## Flutter

Eliminar **todos** los consumidores del contrato inseguro, no solo `_PasswordDialog`:

- `usuario_invite_dialog.dart`;
- `usuarios_staff_screen.dart`;
- `autorizaciones_screen.dart`;
- modelos/repositorios que parsean `password_temporal`;
- tests que esperan la contraseña.

La auditoría B demuestra que existen al menos tres superficies UI relacionadas con ese secreto; el lote IAM-1 debe cubrirlas todas.

## Web

Alinear el contrato de invitación con backend, pero no forzar todavía un selector de comercio hasta resolver `D-IAM-WEB-SCOPE`.

---

# 4. Observación sobre baselines

No hay contradicción fatal entre los informes B/C y la consolidación:

- los agentes B/C no pudieron ejecutar ciertas suites en sus sandboxes;
- el orquestador declara haber ejecutado posteriormente `flutter analyze`, `flutter test` y web build en un entorno con toolchain.

Para trazabilidad, conviene que el consolidado registre el **commit SHA** exacto de Flutter/Web contra el que se ejecutaron esos baselines. Así los resultados 278/278 y build OK quedan reproducibles y no solo narrativos.

---

# 5. Veredicto

### IAM-0: APROBADO CON CONDICIONES

Se puede iniciar el **diseño/implementación local de IAM-1** siempre que:

- C-01 y C-02 se resuelvan antes de fijar la migración/EF definitiva;
- C-03 evite arrastrar a web un modelo tenant que quizá no le corresponde;
- C-04 se audite antes del cierre formal de IAM-0/seguridad web;
- ningún cambio llegue a producción sin ejecutar la suite IAM-D correspondiente.

### Próxima orden recomendada al orquestador

1. producir `D-IAM-INVITACIONES.md`;
2. resolver esquema de idempotencia/historial de invitaciones;
3. verificar policies de packages/reportes en cloud read-only;
4. registrar SHAs de baseline;
5. después delegar IAM-1 backend → Flutter/Web → QA en ese orden.
