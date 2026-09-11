# PROMPT CODEX — Push: tap-to-screen + textos por evento (app Flutter)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`, vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Backend push v1 listo y probado (trigger→EF→FCM→bandeja). Falta que **tocar la notificación
abra la pantalla correspondiente**. Catálogo exacto + payloads en
`06-Integraciones/Push-Notificaciones.md` (7 motivos, `data` con ids, teléfono solo en
textos ADMIN — la app NO decide roles, solo muestra lo que llega).

## Cambios (solo app)
1. **Background/terminada**: `getInitialMessage()` + `onMessageOpenedApp` → mapa
   `motivo → ruta`: `reserva_nueva`/`reserva_por_vencer` → detalle/seguimiento de reserva
   (o lista de reservas filtrada por `id_reserva`); `comprobante_recibido` → revisión de
   comprobantes (`id_comprobante`); `envio_asignado`/`entrega_completada` → detalle de envío
   (`id_envio`); `stock_bajo` → `/inventario` (ya existe); `pago_confirmado` → detalle pedido.
   Si la pantalla exacta no existe, navegar a la lista más cercana + TODO explícito.
2. **Foreground**: el snackbar actual debe mostrar `title`/`body` del RemoteMessage
   (ya llega bien formado) — verificar que los 7 motivos se ven correctos.
3. No tocar registro de token, contratos EF, ni secretos. Sin dependencias nuevas.

## Verificación obligatoria
`flutter analyze` limpio + `flutter build apk --debug` exitoso. El dueño prueba taps en
dispositivo (asocia cada motivo a su pantalla). Sin commit (orquestador).
Reportar archivos + salidas + TODOs si alguna pantalla no existe.

## Reglas operativas
Español. Sin capturas. Economía de tokens.
