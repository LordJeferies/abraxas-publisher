#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
APP_NAME="ABRAXAS Publisher"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$PATH"
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
ERRORS=0; WARNS=0
ok(){ printf 'OK    %s\n' "$*"; }
warn(){ printf 'WARN  %s\n' "$*"; WARNS=$((WARNS+1)); }
err(){ printf 'ERROR %s\n' "$*"; ERRORS=$((ERRORS+1)); }
check(){ if command -v "$2" >/dev/null 2>&1; then ok "$1: $(command -v "$2")"; else err "$1 no encontrado"; fi; }
echo "=============================================================="
echo " ABRAXAS Publisher · Doctor v1.1"
echo "=============================================================="
[[ "$(uname -s)" == Darwin ]] && ok "macOS $(sw_vers -productVersion 2>/dev/null || true)" || err "No es macOS"
[[ "$(uname -m)" == arm64 ]] && ok "Apple Silicon arm64" || warn "Arquitectura: $(uname -m)"
xcode-select -p >/dev/null 2>&1 && ok "Xcode CLT: $(xcode-select -p)" || err "Faltan Xcode Command Line Tools"
check Homebrew brew; check Node node; check npm npm; check rustup rustup; check rustc rustc; check cargo cargo; check FFmpeg ffmpeg; check FFprobe ffprobe
[[ -f package.json ]] && ok "package.json" || err "Falta package.json"
[[ -d node_modules ]] && ok "node_modules" || warn "node_modules no existe"
[[ -f src-tauri/Cargo.toml ]] && ok "Cargo.toml" || err "Falta Cargo.toml"
[[ -f src-tauri/tauri.conf.json ]] && ok "tauri.conf.json" || err "Falta tauri.conf.json"
if [[ -d "$INSTALLED_APP" ]]; then ok "App instalada: $INSTALLED_APP"; xattr "$INSTALLED_APP" 2>/dev/null | grep -q '^com.apple.quarantine$' && warn "App con quarantine" || ok "Quarantine limpio"; else warn "App todavía no instalada"; fi
DATA="$HOME/Library/Application Support/com.abraxas.publisher"
mkdir -p "$DATA" 2>/dev/null && touch "$DATA/.doctor" 2>/dev/null && rm -f "$DATA/.doctor" && ok "App Support escribible" || warn "No se pudo comprobar App Support exacto; Tauri puede usar otra ruta derivada del identifier"
echo "WARN: $WARNS · ERROR: $ERRORS"
[[ $ERRORS -gt 0 ]] && exit 2
[[ $WARNS -gt 0 ]] && exit 1
exit 0
