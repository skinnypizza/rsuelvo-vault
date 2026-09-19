# PROMPT ANTIGRAVITY — Móvil: avisos QR/sucursal faltantes

## Contexto (código `/home/nico/StudioProjects/rsuelvo`)
Un comercio nuevo sin QR ni sucursales rompe el flujo de venta en silencio
(caso FEE real). Reglas: jamás `service_role`, español, economía, sin capturas,
`flutter analyze` limpio + tests con mocks (sin datos reales).

## Cambio (sin cambios BD)
En el dashboard/config del dueño, banner de advertencia cuando falte:
1. **QR**: listar `qr-pagos/<id_comercio>/` por Storage API; si vacío → aviso
   «Subí tu QR para cobrar» con botón a `/qr-comercio`.
2. **Sucursales**: si el comercio no tiene sucursales activas → aviso con botón
   a sucursales. (Normalmente existe 1 por el alta; es red de seguridad.)
Solo dueño; no bloquear el resto de la pantalla.

## Verificación y entregable
Tests (casos falta/no-falta) + commit. Si un contrato no existe, reportar.
