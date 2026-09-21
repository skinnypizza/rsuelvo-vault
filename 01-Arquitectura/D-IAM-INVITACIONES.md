# D-IAM-INVITACIONES — Decisión de diseño (resuelve C-01 + C-02)

**Fecha:** 2026-09-21 · **Estado:** DECIDIDA (implementación en IAM-1) · Responde a `Revision-ChatGPT-IAM0.md` C-01/C-02.

## Opción elegida: Supabase como único secreto + `tbl_invitaciones` como contexto/estado

Un solo secreto (el token nativo de Supabase, solo para usuarios nuevos). Cero criptografía propia. La tabla RSUELVO guarda contexto y estado, NUNCA tokens.

## Schema (migración IAM-1, aditiva)

```sql
tbl_invitaciones (
  id uuid PK, id_comercio uuid NOT NULL, id_rol smallint NOT NULL,
  id_sucursal uuid NULL, email text NOT NULL,
  invited_by uuid NOT NULL, estado text NOT NULL DEFAULT 'PENDIENTE',  -- PENDIENTE|ACEPTADA|VENCIDA|REVOCADA
  expira_at timestamptz NOT NULL DEFAULT now()+interval '7 days',
  accepted_at timestamptz NULL, created_at timestamptz DEFAULT now()
)
CREATE UNIQUE INDEX invit_pendiente_unica ON tbl_invitaciones (email, id_comercio) WHERE estado='PENDIENTE';
```

RLS deny-by-default: solo `service_role` + función `fn_aceptar_invitacion` (SECURITY DEFINER). Idempotencia (C-02): unicidad parcial sobre PENDIENTE — el historial (ACEPTADA/VENCIDA/REVOCADA) se conserva siempre.

## Flujos

**Usuario nuevo:** admin crea invitación (EF, guarda rol+sucursal del tenant) → EF llama `auth.admin.inviteUserByEmail(email)` → usuario pone su contraseña vía link Supabase → app invoca `fn_aceptar_invitacion` que vincula por email PENDIENTE vigente → vínculo ACTIVE + invitación ACEPTADA. Admin jamás ve secreto.

**Usuario existente:** sin token Supabase. Usuario autenticado acepta por id de invitación; guarda: `auth.email() = invitacion.email` + PENDIENTE + vigente. Mismo `fn_aceptar_invitacion`, mismo resultado.

**Expiración/revocación:** guarda `expira_at` en accept; cron marca VENCIDA; admin revoca PENDIENTE→REVOCADA vía fn con guarda de rol. Todo a `tbl_logs_auditoria`.

## Reglas invariantes

Nunca token en claro ni en logs (Regla 9) · `email ya existe → vincular`, jamás 409 como único camino · compensación: si falla createUser tras crear invitación, la invitación queda PENDIENTE y reintento la reutiliza (idempotencia por índice parcial).
