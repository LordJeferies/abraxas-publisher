# HANDOFF AI — ABRAXAS Publisher

Este archivo existe para que otro chat/agente pueda continuar el producto sin depender del historial de conversación.

## Producto

ABRAXAS Publisher administra grandes lotes de contenido desde importación hasta publicación/registro externo. Tiene Desktop macOS, Web/PWA y una capa MCP.

## Stack

- Tauri 2
- React 19 + TypeScript + Vite
- Rust
- SQLite/rusqlite
- Supabase Auth + `public.editorial_state`
- Zustand
- ffmpeg/ffprobe
- Google Drive OAuth Desktop + Web
- MCP stdio sobre bridge Rust

Identifier Tauri:

```text
com.abraxas.publisher
```

## Estado de producto

Funcionan:

- marcas;
- importación local y Drive;
- revisión/editorial;
- notas + `CORRECCION.txt`;
- refresh/versionado;
- calendario;
- Accounts Center;
- Publishing Center;
- AUTO_API / MANUAL / EXTERNAL;
- preflight;
- publication jobs;
- SCHEDULED_EXTERNAL;
- Desktop + PWA sync;
- MCP;
- pantalla de bienvenida;
- barra global de progreso no bloqueante.

## Estados

Editorial:

```text
EN_CONFIRMACION
CON_CORRECCION
LISTO_POR_PROGRAMAR
PROGRAMADO
```

Publicación:

```text
READY_AUTO
MANUAL_REQUIRED
MANUAL_DUE
MANUAL_OVERDUE
QUEUED
DISPATCHING
VERIFYING
SCHEDULED_REMOTE
SCHEDULED_EXTERNAL
PUBLISHED
PUBLISHED_EXTERNAL
FAILED
```

No tratar fecha local como confirmación remota.

## Sync

Proyecto Supabase compartido con Editorial OS.

```text
table: public.editorial_state
workspace_key: abraxas-publisher
```

Preservar ramas desconocidas del payload y metadatos `revision`, `baseRevision`, `deviceId`, `updatedAt`.

No sincronizar passwords, service-role keys, tokens OAuth privados, rutas locales ni temporales de ffmpeg.

## MCP

Arquitectura:

```text
MCP client
→ mcp/server.mjs
→ publisher_mcp_bridge
→ mismo Rust/SQLite de Publisher
```

No crear una segunda base ni una lógica paralela.

Documentación: `docs/MCP.md`.

Acciones sensibles deben requerir confirmación explícita. Drive OAuth interactivo continúa en UI; un agente headless no debe robar/reutilizar tokens del login interactivo.

## UX de operaciones largas

Toda operación que use el estado `loading` debe mostrar la barra global de progreso. La navegación continúa disponible por defecto.

Bloquear la UI sólo cuando la operación necesite exclusividad/integridad; en ese caso mostrar claramente que Publisher está temporalmente bloqueado y por qué.

## GitHub Pages

PWA:

```text
https://lordjeferies.github.io/abraxas-publisher/
```

Guide:

```text
https://lordjeferies.github.io/abraxas-publisher/guide.html
```

El repo usa `.github/workflows/pages.yml`. La creación inicial del sitio Pages debe hacerla una identidad con permisos admin; el `GITHUB_TOKEN` de Actions no debe usarse para intentar habilitar Pages por primera vez.

## Principios

1. No romper SQLite existente.
2. No borrar datos de usuario para reparar migraciones.
3. Reusar el motor actual; no sustituirlo por mockups.
4. No fingir publicación remota.
5. No secretos en Git.
6. No force push para releases normales.
7. Mantener Desktop y PWA compatibles en modelo de dominio.
8. Mantener IDs estables; no usar paths locales como identidad cloud.
9. `CORRECCION.txt` nunca es un TXT de red social.
10. MCP debe operar el mismo backend real que la app.

## QA

Antes de cerrar cambios:

```bash
npm ci
npm run check
npm run build
GITHUB_ACTIONS=true npm run build:web
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
npm run mcp:build
npm run mcp:selftest
npm run tauri:build
```

Leer además:

- `README.md`
- `START_HERE.md`
- `AGENTS.md`
- `docs/MCP.md`
- `docs/DESKTOP_WEB_PWA_SYNC.md`
- `docs/GOOGLE_DRIVE.md`
- `docs/TROUBLESHOOTING.md`
