#!/bin/bash
set -Eeuo pipefail

REPO="LordJeferies/abraxas-publisher"
SOURCE="$HOME/Developer/abraxas-publisher"
STAMP="$(date +%Y%m%d_%H%M%S)"
BUILD="$HOME/Developer/abraxas-publisher-main-build-$STAMP"
APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP="$HOME/Applications/ABRAXAS Publisher.pre-progress-$STAMP.app"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

section(){
  echo
  echo "=============================================================="
  echo " $*"
  echo "=============================================================="
}

fail(){
  echo "ERROR: $*" >&2
  exit 1
}

section "1/6 · GITHUB PAGES"

command -v gh >/dev/null || fail "Falta GitHub CLI (gh)."
gh auth status >/dev/null 2>&1 || fail "gh no está autenticado. Ejecuta: gh auth login"

if gh api "repos/$REPO/pages" >/dev/null 2>&1; then
  gh api \
    --method PUT \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$REPO/pages" \
    -f build_type=workflow \
    >/dev/null
  echo "✓ GitHub Pages ya existía; quedó en modo workflow"
else
  gh api \
    --method POST \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$REPO/pages" \
    -f build_type=workflow \
    >/dev/null \
    || fail "No se pudo habilitar Pages. Revisa Settings → Pages → Source: GitHub Actions."
  echo "✓ GitHub Pages habilitado"
fi

gh workflow run pages.yml \
  --repo "$REPO" \
  --ref main \
  || true

section "2/6 · WORKTREE LIMPIO"

if [ ! -d "$SOURCE/.git" ]; then
  mkdir -p "$HOME/Developer"
  git clone "https://github.com/$REPO.git" "$SOURCE"
fi

git -C "$SOURCE" fetch origin

git -C "$SOURCE" worktree add \
  --detach \
  "$BUILD" \
  origin/main

cd "$BUILD"

echo "✓ Build limpio: $BUILD"

section "3/6 · QA"

npm ci
npm run check
npm run build
GITHUB_ACTIONS=true npm run build:web

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all \
  --check

cargo check \
  --manifest-path src-tauri/Cargo.toml

cargo test \
  --manifest-path src-tauri/Cargo.toml

npm run mcp:build
npm run mcp:selftest

echo "✓ QA completo"

section "4/6 · MCP"

bash mcp/install.sh

echo "✓ MCP instalado en ruta estable"

section "5/6 · DESKTOP"

unset GITHUB_ACTIONS
npm run tauri:build

NEW_APP="$BUILD/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"

if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(find "$BUILD/src-tauri/target/release/bundle" -type d -name '*.app' -print -quit)"
fi

[ -d "$NEW_APP" ] || fail "No se encontró el bundle .app."

mkdir -p "$HOME/Applications"

if [ -d "$APP" ]; then
  mv "$APP" "$BACKUP"
fi

STAGE="$HOME/Applications/.ABRAXAS Publisher.$STAMP.app"
rm -rf "$STAGE"
ditto "$NEW_APP" "$STAGE"
xattr -dr com.apple.quarantine "$STAGE" >/dev/null 2>&1 || true
mv "$STAGE" "$APP"

rm -f "$HOME/Desktop/ABRAXAS Publisher.app"
ln -s "$APP" "$HOME/Desktop/ABRAXAS Publisher.app"

echo "✓ App instalada: $APP"

section "6/6 · RESULTADO"

echo ""
echo "ABRAXAS Publisher actualizado."
echo ""
echo "App Mac:"
echo "  $APP"
echo ""
echo "Backup anterior:"
echo "  $BACKUP"
echo ""
echo "MCP:"
echo "  $HOME/.local/share/abraxas-publisher-mcp"
echo ""
echo "PWA:"
echo "  https://lordjeferies.github.io/abraxas-publisher/"
echo ""
echo "Guía:"
echo "  https://lordjeferies.github.io/abraxas-publisher/guide.html"
echo ""
echo "Acciones Pages:"
echo "  https://github.com/$REPO/actions/workflows/pages.yml"
echo ""

open "$APP" || true
