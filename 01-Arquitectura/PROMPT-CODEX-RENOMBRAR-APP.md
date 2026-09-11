# PROMPT CODEX — Renombrar applicationId a `bo.rsuelvo.app` (app Flutter)

## Contexto (código `/home/nico/StudioProjects/rsuelvo`, vault `/home/nico/obsidian/Rsuelvo-CLEAN`)
Decisión del dueño: el `applicationId` placeholder `com.example.rsuelvo.rsuelvo` pasa a
**`bo.rsuelvo.app`** antes de la integración FCM (el dueño re-registra en Firebase después).
Solo renombre: sin Firebase, sin dependencias nuevas, sin cambios funcionales.

## Cambios (Android + iOS, para no pagarlo dos veces)
1. **Android**: `applicationId` y `namespace` en `android/app/build.gradle(.kts)` →
   `bo.rsuelvo.app`; atributo `package` del `AndroidManifest.xml` si existe; paquete y
   ruta de `MainActivity` (`android/app/src/main/kotlin/...` + declaración `package`).
   Revisar flavors/buildTypes si referencian el ID viejo, y `androidTest`/test si aplica.
2. **iOS**: `PRODUCT_BUNDLE_IDENTIFIER` a `bo.rsuelvo.app` (Runner + perfiles asociados),
   `CFBundleName`/display name coherente con RSUELVO si aplica.
3. **Nombre visible**: verificar que el label de la app sea RSUELVO (o el definido en marca).
4. Buscar en todo el repo restos de `com.example` / `com.example.rsuelvo` (código, configs,
   docs) y actualizarlos o reportarlos.
5. NO tocar `google-services.json` (lo re-descarga el dueño tras re-registrar) ni agregar
   `firebase_core`/`firebase_messaging` (eso es Fase 2).

## Verificación obligatoria
`flutter analyze` sin issues + `flutter build apk --debug` exitoso (prueba real de que el
renombre compila). Reportar warnings si los hubiera. Sin pruebas vivas.

## Entregable
Responder: archivos tocados + salida de analyze/build. Sin commit (lo hace el orquestador).
Si algo no aplica (p.ej. iOS sin proyecto Xcode esperable), reportarlo, no improvisar.

## Reglas operativas
Español. Sin capturas. Economía de tokens.
