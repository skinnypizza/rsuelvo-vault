# OpenWA 0.21.0 — Instalación y Configuración

> **Versión:** 0.21.0 (WPPConnect/OpenWA Server)
> **Ruta de instalación:** `/home/nico/OpenWA/`
> **Estado:** ✅ Instalado y corriendo | ⚠️ Sin sesión activa

## ¿Qué es OpenWA 0.21.0?

Es un servidor REST que expone la API de WhatsApp Web como endpoints HTTP. Permite:
- Enviar mensajes de texto, imágenes, documentos
- Recibir mensajes entrantes via Webhooks
- Descargar archivos multimedia (imágenes de comprobantes para OCR)
- Gestionar múltiples sesiones (multi-instancia)

## Estado actual del contenedor

```bash
docker ps | grep openwa-api
# openwa-api  → Up (healthy) → 127.0.0.1:2785->2785
```

> ⚠️ El dashboard web principal corre en `http://localhost:8002` y **no responde** en este momento (solo el mapeo `127.0.0.1:2785` está activo). Revisar el mapeo de puertos / la configuración del contenedor antes de escanear el QR.

## Iniciar el servidor (fuente)

```bash
cd /home/nico/OpenWA
npm start
# o con Docker:
# docker compose up -d
```

## Crear una sesión (primera vez)

```bash
# Llamar al endpoint de creación de sesión
curl -X POST http://localhost:2785/api/sessions/start \
  -H "Content-Type: application/json" \
  -d '{"session": "rsuelvo"}'
```

Esto retorna un **código QR** que debes escanear con tu WhatsApp.

O visita el dashboard: `http://localhost:8002/` y escanea el QR.

## Endpoints principales

| Método | Endpoint | Descripción |
|---|---|---|
| POST | `/api/sendText` | Enviar mensaje de texto |
| POST | `/api/sendImage` | Enviar imagen |
| GET | `/api/sessions` | Listar sesiones activas |
| POST | `/api/sessions/start` | Iniciar nueva sesión |
| POST | `/api/webhook` | Configurar webhook global |

## Configurar Webhook para recibir mensajes en n8n

Una vez tengas la sesión activa, configura el webhook para que los mensajes entrantes (incluidas las imágenes de comprobantes) lleguen al **WF3 (adaptador)**, no directamente a WF2:

```bash
curl -X POST http://localhost:2785/api/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://rsuelvo2026.app.n8n.cloud/webhook/wa-comprobante",
    "events": ["message", "media"]
  }'
```

O en el archivo de configuración de OpenWA (si existe `config.json`):
```json
{
  "sessionId": "rsuelvo",
  "webhook": "https://rsuelvo2026.app.n8n.cloud/webhook/wa-comprobante",
  "mapChatIdToJid": true
}
```

## Payload que OpenWA envía a n8n (mensaje con imagen)

```json
{
  "event": "media",
  "session": "rsuelvo",
  "data": {
    "id": "MESSAGE_ID",
    "from": "591XXXXXXXX@c.us",
    "type": "image",
    "mimetype": "image/jpeg",
    "caption": "RQ-<UUID_DEL_COBRO>",
    "mediaUrl": "https://tu-servidor/media/MESSAGE_ID.jpg",
    "body": "base64_de_la_imagen_o_url"
  }
}
```

> **Nota:** El caption debe contener el identificador de cobro (formato por definir, ej. `RQ-<UUID>` o el UUID directo) para que el **WF3** lo extraiga y llame al WF2.

## Exposición para n8n Cloud

Como n8n está en cloud y OpenWA corre en localhost, para que n8n Cloud pueda **enviar mensajes** al cliente (notificación post-pago) o recibir webhooks de OpenWA con URL pública:

- **Opción A:** `ngrok http 2785` (tunnel temporal)
- **Opción B:** Mover OpenWA a VPS/servidor con IP pública

## Enviar mensaje desde n8n hacia cliente

En n8n, usar nodo **HTTP Request**:

```
POST http://<host-externo>:2785/api/sendText
Headers: { "Content-Type": "application/json" }
Body: {
  "session": "rsuelvo",
  "phone": "591XXXXXXXXX",
  "message": "¡Pago recibido! Tu guía de seguimiento es RS-XXXXX 🚀"
}
```