# Rsuelvo — Diseño de Base de Datos

> Documento de arquitectura y modelo de datos para Rsuelvo.
>
> **Stack objetivo:** PostgreSQL / Supabase  
> **Arquitectura:** Multi-tenant con RLS  
> **Estado:** Diseño conceptual aprobado para pasar posteriormente a ERD y `schema.sql`.

---

## 1. Contexto funcional

Rsuelvo busca ordenar el flujo de ventas de comercios informales que comercializan productos mediante lives de TikTok y gestionan las compras por WhatsApp.

El flujo comercial base es:

1. El comprador identifica un artículo durante un live.
2. Envía el SKU al vendedor por WhatsApp.
3. Rsuelvo valida el SKU.
4. Se verifica la disponibilidad del inventario.
5. Si existe stock, se crea una **reserva temporal** y se bloquea el stock.
6. Si el producto ya está reservado, el comprador puede entrar a la **lista de espera**.
7. Cuando una reserva vence o es liberada, se notifica al siguiente comprador de la lista.
8. El comprador acepta la oportunidad y obtiene una nueva reserva.
9. Se genera/responde el QR de pago.
10. El comprador envía el comprobante.
11. Se procesa y verifica el comprobante.
12. La verificación consume créditos del comercio según el servicio utilizado.
13. Si el pago es válido, se solicita y guarda la información de envío.
14. Se confirma la compra.
15. Se genera el pedido y continúa el flujo logístico.

### Principio clave

Una **reserva no es una venta**.

La reserva bloquea temporalmente el producto; la venta solamente queda confirmada después de la validación del pago.

---

# 2. Arquitectura general

La base de datos se divide en los siguientes dominios:

```text
RSUELVO
│
├── IDENTIDAD Y ACCESO
│   ├── tbl_usuarios
│   ├── tbl_roles
│   └── tbl_usuario_comercio
│
├── COMERCIOS
│   ├── tbl_comercios
│   ├── tbl_comercio_config
│   └── tbl_sucursales
│
├── CATÁLOGO
│   ├── tbl_categorias
│   ├── tbl_productos
│   └── tbl_variantes
│
├── INVENTARIO
│   ├── tbl_inventario
│   └── tbl_inventario_movimientos
│
├── CLIENTES
│   └── tbl_clientes
│
├── VENTAS
│   ├── tbl_reservas
│   ├── tbl_lista_espera
│   ├── tbl_pedidos
│   └── tbl_pedido_detalles
│
├── PAGOS
│   ├── tbl_metodos_pago
│   ├── tbl_qr_cobros
│   ├── tbl_comprobantes_pago
│   └── tbl_verificaciones
│
├── CRÉDITOS
│   ├── tbl_cuentas_creditos
│   ├── tbl_movimientos_creditos
│   ├── tbl_servicios_creditos
│   ├── tbl_paquetes_creditos
│   ├── tbl_compras_creditos
│   └── tbl_pagos_creditos
│
├── LOGÍSTICA
│   ├── tbl_envios
│   └── tbl_env_seguimiento_estados
│
└── AUDITORÍA
    └── tbl_logs_auditoria
```

---

# 3. Multi-tenancy

Todo dato perteneciente a un comercio debe estar asociado a `id_comercio`, directa o indirectamente.

El aislamiento se implementará mediante **Row Level Security (RLS)** de PostgreSQL/Supabase.

Conceptualmente:

```text
Usuario autenticado
       ↓
tbl_usuario_comercio
       ↓
id_comercio
       ↓
RLS
       ↓
Datos permitidos del tenant
```

No se debe confiar exclusivamente en que el frontend o n8n envíe correctamente `id_comercio`.

La seguridad debe estar garantizada por PostgreSQL.

---

# 4. Roles del sistema

## 4.1 ROLE_SUPERADMIN

Owner global de Rsuelvo.

