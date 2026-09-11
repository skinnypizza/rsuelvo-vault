# PROMPT CODEX — Fix tap push cae en dashboard + snackbars fugaces (app Flutter)

## Diagnóstico verificado por el orquestador (partir de aquí)
1. **Tap → dashboard en vez de `/inventario`:** el mapa en `_openNotification` es CORRECTO
   (`stock_bajo → /inventario`). La sospecha es carrera en frío: con app terminada, el tap
   corre antes de que auth restaure la sesión y el `redirect` del router manda a `/login`
   (`user == null`), terminando en dashboard tras el login. Verificar y corregir: diferir la
   navegación push hasta `authProvider.isInitialized == true` (o sesión lista); si el contexto
   aún no existe, reintentar tras inicialización en vez de un solo postFrame.
2. Agregar `debugPrint` en `_openNotification` (motivo + ruta) y en el `redirect` cuando
   redirija un destino push, para diagnosticar con `adb logcat` si persiste.
3. **Snackbars fugaces:** los pushes #1/#2 llegaron (`enviados:1`) pero con app abierta solo
   hay snackbar breve y se pierde. Subir la duración del snackbar push (8–10s) y, si es
   trivial, acción "Ver" que abra la ruta del motivo.
4. Actualizar el comentario stale del guard de cajero (dice que solo accede a
   verificaciones/pedidos/puntos-entrega; hoy también `/inventario` y dashboard).

## Verificación obligatoria
`flutter analyze` limpio + `flutter build apk --debug` exitoso. El dueño retestea:
(a) app TERMINADA → push → tap → pantalla correcta; (b) app en BACKGROUND → igual.
Sin commit (orquestador). Reportar archivos + salidas.

## Reglas operativas
Español. Sin capturas. Economía de tokens. Sin dependencias nuevas. No tocar contratos push.
