# Wireframes App Móvil — RSUELVO

> **Fecha:** 24 de agosto de 2026 · **Herramienta:** Google Stitch (MCP) · **Viewport:** 390×844 px (export 780×1768 @2x)
> **Estado:** ✅ **Completo — 39 de 39 wireframes generados**
> **Alcance:** App Flutter para **Dueño de Comercio** (`ROLE_TENANT_ADMIN`), **Cajero** (`ROLE_TENANT_CASHIER`) y **Agente Logístico** (`ROLE_LOGISTICS_AGENT`).
> El comprador NO usa la app: su flujo completo vive en WhatsApp + n8n (ver [[arquitectura-general]]).

---

## 1. Contexto del ejercicio

Se solicitó inspeccionar el vault, deducir la experiencia móvil y generar wireframes mediante MCP de diseño.
El MCP `pen.dev` no estaba disponible; se confirmó con el usuario el uso de **Google Stitch** como sustituto.

**Proyecto Stitch:** `RSUELVO — Wireframes App Móvil (Dueño de Tienda + Repartidor)`
**ID:** `projects/1852486780525167950`
**Design System generado:** "Resuelvo Bolivia Design System" (asset `assets/b300140349504d159425550432999c96`)

## 2. Fuentes ingeridas del vault

| Fuente | Qué aportó al diseño |
|---|---|
| [[arquitectura-general]] | Roles RBAC, regla "comprador solo WhatsApp", funciones de la app Flutter |
| [[Rsuelvo_Documentacion_Base_de_Datos]] | ERD conceptual, enums de estados (reservas, pedidos, comprobantes, envíos), lista de espera, créditos |
| [[workflows]] | Flujo conversacional n8n WF-00…WF-80, estados conversacionales, RPCs esperadas |
| [[Matriz de permisos]] | Permisos por módulo → qué ve cada rol en la app |
| Código Flutter existente (`lib/features/*`) | Pantallas ya iniciadas (login, dashboard, cobros, productos, créditos, envíos, config), paleta real `#2FAC66` |

## 3. Filtrado de alcance

### ✅ Incluido (experiencia móvil)
Dueño: dashboard, cobros QR, verificación IA, catálogo/inventario, reservas/lista de espera, créditos, envíos, configuración, usuarios/sucursales. Cajero: vista limitada a su sucursal. Repartidor: hoja de ruta y prueba de entrega.

### ❌ Descartado (no pertenece a la app móvil)
| Flujo descartado | Motivo |
|---|---|
| Comprador: SKU → reserva → QR → comprobante por chat | Vive en WhatsApp/n8n; "el comprador no tiene cuenta" |
| Workflows n8n (normalizador, router, expiración, GPT-4o pipeline) | Backend de orquestación |
| Panel SuperAdmin global (tenants, costos API) | Web administrativa cross-tenant |
| Sesión/configuración OpenWA | Infraestructura |

## 4. Inventario de pantallas

> **PDF consolidado (40 páginas):** `[[RSUELVO_Wireframes_App_Movil.pdf]]` — portada logo + 39 pantallas.
> PNG individuales embebidos desde `attachments/wireframes/`.

### Flujo A — Autenticación (4)
![[attachments/wireframes/01-login.png]]
*01 Login base · 21 estado carga · 38 error credenciales · 02 Registro comercio*

![[attachments/wireframes/21-login-carga.png]]
![[attachments/wireframes/38-login-error-credenciales.png]]
![[attachments/wireframes/02-registro-comercio.png]]

### Flujo B — Dashboard (2)
![[attachments/wireframes/03-dashboard-inicio.png]]
![[attachments/wireframes/22-dashboard-vacio.png]]
*03 Dashboard con métricas y alerta de saldo bajo · 22 estado vacío (comercio nuevo)*

### Flujo C — Cobros QR y Verificación IA (7)
![[attachments/wireframes/04-lista-cobros.png]]
![[attachments/wireframes/05-emitir-cobro-qr.png]]
![[attachments/wireframes/23-detalle-cobro-qr-ampliado.png]]
![[attachments/wireframes/24-modal-comprobante-recibido-ocr.png]]
![[attachments/wireframes/06-verificacion-en-curso.png]]
![[attachments/wireframes/07-resultado-verificacion-valido.png]]
![[attachments/wireframes/25-verificacion-invalida-monto.png]]
*04 Lista con chips por estado · 05 Emitir cobro · 23 QR ampliado modal · 24 Modal comprobante+OCR · 06 Espera PROCESANDO · 07 VÁLIDO (confianza 94%) · 25 INVÁLIDO (Bs 150 vs Bs 120)*

*(el estado SIN_CRÉDITOS se cubre en el flujo F, pantalla 08)*

### Flujo D — Catálogo e inventario (5)
![[attachments/wireframes/09-productos-catalogo.png]]
![[attachments/wireframes/26-productos-catalogo-vacio.png]]
![[attachments/wireframes/10-nuevo-producto-variantes-sku.png]]
![[attachments/wireframes/27-editar-producto-variantes.png]]
![[attachments/wireframes/11-detalle-inventario-ajuste.png]]
*09 Lista con stock actual/reservado/disponible · 26 Vacío · 10 Alta con SKU autogenerado `[3L][1N][1L][3A]` + error duplicado · 27 Edición variantes · 11 Ajuste + historial movimientos*

### Flujo E — Reservas y lista de espera (4)
![[attachments/wireframes/12-reservas-activas-countdown.png]]
![[attachments/wireframes/13-detalle-reserva-lista-espera.png]]
![[attachments/wireframes/28-detalle-reserva-vencida.png]]
![[attachments/wireframes/34-dialogo-confirmacion-destructiva.png]]
*12 Lista con countdown · 13 Detalle + posiciones ESPERANDO/NOTIFICADO · 28 VENCIDA con timeline posterior · 34 Diálogo "¿Liberar stock?"*

