# ABRAXAS Publisher MCP

ABRAXAS Publisher expone un servidor MCP local por `stdio` para que ChatGPT/Codex/Claude y otros clientes compatibles puedan operar el mismo workspace real que usa la app Desktop.

## Arquitectura

```text
Cliente MCP
  ↓ stdio JSON-RPC
mcp/server.mjs
  ↓
publisher_mcp_bridge (Rust)
  ↓
ABRAXAS Publisher backend
  ↓
SQLite / scanner / publishing / ffmpeg
```

No existe una segunda base de datos ni una copia separada del dominio. El MCP usa el mismo `default_db_path()` de Publisher.

## Qué puede hacer

### Lectura y diagnóstico

- doctor de SQLite / ffmpeg / ffprobe;
- listar marcas;
- listar y abrir fichas;
- revisar assets, targets e issues;
- leer programación;
- actividad;
- dry-run;
- listar cuentas;
- listar publication jobs;
- ejecutar publishing preflight;
- leer Google Drive Client ID público.

### Edición

- crear marcas;
- importar carpetas locales;
- refrescar contenido;
- cambiar estado editorial;
- guardar correcciones y generar `CORRECCION.txt`;
- calendarizar / descalendarizar;
- undo / redo;
- crear/editar metadatos de cuentas;
- encolar publication jobs;
- registrar `SCHEDULED_EXTERNAL`;
- configurar Google Drive Client ID.

### UI

- abrir ABRAXAS Publisher Desktop;
- abrir la Web/PWA.

## Limitación deliberada de Google Drive

El MCP **no roba ni persiste tokens OAuth**. El consentimiento Google se hace en Publisher Desktop/Web. El MCP puede leer/configurar el Client ID público, pero la sesión OAuth interactiva pertenece a la UI.

## Acciones sensibles

Las siguientes tools requieren `confirm: true`:

- `publisher_import_local`
- `publisher_remove_account`
- `publisher_enqueue_publications`
- `publisher_mark_scheduled_external`
- `publisher_clear_workspace`

El agente debe explicar primero qué cambiará. No debe convertir una intención ambigua en una escritura.

## Estados: criterio obligatorio

No mezclar estas capas:

### Workflow editorial

- `EN_CONFIRMACION`
- `CON_CORRECCION`
- `LISTO_POR_PROGRAMAR`
- `PROGRAMADO`

### Scheduling / publicación

- `UNSCHEDULED`
- `PRECALENDARIZED`
- `QUEUED`
- `MANUAL_REQUIRED`
- `SCHEDULED_EXTERNAL`
- `SCHEDULED_REMOTE`
- `PUBLISHED`
- `PUBLISHED_EXTERNAL`
- `FAILED`

`PROGRAMADO` editorial **no significa** que Instagram/YouTube/etc. hayan confirmado programación.

`SCHEDULED_REMOTE` sólo puede representar una confirmación real de un provider remoto.

## Instalación

Desde el repo:

```bash
cd ~/Developer/abraxas-publisher
chmod +x mcp/install.sh
./mcp/install.sh
```

El instalador compila:

```text
src-tauri/target/release/publisher_mcp_bridge
```

y ejecuta un self-test.

## Configuración MCP genérica

```json
{
  "mcpServers": {
    "abraxas-publisher": {
      "command": "node",
      "args": [
        "/Users/TU_USUARIO/Developer/abraxas-publisher/mcp/server.mjs"
      ],
      "env": {
        "ABRAXAS_PUBLISHER_MCP_BRIDGE": "/Users/TU_USUARIO/Developer/abraxas-publisher/src-tauri/target/release/publisher_mcp_bridge"
      }
    }
  }
}
```

La ubicación exacta del archivo de configuración depende del cliente. Usa este objeto como contrato común.

## Tools

### Workspace

- `publisher_doctor`
- `publisher_list_brands`
- `publisher_create_brand`
- `publisher_list_contents`
- `publisher_get_content`
- `publisher_refresh_content`
- `publisher_import_local`
- `publisher_list_activity`
- `publisher_undo`
- `publisher_redo`
- `publisher_dry_run`
- `publisher_clear_workspace`

