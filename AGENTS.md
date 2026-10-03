# ABRAXAS Publisher · Agent rules

Trabaja sobre la aplicación existente. No la sustituyas por un mockup.

Stack que debe conservarse salvo razón técnica demostrable:

- Tauri 2
- React 19
- TypeScript
- Vite
- Rust
- SQLite/rusqlite
- FFmpeg/FFprobe
- Zustand
- Supabase
- Google Drive OAuth Desktop/Web
- MCP stdio

## Reglas críticas

1. Mantener identifier `com.abraxas.publisher`.
2. Mantener compatibilidad con la SQLite existente.
3. Nunca borrar datos de usuario para solucionar una migración.
4. No fingir estados remotos. `SCHEDULED_REMOTE` requiere verificación real del provider.
5. `PROGRAMADO` editorial no equivale a programación remota.
6. No almacenar OAuth tokens, passwords, service-role keys ni secretos en Git.
7. Google Drive OAuth interactivo debe permanecer en la UI apropiada; el MCP no debe robar ni persistir tokens de usuario.
8. La app debe seguir funcionando aunque Google Drive o una API social no estén configurados.
9. `CORRECCION.txt` no se interpreta como TXT de red social.
10. El Kanban es de visualización; el workflow cambia desde la ficha/acciones explícitas.
11. Desktop y PWA comparten modelo portable, pero paths locales/temporales no se sincronizan como identidad cloud.
12. El MCP usa el mismo backend/SQLite real de Publisher; no crear una segunda base.
13. En MCP: leer antes de escribir y verificar después de escribir.
14. Acciones destructivas/sensibles requieren confirmación explícita.
15. Para Publishing: ejecutar preflight antes de encolar.
16. `MANUAL_REQUIRED` no es `FAILED`.
17. Para operaciones largas, usar la barra global de progreso. No bloquear la UI por defecto.
18. Si una operación requiere exclusividad, marcarla como bloqueante y mostrar claramente el motivo.
19. No romper el instalador de macOS ni el acceso `~/Applications/ABRAXAS Publisher.app`.
20. GitHub Pages se despliega con Actions, pero la creación inicial del site debe realizarla una identidad con permisos admin.
21. No force push para releases normales.

## QA obligatorio

Antes de terminar:

```bash
npm ci
npm run check
npm run build
GITHUB_ACTIONS=true npm run build:web
cargo fmt --manifest-path src-tauri/Cargo.toml --all --check
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
npm run mcp:build
npm run mcp:selftest
npm run tauri:build
```

## Documentación que debe mantenerse

- `README.md`
- `START_HERE.md`
- `HANDOFF_AI.md`
- `CHANGELOG.md`
- `docs/MCP.md`
- documentación afectada por cada cambio

## Fuente de verdad

Antes de modificar:

```bash
git fetch origin
git status --short
git log --oneline --decorate -10
```

Usar `main`/estado más reciente del repo como fuente de verdad, no snapshots antiguos.