- Acceso total.
- Exento del aislamiento RLS según la arquitectura de Supabase/PostgreSQL.
- Superusuario.
- Gestión global de tenants.
- Gestión de licencias.
- Gestión de llaves maestras.
- Configuración financiera.

---

## 4.2 ROLE_SYSADMIN

Administrador de infraestructura.

Puede gestionar:

- Infraestructura.
- Logs.
- Monitoreo.
- Parámetros globales del sistema.

### Restricción estricta

No debe poder consultar mediante RLS:

- Saldos de comercios.
- Cuentas bancarias.
- Transacciones QR.
- Datos sensibles de clientes de tenants.

---

## 4.3 ROLE_SUPPORT

Agente de mesa de ayuda.

Acceso:

- Solo lectura.
- Datos operativos necesarios para soporte.
- Sin acceso financiero sensible.
- Respetando aislamiento por tenant.

---

## 4.4 ROLE_TENANT_ADMIN

Administrador de un comercio.

Control sobre su `id_comercio`:

- Sucursales.
- Usuarios.
- Catálogo.
- Categorías.
- Productos.
- Variantes.
- Precios.
- Inventario.
- Reservas.
- Lista de espera.
- Pedidos.
- Logística.
- Configuración del comercio.

---

## 4.5 ROLE_TENANT_CASHIER

Operador/cajero.

### Restricción por sucursal

Un `ROLE_TENANT_CASHIER` pertenece a **una única sucursal**.

No debe tener acceso operativo a otras sucursales del mismo comercio.

Su alcance es:

```text
ROLE_TENANT_CASHIER
        │
        ▼
   id_comercio
        │
        ▼
   id_sucursal
        │
        ▼
Datos operativos de esa sucursal
```

Puede:

- Emitir cobros QR.
- Verificar cobros/comprobantes.
- Consultar stock de su sucursal.
- Registrar clientes.
- Gestionar operaciones de despacho correspondientes a su sucursal.

### Modelo recomendado

La asignación de sucursal se realizará en `tbl_usuario_comercio` mediante `id_sucursal`.

Para un cashier:

```text
id_usuario
id_comercio
id_rol = ROLE_TENANT_CASHIER
id_sucursal = sucursal asignada
```

Debe existir una restricción que garantice que un cashier no tenga simultáneamente múltiples sucursales activas.

---

## 4.6 ROLE_LOGISTICS_AGENT

Repartidor externo.

Acceso exclusivo a:

- Datos necesarios para despacho.
- Datos necesarios para entrega.
- Actualización de `tbl_env_seguimiento_estados`.

Debe acceder solamente a la información logística que necesita para realizar su trabajo.

---

# 5. Usuarios y asignación de roles

## 5.1 `tbl_usuarios`

```text
id_usuario UUID PK
nombre
apellido
telefono
email
auth_user_id UUID
activo
created_at
updated_at
```

`auth_user_id` representa la relación con el usuario de autenticación de Supabase.

---

## 5.2 `tbl_roles`

```text
id_rol
codigo
nombre
nivel
```

Roles:

```text
ROLE_SUPERADMIN
ROLE_SYSADMIN
ROLE_SUPPORT
ROLE_TENANT_ADMIN
ROLE_TENANT_CASHIER
ROLE_LOGISTICS_AGENT
```

---

## 5.3 `tbl_usuario_comercio`

Tabla de relación entre usuarios, comercios, roles y alcance operativo.

```text
id
id_usuario
id_comercio
id_rol
id_sucursal NULL
activo
created_at
```

### Regla

`id_sucursal` es obligatorio para:

```text
ROLE_TENANT_CASHIER
ROLE_LOGISTICS_AGENT
```

En el caso de `ROLE_TENANT_CASHIER`, representa exactamente una sucursal.

Para roles globales o administrativos no se utiliza como restricción de alcance de la misma forma.

---

# 6. Comercios

## 6.1 `tbl_comercios`

```text
id_comercio UUID PK
nombre_comercial
razon_social
nit
telefono
email
estado
created_at
updated_at
```

