#!/bin/bash
set -Eeuo pipefail

###############################################################################
# ABRAXAS PUBLISHER V1.2
# Reparación final + QA + Build + Instalación + GitHub
###############################################################################

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$ROOT/logs"
LOG="$LOG_DIR/v12_final_$STAMP.log"
BRANCH="v1.2-workspace"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS PUBLISHER V1.2 · FALLO"
  echo "=============================================================="
  echo "$*"
  echo
  echo "Log:"
  echo "$LOG"
  exit 1
}

section() {
  echo
  echo "=============================================================="
  echo " $*"
  echo "=============================================================="
}

###############################################################################
# 1. BACKUP DE FUENTES
###############################################################################

section "1/11 · BACKUP"

BACKUP_DIR="$ROOT/.v12-final-backup/$STAMP"
mkdir -p "$BACKUP_DIR"

for f in \
  src/App.tsx \
  src/components/ContentDetail.tsx \
  src/views/CalendarView.tsx \
  src/views/ImportView.tsx
do
  if [ -f "$f" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
done

echo "✓ Backup:"
echo "$BACKUP_DIR"

###############################################################################
# 2. REPARAR TYPESCRIPT
###############################################################################

section "2/11 · REPARACIÓN TYPESCRIPT"

python3 <<'PY'
from pathlib import Path
import re

###############################################################################
# APP.TSX
###############################################################################

p = Path("src/App.tsx")
s = p.read_text(encoding="utf-8")

# ContentDetail sólo recibe item.
# Eliminar brands={brands} si quedó de una versión anterior.
s = re.sub(
    r'\s*brands=\{brands\}',
    '',
    s,
)

p.write_text(s, encoding="utf-8")

print("✓ App.tsx")

###############################################################################
# CONTENTDETAIL.TSX
###############################################################################

p = Path("src/components/ContentDetail.tsx")
s = p.read_text(encoding="utf-8")

# changeStatus puede recibir string.
# Rust valida los estados permitidos.
s = re.sub(
    r'''const\s+changeStatus\s*=\s*
        async\s*\(\s*
        value:\s*WorkflowStatus\s*
        \)''',
    '''const changeStatus =
    async (
      value: string,
    )''',
    s,
    flags=re.S | re.X,
)

# Si el formato exacto es distinto:
s = re.sub(
    r'value:\s*WorkflowStatus',
    'value: string',
    s,
)

# Eliminar casts restantes:
s = re.sub(
    r'e\.target\.value\s+as\s+WorkflowStatus',
    'e.target.value',
    s,
)

s = re.sub(
    r'item\.status\s+as\s+WorkflowStatus',
    'item.status',
    s,
)

p.write_text(s, encoding="utf-8")

print("✓ ContentDetail.tsx")

###############################################################################
# LIMPIEZA DE IMPORTS NO USADOS DE WorkflowStatus
###############################################################################

# No lo eliminamos agresivamente porque todavía puede usarse en la lista
# statuses. TypeScript decidirá.
PY

###############################################################################
# 3. TYPECHECK
###############################################################################

section "3/11 · TYPESCRIPT"

set +e

npm run check 2>&1 | tee /tmp/abraxas_v12_final_tsc.log

TSC_STATUS="${PIPESTATUS[0]}"

set -e

if [ "$TSC_STATUS" -ne 0 ]; then

  echo
  echo "=============================================================="
  echo " ERRORES TYPESCRIPT RESTANTES"
  echo "=============================================================="

  python3 <<'PY'
from pathlib import Path
import re

log = Path(
    "/tmp/abraxas_v12_final_tsc.log"
).read_text(
    encoding="utf-8",
    errors="replace",
)

matches = re.findall(
    r'(src/[^(:]+\.(?:tsx|ts))\((\d+),(\d+)\)',
    log,
)

seen = set()

for filename, line, col in matches:
    line = int(line)

    key = (filename, line)

    if key in seen:
        continue

    seen.add(key)

    path = Path(filename)

    if not path.exists():
        continue

    lines = path.read_text(
        encoding="utf-8",
        errors="replace",
    ).splitlines()

    print()
    print("=" * 72)
    print(f"{filename}:{line}:{col}")
    print("=" * 72)

    lo = max(1, line - 8)
    hi = min(len(lines), line + 8)

    for n in range(lo, hi + 1):
        mark = ">>" if n == line else "  "
        print(
            f"{mark} {n:4}: {lines[n-1]}"
        )
PY

  fail "TypeScript todavía tiene errores."

fi

echo "✓ TypeScript"

###############################################################################
# 4. FRONTEND
###############################################################################

section "4/11 · FRONTEND"

npm run build \
  || fail "Vite build falló."

echo "✓ Frontend"

###############################################################################
# 5. RUST CHECK
###############################################################################

section "5/11 · RUST CHECK"

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all \
  || true

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

echo "✓ cargo check"

###############################################################################
# 6. RUST TESTS
###############################################################################

section "6/11 · RUST TESTS"

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

echo "✓ cargo test"

###############################################################################
# 7. CLI + MCP
###############################################################################

section "7/11 · PUBLISHERCTL / MCP"

cargo build \
  --release \
  --manifest-path src-tauri/Cargo.toml \
  --bin publisherctl \
  || fail "publisherctl no compiló."

chmod +x \
  publisherctl \
  publisher-mcp \
  tools/publisher_mcp.py \
  2>/dev/null || true

./publisherctl qa \
  || fail "publisherctl qa falló."

./publisher-mcp --self-test \
  || fail "publisher-mcp self-test falló."

echo "✓ publisherctl"
echo "✓ publisher-mcp"

###############################################################################
# 8. DOCTOR
###############################################################################

section "8/11 · DOCTOR"

if [ -x scripts/doctor.sh ]; then
  scripts/doctor.sh \
    || fail "Doctor falló."
else
  echo "WARN: scripts/doctor.sh no encontrado."
fi

###############################################################################
# 9. TAURI BUILD
###############################################################################

section "9/11 · TAURI BUILD"

npm run tauri:build \
  || fail "Tauri build falló."

NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"

if [ ! -d "$NEW_APP" ]; then

  NEW_APP="$(
    find \
      "$ROOT/src-tauri/target/release/bundle" \
      -type d \
      -name "ABRAXAS Publisher.app" \
      -print \
      -quit
  )"

