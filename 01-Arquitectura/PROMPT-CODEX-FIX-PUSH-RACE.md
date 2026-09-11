# PROMPT CODEX — Fix carrera de permiso FCM en login (app Flutter)

## Diagnóstico verificado por el orquestador (partir de aquí)
Error en login: `[firebase_messaging/unknown] A request for permissions is already running`.
Causa (doble ejecución concurrente, ambas terminan en `registerCurrentDevice` →
`requestPermission`):
1. `signIn()` (`auth_controller.dart:173`) llama `_loadUserProfile()` directo.
2. `onAuthStateChange` (`auth_controller.dart:74-78`) TAMBIÉN llama `_loadUserProfile()`
   ante el evento SIGNED_IN del mismo login.
Además el throw SÍ bloquea el login (contrario al comentario): el `catch` de
`_loadUserProfile` setea `error` + `clearUser`, por lo que el login aparenta fallar.

## Fix (solo app, 2 capas)
**A. `auth_controller.dart` — single-flight de `_loadUserProfile`:** agregar campo
`String? _loadingUserId`; al inicio: si es el mismo `authUserId` ya en curso, retornar;
setearlo, y limpiarlo en `finally`. Mantener ambos disparadores (signIn directo +
listener); solo se serializa por usuario.
**B. `push_notifications_service.dart` — endurecer `registerCurrentDevice`:**
1. Flag `_registering`: si ya hay un registro en curso, retornar.
2. Leer `getNotificationSettings()` primero; solo llamar `requestPermission()` si
   `authorizationStatus == notDetermined` (si `denied`, retornar como hoy).
3. Envolver TODO el cuerpo en try/catch que traga errores (hacer real el contrato
   "Push nunca bloquea el acceso": hoy el throw sí llega al catch del perfil).
No cambiar textos, rutas ni contratos con `registrar-dispositivo`.

## Verificación obligatoria
`flutter analyze` limpio + `flutter build apk --debug` exitoso. El dueño retestea el login
en dispositivo (ya no debe aparecer el error ni tumbar la sesión). Sin commit (orquestador).
Reportar archivos + salidas.

## Reglas operativas
Español. Sin capturas. Economía de tokens. Sin dependencias nuevas.