Estados:

```text
ACTIVO
SUSPENDIDO
BLOQUEADO
CANCELADO
```

---

## 6.2 `tbl_comercio_config`

Configuración específica del comercio.

```text
id_comercio PK/FK
tiempo_reserva_minutos
tiempo_aceptacion_lista_espera_minutos
max_lista_espera_por_producto
verificacion_automatica
...
```

Los tiempos deben ser configurables y no estar hardcodeados dentro de n8n.

Ejemplo:

```text
Reserva: 10 minutos
Aceptación de oportunidad: 2 minutos
Máximo de personas en lista: 5
```

---

# 7. Sucursales

## `tbl_sucursales`

```text
id_sucursal UUID PK
id_comercio FK
nombre
direccion
referencia
latitud
longitud
telefono
activo
created_at
```

Relación:

```text
COMERCIO
   │
   ├── Sucursal Central
   ├── Sucursal Norte
   └── Sucursal Sur
```

El inventario pertenece a una sucursal.

---

# 8. Catálogo

## 8.1 `tbl_categorias`

```text
id_categoria
id_comercio
nombre
descripcion
activo
```

## 8.2 `tbl_productos`

```text
id_producto UUID PK
id_comercio FK
id_categoria FK
nombre
descripcion
imagen_url
activo
created_at
updated_at
```

## 8.3 `tbl_variantes`

```text
id_variante UUID PK
id_producto FK
sku
nombre
precio
activo
```

El SKU pertenece a la variante.

Ejemplo:

```text
Producto:
Polera Oversize

Variantes:
POL-001-NEG-S
POL-001-NEG-M
POL-001-NEG-L
POL-001-BLA-S
POL-001-BLA-M
```

Restricción:

```text
UNIQUE(id_comercio, sku)
```

---

# 9. Inventario

## `tbl_inventario`

```text
id_inventario UUID PK
id_sucursal FK
id_variante FK
stock_actual
stock_reservado
updated_at
```

El stock disponible puede calcularse:

```text
stock_disponible =
stock_actual - stock_reservado
```

No es necesario almacenar `stock_disponible` si puede calcularse de forma segura.

---

## 9.1 `tbl_inventario_movimientos`

Registro histórico de cambios.

```text
id_movimiento
id_comercio
id_sucursal
id_variante
tipo
cantidad
referencia_tipo
referencia_id
usuario_id
created_at
```

Tipos:

```text
ENTRADA
SALIDA
RESERVA
LIBERACION_RESERVA
VENTA
AJUSTE
DEVOLUCION
```

Permite reconstruir por qué el inventario tiene determinado valor.

---

# 10. Clientes

## `tbl_clientes`

```text
id_cliente UUID PK
id_comercio FK
nombre
telefono
telefono_whatsapp
email
created_at
updated_at
```

Restricción recomendada:

```text
UNIQUE(id_comercio, telefono_whatsapp)
```

El mismo cliente puede existir en diferentes comercios sin mezclar información.

---

# 11. Reservas

La reserva representa el derecho temporal de un comprador a completar una compra.

## `tbl_reservas`

```text
id_reserva UUID PK
id_comercio FK
id_sucursal FK
id_variante FK
id_cliente FK
id_pedido FK NULL
origen
estado
cantidad
fecha_inicio
fecha_expiracion
fecha_finalizacion
created_at
updated_at
```

### `origen`

```text
DIRECTA
LISTA_ESPERA
```

### `estado`

```text
ACTIVA
PAGO_VALIDANDO
CONFIRMADA
VENCIDA
CANCELADA
LIBERADA
```

Regla crítica:

> Una reserva activa bloquea el producto temporalmente, pero no representa una venta confirmada.

---

# 12. Lista de espera

El concepto de turnos se conserva funcionalmente, pero la tabla se denomina **lista de espera** para evitar mantener dos conceptos redundantes en el modelo de negocio.

