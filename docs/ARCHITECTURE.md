# Architecture v1.1

```text
React UI
  -> Tauri invoke
Rust Commands
  -> Scanner (TXT/media/hash/ffprobe)
  -> SQLite WAL
  -> Atomic correction file writer
```

## Core invariants

- Workflow editorial != validación técnica != estado remoto de provider.
- No renombrar TXT de plataforma por una simulación local.
- `CORRECCION.txt` se ignora al detectar plataformas.
- Refresh preserva notas/workflow/schedule.
- Kanban no modifica estado.
- Social APIs siguen apagadas en v1.1.
