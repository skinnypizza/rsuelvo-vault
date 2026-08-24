# Correlación Wireframes ↔ Historias de Usuario

> **Fecha:** 2026-08-24 · **39 pantallas ↔ 148 HU** · Complemento de [[02-Auditoria-de-Consistencia]]
> Leyenda roles: **AD**=Admin Comercio · **CA**=Cajero · **RL**=Repartidor · **SIS**=Sistema/n8n

## 1. Matriz por pantalla

| WF | Pantalla | Flujo | Rol | HU principales | Estados/UI que cubre |
|----|----------|-------|-----|----------------|----------------------|
| 01 | Login base | A | AD/CA/RL | 001 | formulario, demo badge |
| 02 | Registro comercio | A | AD | 002 ⚠I4 | alta tenant+admin |
| 03 | Dashboard inicio | B | AD | 066, 050, 082 (agregación) | métricas, alerta saldo bajo |
| 04 | Lista de cobros | C | AD/CA | 097, 098, 082 | chips: ESPERANDO_PAGO/PAGO_VALIDANDO/PAGADO/RECHAZADO/VENCIDA |
| 05 | Emitir cobro QR | C | AD/CA | 098, 042, 051 | QR estático, referencia, countdown reserva |
| 06 | Verificación en curso | C | AD/CA/SIS | 058–059 | PROCESANDO, checklist OCR |
| 07 | Resultado válido | C | AD/CA | 063, 078, 076(CTA) | VALIDO, confianza OCR, −1 crédito |
| 08 | Sin créditos (bloqueada) | C/F | AD | 067, **141**, 073 | SIN_CREDITOS, RECIBIDO retenido |
| 09 | Productos lista | D | AD | 029, 036 | stock actual/reservado/disponible, SIN STOCK, RESERVADO |
| 10 | Nuevo producto + variantes | D | AD | 023, 024, 025, 026 | SKU autogenerado `[3L][1N][1L][3A]`, error duplicado |
| 11 | Inventario y ajuste | D | AD | 030, 032, 033, 034, 035 | ENTRADA/AJUSTE, historial movimientos |
| 12 | Reservas activas | E | AD | 050, 051, 054 | ACTIVA/PAGO_VALIDANDO/VENCIDA + countdown |
| 13 | Detalle reserva + espera | E | AD | 044, 045, 049, 054 | posiciones ESPERANDO/NOTIFICADO, liberar/cancelar |
| 14 | Créditos saldo/movimientos | F | AD | 066, 070, 071 | ledger CONSUMO/COMPRA/BONIFICACION |
| 15 | Recargar créditos | F | AD | 072, 073 | paquetes, PENDIENTE_DE_PAGO |
| 16 | Envíos lista | G | AD | 088, 085, 092–094 | PENDIENTE→ENTREGADO/NO_ENTREGADO, timeline mini |
| 17 | Nuevo envío | G | AD | 086, 087 | dirección+GPS, asignar repartidor |
| 18 | Hoja de ruta repartidor | H | RL | 090, 092 | paradas del día, GPS toggle |
| 19 | Prueba de entrega | H | RL | 095, 093, 094 | foto+firma+GPS, ENTREGADO/NO_ENTREGADO |
| 20 | Configuración tienda | I | AD | 006–011 | bucket `qr-pagos`, tiempos 008-010, `verificacion_automatica` |
| 21 | Login carga | A | todos | 001 | spinner, botón deshabilitado |
| 22 | Dashboard vacío | B | AD | 140 | onboarding, bonificación 100 créditos |
| 23 | QR ampliado (modal) | C | AD/CA | 042, 098 | compartir WhatsApp/guardar |
| 24 | Modal comprobante recibido | C | AD/CA | 058, **141** | datos OCR previos, "Verificar ahora" |
| 25 | Verificación inválida | C | AD/CA | 060, 064, 065 | esperado≠detectado, reenvío |
| 26 | Catálogo vacío | D | AD | 140 | empty state + microcopy SKU |
| 27 | Editar producto | D | AD | 027, 028, 030 | variantes editables, desactivar |
| 28 | Reserva vencida | E | AD | 048, 052, 053, 049 | timeline posterior (liberado→notificado) |
| 29 | Compra créditos exitosa | F | AD | 074, 075 | PAGADA, saldo 47→547 |
| 30 | Detalle envío + timeline | G | AD | 089, 096, 087 | seguimiento completo por estado |
| 31 | Detalle entrega (RL) | H | RL | 091, 092 | mapa, contacto, cobro contra entrega |
| 32 | Sucursales | I | AD | 012–015 | activa/inactiva, lat/lng |
| 33 | Usuarios y roles | I | AD | 016–021 | cajero→sucursal obligatoria |
| 34 | Diálogo liberar stock | E | AD | 053, 054 | confirmación destructiva, pasa a #1 |
| 35 | Offline | J | todos | 137, 138, 139 | banner ámbar, datos atenuados |
| 36 | Menú Más | J | AD | navegación | perfil, ROL chip, logout |
| 37 | Onboarding permisos | J | AD | 004(UX), UX | notificaciones/cámara/GPS |
| 38 | Login error credenciales | A | todos | 001 | banner error, intentos |
| 39 | Vista limitada cajero | K | CA | 031, 097–102 | solo su sucursal, inventario lectura |

## 2. Cobertura inversa por dominio

| Dominio funcional | Pantallas | Épicas/HU núcleo |
|---|---|---|
| Auth & onboarding | 01, 02, 21, 37, 38 | E01 |
| Monitoreo ventas | 03, 22, 35, 36 | E13/E22 |
| Cobros & verificación IA | 04, 05, 06, 07, 08, 23, 24, 25, 39 | E10, E11(I5), E15 |
| Catálogo e inventario | 09, 10, 11, 26, 27 | E05, E06 |
| Reservas & lista de espera | 12, 13, 28, 34 | E08, E09 |
| Créditos | 14, 15, 29 (+03/08 chip) | E11 |
| Logística admin | 16, 17, 30 | E13, E14 |
| Logística repartidor | 18, 19, 31 | E14 |
| Administración | 20, 32, 33, 36, 37, 39 | E02-E04, E15 |

## 3. Hallazgos de correlación

1. **Sin pantallas huérfanas**: las 39 mapean a ≥1 HU; sin HU móviles sin pantalla (E07 compra WhatsApp y E19 canal son conversacionales por diseño; E16-E18 son panel web fuera de MVP móvil).
2. **HU sin pantalla legítimas**: 037–049, 056–057, 065, 076 (comprador vía WhatsApp), 120–126 (n8n), 103–119 (web admin/soporte), 127–136 (backend).
3. **Dependencias UI nuevas detectadas**: HU-141 requiere el botón ya existente en 24; HU-143 exige tabla nueva (`tbl_whatsapp_eventos`) antes de codificar pantallas de cobros.
4. Regla para desarrollo: cada tarea Flutter debe citar su **WF# + HU#** en el PR; cada RPC nueva debe actualizar esta matriz.