## `tbl_lista_espera`

```text
id_lista_espera UUID PK
id_comercio FK
id_sucursal FK
id_variante FK
id_cliente FK

posicion
estado

fecha_ingreso
fecha_notificacion
fecha_aceptacion
fecha_expiracion

id_reserva_generada NULL

created_at
updated_at
```

### Estados

```text
ESPERANDO
NOTIFICADO
ACEPTADO
CONVERTIDO_RESERVA
RECHAZADO
VENCIDO
CANCELADO
```

### Funcionamiento

Ejemplo:

```text
SKU = POL-001-M

Lista de espera
────────────────────────
#1 → Cliente A → ESPERANDO
#2 → Cliente B → ESPERANDO
#3 → Cliente C → ESPERANDO
```

Cuando la reserva actual vence:

```text
Reserva vence
     ↓
Liberar reserva
     ↓
Buscar posición #1
     ↓
Notificar cliente
     ↓
¿Acepta?
   /   \
 NO     SI
 │       │
 ↓       ↓
Siguiente  Crear reserva
```

### Importante

La lista de espera no garantiza una venta.

Representa una posición para obtener una oportunidad de reserva.

---

# 13. Flujo de reservas y lista de espera

```text
SOLICITUD SKU
      │
      ▼
VALIDAR SKU
   /       \
 NO         SI
 │           │
 ▼           ▼
FIN      VALIDAR INVENTARIO
             │
        ┌────┴────┐
        │         │
       SI         NO
        │         │
        ▼         ▼
 CREAR RESERVA  ¿RESERVADO?
                    │
               ┌────┴────┐
               │         │
              NO         SI
               │         │
               ▼         ▼
          SIN STOCK   ¿LISTA DISPONIBLE?
                         │
                    ┌────┴────┐
                    │         │
                   NO         SI
                    │         │
                    ▼         ▼
                   FIN    CREAR LISTA
                              │
                              ▼
                         ESPERAR
                              │
                              ▼
                      RESERVA LIBERADA
                              │
                              ▼
                    SIGUIENTE POSICIÓN
                              │
                              ▼
                         NOTIFICAR
                              │
                     ┌────────┴────────┐
                    NO                 SI
                    │                   │
                    ▼                   ▼
               SIGUIENTE          CREAR RESERVA
                                     │
                                     ▼
                                    PAGO
```

---

# 14. Pedidos

## `tbl_pedidos`

```text
id_pedido UUID PK
id_comercio FK
id_sucursal FK
id_cliente FK
numero_pedido
estado
subtotal
descuento
total
id_reserva FK NULL
fecha_creacion
fecha_confirmacion
created_at
updated_at
```

### Estados

```text
CREADO
ESPERANDO_PAGO
PAGO_RECIBIDO
PAGO_VALIDANDO
PAGADO
PREPARANDO
DESPACHADO
ENTREGADO
CANCELADO
```

---

## 14.1 `tbl_pedido_detalles`

```text
id_detalle
id_pedido
id_variante
sku_snapshot
nombre_snapshot
precio_unitario
cantidad
subtotal
```

Los campos `snapshot` conservan la información histórica del pedido aunque posteriormente cambien el SKU, nombre o precio del producto.

---

# 15. Pagos y QR

La arquitectura separa:

```text
QR
 ↓
Cobro
 ↓
Comprobante
 ↓
Verificación
```

## 15.1 `tbl_metodos_pago`

```text
id_metodo_pago
id_comercio
nombre
tipo
proveedor
activo
```

---

## 15.2 `tbl_qr_cobros`

```text
id_qr_cobro
id_comercio
id_pedido
id_metodo_pago
monto
referencia
qr_url
estado
created_at
```

---

## 15.3 `tbl_comprobantes_pago`

```text
id_comprobante UUID PK
id_comercio FK
id_pedido FK
id_cliente FK
tipo_archivo
archivo_url
monto_detectado
fecha_detectada
numero_operacion
nombre_pagador
estado
created_at
```

