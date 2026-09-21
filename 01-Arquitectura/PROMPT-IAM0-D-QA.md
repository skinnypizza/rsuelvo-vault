# IAM-0/D — Suite de aceptación IAM + regresión (diseño, sin tocar producción)

## OBJETIVO
Diseñar la suite de aceptación que se ejecutará después de IAM-1/IAM-3 y fijar la línea base de regresión de los módulos operativos. CERO cambios en producción.

## ALCANCE EXACTO
Solo diseñar y documentar casos + verificar estado verde actual de suites existentes. No modificar código, BD ni desplegar.

## REPOSITORIO
Vault (`07-Control-de-Calidad/`) como salida; lectura de `rsuelvo-flutter` (tests), `rsuelvo-web` (tests), SQL canónico y matrices (`Matriz-Consistencia-WF-BD-HU.md`, `03-Correlacion-Wireframes-HU.md`).

## ARCHIVOS/RUTAS CANÓNICAS A REVISAR
- `07-Control-de-Calidad/` (formato de auditorías previas)
- Suites actuales: `flutter test` (278), tests web (`permissions.test.ts`, `auth-flows.test.tsx`), suite SQL/RLS de aislamiento (11 casos)
- Contratos: EF invite v8, `fn_gestionar_vinculo`, `fn_editar_usuario`, RLS usuarios/vínculos
- DoD global §5 del doc orquestador (criterios 1-15 a cubrir)

## DEPENDENCIAS
Informes A/B/C (para alinear casos con hallazgos reales). Puede empezar el esqueleto en paralelo.

## CONTRATOS QUE NO SE PUEDEN ROMPER
- Reglas de Oro 5 (DoD por HU) y 7/9 (idempotencia/auditoría) en cada caso diseñado
- Módulos operativos (pedidos/pagos/inventario/créditos/logística) con regresión explícita por caso

## CAMBIOS PERMITIDOS
Crear el documento de suite en `07-Control-de-Calidad/`. Nada más.

## CAMBIOS PROHIBIDOS
Modificar tests/código existentes, tocar BD/cloud, ejecutar flujos con datos reales de FEE/FER, cambiar producción.

## PRUEBAS REQUERIDAS
Confirmar línea base verde actual (flutter 278, web build/tests, aislamiento SQL 11) por ejecución read-only y dejarla registrada como baseline fechada.

## ENTREGABLES
`07-Control-de-Calidad/Suite-Aceptacion-IAM.md` con casos: invitación nueva/idempotente/expirada/usada/revocada/email-existente/email-nuevo/rol-no-permitido/sucursal-otro-tenant/atacante-sin-permisos/sin-password-en-responses; multi-comercio (2 roles iguales, 2 distintos, cambio repetido, revocación del seleccionado, restart); revocación unilateral (User A Admin C1 + Cashier C2); recovery privilegiado; regresión por módulo operativo. Cada caso: precondiciones con fósiles (jamás FEE/FER reales), pasos, resultado esperado, criterio pass/fail.

## DEFINITION OF DONE
Suite documentada cubriendo los 15 criterios del DoD global; baseline verde registrada; cero cambios en producción.