fi

[ -n "${NEW_APP:-}" ] \
  || fail "No apareció el bundle .app."

[ -d "$NEW_APP" ] \
  || fail "El bundle generado no existe."

echo "✓ Bundle:"
echo "$NEW_APP"

###############################################################################
# 10. INSTALACIÓN
###############################################################################

section "10/11 · INSTALACIÓN"

INSTALL_DIR="$HOME/Applications"

APP="$INSTALL_DIR/ABRAXAS Publisher.app"

BACKUP_APP="$INSTALL_DIR/ABRAXAS Publisher.before-v12-$STAMP.app"

STAGE="$INSTALL_DIR/.ABRAXAS Publisher.stage-$STAMP.app"

mkdir -p "$INSTALL_DIR"

rm -rf "$STAGE"

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

  echo "✓ Backup app anterior:"
  echo "$BACKUP_APP"

fi

if ! mv \
  "$STAGE" \
  "$APP"
then

  echo "ERROR instalando bundle nuevo."

  if [ -d "$BACKUP_APP" ]; then

    mv \
      "$BACKUP_APP" \
      "$APP" \
      || true

    echo "✓ Restaurada app anterior."

  fi

  fail "No se pudo instalar V1.2."

fi

xattr -dr \
  com.apple.quarantine \
  "$APP" \
  >/dev/null 2>&1 \
  || true

echo "✓ Instalada:"
echo "$APP"

###############################################################################
# INSTALAR publisherctl
###############################################################################

mkdir -p "$HOME/.local/bin"

cp \
  "$ROOT/src-tauri/target/release/publisherctl" \
  "$HOME/.local/bin/publisherctl"

chmod +x \
  "$HOME/.local/bin/publisherctl"

###############################################################################
# INSTALAR publisher-mcp
###############################################################################

MCP_DIR="$HOME/Library/Application Support/com.abraxas.publisher/tools"

mkdir -p "$MCP_DIR"

cp \
  "$ROOT/tools/publisher_mcp.py" \
  "$MCP_DIR/publisher_mcp.py"

chmod +x \
  "$MCP_DIR/publisher_mcp.py"

cat > "$HOME/.local/bin/publisher-mcp" <<EOF
#!/bin/bash
set -Eeuo pipefail

export PATH="\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"

exec python3 \
  "$MCP_DIR/publisher_mcp.py" \
  "\$@"
EOF

chmod +x \
  "$HOME/.local/bin/publisher-mcp"

export PATH="$HOME/.local/bin:$PATH"

###############################################################################
# POST-INSTALL QA
###############################################################################

echo
echo "Post-install QA..."

publisherctl doctor \
  || fail "publisherctl doctor falló."

publisherctl qa \
  || fail "publisherctl qa post-install falló."

publisher-mcp --self-test \
  || fail "MCP post-install falló."

echo "✓ Post-install QA"

###############################################################################
# 11. GITHUB
###############################################################################

section "11/11 · GITHUB"

if git show-ref \
  --verify \
  --quiet \
  "refs/heads/$BRANCH"
then

  git switch "$BRANCH"

else

  git switch \
    -c "$BRANCH"

fi

git add -A

if ! git diff \
  --cached \
  --quiet
then

  git commit \
    -m "Complete ABRAXAS Publisher V1.2"

fi

git push \
  -u origin \
  "$BRANCH"

echo "✓ GitHub actualizado"

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.2 · COMPLETADA"
echo "=============================================================="
echo
echo "App:"
echo "  $APP"
echo
echo "Backup de la anterior:"
echo "  ${BACKUP_APP:-ninguno}"
echo
echo "CLI:"
echo "  $(command -v publisherctl)"
echo
echo "MCP:"
echo "  $(command -v publisher-mcp)"
echo
echo "Repo:"
echo "  https://github.com/LordJeferies/abraxas-publisher"
echo
echo "Rama:"
echo "  $BRANCH"
echo
echo "Log:"
echo "  $LOG"
echo
echo "Tests ejecutados:"
echo "  ✓ TypeScript"
echo "  ✓ Vite"
echo "  ✓ cargo check"
echo "  ✓ cargo test"
echo "  ✓ publisherctl qa"
echo "  ✓ publisher-mcp"
echo "  ✓ Tauri build"
echo "  ✓ post-install QA"
echo
echo "Publicación social:"
echo "  DESACTIVADA"
echo
echo "Puedes probar además:"
echo
echo "  publisherctl brands list"
echo "  publisherctl content list"
echo "  publisherctl activity"
echo "  publisherctl dry-run"
echo

open "$APP" || true
