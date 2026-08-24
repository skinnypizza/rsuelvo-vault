-- ============================================================
-- RSUELVO v2 :: 10. SEED — DATOS INICIALES
-- ============================================================

set search_path = rsuelvo, public;

insert into tbl_roles (codigo,nombre,nivel) values
('ROLE_SUPERADMIN','Superadministrador',100),
('ROLE_SYSADMIN','Administrador de infraestructura',90),
('ROLE_SUPPORT','Soporte',50),
('ROLE_TENANT_ADMIN','Administrador del comercio',30),
('ROLE_TENANT_CASHIER','Cajero',20),
('ROLE_LOGISTICS_AGENT','Repartidor',10)
on conflict (codigo) do nothing;


insert into tbl_servicios_creditos(codigo,nombre,descripcion,costo_creditos)
values
('VERIFICACION_COMPROBANTE','Verificación de comprobante','Verificación completa de un comprobante de pago',1),
('OCR_COMPROBANTE','OCR de comprobante','Extracción de información del comprobante',1),
('VALIDACION_AVANZADA','Validación avanzada','Validaciones adicionales del comprobante',3)
on conflict (codigo) do nothing;


-- Paquetes de créditos activos (wireframe 15 / HU-072/073)
insert into tbl_paquetes_creditos(nombre,creditos,precio,moneda) values
  ('Basico',100,100,'BOB'),
  ('Pro',500,450,'BOB'),
  ('Empresa',1000,800,'BOB')
on conflict (nombre) do nothing;

-- codigo_tienda se asigna al crear el comercio (HU-002/HU-104):
-- update rsuelvo.tbl_comercios set codigo_tienda='FER' where nombre_comercial='Feria La Paz';
