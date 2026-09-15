# PLAN F8 — Panel web SuperAdmin (Refine React + Cloudflare Pages)

> **Decisiones dueño 2026-09-15:** Refine React + Cloudflare Pages. Stack web a confirmar
> en familia queda RESUELTO por esta vía. Estado: planificación, nada implementado.

## 1. Stack fijado
- **Refine (React + TypeScript + Vite SPA)** + MUI (recomendado: más ejemplos Refine+Supabase).
- **Cloudflare Pages** (estático): build `dist/` + `_redirects` (`/* /index.html 200`).
- Cliente Supabase JS con anon key + RLS (jamás service_role, igual que Flutter).
- Repo nuevo: `~/StudioProjects/rsuelvo-admin/` (git local; deploy por `wrangler pages deploy`).

## 2. Auth y roles (bloqueante: cuenta superadmin)
- Registro normal (email/pass) → orquestador otorga `ROLE_SUPERADMIN` mediante vínculo
  a un comercio cualquiera (`tbl_usuario_comercio.id_comercio` es NOT NULL: no existe
  vínculo global; el poder cross-tenant viene del código de rol, verificado 2026-09-15).
  Sin esto nadie entra al panel.
- RLS cross-tenant SOLO lectura/escritura-admin vía `fn_es_superadmin()` (migración,
  aditiva): comercios, config, cuentas, movimientos, sucursales, usuarios, vínculos,
  plantillas, logs_auditoria. Tablas tenant intactas.
- SYSADMIN/SOPORTE (solo lectura operativa) fuera del MVP (fase posterior).

## 3. Alcance MVP (F8-slice: alta + gobierno mínimo)
1. Login + gate por rol (no-admin rebota).
2. Lista/detalle de comercios (estado, config, saldo, sucursales, canales).
3. **Alta wizard** → `fn_alta_comercio` (nombre, código 3 sin O, sucursal) + invitar admin
   (EF existente) + **subida QR** a `qr-pagos/<id>/tienda.png` (requiere policy storage
   superadmin, migración).
4. Suspender/Bloquear/Reactivar (HU-105/106) → `fn_cambiar_estado_comercio` (migración).
5. Lecturas: créditos globales, movimientos, auditoría.
- Fuera MVP: numeración por comercio (E18), SysAdmin infra, Soporte, dominio custom.

## 4. Backend del orquestador (previo/paralelo al agente)
- `fn_alta_comercio` corregida (sin `max(uuid)`) + fix `fn_identificar` multi-fila→NULL.
- `fn_cambiar_estado_comercio` (ACTIVO/SUSPENDIDO/BLOQUEADO/CANCELADO + auditoría).
- RLS superadmin + policy storage qr-pagos. Tests SQL + espejos vault.
- Alta de prueba: crear tenant TEST → verificar → dejarlo CANCELADO (no se borra).

## 5. Dueño (insumos)
- Email superadmin (registrar cuenta y avisar para otorgar rol).
- Proyecto Cloudflare Pages (conectar cuando el build exista) + `wrangler login`.
- Dominio custom: opcional, después.

## 6. Verificación
Build OK, gate por rol (no-admin bloqueado), alta TEST E2E (tenant + config + bonus +
sucursal + canal + QR + invite), suspender/reactivar, auditoría con rastros.