Estados:

```text
RECIBIDO
PROCESANDO
VALIDO
INVALIDO
RECHAZADO
```

El archivo debe almacenarse preferentemente en Supabase Storage y guardar en PostgreSQL su referencia/path.

---

# 16. Verificaciones

Un comprobante y una verificación son entidades diferentes.

## `tbl_verificaciones`

```text
id_verificacion UUID PK
id_comercio FK
id_comprobante FK
id_pedido FK
tipo_verificacion
estado
resultado
confianza
creditos_consumidos
fecha_inicio
fecha_fin
created_at
```

Tipos posibles:

```text
OCR
VALIDACION_MONTO
VALIDACION_FECHA
VALIDACION_OPERACION
VALIDACION_QR
VERIFICACION_COMPLETA
```

Una verificación puede consumir créditos.

---

# 17. Sistema de créditos

Los créditos se modelan mediante una cuenta y un ledger de movimientos.

No se recomienda depender únicamente de:

```text
comercios.creditos = 500
```

La fuente de auditoría debe ser el historial de movimientos.

---

## 17.1 `tbl_cuentas_creditos`

```text
id_cuenta_creditos UUID PK
id_comercio FK UNIQUE
saldo_actual
updated_at
```

---

## 17.2 `tbl_movimientos_creditos`

```text
id_movimiento UUID PK
id_comercio FK
id_cuenta_creditos FK
tipo
cantidad
saldo_anterior
saldo_posterior
concepto
referencia_tipo
referencia_id
created_at
```

Tipos:

```text
COMPRA
BONIFICACION
AJUSTE
CONSUMO_VERIFICACION
DEVOLUCION
EXPIRACION
```

Ejemplo:

```text
Saldo inicial       +100
Compra créditos     +500
Verificación #123     -1
Verificación #124     -1
Verificación #125     -5
────────────────────────
Saldo                593
```

---

# 18. Tarifario de servicios que consumen créditos

## `tbl_servicios_creditos`

```text
id_servicio
codigo
nombre
descripcion
costo_creditos
activo
```

Ejemplo:

```text
VERIFICACION_COMPROBANTE
OCR_COMPROBANTE
VALIDACION_AVANZADA
```

El costo no debe estar hardcodeado en n8n.

---

# 19. Consumo de créditos

Flujo:

```text
Comprobante
     ↓
Crear verificación
     ↓
Consultar costo del servicio
     ↓
¿Saldo suficiente?
   /           \
 NO             SI
 │               │
 ▼               ▼
Bloquear       Consumir
verificación   créditos
                 │
                 ▼
          Registrar movimiento
                 │
                 ▼
          Ejecutar verificación
```

El consumo queda registrado en `tbl_movimientos_creditos`:

```text
tipo = CONSUMO_VERIFICACION
referencia_tipo = VERIFICACION
referencia_id = UUID de la verificación
cantidad = -N
```

---

# 20. Compra de créditos

## 20.1 `tbl_paquetes_creditos`

```text
id_paquete
nombre
creditos
precio
moneda
activo
```

Ejemplo conceptual:

```text
Pack Básico → 100 créditos
Pack Pro    → 500 créditos
Pack Empresa → 1000 créditos
```

Los precios son configurables y quedan fuera de este diseño hasta definir el pricing final.

---

## 20.2 `tbl_compras_creditos`

```text
id_compra UUID PK
id_comercio FK
id_paquete FK
creditos_comprados
monto
moneda
estado
fecha_creacion
fecha_pago
```

Estados:

```text
PENDIENTE
PAGADA
RECHAZADA
CANCELADA
```

---

## 20.3 `tbl_pagos_creditos`

```text
id_pago
id_compra
metodo_pago
referencia_externa
monto
estado
fecha_pago
```

Flujo:

