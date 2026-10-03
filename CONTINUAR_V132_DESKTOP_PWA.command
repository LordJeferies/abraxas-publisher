#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

BRANCH="v1.3-publishing-center"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$ROOT/logs/v132_continue_$STAMP.log"

mkdir -p "$ROOT/logs"

exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS PUBLISHER V1.3.2 · FALLO"
  echo "=============================================================="
  echo "$*"
  echo
  echo "Log:"
  echo "  $LOG"
  exit 1
}

section() {
  echo
  echo "=============================================================="
  echo " $*"
  echo "=============================================================="
}

###############################################################################
# 1. VERIFICAR LO YA CREADO
###############################################################################

section "1/9 · VERIFICAR V1.3.2 PARCIAL"

git switch "$BRANCH"

REQUIRED=(
  "src/lib/nativeBackend.ts"
  "src/lib/webBackend.ts"
  "src/lib/runtime.ts"
  "src/lib/sync.ts"
  "src/views/SyncView.tsx"
  "src/views/HelpView.tsx"
  "src/pwa.ts"
  "public/manifest.webmanifest"
  "public/sw.js"
  "public/abraxas-icon.svg"
  ".github/workflows/pages.yml"
  "docs/DESKTOP_WEB_PWA_SYNC.md"
  "docs/MOBILE_PUBLISHING.md"
)

MISSING=0

for FILE in "${REQUIRED[@]}"
do
  if [ -f "$FILE" ]; then
    echo "✓ $FILE"
  else
    echo "✕ FALTA: $FILE"
    MISSING=1
  fi
done

if [ "$MISSING" -ne 0 ]; then
  fail "El script anterior se cortó antes de terminar los archivos fundamentales."
fi

echo
echo "Versión package:"
node -p "require('./package.json').version"

###############################################################################
# 2. VALIDAR ROUTER BACKEND
###############################################################################

section "2/9 · VALIDAR DESKTOP / WEB ROUTER"

cat > src/lib/backend.ts <<'TS'
import {
  nativeBackend,
} from './nativeBackend'

import {
  webBackend,
} from './webBackend'

import {
  isTauriRuntime,
} from './runtime'

/*
 * Desktop:
 *   Tauri commands + SQLite + filesystem + Drive Desktop.
 *
 * Web/PWA:
 *   browser-safe implementation.
 *
 * Cuando ABRAXAS Sync API esté configurada,
 * WebBackend evolucionará para usar el workspace cloud.
 */
export const backend =
  (
    isTauriRuntime()
      ? nativeBackend
      : webBackend
  ) as unknown as
    typeof nativeBackend
TS

grep -q \
  "export const nativeBackend" \
  src/lib/nativeBackend.ts \
  || fail "nativeBackend.ts no exporta nativeBackend."

grep -q \
  "export const webBackend" \
  src/lib/webBackend.ts \
  || fail "webBackend.ts no exporta webBackend."

echo "✓ Backend runtime router"

###############################################################################
# 3. ASEGURAR SERVICE WORKER
###############################################################################

section "3/9 · PWA FOUNDATION"

python3 <<'PY'
from pathlib import Path

p = Path("src/main.tsx")
s = p.read_text()

if "registerPwa" not in s:
    s = s.replace(
        "import './styles.css'",
        """import './styles.css'
import { registerPwa } from './pwa'""",
        1,
    )

    s += """

registerPwa()
"""

p.write_text(s)

print("✓ main.tsx")
PY

python3 <<'PY'
from pathlib import Path

p = Path("index.html")
s = p.read_text()

if 'manifest.webmanifest' not in s:
    s = s.replace(
        '</head>',
        '''  <link rel="manifest" href="./manifest.webmanifest">
  <meta name="theme-color" content="#17253c">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-title" content="ABRAXAS">
  <link rel="icon" href="./abraxas-icon.svg">
</head>''',
        1,
    )

p.write_text(s)

print("✓ index.html")
PY

###############################################################################
# 4. TERMINAR CSS SI EL SCRIPT ANTERIOR NO LLEGÓ
###############################################################################

section "4/9 · UI SYNC / HELP"

if ! grep -q \
  "V1.3.2 · Desktop / Web / PWA / Sync" \
  src/styles.css
then

cat >> src/styles.css <<'CSS'

/* ==========================================================
   V1.3.2 · Desktop / Web / PWA / Sync
   ========================================================== */

.sync-grid{
  display:grid;
  grid-template-columns:repeat(2,minmax(0,1fr));
  gap:10px;
  margin-bottom:10px;
}

.sync-card{
  position:relative;
}

.sync-card-icon{
  width:38px;
  height:38px;
  border-radius:11px;
  display:grid;
  place-items:center;
  margin-bottom:10px;
  background:rgba(60,90,150,.09);
}

.sync-card h2{
  margin:4px 0;
}

