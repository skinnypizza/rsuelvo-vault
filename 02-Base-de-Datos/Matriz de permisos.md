| **Módulo / Recurso**      | **Acción / Permiso**                | **Superadmin** | **Admin Sistema** | **Agente Soporte** | **Admin Comercio** | **Operador / Cajero** | **Agente Logístico** |
| ------------------------- | ----------------------------------- | -------------- | ----------------- | ------------------ | ------------------ | --------------------- | -------------------- |
| **Tenants / Comercios**   | Crear / Eliminar / Suspender Tenant | **X**          | -                 | -                  | -                  | -                     | -                    |
| **Alta de comercios**     | Crear con dueño (pendiente aprobación SuperAdmin) | Autoriza (web+móvil) | **X**       | **X**              | -                  | -                     | -                    |
| **Usuarios plataforma**   | CRUD usuarios (excepto SuperAdmin/Cajero/Repartidor) | **X**       | -                 | -                  | -                  | -                     | -                    |
| **Créditos**              | Solicitar créditos (dueño) / Aprobar c/comprobante depósito (web+móvil) | **X** | Aprueba **X** | Aprueba **X** | Solicita **X** | -                     | -                    |
| **Reportes**              | Depósitos / Créditos+consumo / Estado comercios / Estado usuarios / Estado autorizaciones | Todos **X** | Créd+Estado com. | Créd+Estado com. | Propios | -                     | -                    |
| **Configuración Global**  | Modificar Parámetros / Keys         | **X**          | **X**             | -                  | -                  | -                     | -                    |
| **Auditoría Global**      | Ver Bitácora de Auditoría           | **X**          | **X**             | -                  | -                  | -                     | -                    |
| **Soporte & Tickets**     | Diagnóstico y Verificación          | **X**          | **X**             | **X**              | Lectura            | -                     | -                    |
| **Sucursales & Usuarios** | Gestionar Roles y Personal          | **X**          | -                 | -                  | **X**              | -                     | -                    |
| **Catálogo & Precios**    | Crear / Modificar Productos/SKUs    | **X**          | -                 | -                  | **X**              | -                     | -                    |
| **Inventario & Stock**    | Ajustes y Transferencias            | **X**          | -                 | -                  | **X**              | Lectura               | -                    |
| **Cobros QR / POS**       | Emitir / Validar Transacciones      | **X**          | -                 | -                  | **X**              | **X**                 | -                    |
| **Envíos & Guías**        | Crear / Asignar Pedidos             | **X**          | -                 | -                  | **X**              | **X**                 | -                    |
| **Seguimiento Logístico** | Actualizar Estado de Entrega        | **X**          | -                 | -                  | **X**              | -                     | **X**                |
