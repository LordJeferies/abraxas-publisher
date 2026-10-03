# ABRAXAS Publisher

ABRAXAS Publisher es el centro de operaciones de contenido para revisar, corregir, calendarizar, preparar y coordinar publicaciones desde macOS y Web/PWA.

## Superficies

- **Desktop/Tauri (macOS)**: filesystem local, SQLite, ffmpeg/ffprobe, Google Drive OAuth Desktop, workers y herramientas nativas.
- **Web/PWA**: revisión, calendario, Drive Web OAuth, Publishing Center y sincronización cloud.
- **MCP**: permite que ChatGPT, Codex, Claude u otros clientes compatibles operen el mismo workspace usando el mismo motor Rust/SQLite del Desktop.

## Flujo editorial

```text
IMPORTAR
→ EN_CONFIRMACION
→ CON_CORRECCION (si hace falta)
→ LISTO_POR_PROGRAMAR
→ CALENDARIO
→ PUBLISHING
→ AUTO_API / MANUAL / EXTERNAL
→ QUEUE
```

Estados remotos como `SCHEDULED_REMOTE` sólo deben representar confirmación real del provider. `SCHEDULED_EXTERNAL` registra programación realizada fuera de Publisher.

## Sincronización

Publisher comparte el mismo proyecto Supabase del ecosistema Editorial OS usando:

```text
public.editorial_state
workspace_key = abraxas-publisher
```

Desktop y PWA comparten estado portable mediante Supabase Auth + Realtime. Nunca deben sincronizarse secretos, contraseñas, rutas locales privadas ni tokens OAuth sensibles.

## Google Drive

- Desktop: OAuth tipo Desktop/Tauri.
- Web/PWA: Google Identity Services con OAuth Web.
- El token no se guarda en Git.

## MCP

Arquitectura:

```text
Cliente MCP
   ↓ stdio
mcp/server.mjs
   ↓
publisher_mcp_bridge
   ↓
Rust + SQLite de ABRAXAS Publisher
```

Herramientas disponibles incluyen lectura y edición de marcas, contenido, notas, calendario, cuentas, cola, preflight y publicación externa. Acciones sensibles requieren confirmación explícita según `docs/MCP.md`.

Instalación MCP en Mac:

```bash
chmod +x INSTALAR_MCP_ABRAXAS_PUBLISHER.command
./INSTALAR_MCP_ABRAXAS_PUBLISHER.command
```

Comandos útiles:

```bash
npm run mcp:build
npm run mcp:selftest
npm run mcp:start
```

## UX de progreso

Publisher muestra una barra global superior para operaciones largas. Por defecto las tareas son **no bloqueantes**: puedes seguir navegando mientras trabajan. Sólo operaciones que necesiten exclusividad deben bloquear la interfaz y mostrar un aviso explícito.

La pantalla de bienvenida se carga al iniciar y el workspace puede prepararse en segundo plano.

## Web/PWA

URL:

```text
https://lordjeferies.github.io/abraxas-publisher/
```

Guía:

```text
https://lordjeferies.github.io/abraxas-publisher/guide.html
```

GitHub Pages necesita habilitarse una vez para el repositorio. Después el workflow `.github/workflows/pages.yml` construye y despliega `dist/` automáticamente.

## Mac

Destino canónico:

```text
~/Applications/ABRAXAS Publisher.app
```

Acceso de Escritorio:

```text
~/Desktop/ABRAXAS Publisher.app
```

## QA obligatorio

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

## Documentación

Empieza por:

- `START_HERE.md`
- `HANDOFF_AI.md`
- `AGENTS.md`
- `docs/MCP.md`
- `docs/DESKTOP_WEB_PWA_SYNC.md`
- `docs/MOBILE_PUBLISHING.md`
- `docs/GOOGLE_DRIVE.md`
- `docs/TROUBLESHOOTING.md`

## Seguridad

- No secrets en Git.
- No service-role keys en frontend.
- No passwords reales dentro del código.
- No force push para releases normales.
- Ningún provider se considera publicado/programado remotamente sin verificación real.
