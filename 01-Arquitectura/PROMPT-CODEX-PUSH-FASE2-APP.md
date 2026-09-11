# PROMPT CODEX — Push Fase 2, lado app (Flutter)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`, vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Fase 1 lista: tabla `tbl_dispositivos_push` migrada (m45), proyecto Firebase `rsuelvo-18442`,
app Android `bo.rsuelvo.app` (renombre ya aplicado), `google-services.json` en
`/home/nico/Escritorio/FIREBASE/google-services.json`. El backend (2 Edge Functions +
trigger) lo despliega el orquestador en paralelo; programá contra estos contratos exactos
(aunque las EF aún no respondan, el código debe quedar integrado):

- `registrar-dispositivo` (`verify_jwt=true`): `POST {token_fcm, plataforma}` con JWT de
  sesión → `200/201 {ok:true}`. Resuelve el dueño desde el JWT; nunca enviar `id_usuario`.
- `notificar-reserva-sucursal`: interna, no llamarla desde Flutter.

## Cambios (solo app)
1. Copiar `google-services.json` a `android/app/` (origen: `/home/nico/Escritorio/FIREBASE/`).
2. Agregar `firebase_core` + `firebase_messaging` (versiones compatibles con el SDK del repo),
   `Firebase.initializeApp()` al arranque, permiso `POST_NOTIFICATIONS` (Android 13+) y
   entradas FCM del Manifest si el plugin las requiere.
3. Ciclo del token: al login exitoso → `getToken()` → invocar `registrar-dispositivo`;
   renovar con `onTokenRefresh`; al logout → marcar baja (llamar endpoint si existe, o
   documentar pendiente; nunca exponer service_role ni secretos).
4. Mostrar la notificación en primer plano (snackbar/diálogo simple); en segundo plano
   basta el tray del sistema. iOS/APNs fuera de alcance (fase posterior).
5. NO commitear `google-services.json` si el repo lo ignora... verificar `.gitignore`:
   si está ignorado, igual debe existir localmente en `android/app/` para compilar.

## Verificación obligatoria
`flutter analyze` limpio + `flutter build apk --debug` exitoso. Probar en dispositivo real
lo hará el dueño (los pushes de prueba llegan con la primera reserva post-deploy).
Sin commit (lo hace el orquestador). Reportar archivos + salidas + cualquier pendiente.

## Reglas operativas
Español. Sin capturas. Economía de tokens. Sin dependencias sin avisar.
