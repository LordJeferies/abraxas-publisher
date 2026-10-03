# ABRAXAS Publisher
## Desktop + Web/PWA + Sync Architecture

### Una aplicación, varias superficies

ABRAXAS Publisher usa un solo producto y un solo modelo conceptual.

Existen dos superficies principales:

1. Desktop / Tauri
2. Web / PWA

No tienen exactamente las mismas capacidades porque el navegador y macOS
tienen permisos y recursos diferentes.

---

# Desktop

Desktop es el ejecutor nativo.

Puede:

- leer carpetas locales;
- trabajar con SQLite nativo;
- usar ffmpeg;
- usar ffprobe;
- trabajar con Keychain;
- ejecutar adapters locales;
- localizar assets del Mac;
- ejecutar trabajos que requieren procesos locales;
- mantener workers/daemons;
- generar receipts después de una acción remota.

---

# Web / PWA

Web/PWA está optimizada para:

- móvil;
- iPad/tablet;
- navegador;
- revisión remota;
- aprobación;
- calendarización;
- copies;
- notas;
- previews;
- selección de destinos;
- creación de jobs;
- visualización de actividad;
- seguimiento de jobs.

Cuando un provider puede ejecutarse directamente desde Cloud/Web,
la PWA puede solicitar la ejecución sin necesidad de Desktop.

---

# Execution Host

Cada operación puede tener uno de estos hosts:

CLOUD
DESKTOP
MANUAL

## CLOUD

Usar cuando:

- provider tiene API compatible;
- OAuth válido;
- asset accesible desde cloud;
- no necesita recursos locales.

## DESKTOP

Usar cuando:

- asset sólo está en Mac;
- requiere ffmpeg;
- requiere filesystem local;
- requiere Keychain local;
- requiere herramienta nativa.

Status:

WAITING_FOR_DESKTOP

## MANUAL

Usar cuando:

- no existe API;
- usuario elige manual;
- provider no está configurado.

---

# Drive

Drive puede ser una fuente común de assets.

Desktop usa OAuth Desktop.

Web/PWA debe usar OAuth Web.

No reutilizar secretos Desktop en frontend Web.

Una referencia Drive puede permitir:

Web/PWA
→ revisar asset
→ aprobar
→ crear job

Después:

- Cloud puede obtener el asset si la arquitectura lo permite; o
- Desktop puede descargar/localizar el asset y ejecutar.

---

# Publicación móvil

Publicar desde móvil NO depende simplemente de que sea móvil.

Depende de:

1. Provider.
2. OAuth.
3. permisos/scopes.
4. tipo de contenido.
5. disponibilidad del asset.
6. política de ejecución.

Ejemplos:

TikTok + OAuth Web + asset accesible
→ CLOUD posible

YouTube + OAuth + asset accesible
→ CLOUD posible

Asset sólo en /Users/... del Mac
→ DESKTOP_REQUIRED

API no configurada
→ MANUAL_REQUIRED

---

# Sync

GitHub Pages NO es el backend de sincronización.

GitHub Pages sirve únicamente:

- HTML
- JS
- CSS
- manifest
- service worker

La sincronización real necesita ABRAXAS Sync API.

Variable:

VITE_ABRAXAS_SYNC_API

La Sync API será responsable de:

- auth;
- workspace;
- content metadata;
- publication jobs;
- devices;
- heartbeat;
- receipts;
- conflict resolution;
- realtime updates.

---

# Device heartbeat

Desktop debe registrar:

deviceId
deviceName
appVersion
lastSeen
capabilities

Web puede saber:

Desktop Online
Desktop Offline

y decidir si un job puede ejecutarse.

---

# Seguridad

Nunca publicar secretos en GitHub.

Nunca poner refresh tokens privados en el bundle Web.

Nunca marcar un job PUBLISHED si no existe verificación.

Nunca considerar GitHub Pages una base de datos segura.

---

# Offline

PWA puede cachear el shell y almacenar cambios locales.

Los cambios remotos deben marcarse como pendientes hasta sincronización.

Offline nunca significa que una publicación externa ocurrió.

---

# Source of truth

El repositorio contiene:

- frontend compartido;
- NativeBackend;
- WebBackend;
- contratos Sync;
- documentación;
- Pages workflow;
- Tauri desktop.

Desktop y Web/PWA evolucionan desde la misma base de código.