```text
Comercio
   ↓
Compra paquete
   ↓
Pago
   ↓
PAGO CONFIRMADO
   ↓
Agregar créditos
   ↓
Registrar movimiento
```

---

# 21. Flujo completo de créditos + verificación

```text
CLIENTE
   │
   ▼
ENVÍA COMPROBANTE
   │
   ▼
tbl_comprobantes_pago
   │
   ▼
tbl_verificaciones
   │
   ▼
¿CRÉDITOS DISPONIBLES?
   │
 ┌─┴──────────┐
NO            SI
│              │
▼              ▼
Bloquear     Consumir
verificación créditos
               │
               ▼
       Movimiento de créditos
               │
               ▼
          Verificación
          /           \
       VÁLIDO        INVÁLIDO
         │              │
         ▼              ▼
   Confirmar pedido   Rechazar
```

---

# 22. Logística

## `tbl_envios`

```text
id_envio UUID PK
id_comercio FK
id_pedido FK
id_sucursal FK
direccion
referencia
telefono_contacto
id_repartidor NULL
estado
numero_guia
created_at
updated_at
```

Estados:

```text
PENDIENTE
PREPARANDO
ASIGNADO
EN_RUTA
ENTREGADO
NO_ENTREGADO
CANCELADO
```

---

## 22.1 `tbl_env_seguimiento_estados`

```text
id_seguimiento
id_envio
estado
observacion
latitud NULL
longitud NULL
created_at
usuario_id
```

Ejemplo:

```text
PENDIENTE
   ↓
PREPARANDO
   ↓
ASIGNADO
   ↓
EN_RUTA
   ↓
ENTREGADO
```

---

# 23. Auditoría

## `tbl_logs_auditoria`

```text
id_log UUID PK
id_comercio NULL
id_usuario NULL
accion
tabla
registro_id
datos_anteriores JSONB
datos_nuevos JSONB
ip
user_agent
created_at
```

Debe permitir responder preguntas como:

- ¿Quién modificó el stock?
- ¿Quién cambió el precio?
- ¿Quién verificó un comprobante?
- ¿Cuándo se consumieron créditos?
- ¿Qué usuario canceló una reserva?
- ¿Qué operación cambió un pedido?

---

# 24. Reglas críticas de integridad

Estas reglas deben protegerse desde PostgreSQL y no depender únicamente de n8n.

## SKU único por comercio

```text
UNIQUE(id_comercio, sku)
```

## Cliente único por WhatsApp dentro del comercio

```text
UNIQUE(id_comercio, telefono_whatsapp)
```

## Una sola reserva activa por variante

Conceptualmente:

```text
UNIQUE(id_variante)
WHERE estado = 'ACTIVA'
```

Esto evita que dos ejecuciones concurrentes creen dos reservas para el mismo último producto.

## Lista de espera

Debe existir una única posición activa por variante:

```text
UNIQUE(id_variante, posicion)
WHERE estado IN ('ESPERANDO', 'NOTIFICADO')
```

La gestión de posiciones deberá hacerse de forma transaccional para evitar colisiones cuando alguien abandone o avance en la lista.

## Cashier

Un `ROLE_TENANT_CASHIER` debe tener una única asignación de sucursal activa.

---

# 25. Concurrencia de reservas

Este es uno de los puntos más importantes de la implementación.

Caso:

```text
Stock disponible = 1

Cliente A → solicita SKU
Cliente B → solicita SKU
```

Ambas solicitudes pueden llegar casi simultáneamente.

No se debe confiar en:

```text
n8n consulta stock
↓
n8n decide
↓
n8n crea reserva
```

porque ambas ejecuciones podrían leer:

```text
stock = 1
```

La creación de reserva y bloqueo de inventario debe ejecutarse de forma **atómica/transaccional en PostgreSQL**.

Resultado esperado:

```text
Cliente A → RESERVA ACTIVA
Cliente B → LISTA DE ESPERA
```

Nunca:

```text
Cliente A → RESERVA
Cliente B → RESERVA
```