### Revisión

- `publisher_set_status`
- `publisher_add_correction_note`

### Calendario

- `publisher_get_schedule`
- `publisher_set_schedule`
- `publisher_clear_schedule`

### Accounts / Publishing Center

- `publisher_list_accounts`
- `publisher_save_account`
- `publisher_remove_account`
- `publisher_list_jobs`
- `publisher_preflight`
- `publisher_enqueue_publications`
- `publisher_mark_scheduled_external`

### Drive

- `publisher_get_drive_client_id`
- `publisher_set_drive_client_id`

### Navegación

- `publisher_open_app`
- `publisher_open_web`

## Ejemplos de uso

### 1. Revisar qué necesita atención

> Revisa Publisher y dime qué contenidos están con corrección, cuáles están listos por programar y cuáles tienen errores técnicos. No cambies nada.

El agente debe usar lecturas: `publisher_list_contents`, `publisher_list_jobs` y opcionalmente `publisher_dry_run`.

### 2. Registrar una corrección

> En la ficha X deja la nota “cambiar portada por la versión aprobada” y márcala con corrección.

Uso esperado:

1. `publisher_get_content`
2. `publisher_add_correction_note`
3. `publisher_get_content` para verificar.

### 3. Calendarizar

> Pon el Reel X en Instagram para el 8 de octubre a las 17:00.

Uso esperado:

1. comprobar ficha;
2. `publisher_set_schedule`;
3. `publisher_get_schedule` para verificar.

No marcar `SCHEDULED_REMOTE`.

### 4. Preparar publicación

> Prepara el contenido X para Instagram con la cuenta Y.

Uso esperado:

1. `publisher_get_content`
2. `publisher_preflight`
3. explicar bloqueos/modo `AUTO_API` o `MANUAL`;
4. sólo después de confirmación del usuario: `publisher_enqueue_publications` con `confirm:true`.

### 5. Programado fuera

> Ya programé este contenido en Meta Business Suite para mañana a las 6 PM. Regístralo.

El agente debe confirmar target/método/fecha y después llamar `publisher_mark_scheduled_external` con `confirm:true`.

### 6. Auditoría de la mañana

> Hazme una revisión de Publisher y dime qué requiere mi atención hoy.

El servidor incluye el prompt MCP `publisher_morning_review`.

## Criterios para agentes

1. **Leer antes de escribir.**
2. **Verificar después de escribir.**
3. No inventar `contentId`, `targetId` o `accountId`.
4. Si hay varias coincidencias, pedir/mostrar las opciones.
5. Coherencia editorial > velocidad.
6. Una fecha local no equivale a programación remota.
7. `MANUAL_REQUIRED` no es un fallo.
8. No guardar passwords, service-role keys ni tokens OAuth.
9. No borrar workspace ni cuenta sin confirmación explícita.
10. Antes de encolar, usar `publisher_preflight`.
11. Si el preflight tiene un check bloqueante fallido, no encolar como si estuviera listo.
12. No automatizar el login de Google; abrir la UI cuando sea necesario.
13. Undo/redo sólo aplica a operaciones locales soportadas por el backend.
14. Para lotes grandes: primero dry-run/preflight, después escritura.
15. Tras una importación o refresh, releer el contenido.

## Prompts MCP incluidos

- `publisher_morning_review`
- `publisher_prepare_week`
- `publisher_fix_content`

## Seguridad

El servidor MCP es local por stdio. No abre un puerto HTTP y no publica la SQLite en red.

Nunca introducir en el repo:

- passwords;
- Supabase `service_role`;
- Google client secrets;
- refresh tokens;
- access tokens sociales.

## Desarrollo / QA

```bash
cargo fmt --manifest-path src-tauri/Cargo.toml --all --check
cargo check --manifest-path src-tauri/Cargo.toml --bin publisher_mcp_bridge
cargo test --manifest-path src-tauri/Cargo.toml
cargo build --release --manifest-path src-tauri/Cargo.toml --bin publisher_mcp_bridge
node mcp/server.mjs --self-test
```

También existe `.github/workflows/mcp-ci.yml` para validar la integración en GitHub Actions.
