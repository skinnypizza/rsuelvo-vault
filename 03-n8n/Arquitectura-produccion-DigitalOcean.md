# Arquitectura de n8n para producción en DigitalOcean

**Estado: decisión pendiente de contratación/licencia y benchmark.** Esta nota es la base del despliegue; no se cambió el runtime actual.

## Estado observado

- El Compose local fija n8n `2.40.7`, un proceso principal, PostgreSQL local para estado interno, un sidecar de task runners y Cloudflare Tunnel.
- `N8N_DEFAULT_BINARY_DATA_MODE=filesystem`; WF-22 descarga comprobantes como binarios y los procesa en más de un nodo.
- No hay queue mode, Redis/Valkey ni workers adicionales en el Compose observado. El endpoint productivo sigue dependiendo del escritorio y el túnel, así que no ofrece continuidad 24/7.

## Diseño objetivo

Separar componentes y zonas de fallo:

1. **n8n main** detrás de la ruta de editor/admin, sin publicar el puerto 5678 directamente.
2. **Workers n8n** con la misma versión y `N8N_ENCRYPTION_KEY`; un sidecar `n8nio/runners` propio por worker.
3. **PostgreSQL administrado para el estado interno de n8n**, aislado de la base de negocio Supabase. TLS, red privada, standby y credenciales dedicadas.
4. **Valkey administrado compatible con Redis** para el broker Bull del queue mode, en la misma región y red privada, con al menos un standby.
5. Cloudflare delante del dominio/túnel; reglas de firewall permiten solo proxy, SSH administrativo limitado y tráfico privado a las bases. Con más de un webhook processor, un balanceador enruta `/webhook/*` a su pool y el editor/main queda fuera de ese pool.
6. Droplet **General Purpose con CPU dedicada** como punto de partida de producción, dimensionado mediante prueba de carga representativa. No fijar una talla final ni prometer capacidad masiva antes de medir workflows, OCR, concurrencia, conexiones PostgreSQL, cola, CPU, RAM, disco y latencia de Meta.

DigitalOcean describe General Purpose dedicado para cargas estables de producción/SaaS; recomienda dimensionar por medición. PostgreSQL administrado requiere standby para alta disponibilidad. Valkey ofrece clúster HA con standby y declara compatibilidad total con Redis. Verificar planes/región vigentes al contratar: DigitalOcean anunció cambios a Standard PostgreSQL a partir del 15 de octubre y 30 de noviembre de 2026.

## Decisiones Community que bloquean queue mode

- **No activar queue mode conservando filesystem.** La guía actual de n8n dice que queue mode no soporta almacenamiento binario en filesystem. La ruta de comprobantes usa binarios, por lo que esto puede romper WF-22 al mover ejecuciones entre instancias.
- En Community, evaluar `N8N_DEFAULT_BINARY_DATA_MODE=database` con los workers y un PostgreSQL dimensionado para esa carga. Medir tamaño de binarios, crecimiento de la DB, I/O, pruning y concurrencia con comprobantes sintéticos. No pasar a producción hasta que el benchmark y la restauración demuestren que la base tolera la carga.
- Almacenar binarios en S3 externo requiere n8n Business o Enterprise; la guía de n8n soporta oficialmente AWS S3 y dice que proveedores S3 compatibles no nombrados no están oficialmente soportados. No asumir que DigitalOcean Spaces es compatible con n8n sin una prueba de versión/licencia/restauración.
- **Multi-main para alta disponibilidad requiere Enterprise** en self-hosted. Queue mode Community permite escalar workers, pero el main único sigue siendo un punto único de fallo. Para el objetivo de escala alta, presupuestar Enterprise o aceptar y documentar explícitamente el RTO/RPO de main único.
- En queue mode, cada worker necesita su propio sidecar externo de task runners. n8n recomienda concurrencia de worker de 5 o más y advierte que muchos workers con concurrencia baja pueden agotar conexiones de la base.

## Puertas previas al cutover

- [ ] Contratar y aprovisionar la infraestructura DO; seleccionar región, red privada, firewall, backups, métricas y alertas.
- [ ] Decidir n8n Community + binarios en PostgreSQL con benchmark aprobado, o licencia Business/Enterprise + almacenamiento externo. Decidir también si multi-main Enterprise es requisito para el SLO.
- [ ] Preparar un entorno DO de ensayo con versión exacta, Postgres/Valkey HA, cifrado TLS, runners por worker, secrets fuera del repo y objetos binarios de prueba.
- [ ] Hacer carga concurrente de rutas representativas: texto/SKU, comprobante/OCR/Storage, reserva, pagos, lista de espera y callbacks; fijar SLO de webhook, tasa de error y máximo de cola.
- [ ] Ensayar failover de PostgreSQL y Valkey, reconexión del cliente, reinicio de un worker durante ejecución, restore del backup y recuperación de n8n encryption key/credenciales.
- [ ] Confirmar Meta real → `meta-ingress` → webhook n8n → respuesta Graph en canary, sin usar OpenWA.
- [ ] Mantener los cinco callbacks `pg_net` y el hostname actuales durante la prueba de corte; activar gradualmente después de backup y rollback verificados.

## Fuentes oficiales consultadas — 2026-10-02

- n8n: [queue mode](https://docs.n8n.io/hosting/scaling/queue-mode/) — workers, Redis, restricciones de binarios, concurrencia y multi-main.
- n8n: [external storage](https://docs.n8n.io/hosting/scaling/external-storage/) — licencia requerida para S3 y soporte de proveedores.
- n8n: [task runners](https://docs.n8n.io/hosting/configuration/task-runners/) — aislamiento en producción y runner sidecar por worker.
- DigitalOcean: [elegir un plan de CPU](https://docs.digitalocean.com/products/droplets/concepts/choosing-a-plan/) — dedicado frente a compartido y benchmark por carga.
- DigitalOcean: [Managed Databases](https://docs.digitalocean.com/products/databases/) — standby, failover y cambios próximos en planes PostgreSQL.
- DigitalOcean: [Valkey HA y precios](https://docs.digitalocean.com/products/databases/valkey/details/pricing/) — compatibilidad Redis y standby HA.