sobre la misma unidad disponible.

---

# 26. Regla de inventario

El flujo comercial recomendado es:

```text
SOLICITUD
   ↓
RESERVA
   ↓
PAGO
   ↓
VERIFICACIÓN
   ↓
CONFIRMACIÓN
   ↓
VENTA
```

Por tanto:

### Al crear reserva

```text
stock_reservado += cantidad
```

### Al liberar/vencer reserva

```text
stock_reservado -= cantidad
```

### Al confirmar venta

La unidad pasa de reservada a vendida y se registra el movimiento de inventario correspondiente.

Una reserva nunca debe considerarse automáticamente una venta.

---

# 27. Modelo relacional resumido

```text
                         ┌──────────────┐
                         │  COMERCIOS   │
                         └──────┬───────┘
                                │
             ┌──────────────────┼──────────────────┐
             │                  │                  │
             ▼                  ▼                  ▼
        SUCURSALES          USUARIOS           CRÉDITOS
             │                  │                  │
             │                  ▼                  ├── CUENTAS
             │          USUARIO_COMERCIO           ├── MOVIMIENTOS
             │                                     ├── SERVICIOS
             │                                     ├── PAQUETES
             │                                     └── COMPRAS
             │
             ▼
        INVENTARIO
             │
             ▼
         VARIANTE
             │
             ▼
         PRODUCTO
             │
             │
       ┌─────┴────────────────┐
       │                      │
       ▼                      ▼
    RESERVA            LISTA DE ESPERA
       │                      │
       └──────────┬───────────┘
                  ▼
                PEDIDO
                  │
          ┌───────┴────────┐
          │                │
          ▼                ▼
       QR COBRO       COMPROBANTE
                           │
                           ▼
                      VERIFICACIÓN
                           │
                           ▼
                   CONSUMO CRÉDITOS
                           │
                           ▼
                         PAGO
                           │
                           ▼
                         ENVÍO
                           │
                           ▼
                    SEGUIMIENTO
```

---

# 28. Estructura final de tablas

```text
IDENTIDAD
├── tbl_usuarios
├── tbl_roles
└── tbl_usuario_comercio

COMERCIO
├── tbl_comercios
├── tbl_comercio_config
└── tbl_sucursales

CATÁLOGO
├── tbl_categorias
├── tbl_productos
└── tbl_variantes

INVENTARIO
├── tbl_inventario
└── tbl_inventario_movimientos

CLIENTES
└── tbl_clientes

VENTAS
├── tbl_reservas
├── tbl_lista_espera
├── tbl_pedidos
└── tbl_pedido_detalles

PAGOS
├── tbl_metodos_pago
├── tbl_qr_cobros
├── tbl_comprobantes_pago
└── tbl_verificaciones

CRÉDITOS
├── tbl_cuentas_creditos
├── tbl_movimientos_creditos
├── tbl_servicios_creditos
├── tbl_paquetes_creditos
├── tbl_compras_creditos
└── tbl_pagos_creditos

LOGÍSTICA
├── tbl_envios
└── tbl_env_seguimiento_estados

AUDITORÍA
└── tbl_logs_auditoria
```

---

# 29. Siguiente etapa de implementación

Este documento representa el **modelo conceptual aprobado**.

La siguiente etapa recomendada es convertirlo en:

1. ERD completo.
2. Definición exacta de PK/FK.
3. Tipos de datos PostgreSQL.
4. `ENUM` o `CHECK constraints`.
5. Índices.
6. Constraints de unicidad.
7. Transacciones para reservas e inventario.
8. Funciones PostgreSQL necesarias.
9. Políticas RLS de Supabase.
10. Triggers de auditoría cuando corresponda.
11. `schema.sql`.
12. Seed inicial de roles y configuraciones.

La implementación de n8n deberá consumir esta capa de datos mediante operaciones transaccionales y no replicar reglas críticas de integridad únicamente en los workflows.
