# IAM-1/FLUTTER — Eliminar contraseña temporal (implementación)

## OBJETIVO
Eliminar TODAS las superficies que consumen/presentan `password_temporal` y cambiar la UX a estados de invitación. Depende del backend IAM-1 (contrato EF v9).

## ALCANCE EXACTO
Solo invite/usuarios/autorizaciones. Prohibido tocar selección de membresía (IAM-3) o navegación por rol.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `07-Control-de-Calidad/Informe-IAM0-B-Flutter.md` (mapa exacto de superficies — cubrirlas TODAS)
- `lib/features/usuarios/usuario_invite_dialog.dart` (diálogo + Copiar)
- `lib/features/usuarios/usuarios_staff_screen.dart`, `usuarios_repository.dart`, modelos con `passwordTemporal`
- `lib/features/autorizaciones/` (screen+repository+tests que asumen el secreto)
- `test/usuarios_global_repository_test.dart`, `test/autorizaciones_repository_test.dart` (actualizar expectativas)
- `01-Arquitectura/D-IAM-INVITACIONES.md` (flujos nuevo/existente a reflejar en UX)

## DEPENDENCIAS
Backend IAM-1 desplegado (EF v9 + `fn_aceptar_invitacion`). Sin eso, solo preparar sin integrar.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Jamás mostrar/copiar/loggear secreto; jamás `service_role`; suite 278 debe quedar verde (actualizada, no reducida)
- Flujos operativos (pedidos/pagos/inventario/logística/créditos) intactos

## CAMBIOS PERMITIDOS
Eliminar `_PasswordDialog`/`passwordTemporal`/Copiar/textos de compartir · UX "Invitación enviada..." + estados Pendiente/Aceptada/Vencida/Revocada · actualizar repos/tests al contrato v9 · `flutter analyze` limpio.

## CAMBIOS PROHIBIDOS
Selector multi-comercio, `selected.first`, providers tenant-keyed (IAM-3) · MFA · N-4 · inventar auth paralelo.

## PRUEBAS REQUERIDAS
Tests con mocks: invite muestra estado (no secreto), reintento idempotente, vencida/revocada visibles, existente vs nuevo, grep `passwordTemporal|Clipboard` sobre `lib/` debe dar CERO resultados funcionales.

## ENTREGABLES
Commit en `main` con analyze limpio + suite verde (nº tests informado).

## DEFINITION OF DONE
Cero `passwordTemporal` en `lib/`; UX de estados verificada; suite verde; sin cambios fuera del alcance.
