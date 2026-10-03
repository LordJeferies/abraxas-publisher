#!/bin/bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
mkdir -p logs "$HOME/Applications" "$HOME/Library/Application Support/ABRAXAS Publisher/installer-backups"
LOG="$SCRIPT_DIR/logs/install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
APP_NAME="ABRAXAS Publisher"
APP_DEST="$HOME/Applications/$APP_NAME.app"
BACKUP="$HOME/Library/Application Support/$APP_NAME/installer-backups/$APP_NAME.previous.app"
STAGE="$HOME/Applications/.$APP_NAME.installing.$$.app"
trap 'code=$?; echo; echo "FALLO · línea $LINENO · comando: $BASH_COMMAND · código $code"; echo "Log: $LOG"; rm -rf "$STAGE" 2>/dev/null || true; exit "$code"' ERR
fail(){ echo "ERROR: $1"; echo "Log: $LOG"; exit 1; }
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$PATH"
echo "=============================================================="
echo " ABRAXAS Publisher v1.1 · Instalador / Actualizador"
echo "=============================================================="
echo "Proyecto: $SCRIPT_DIR"; echo "Log: $LOG"
[[ "$(uname -s)" == Darwin ]] || fail "Este instalador es para macOS."
[[ -f package.json && -f src-tauri/Cargo.toml ]] || fail "No estás ejecutando el instalador desde el proyecto correcto."
echo "[1/9] Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then xcode-select --install >/dev/null 2>&1 || true; echo "Completa la instalación de Apple y vuelve a ejecutar este archivo."; exit 2; fi
echo "[2/9] Homebrew"
if ! command -v brew >/dev/null 2>&1; then /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; fi
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
command -v brew >/dev/null 2>&1 || fail "Homebrew no quedó disponible."
echo "[3/9] Node / npm"
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then brew install node; fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"; [[ "$NODE_MAJOR" -ge 20 ]] || fail "Se requiere Node 20 o superior."
echo "Node $(node -v) · npm $(npm -v)"
echo "[4/9] Rust"
if ! command -v rustup >/dev/null 2>&1; then curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal; fi
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
command -v cargo >/dev/null 2>&1 || fail "cargo no disponible."
rustup default stable >/dev/null
echo "$(rustc --version)"
echo "[5/9] FFmpeg"
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then brew install ffmpeg; fi
echo "$(ffmpeg -hide_banner -version | head -n 1)"
echo "[6/9] Dependencias JavaScript"
rm -rf node_modules
npm cache verify >/dev/null 2>&1 || true
if [[ -f package-lock.json ]]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
[[ -x node_modules/.bin/patch-package ]] || fail "patch-package no quedó disponible para LiquidGlass."
echo "[7/9] Validación"
npm run check
npm run build
cargo check --manifest-path src-tauri/Cargo.toml
echo "[8/9] Build Tauri"
BUILD_EXIT=0
npm run tauri:build || BUILD_EXIT=$?
APP_SRC="$(find src-tauri/target/release/bundle/macos -maxdepth 2 -type d -name '*.app' -prune -print 2>/dev/null | head -n 1 || true)"
[[ -n "$APP_SRC" && -d "$APP_SRC" ]] || fail "No se generó la .app (Tauri exit=$BUILD_EXIT)."
[[ "$BUILD_EXIT" -eq 0 ]] || echo "WARN: Tauri devolvió $BUILD_EXIT, pero la .app sí existe; se instalará el bundle macOS."
echo "[9/9] Stage + backup + instalación"
rm -rf "$STAGE"; ditto "$APP_SRC" "$STAGE"; xattr -dr com.apple.quarantine "$STAGE" >/dev/null 2>&1 || true
rm -rf "$BACKUP"
[[ -d "$APP_DEST" ]] && mv "$APP_DEST" "$BACKUP"
if ! mv "$STAGE" "$APP_DEST"; then rm -rf "$APP_DEST"; [[ -d "$BACKUP" ]] && mv "$BACKUP" "$APP_DEST"; fail "No se pudo reemplazar la app; rollback ejecutado."; fi
xattr -dr com.apple.quarantine "$APP_DEST" >/dev/null 2>&1 || true
codesign --verify --deep --strict "$APP_DEST" >/dev/null 2>&1 && echo "codesign verify: OK" || echo "WARN: build local sin firma estricta / verificar antes de distribución."
set +e; "$SCRIPT_DIR/scripts/doctor.sh"; DOCTOR=$?; set -e
[[ "$DOCTOR" -le 1 ]] || echo "WARN: Doctor reportó errores; revisa $LOG"
open "$APP_DEST"
echo; echo "INSTALACIÓN / ACTUALIZACIÓN TERMINADA"; echo "App: $APP_DEST"; echo "Log: $LOG"; echo "Los datos del workspace se conservan porque el identifier sigue siendo com.abraxas.publisher."
