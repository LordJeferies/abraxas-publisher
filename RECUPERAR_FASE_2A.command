#!/bin/bash
set -Eeuo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

ROOT="$(ls -td "$HOME"/Developer/abraxas-publisher-v14-* 2>/dev/null | head -n 1 || true)"
[ -n "$ROOT" ] || { echo "No se encontró una carpeta abraxas-publisher-v14-*"; exit 1; }

APP="$HOME/Applications/ABRAXAS Publisher.app"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$HOME/Applications/ABRAXAS Publisher.pre-v14-recovery-$STAMP.app"

cd "$ROOT"

echo "1/5 · Reparando Sidebar"
python3 <<'PY'
from pathlib import Path
p = Path('src/components/Sidebar.tsx')
s = p.read_text()
# Corrige variantes defectuosas del tuple de providers.
s = s.replace("    [\n      'providers',\n      'Proveedores',\n      Plug,\n    ],\n", "    [\n      'providers',\n      Plug,\n      'Proveedores',\n    ],\n")
s = s.replace("    [\n      'providers',\n      Plug,\n      Plug,\n    ],\n", "    [\n      'providers',\n      Plug,\n      'Proveedores',\n    ],\n")
# Si el bloque existe pero quedó malformado, normalízalo.
start = s.find("    [\n      'providers',")
if start != -1:
    end = s.find("    ],\n", start)
    if end != -1:
        end += len("    ],\n")
        s = s[:start] + "    [\n      'providers',\n      Plug,\n      'Proveedores',\n    ],\n" + s[end:]
if "  Plug,\n" not in s:
    s = s.replace("  UsersRound,\n", "  UsersRound,\n  Plug,\n")
p.write_text(s)
PY

npm run check

echo "2/5 · QA completo"
npm run build
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
npm run mcp:test

echo "3/5 · Commit y push de la rama"
git add src/lib/providers src/views/ProvidersView.tsx src/lib/store.ts src/App.tsx src/components/Sidebar.tsx src/styles.css docs/PHASE_2_PROVIDER_ADAPTERS.md
if ! git diff --cached --quiet; then
  git commit -m "ABRAXAS Publisher V1.4 provider adapter foundation"
fi
git push -u origin v1.4-provider-adapters

echo "4/5 · Build e instalación Mac"
npm run tauri:build
NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"
[ -d "$NEW_APP" ] || { echo "No se encontró la app compilada"; exit 1; }
mkdir -p "$HOME/Applications"
if [ -d "$APP" ]; then mv "$APP" "$BACKUP"; fi
ditto "$NEW_APP" "$APP"
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
rm -f "$HOME/Desktop/ABRAXAS Publisher.app"
ln -s "$APP" "$HOME/Desktop/ABRAXAS Publisher.app"

echo "5/5 · Listo"
echo "FASE 2A COMPLETADA"
echo "Rama: v1.4-provider-adapters"
echo "App: $APP"
echo "Backup: $BACKUP"
open "$APP" 2>/dev/null || true
