# IAM-0/B — Auditoría Flutter IAM (solo lectura)

## OBJETIVO
Mapear todo el código Flutter que depende de identidad, membresía, invitación y rol. CERO cambios.

## ALCANCE EXACTO
Solo leer e informar: auth, selección de comercio/membresía, invitación de personal, gestión de usuarios, cambio de contraseña, perfil, caches por tenant.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `lib/features/auth/auth_controller.dart` (selección por `_rolePriority` + `selected.first` — H-IAM-02), `auth_model.dart`, `login_screen.dart`
- `lib/features/usuarios/usuario_invite_dialog.dart` (`passwordTemporal` + botón Copiar — H-IAM-01), `usuarios_repository.dart`, `usuarios_staff_screen.dart`
- `lib/features/autorizaciones/` (repository+screen, reutilizan invite)
- `lib/features/comercios/`, `lib/features/sucursales/` (supuestos de comercio actual)
- `lib/shell/app_shell.dart` (navegación por rol), `lib/auth/permissions`-equivalente si existe
- Todo `test/*usuarios*`, `test/*autorizacion*`, `test/*auth*` (qué cubren hoy)

## DEPENDENCIAS
Ninguna (paralelo con A/C/D). Su mapa archivo→riesgo define el alcance de IAM-1 Flutter e IAM-3.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Ningún cambio de código en esta fase (auditoría pura)
- Flujos operativos: pedidos/pagos/inventario/logística/créditos + 278 tests verdes al cierre (verificar que siguen verdes, sin tocarlos)

## CAMBIOS PERMITIDOS
Ninguno en código. Solo el informe.

## CAMBIOS PROHIBIDOS
Editar `lib/` o `test/`, agregar dependencias, tocar schema Supabase, usar `service_role`, loggear/imprimir credenciales.

## PRUEBAS REQUERIDAS
`flutter analyze` + `flutter test` de confirmación (solo lectura del estado, sin modificar). Cada hallazgo con cita archivo:línea.

## ENTREGABLES
Mapa archivo→comportamiento→riesgo→cambio propuesto para: 1) cada uso de `passwordTemporal`/diálogo/copy; 2) cada supuesto "un comercio actual" (providers, caches, selected); 3) puntos donde `id_comercio` del cliente alimenta queries; 4) matriz actual→objetivo.

## DEFINITION OF DONE
Cero cambios funcionales; todos los usos de contraseña temporal localizados; todos los supuestos single-tenant localizados; suite sigue 278/278 sin modificaciones.
