# IAM-3/FLUTTER — Selector multi-comercio (implementación, SOLO tras aprobación del contrato)

## OBJETIVO
Implementar `01-Arquitectura/D-IAM-MULTICOMERCIO-FLUTTER.md`: identidad + N membresías + contexto explícito seleccionable, sin mezclar tenants.

## ALCANCE EXACTO
Solo auth/selección/caches. No tocar backend, roles, ni pantallas operativas salvo invalidación de providers.

## REPOSITORIO
`skinnypizza/rsuelvo-flutter`, rama `main`.

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `01-Arquitectura/D-IAM-MULTICOMERCIO-FLUTTER.md` (contrato — manda la versión revisada)
- `lib/features/auth/auth_controller.dart` (`selected.first:130-135` a reemplazar; `recargarPerfil` a reutilizar)
- `lib/features/auth/auth_model.dart` (AppUser como vista derivada; flags por membresía seleccionada)
- `07-Control-de-Calidad/Informe-IAM0-B-Flutter.md` (providers no tenant-keyed, caches a sanear)
- `lib/features/shell/app_shell.dart` (selector en perfil/header), `lib/core/router.dart` (bootstrap 0/1/N)

## DEPENDENCIAS
Contrato aprobado. IAM-2B backend ya desplegado (lifecycle disponible).

## CONTRATOS QUE NO SE PUEDEN ROMPER
- RLS/fns como autoridad; `id_comercio` del cliente nunca autoriza
- Suite 285+ verde durante todo el cambio (actualizar, no reducir); analyze 0
- Flujos operativos intactos; `password_temporal` sigue en cero

## CAMBIOS PERMITIDOS
Modelo Membership + SelectedMembership + `noMemberships`; selector UI; persistencia `selected_membership:<auth_user_id>` con validación/purga; transición `switchingMembership` con bloqueo UI + family/generation anti-stale; reconciliación en bootstrap/recargar/resume/accept/pérdida-acceso; segunda invitación NO cambia contexto.

## CAMBIOS PROHIBIDOS
Backend/schema; reescribir pantallas operativas; permisos dinámicos; MFA; secretos en storage/logs; `service_role`.

## PRUEBAS REQUERIDAS
E2E del contrato con mocks: A persisted ajeno jamás restaura · B persisted no-vigente se descarta · C N sin válida→selector · D request tardío de A no aparece en B · E revocación+2→selector · F revocación+1→auto · G revocación+0→`noMemberships` con invitaciones accesibles · H logout/login distinto sin contaminación · grep `selected.first` en `lib/` cero.

## ENTREGABLES
Commit en `main` + SHA para revisión.

## DEFINITION OF DONE
Sin `selected.first`; sin mezcla entre tenants (evidencia); analyze 0; suite verde; vault actualizado.
