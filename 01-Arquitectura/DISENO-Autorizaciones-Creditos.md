# DISEÑO — Autorizaciones y Créditos con comprobante (staff + dueño)

> **Origen:** roles expandidos 2026-09-15 (D17) · **Estado:** diseño, sin implementar
> **Cubre:** pendiente de aprobación · solicitudes de créditos · QR dueño · app staff · delta panel

## 0. Principios
- Todo lo transaccional en `fn_*` (Regla de Oro 2); panel/app solo llaman RPC.
- Guards: `fn_es_superadmin()` para autorizar comercios; SysAdmin/Soporte/SuperAdmin
  para resolver créditos; dueño solo solicita lo propio.
- Estados como códigos (`{ok:false,codigo}`), nunca excepciones de negocio.

## 1. Comercios pendientes de aprobación (D17)
- **Mecanismo:** nuevo valor `PENDIENTE_APROBACION` en `estado_comercio`
  (D4 intacto: self-service sigue entrando `ACTIVO`).
- **Alta staff:** `fn_alta_comercio` gana `p_estado` (default `ACTIVO`; staff pasa
  `PENDIENTE_APROBACION`). El usuario dueño se crea con el alta; la **invitación
  (EF existente) se dispara al aprobar**, no al crear (sin logins huérfanos).
- **Cuarentena:** fns de ruteo/venta exigen comercio `ACTIVO`
  (`fn_resolver_sku_universal`, `fn_contexto_por_telefono`, `fn_estado_pago_cliente`,
  receiver WF-02/WF-04 vía filtro de estado). Pendiente = invisible al flujo.
- **Aprobación:** `fn_cambiar_estado_comercio(...,'ACTIVO')` (ya existe, solo
  superadmin) + invite; rechazo = `'CANCELADO'` con motivo (concepto actual, sin campo extra en v1).
- **Visibilidad:** pendientes visibles para superadmin y su creador (RLS por revisar en mig).

## 2. Solicitudes de créditos con comprobante de depósito
- **Tabla existente `tbl_compras_creditos`** (vacía, sin uso): se extiende con
  `comprobante_deposito_url text`, `id_revisor uuid NULL`, `fecha_revision timestamptz NULL`,
  `motivo_rechazo text NULL`. Se reutiliza `estado_compra_creditos`
  (PENDIENTE→PAGADA/RECHAZADA/CANCELADA).
- **Bucket nuevo `depositos-creditos`** (RLS limpio): dueño sube en
  `<id_comercio>/...`; staff lee todo; nadie más.
- **RPCs:**
  - `fn_solicitar_creditos(p_id_paquete)` — dueño; crea fila PENDIENTE (valida paquete de `tbl_paquetes_creditos`); el upload del comprobante va antes por Storage API y su path entra en `p_comprobante_url`.
  - `fn_resolver_compra_creditos(p_id_compra, p_aprueba bool, p_motivo text)` — staff; aprueba→acredita `COMPRA` atómico (cuenta+movimiento, mismo patrón que el bonus); rechaza→motivo; dueño→solo CANCELADA propia.
- **RLS:** dueño ve las propias; staff ve todas; escribir solo vía fns.
- **Reportes (lecturas directas):** depósitos (compras+comprobante), créditos+consumo
  (`tbl_movimientos_creditos` por comercio), estados, autorizaciones pendientes.

## 3. QR del dueño (tenant)
- **Backend (1 mig):** policies `qr-pagos` para dueño: UPDATE/SELECT/INSERT en path
  `<id_comercio>/...` vía `fn_es_admin_comercio(id_comercio_del_path)` — el path
  manda, no el JWT (extraer id del `name` del objeto).
- **App (Codex):** pantalla en ficha comercio: ver QR actual, subir/reemplazar
  (PNG/JPG), confirmación. Contrato: Storage API directo, sin RPC.

## 4. App móvil staff (Codex)
- Secciones con gate por rol (mismo `role_dashboard`):
  - **Autorizaciones** (superadmin): lista pendientes → ficha (datos+sucursal+creador) → aprobar (dispara invite) / rechazar.
  - **Créditos por revisar** (sysadmin/soporte/superadmin): lista PENDIENTE → ficha (paquete, monto, comprobante imagen) → aprobar / rechazar con motivo.
- Contratos: `fn_cambiar_estado_comercio`, `fn_resolver_compra_creditos`, lecturas RLS.
- Push de aviso a staff: fuera de v1 (nota para push v1.1).

## 5. Delta panel web F8
- Mismo backend: Autorizaciones + Créditos + Reportes (depósitos, créditos+consumo,
  estado comercios/usuarios/autorizaciones) con los reportes de Matriz de permisos.

## 6. Orden de implementación
1. **Backend 62:** enum `PENDIENTE_APROBACION` + `p_estado` en alta + cuarentena + QR tenant.
2. **Backend 63:** extensión compras + bucket + 2 fns + RLS.
3. **Prompts:** Codex app (staff+QR+solicitud) · Codex panel (delta reportes/autorizaciones).

## 7. Abierto (no bloquear diseño)
- Repartidor + `pago_confirmado`: precisar alcance (mala lectura otro agente).
- Validación del depósito: ¿monto de la imagen vs paquete? (manual staff en v1).
- Expiración de pendientes/solicitudes; rechazos apelables (v2).
