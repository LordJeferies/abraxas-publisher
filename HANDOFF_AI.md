# HANDOFF AI — ABRAXAS Publisher v1.1

Este archivo existe para que otro chat/IA pueda leer el repositorio y continuar sin depender del historial de conversación.

## Producto

ABRAXAS Publisher administra grandes lotes de contenido. Cada contenido vive normalmente en una carpeta con medio(s) y uno o más TXT por plataforma. La app importa, valida, permite revisión/corrección, precalendariza y finalmente (Paso 2) publicará en redes.

## Stack innegociable actual

- Tauri 2 desktop macOS.
- React + TypeScript + Vite.
- Rust backend.
- SQLite local (`rusqlite`, WAL).
- FFmpeg/ffprobe.
- LiquidGlass sólo en superficies pequeñas de navegación; no convertir listas/calendario en decenas de WebGL contexts.
- identifier Tauri: `com.abraxas.publisher`.

## Estado de v1.1

Funciona localmente: import, parser, preview, notas, corrección TXT, hash/mtime refresh, versionado, workflow, Kanban informativo, calendar DnD, unscheduled rail, dry run.

Publicación real está deliberadamente apagada.

## Principio clave de estados

No mezclar validación técnica con workflow editorial.

- `validationStatus`: VALID / WARNING / INVALID.
- `status` editorial: EN_CONFIRMACION / CON_CORRECCION / LISTO_POR_PROGRAMAR / PROGRAMADO.
- `target.status`: READY / PRECALENDARIZED y posteriormente estados remotos del provider.

## Correcciones

`save_correction_note`:
1. guarda nota en SQLite;
2. actualiza estado editorial;
3. genera `CORRECCION.txt` en la carpeta del contenido mediante temp + rename.

`CORRECCION.txt` no se interpreta como TXT de una plataforma.

## Refresh

`refresh_content` reescanea sólo la carpeta de la ficha. Scanner calcula SHA-256 y mtime de medios/TXT, genera `sourceFingerprint`; si cambia, DB incrementa `version`. Al upsert se preservan workflow, notas y horarios existentes.

## Instalación macOS

Nunca asumir cwd del usuario. Todos los scripts usan `SCRIPT_DIR`.
Destino canónico: `~/Applications/ABRAXAS Publisher.app`.
Instalador usa stage + backup + swap y conserva App Support/SQLite.
LiquidGlass 1.0.3 tiene lifecycle `postinstall: patch-package`; root declara `patch-package` para evitar npm 127.

## Paso 2

Crear interfaz de providers desacoplada. Empezar conexión individual y validación, no publicación en lote. La publicación del primer lote real es la prueba final.