### Flujo F — Créditos IA (3)
![[attachments/wireframes/14-creditos-ia-saldo-movimientos.png]]
![[attachments/wireframes/15-recargar-creditos-paquetes.png]]
![[attachments/wireframes/29-compra-creditos-exitosa.png]]
![[attachments/wireframes/08-verificacion-bloqueada-sin-creditos.png]]
*14 Saldo + ledger · 15 Paquetes PENDIENTE_DE_PAGO · 29 Compra PAGADA (+500=547) · 08 SIN_CRÉDITOS bloqueada*

### Flujo G — Envíos admin (3)
![[attachments/wireframes/16-envios-logistica-admin.png]]
![[attachments/wireframes/30-detalle-envio-timeline.png]]
![[attachments/wireframes/17-nuevo-envio-asignar-repartidor.png]]
*16 Lista con chips por estado · 30 Detalle con timeline completo · 17 Crear/asignar repartidor*

### Flujo H — App repartidor (3)
![[attachments/wireframes/18-repartidor-hoja-de-ruta.png]]
![[attachments/wireframes/31-repartidor-detalle-entrega.png]]
![[attachments/wireframes/19-repartidor-prueba-entrega.png]]
*18 Hoja de ruta del día · 31 Detalle entrega (mapa, contacto, cobro contra entrega) · 19 Prueba de entrega bottom-sheet (foto+firma+GPS)*

### Flujo I — Configuración y equipo (3)
![[attachments/wireframes/20-configuracion-tienda.png]]
![[attachments/wireframes/32-gestion-sucursales.png]]
![[attachments/wireframes/33-gestion-usuarios-roles.png]]
*20 Mi tienda (QR bucket `qr-pagos`, tiempos, toggles) · 32 Sucursales · 33 Usuarios/roles (cajero→sucursal obligatoria)*

### Flujo J — Estados transversales y roles (4)
![[attachments/wireframes/35-reservas-sin-conexion.png]]
![[attachments/wireframes/36-menu-mas-perfil.png]]
![[attachments/wireframes/37-onboarding-permisos.png]]
![[attachments/wireframes/39-vista-cajero-limitada.png]]
*35 Estado offline (datos atenuados + reintento) · 36 Menú Más/perfil · 37 Onboarding permisos · 39 Vista limitada del cajero (solo su sucursal, inventario lectura)*

## 6. Estados de interfaz cubiertos (trazabilidad con el ERD)

| Estado UI | Pantalla(s) | Enum/tabla del modelo |
|---|---|---|
| Éxito verificación | 07 | `tbl_comprobantes_pago.estado = VALIDO`, confianza OCR |
| Espera/procesando | 06, 21 | `PROCESANDO`; checklist RECIBIDO→OCR→validación |
| Inválido por monto | 25 | comparación pedido vs OCR; `RECHAZADO` |
| Bloqueo sin créditos | 08 | `SIN_CREDITOS`, verificación `BLOQUEADA` |
| Expiración | 05, 12, 13, 28 | countdown sobre `fecha_expiracion` (`tiempo_reserva_minutos`) |
| Error SKU duplicado | 10 | `UNIQUE(id_comercio, sku)` |
| Lista de espera | 13, 28, 34 | posiciones `ESPERANDO`/`NOTIFICADO`, aceptación 2 min |
| Logística completa | 16–19, 30 | `PENDIENTE→PREPARANDO→ASIGNADO→EN_RUTA→ENTREGADO/NO_ENTREGADO` |
| Créditos ledger | 14, 15, 29 | `CONSUMO_VERIFICACION`, `COMPRA`, compra `PAGADA` |
| Vacíos | 22, 26 | onboarding de comercio nuevo |
| Offline | 35 | sincronización diferida, banner ámbar |
| Roles | 33, 39 | matriz de permisos; cajero→1 sucursal, lectura inventario |

## 7. Componentes base reutilizables

AppBar verde `#2FAC66` · Bottom nav 4 tabs (Inicio/Cobros/Productos/Más) · Chip persistente de créditos IA teal · Status chips codificados según enums · Countdown pill mono · Cards de lista (thumbnail+SKU+Bs+chip) · Bottom sheets · Alert dialogs destructivos · Empty states con CTA · Banner offline · Botón primario verde radio 12.

## 8. Decisiones y notas de proceso

1. **Sustitución de herramienta:** `pen.dev` no conectado → Stitch aprobado por usuario.
2. **Timeouts del transporte MCP ≠ fallo de generación**: las pantallas completan del lado del servidor (patrón disparar → sondear).
3. Set ampliado a petición del usuario de 20 → **39 pantallas completas**. Las 5 últimas requerireron regeneración porque el endpoint de listado de Stitch quedó saturado; los reintentos individuales resolvieron.
4. Export PDF regenerado tras cada lote (v1: 21 pág · v2: 35 pág · v3 final: 40 pág, 626 KB).

## 9. Próximos pasos sugeridos

- [x] Completar las 39 pantallas y re-exportar el PDF (v3).
- [ ] Validar wireframes contra historias de cajero (`ROLE_TENANT_CASHIER`).
- [ ] Definir navegación del modo repartidor (¿app separada o rol en la misma app?).
- [ ] Mapear cada pantalla a rutas GoRouter existentes en `lib/core/router`.
- [ ] Alta-fidelidad: aplicar tokens del DS de Stitch al `ThemeData` de Flutter.
