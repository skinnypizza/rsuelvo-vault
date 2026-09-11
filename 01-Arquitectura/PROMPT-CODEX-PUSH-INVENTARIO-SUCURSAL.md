# PROMPT CODEX — Push de reservas + módulo Inventario por sucursal (app Flutter)

## Contexto (vault `/home/nico/obsidian/Rsuelvo-CLEAN`, código `/home/nico/StudioProjects/rsuelvo`)
Decisión del dueño: el cajero debe enterarse al instante cuando se crea una reserva en su
sucursal (hoy depende de abrir la app; las reservas vencen en 10 min). Además falta una pantalla
de inventario real por sucursal. Contratos vigentes: `fn_listar_variantes_sucursal` (valores
efectivos + stock), Edge Functions con `verify_jwt`, RLS por sucursal. Reglas: jamás
`service_role` en Flutter, español, marca en `brand.dart`, SKU solo lectura, economía de tokens.

## A. Push notifications (2 fases, NO implementar todo de golpe)
**Fase 1 — diseño + insumos (entregable de esta fase):**
1. Diseñar el flujo: token FCM por dispositivo → tabla nueva `tbl_dispositivos_push`
   (proponer SQL COMPLETO: `id_usuario, token_fcm UNIQUE, plataforma, created_at/updated_at`,
   RLS por usuario propio + inserción vía Edge Function) → **el orquestador aplica la
   migración, vos NO tocas la BD**.
2. Emisor propuesto: Database Webhook o pg_net en el evento de reserva → Edge Function
   `notificar-reserva-sucursal` (nueva, `verify_jwt` interno) → FCM v1 a tokens de usuarios
   con vínculo ACTIVO a (comercio, sucursal) y rol ADMIN/CAJERO. Sin n8n (D11 intacto: esto
   es push de app, no WhatsApp). Respetar opt-out comercial NO aplica aquí (es personal
   interno), pero sí baja de token inválido.
3. Listar INSUMOS DEL DUEÑO sin los cuales no hay Fase 2: proyecto Firebase (Android primero;
   iOS/APNs como fase posterior), `google-services.json`, cuenta de servicio FCM.
4. App: registro del token al login (`firebase_messaging`), renovación y baja al logout.
**Fase 2** (solo cuando el dueño entregue insumos): implementar emisor + registro + indicador.

## B. Módulo Inventario por sucursal (implementar directo, sin cambios BD)
Pantalla "Inventario de mi sucursal" con la MISMA fuente que variantes
(`fn_listar_variantes_sucursal`): lista plana de TODAS las variantes con fila de inventario
en la sucursal (independiente del producto), mostrando por ítem nombre efectivo, SKU,
`stock_actual`, reservado y disponible (`actual - reservado`), badge "Sin stock",
buscador por SKU/nombre y agrupación visual por producto. ADMIN con selector de sucursal;
CAJERO fijo a la suya. Reutilizar repositorio/estilos existentes; `flutter analyze` limpio.

## Entregable
Responder: A-fase-1 (diseño + SQL propuesto + lista de insumos) y B implementado con tests
si corresponde. Sin dependencias nuevas sin avisar. Si algo del contrato no existe, reportar.
