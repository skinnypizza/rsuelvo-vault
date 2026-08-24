-- ============================================================
-- RSUELVO :: DATOS INICIALES (SEED)
-- Archivo 10/12 del schema separado
-- Ejecutar en orden. Idempotente. Esquema: rsuelvo
-- ============================================================

set search_path = rsuelvo, public;


-- Roles del sistema
insert into tbl_roles (codigo,nombre,nivel) values
('ROLE_SUPERADMIN','Superadministrador',100),
('ROLE_SYSADMIN','Administrador de infraestructura',90),
('ROLE_SUPPORT','Soporte',50),
('ROLE_TENANT_ADMIN','Administrador del comercio',30),
('ROLE_TENANT_CASHIER','Cajero',20),
('ROLE_LOGISTICS_AGENT','Repartidor',10)
on conflict (codigo) do nothing;

-- Servicios de créditos
insert into tbl_servicios_creditos(codigo,nombre,descripcion,costo_creditos)
values
('VERIFICACION_COMPROBANTE','Verificación de comprobante','Verificación completa de un comprobante de pago',1),
('OCR_COMPROBANTE','OCR de comprobante','Extracción de información del comprobante',1),
('VALIDACION_AVANZADA','Validación avanzada','Validaciones adicionales del comprobante',3)
on conflict (codigo) do nothing;

-- Paquetes de créditos sugeridos (alineados a wireframe 15):
-- insert into tbl_paquetes_creditos(nombre,creditos,precio) values
--   ('Básico',100,100),('Pro',500,450),('Empresa',1000,800)
-- on conflict (nombre) do nothing;