.sync-card p,
.sync-card small{
  color:var(--muted);
}

.sync-explainer{
  margin-bottom:10px;
}

.sync-flow-row{
  display:grid;
  grid-template-columns:100px 1fr auto 1fr auto 1fr;
  gap:8px;
  align-items:center;
  border-top:1px solid var(--line);
  padding:10px 0;
  font-size:9px;
}

.cloud-foundation-warning{
  display:grid;
  grid-template-columns:auto 1fr;
  gap:10px;
  align-items:flex-start;
  margin-bottom:10px;
  background:rgba(220,145,20,.07);
  border-color:rgba(220,145,20,.3);
}

.cloud-foundation-warning p{
  color:var(--muted);
  margin-bottom:0;
}

.capability-table{
  display:grid;
}

.capability-table>div{
  display:flex;
  justify-content:space-between;
  gap:15px;
  padding:8px 0;
  border-top:1px solid var(--line);
}

.capability-table b{
  display:flex;
  gap:5px;
  align-items:center;
  text-align:right;
}

.help-architecture{
  margin-bottom:10px;
}

.architecture-diagram{
  display:grid;
  grid-template-columns:1fr auto 1fr auto 1fr;
  gap:10px;
  align-items:center;
  margin-top:14px;
}

.architecture-diagram>div{
  border:1px solid var(--line);
  border-radius:12px;
  padding:12px;
}

.architecture-diagram strong,
.architecture-diagram span{
  display:block;
}

.architecture-diagram span{
  color:var(--muted);
  margin-top:4px;
  font-size:9px;
}

.help-comparison{
  display:grid;
}

.help-comparison>div{
  display:grid;
  grid-template-columns:minmax(180px,1fr) 120px 120px;
  gap:10px;
  padding:7px 0;
  border-top:1px solid var(--line);
}

.help-comparison-head{
  border-top:0 !important;
}

.execution-doc-grid{
  display:grid;
  grid-template-columns:repeat(3,1fr);
  gap:8px;
  margin-top:10px;
}

.execution-doc-grid article{
  border:1px solid var(--line);
  border-radius:11px;
  padding:11px;
}

.execution-doc-grid p{
  color:var(--muted);
  font-size:9px;
  line-height:1.5;
}

.help-steps{
  color:var(--muted);
  line-height:1.7;
}

@media(max-width:800px){
  .sync-grid{
    grid-template-columns:1fr;
  }

  .sync-flow-row{
    grid-template-columns:1fr;
  }

  .architecture-diagram{
    grid-template-columns:1fr;
  }

  .architecture-diagram>b{
    transform:rotate(90deg);
    justify-self:center;
  }

  .help-comparison{
    overflow-x:auto;
  }

  .help-comparison>div{
    min-width:520px;
  }

  .execution-doc-grid{
    grid-template-columns:1fr;
  }
}
CSS

  echo "✓ CSS V1.3.2 añadido"
else
  echo "✓ CSS V1.3.2 ya existía"
fi

###############################################################################
# 5. TYPESCRIPT / FRONTEND
###############################################################################

section "5/9 · TYPESCRIPT / VITE"

npm install

npm run check \
  || fail "TypeScript falló."

npm run build \
  || fail "Frontend Desktop falló."

echo "✓ TypeScript"
echo "✓ Vite Desktop"

###############################################################################
# 6. RUST
###############################################################################

section "6/9 · RUST"

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

echo "✓ Rust"

###############################################################################
# 7. PWA BUILD
###############################################################################

section "7/9 · WEB / PWA BUILD"

rm -rf dist

GITHUB_ACTIONS=true \
npm run build:web \
  || fail "build:web falló."

[ -f dist/index.html ] \
  || fail "No existe dist/index.html"

[ -f dist/manifest.webmanifest ] \
  || fail "No existe manifest.webmanifest en dist."

[ -f dist/sw.js ] \
  || fail "No existe sw.js en dist."

[ -f dist/abraxas-icon.svg ] \
  || fail "No existe icono PWA."

grep -q \
  "/abraxas-publisher/" \
  dist/index.html \
  || fail "El build de Pages no está usando /abraxas-publisher/."

echo
echo "✓ PWA build"
echo "✓ manifest"
echo "✓ service worker"
echo "✓ GitHub Pages base"

###############################################################################
# 8. DESKTOP BUILD / INSTALL
###############################################################################

section "8/9 · DESKTOP BUILD / INSTALL"

unset GITHUB_ACTIONS

npm run tauri:build \
  || fail "Tauri build falló."

NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"

if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(
    find \
      "$ROOT/src-tauri/target/release/bundle" \
      -type d \
      -name "*.app" \
      -print \
      -quit
  )"
fi

[ -d "$NEW_APP" ] \
  || fail "No se encontró ABRAXAS Publisher.app."

APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP_APP="$HOME/Applications/ABRAXAS Publisher.V131.pre-v132.$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.V132.$STAMP.app"

