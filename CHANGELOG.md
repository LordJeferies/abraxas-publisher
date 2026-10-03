# Changelog

## 0.2.0 — Planning & Review

- Welcome/Home funcional.
- Help Center por escenarios.
- Ficha de contenido con preview real local.
- Workflow editorial separado de validación técnica.
- Estados: En confirmación / Con corrección / Listo por programar / Programado.
- Kanban informativo sin drag entre estados.
- Correcciones persistentes + `CORRECCION.txt` atómico.
- Refresh por SHA-256 + mtime y versionado de contenido.
- Calendar DnD con bandeja Sin calendarizar.
- Precalendarización desde DATE/TIME de TXT.
- Instalador de actualización con stage/backup/rollback.
- Doctor y handoff de repo.

## 0.3.0 · V1.2 Workspace

- marcas;
- importación recursiva;
- duplicados;
- Drive OAuth directo;
- calendar Day/Week/Month;
- multi-network scheduling;
- inspector dock/float/hide;
- activity;
- undo/redo;
- publisherctl;
- publisher-mcp;
- QA automatizado.

## 0.4.0 · Publisher V1.3

- Accounts Center.
- Provider capability registry.
- Publishing wizard.
- Selection basket.
- Destination/account selection.
- Preflight.
- Platform mockups.
- Persistent publication jobs.
- Idempotency keys.
- Queue V1.3.
- SCHEDULED_EXTERNAL.
- External scheduler provenance.

## 0.4.1 · V1.3.1 Hybrid Publishing

- AUTO_API / MANUAL / EXTERNAL por PublicationTarget.
- Sin API ya no bloquea preflight.
- MANUAL_REQUIRED / MANUAL_DUE / MANUAL_OVERDUE.
- Mixed batch confirmation.
- Queue separa automatic/manual/external.

## 0.4.2 · Shared Desktop/PWA architecture

- Same Supabase project as Editorial OS.
- `public.editorial_state`.
- `workspace_key = abraxas-publisher`.
- Same Supabase Auth across Mac/Web/PWA.
- Local-first portable Publisher workspace.
- Realtime synchronization.
- revision/baseRevision/deviceId conflict contract.
- Desktop mirrors portable state with native backend.
- Google Drive Web OAuth based on Abrxs Review.
- Desktop keeps native Google Drive OAuth.

## 0.4.3 · MCP + Welcome + Global Progress

- MCP stdio conectado al mismo backend Rust/SQLite de Publisher.
- `publisher_mcp_bridge` nativo.
- tools de marcas, contenido, correcciones, calendario, cuentas, queue, preflight y registro externo.
- confirmación explícita para operaciones sensibles.
- CI dedicado para MCP con cargo check/test/build y self-test.
- instalador MCP para macOS y configuración de cliente de ejemplo.
- README/HANDOFF/START_HERE actualizados.
- pantalla de bienvenida al iniciar Publisher.
- barra global superior de progreso con porcentaje y descripción.
- operaciones existentes que usan `setLoading()` alimentan automáticamente la barra global.
- operaciones no bloqueantes por defecto; bloqueo visual sólo cuando una tarea lo requiera explícitamente.
- workflow GitHub Pages corregido para no intentar crear Pages desde el token de Actions.
- `404.html` y `.nojekyll` generados en el deploy PWA.
