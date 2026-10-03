# START HERE — ABRAXAS Publisher

## Estado actual

ABRAXAS Publisher es un workspace Desktop + Web/PWA para importar, revisar, corregir, calendarizar y preparar publicación de contenido.

También incluye un **MCP local** para que clientes compatibles puedan operar el mismo workspace real de la app mediante herramientas estructuradas.

## Superficies

- **Desktop / Tauri**: filesystem, SQLite, ffmpeg/ffprobe, Drive Desktop y ejecución local.
- **Web / PWA**: revisión, calendario, Drive Web y sincronización cloud.
- **MCP local**: control del mismo backend/SQLite del Desktop por stdio.

## Abrir

Desktop:

```text
~/Applications/ABRAXAS Publisher.app
```

Web/PWA:

```text
https://lordjeferies.github.io/abraxas-publisher/
```

Guía pública:

```text
https://lordjeferies.github.io/abraxas-publisher/guide.html
```

## Instalar / actualizar Desktop

```bash
chmod +x *.command scripts/*.sh
./ACTUALIZAR_ABRAXAS_PUBLISHER.command
```

## Instalar MCP

```bash
chmod +x INSTALAR_MCP.command mcp/install.sh
./INSTALAR_MCP.command
```

O:

```bash
npm run mcp:install
```

El instalador compila el bridge Rust, prueba el servidor y muestra un bloque de configuración MCP listo para adaptar al cliente.

Lee:

- `docs/MCP.md`
- `mcp/config.example.json`

## Flujo recomendado

```text
Importar
→ revisar
→ CON_CORRECCION si hace falta
→ refrescar versión
→ LISTO_POR_PROGRAMAR
→ calendario
→ preflight
→ AUTO_API / MANUAL / EXTERNAL
→ cola
→ verificación remota cuando exista adapter real
```

## Regla crítica de estados

`PROGRAMADO` es un estado editorial.

No equivale a:

```text
SCHEDULED_REMOTE
```

Una fecha local tampoco equivale a confirmación de Instagram, YouTube, TikTok, LinkedIn, etc.

## Regla crítica del MCP

- leer antes de escribir;
- verificar después de escribir;
- no inventar IDs;
- usar preflight antes de enqueue;
- acciones sensibles requieren `confirm: true`;
- no automatizar el login de Google;
- nunca guardar passwords, OAuth tokens o service-role keys en Git.

## QA

```bash
npm run check
npm run build
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
npm run mcp:test
```

## Archivos que un agente debe leer primero

1. `START_HERE.md`
2. `HANDOFF_AI.md`
3. `AGENTS.md`
4. `docs/MCP.md`
5. `docs/SHARED_CLOUD_CONTRACT.md`
6. `docs/V13_1_HYBRID_PUBLISHING.md`
7. `CHANGELOG.md`
