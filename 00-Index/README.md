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
| App Móvil      | Flutter (Dart)           | DESARROLLO INICIANDO        |
| Base de Datos  | Supabase (PostgreSQL 17) | Lista para migrar de script |
| Automatización | n8n Cloud                | DESARROLLO INICIANDO        |
| WhatsApp       | OpenWA 0.21.0            | 🔧 Sin sesión               |
| Autenticación  | Supabase Auth + JWT      | ✅ Activo                    |
|                |                          |                             |
|                |                          |                             |

## Rutas del Proyecto

| Recurso                          | Ruta                                                  |
| -------------------------------- | ----------------------------------------------------- |
| Código Flutter                   | AUN INEXISTENTE                                       |
| Favicons y Recursos              | `/home/nico/rsuelvo/logotipo rsuelvo`                 |
| Variables de entorno             | `/mnt/windows/Desktop/Proyectos/Rsuelvo/rsuelvo/.env` |
| OpenWA                           | `/home/nico/OpenWA/`                                  |
| Vault                            | `/home/nico/obsidian/Rsuelvo/`                        |
| Diseño UX / Wireframes app móvil | `/home/nico/obsidian/Rsuelvo/05-Diseño-UX/`           |

