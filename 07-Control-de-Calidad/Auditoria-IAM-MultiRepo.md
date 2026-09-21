# Auditoría IAM Multi-Repo — consolidación IAM-0

**Fecha:** 2026-09-21 · **Modo:** solo lectura, cero cambios · **Agentes:** orquestador (DB, GPT directo) + Codex Terra (Flutter) + Codex Luna (Web, QA).
**Baselines ejecutadas por orquestador:** `flutter analyze` 0 issues · `flutter test` 278/278 · web `npm run build` OK.

Fuentes: `Informe-IAM0-A-DB.md` (este dir) · `Informe-IAM0-B-Flutter.md` · `Informe-IAM0-C-Web.md` · `Suite-Aceptacion-IAM.md`.

## 1. Veredicto H-IAM-01/02/03 (todos CONFIRMADOS en código real)

- **H-IAM-01 P0:** EF v8 devuelve `password_temporal` (201) + doc lo ordena mostrar/copiar + Flutter `usuario_invite_dialog.dart:209-232` lo copia al portapapeles. Doble fuente de verdad del mismo defecto (backend + doc + UI).
- **H-IAM-02:** `auth_controller.dart:130-135` sort `_rolePriority` + `selected.first`; `test/multirol_test.dart` congela la lógica en vez de probar el controller; sin tests de auth controller.
- **H-IAM-03:** `permissions.ts` centraliza gates pero `highestRole` colapsa a rol global sin comercio (misma trampa que Flutter, confirmada estructuralmente por Web).

## 2. Hallazgos nuevos de IAM-0 (fuera del doc orquestador)

| ID | Severidad | Hallazgo | Origen |
|---|---|---|---|
| N-1 | P0 | Web escribe QR/paquetes directo a tabla+Storage pese a que el README exige RPC/EF (`packages.manage` sin autoridad server-side) | C |
| N-2 | P1 | Web permite invitar 3 roles; contradice contrato EF documentado | C |
| N-3 | P1 | Solicitudes: UI/catálogo permite SysAdmin; contrato dice solo SuperAdmin (o actualizar contrato) | C |
| N-4 | P1 | `cajero_multiplo` bloquea ser cajero en 2 comercios (scope global, no por comercio) | A |
| N-5 | P2 | Acciones internas de Usuarios sin gates propios (`users.invite`/`users.mutate` solo a nivel ruta) | C |
| N-6 | P2 | Reportes sensibles filtrados solo en frontend | C |

## 3. Discrepancias conciliadas

- Doc orquestador §1.3 traía roles inexistentes → corregido a canónicos antes de delegar.
- IAM-8 no reabre D4/D17 (corregido): onboarding implementa sobre decisiones cerradas.
- QA no pudo escribir `Suite-Aceptacion-IAM.md` (sandbox read-only) → orquestador la extrajo del log y la guardó (970 líneas, este dir).
- Flutter/Web no pudieron ejecutar suites (sin toolchain en su sandbox) → orquestador ejecutó baselines: todo verde.

## 4. Contrato IAM-1 propuesto (lote exacto a implementar)

1. **Backend (DB):** migración aditiva §3 de `Informe-IAM0-A-DB.md` + `tbl_invitaciones` (token_hash, expira, consumo único, idempotencia por email+comercio, email-existente→vincular) + decisión N-4. EF reescrita: no devuelve secreto; acepta por enlace/código.
2. **Flutter:** eliminar `_PasswordDialog`/`passwordTemporal`/Copiar (2 sitios) + UX Pendiente/Aceptada/Vencida/Revocada; NO tocar selección multi (eso es IAM-3).
3. **Web:** mismo contrato invite; cerrar N-2 (roles permitidos) en la misma pasada.
4. **QA:** ejecutar `Suite-Aceptacion-IAM.md` casos IAM-D invite (nueva/idempotente/expirada/usada/revocada/existente/nuevo/rol/sucursal/atacante/sin-password) + regresión REG-D.
5. **Docs:** actualizar EF-doc (eliminar "mostrar/copiar") + matriz permisos + ESTADO-EJECUCION. N-1/N-3/N-5/N-6 van a IAM-4/IAM-6, NO a IAM-1 (no ampliar el lote).

## 5. DoD IAM-0
Cero cambios funcionales ✅ · inventarios contra código+cloud reales ✅ · breaking changes: ninguno con migración aditiva ✅ · dependencias: IAM-1 necesita migración A-1/A-2 aplicada primero ✅.
