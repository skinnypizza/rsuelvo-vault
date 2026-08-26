# ESTADO DE EJECUCIÓN RSUELVO — Bitácora viva del orquestador

> **Versión:** 0.1 · **Creado:** 2026-08-26 · **Mantiene:** agente `rsuelvo` (orquestador opencode)
> **Fuente de verdad:** [[00-PROMPT-MAESTRO-RSUELVO]] v1.3-FINAL
> **Regla:** este archivo se actualiza tras cada hito. No sustituye al PROMPT MAESTRO; solo registra avance.

## 1. Fases (PROMPT MAESTRO §8)

| Fase | Contenido | Estado | Notas |
|---|---|---|---|
| **F0** | SQL v2 a cloud + seed + `codigo_tienda` + buckets/cron (E21) | ⬜ PENDIENTE | Siguiente a ejecutar; requiere U1 y U3 |
| F1 | WF-00/01/02/03/04/80 + idempotencia + opt-out (E19, HU-142..145) | ⬜ | Incluye archivar WF1/WF2/Diagnostico; requiere U2 y U4 |
| F2 | Compra WhatsApp WF-10..14 + cron 30/31 (E07, E08, E09) | ⬜ | |
| F3 | Pagos + IA WF-20..24 + créditos 50/51/52 (E10, E11, HU-141/146) | ⬜ | |
| F4 | App dueño núcleo: login/dashboard/productos/inventario/reservas/cobros | ⬜ | Wireframes A-F |
| F5 | Logística WF-40/41/42 + app repartidor + envíos admin (E14) | ⬜ | |
| F6 | Créditos UI + compra paquetes + config/usuarios/sucursales (E02-E04, E15) | ⬜ | |
| F7 | Hardening WF-80: cola/rate-limit/breaker + pruebas duplicados/caídas (D9) | ⬜ | |
| F8 (P2) | Panel web SuperAdmin/SysAdmin/Soporte + numeración por comercio (E16-E18) | ⬜ | |

## 2. Inventario actual (verificado 2026-08-26)

- **Vault:** completo y consistente — 32 tablas · 14 enums · 36 fn_* · 47 políticas RLS · 2 vistas · 26 workflows · 148 HU (147 activas + HU-147 descartada D7) · 39 wireframes.
- **Supabase cloud:** proyecto `efsksqrllhenidzqdjsf` (rsuelvo, us-west-2). **Schema v2 aún NO aplicado** (F0).
- **n8n cloud:** `rsuelvo2026.app.n8n.cloud` — 3 workflows legacy (`WF1 - Generar Cobro QR`, `WF2 - Confirmacion y Logistica de Pago`, `Diagnostico Tablas`) previos al diseño canónico → archivar en F1. Credencial OpenAI ✅ (managed); Postgres account ⚠️ a reemplazar.
- **Flutter:** proyecto base creado en `/home/nico/StudioProjects/rsuelvo/` (esqueleto `flutter create`: package `rsuelvo`, solo `lib/main.dart` + test; SDK en `/home/nico/flutter`, ya en PATH; sin repo git todavía).
- **Sistema de agentes opencode:** instalado en `.opencode/` de este vault — orquestador `rsuelvo` + especialistas `rsuelvo-db`, `rsuelvo-n8n`, `rsuelvo-whatsapp`, `rsuelvo-flutter`, `rsuelvo-qa` + comandos `/rsuelvo-fase`, `/rsuelvo-hu`, `/rsuelvo-audit`, `/rsuelvo-estado`.

## 3. Bloqueos que dependen del usuario

| # | Bloqueo | Desbloquea |
|---|---|---|
| U1 | OAuth Supabase MCP (login una vez en opencode → `/mcp`) | F0 |
| U2 | OAuth meta-devtools MCP (cuenta Meta developer; acceso beta gradual) | F1 |
| U3 | Credencial Supabase `service_role` en n8n (reemplaza "Postgres account") | F0/F1 |
| U4 | Credencial Meta Cloud API (System User token, Guía Meta §8-10) en n8n | F1 |

## 4. Bitácora

- **2026-08-26** — Ruta canónica Flutter actualizada a `/home/nico/StudioProjects/rsuelvo/` (proyecto base creado por el usuario) en PROMPT MAESTRO v1.4, README, permisos opencode y agente `rsuelvo-flutter`.
- **2026-08-26** — Archivo creado al instalar el sistema de agentes opencode (1 orquestador + 5 especialistas). Ningún cambio ejecutado contra servicios cloud. Próximo hito sugerido: **F0**, previa resolución de U1/U3.
