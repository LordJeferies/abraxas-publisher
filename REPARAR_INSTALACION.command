#!/bin/bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; cd "$SCRIPT_DIR"
mkdir -p logs
LOG="$SCRIPT_DIR/logs/repair_$(date +%Y%m%d_%H%M%S).log"; exec > >(tee -a "$LOG") 2>&1
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$PATH"
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"; [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"; [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
for c in node npm cargo rustc; do command -v "$c" >/dev/null 2>&1 || { echo "Falta $c. Usa el instalador completo."; exit 1; }; done
rm -rf node_modules; npm cache verify >/dev/null 2>&1 || true
if [[ -f package-lock.json ]]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
npm run check; npm run build; cargo check --manifest-path src-tauri/Cargo.toml
exec "$SCRIPT_DIR/INSTALAR_ABRAXAS_PUBLISHER.command"
