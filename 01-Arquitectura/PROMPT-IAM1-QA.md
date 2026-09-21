# IAM-1/QA — Aceptación invite + regresión (ejecución)

## OBJETIVO
Ejecutar la suite IAM-D de invitaciones contra backend+Flutter+Web desplegados y certificar IAM-1 (o reportar bloqueantes). Último del lote.

## ALCANCE EXACTO
Solo casos invite + regresión módulos operativos. Prohibido modificar código/BD/producción.

## REPOSITORIO
Vault `07-Control-de-Calidad/Suite-Aceptacion-IAM.md` (casos IAM-D + REG-D).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `Suite-Aceptacion-IAM.md` (casos: nueva/idempotente/expirada/usada/revocada/existente/nuevo/rol-no-permitido/sucursal-otro-tenant/atacante/sin-password + REG-D pedidos/pagos/inventario/créditos/logística)
- `01-Arquitectura/D-IAM-INVITACIONES.md` (comportamiento esperado)
- EF-doc v9 + informes B/C (superficies a probar en cada cliente)

## DEPENDENCIAS
Backend + Flutter + Web IAM-1 desplegados. Sin eso, NO ejecutar (reportar pendiente).

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Solo fósiles de prueba (jamás FEE/FER reales); datos limpios al cerrar; Reglas 7/9 en cada caso

## CAMBIOS PERMITIDOS
Crear `07-Control-de-Calidad/Reporte-IAM1.md` con veredicto por caso. Nada más.

## CAMBIOS PROHIBIDOS
Tocar código/BD/cloud, ejecutar con datos reales, declarar verde sin evidencia.

## PRUEBAS REQUERIDAS
Todos los IAM-D + REG-D con pass/fail + evidencia (request/response anonimizada, SHA de builds probados).

## ENTREGABLES
`Reporte-IAM1.md`: tabla caso→resultado→evidencia + veredicto IAM-1 (APROBADO / BLOQUEADO con lista).

## DEFINITION OF DONE
100% casos ejecutados; ningún secreto en responses/UI/logs (grep negativo incluido); regresión verde; reporte archivado + ESTADO-EJECUCION.
