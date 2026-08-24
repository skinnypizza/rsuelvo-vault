### Funciones principales que n8n debería consumir

La arquitectura queda aproximadamente:
`n8n`
 `│`
 `├── fn_solicitar_reserva()`
 `│`
 `├── fn_agregar_lista_espera()`
 `│`
 `├── fn_aceptar_lista_espera()`
 `│`
 `├── fn_crear_pedido_desde_reserva()`
 `│`
 `├── fn_consumir_creditos()`
 `│`
 `├── fn_confirmar_pago()`
 `│`
 `├── fn_rechazar_verificacion()`
 `│`
 `└── fn_crear_envio()`
          `│`
          `▼`
     `PostgreSQL`
          `│`
     `┌────┴────┐`
     `│ reglas  │`
     `│ negocio │`
     `└────┬────┘`
          `▼`
       `datos`
Por ejemplo, n8n **no debería hacer**:
`Consultar stock`
      `↓`
`IF stock > 0`
      `↓`
`Crear reserva`
      `↓`
`Actualizar stock`
Debe hacer simplemente:
`n8n`
 `↓`
`RPC fn_solicitar_reserva()`
 `↓`
`PostgreSQL realiza todo atómicamente`
 `↓`
`RESERVA_CREADA / SIN_STOCK`


. El siguiente paso que recomiendo es hacer una **auditoría del SQL contra el ERD**, especialmente de las relaciones tenant→sucursal→variante→reserva→pedido, y después separar el archivo en:

```
01_extensions.sql
02_enums.sql
03_tables.sql
04_constraints.sql
05_indexes.sql
06_functions.sql
07_triggers.sql
08_rls.sql
09_views.sql
10_seed.sql
11_storage.sql
12_cron.sql
```

Ubicacion de SQL BASE:  /home/nico/RSUELVO