mkdir -p \
  "$HOME/Applications"

rm -rf \
  "$STAGE"

ditto \
  "$NEW_APP" \
  "$STAGE"

xattr -dr \
  com.apple.quarantine \
  "$STAGE" \
  >/dev/null 2>&1 \
  || true

if [ -d "$APP" ]; then
  mv \
    "$APP" \
    "$BACKUP_APP"
fi

if ! mv \
  "$STAGE" \
  "$APP"
then
  if [ -d "$BACKUP_APP" ]; then
    mv \
      "$BACKUP_APP" \
      "$APP" \
      || true
  fi

  fail "No se pudo instalar V1.3.2."
fi

###############################################################################
# ACCESO ESCRITORIO
###############################################################################

DESKTOP_LINK="$HOME/Desktop/ABRAXAS Publisher.app"

rm -f \
  "$DESKTOP_LINK"

ln -s \
  "$APP" \
  "$DESKTOP_LINK"

[ -L "$DESKTOP_LINK" ] \
  || fail "No se creó el acceso del Escritorio."

echo
echo "✓ Desktop instalada:"
echo "  $APP"
echo
echo "✓ Acceso Escritorio:"
echo "  $DESKTOP_LINK"

###############################################################################
# 9. GIT / RELEASE / PAGES
###############################################################################

section "9/9 · GITHUB / RELEASE"

git add -A

if ! git diff \
  --cached \
  --quiet
then
  git commit \
    -m "ABRAXAS Publisher V1.3.2 Desktop Web PWA Sync Foundation"
fi

RELEASE_SHA="$(
  git rev-parse HEAD
)"

git tag \
  -f \
  publisher-v1.3.2

git push \
  -u origin \
  "$BRANCH"

git push \
  origin \
  publisher-v1.3.2 \
  --force

###############################################################################
# MAIN:
# sólo fast-forward; jamás force.
###############################################################################

MAIN_UPDATED="no"

if git push \
  origin \
  "$BRANCH:main"
then
  MAIN_UPDATED="yes"
  echo "✓ main actualizado"
else
  echo
  echo "main no admite fast-forward directo."
  echo "No se forzó."
  echo "La rama V1.3.2 sí está subida."
fi

###############################################################################
# GITHUB PAGES
###############################################################################

echo
echo "Intentando configurar GitHub Pages con Actions..."

if command -v gh >/dev/null 2>&1
then
  if gh auth status >/dev/null 2>&1
  then
    if gh api \
      repos/LordJeferies/abraxas-publisher/pages \
      >/dev/null 2>&1
    then
      gh api \
        --method PUT \
        repos/LordJeferies/abraxas-publisher/pages \
        -f build_type=workflow \
        >/dev/null 2>&1 \
        || true
    else
      gh api \
        --method POST \
        repos/LordJeferies/abraxas-publisher/pages \
        -f build_type=workflow \
        >/dev/null 2>&1 \
        || true
    fi
  fi
fi

###############################################################################
# SNAPSHOTS
###############################################################################

RELEASE_DIR="$HOME/Developer/abraxas-publisher/releases/v1.3.2"

mkdir -p \
  "$RELEASE_DIR"

FULL_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.2_FULL.zip"

rm -f \
  "$FULL_ZIP"

git archive \
  --format=zip \
  --output="$FULL_ZIP" \
  HEAD

###############################################################################
# INFO
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.3.2 · COMPLETADA"
echo "=============================================================="
echo
echo "Desktop:"
echo "  $APP"
echo
echo "Acceso en Escritorio:"
echo "  $DESKTOP_LINK"
echo
echo "Backup:"
echo "  $BACKUP_APP"
echo
echo "Branch:"
echo "  $BRANCH"
echo
echo "Commit:"
echo "  $RELEASE_SHA"
echo
echo "main actualizado:"
echo "  $MAIN_UPDATED"
echo
echo "PWA:"
echo "  https://lordjeferies.github.io/abraxas-publisher/"
echo
echo "FULL:"
echo "  $FULL_ZIP"
echo
echo "Log:"
echo "  $LOG"
echo
echo "VALIDADO:"
echo "  ✓ NativeBackend"
echo "  ✓ WebBackend"
echo "  ✓ Runtime detection"
echo "  ✓ Sync Foundation"
echo "  ✓ Sync Center"
echo "  ✓ Desktop/Web/PWA Help"
echo "  ✓ manifest"
echo "  ✓ service worker"
echo "  ✓ Pages workflow"
echo "  ✓ Web build"
echo "  ✓ Tauri build"
echo "  ✓ Desktop shortcut"
echo
echo "IMPORTANTE:"
echo "  Cross-device Sync todavía requiere"
echo "  VITE_ABRAXAS_SYNC_API."
echo
echo "  GitHub Pages no se usa como base de datos."
echo

open "$APP" || true

