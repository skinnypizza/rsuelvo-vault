# 🏪 RSUELVO — Documentación del Proyecto

> **Para IAs:** Este vault contiene la documentación técnica completa del proyecto Rsuelvo. Antes de hacer cualquier cambio, lee este índice y los archivos relevantes de cada módulo.

## ¿Qué es RSUELVO?

Plataforma **SaaS multitenant** de gestión comercial, **cobranza por WhatsApp** y **verificación de pagos con IA** para vendedores de TikTok Live y Facebook Marketplace en Bolivia.

- **Fluter** (app móvil para dueños/repartidores) + **n8n Cloud** (orquestación) + **Supabase/PostgreSQL** (datos con RLS) + **OpenWA** (WhatsApp).
- **Flujo real del comprador:** envía el SKU por WhatsApp → n8n WF4 responde precio + QR estático de la tienda → paga → reenvía el comprobante → n8n WF2 verifica por OCR.
- Aislamiento por `id_comercio` con Row Level Security.
- Verificación de comprobantes de pago por WhatsApp mediante OCR/IA (GPT-4o Vision) con consumo de créditos transaccional ACID.

## Stack Tecnológico

| Capa           | Tecnología               | Estado                      |
| -------------- | ------------------------ | --------------------------- |
| App Móvil      | Flutter (Dart)           | DESARROLLO INICIANDO (39 wireframes listos) |
| Base de Datos  | Supabase (PostgreSQL 17) | ✅ Schema v2.1 listo (sql/01…12) |
| Automatización | n8n Cloud                | Guía + matriz de consistencia listas |
| WhatsApp       | OpenWA 0.21 / Meta Cloud | OpenWA sin sesión · Guía Meta lista |
| Autenticación  | Supabase Auth + JWT      | ✅ Activo                    |
|                |                          |                             |
|                |                          |                             |

## Rutas del Proyecto

| Recurso                          | Ruta                                                  |
| -------------------------------- | ----------------------------------------------------- |
| **⭐ PROMPT MAESTRO (empezar aquí)** | `00-Index/00-PROMPT-MAESTRO-RSUELVO.md`            |
| Código Flutter                   | `/home/nico/StudioProjects/rsuelvo/`                  |
| Favicons y Recursos              | `/home/nico/rsuelvo/logotipo rsuelvo`                 |
| Variables de entorno             | `/home/nico/StudioProjects/rsuelvo/.env`              |
| OpenWA                           | `/home/nico/OpenWA/`                                  |
| Vault                            | `/home/nico/obsidian/Rsuelvo/`                        |
| Diseño UX / Wireframes app móvil    | `/home/nico/obsidian/Rsuelvo/05-Diseño-UX/`           |
| Backlog HU + Auditoría consistencia | `/home/nico/obsidian/Rsuelvo/06-Backlog-HU/`          |
| Schema SQL separado (12 archivos)   | `02-Base-de-Datos/sql/` · origen: `/home/nico/rsuelvo/` |

