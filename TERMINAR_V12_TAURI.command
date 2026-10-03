#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$ROOT/logs/v12_tauri_final_$STAMP.log"
BRANCH="v1.2-workspace"

mkdir -p "$ROOT/logs"

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
# 1. BACKUP CARGO
###############################################################################

section "1/8 · CARGO CONFIG"

mkdir -p ".v12-cargo-backup/$STAMP"

cp \
  src-tauri/Cargo.toml \
  ".v12-cargo-backup/$STAMP/Cargo.toml"

###############################################################################
# 2. AÑADIR default-run
###############################################################################

python3 <<'PY'
from pathlib import Path
import re

path = Path("src-tauri/Cargo.toml")
text = path.read_text(encoding="utf-8")

# El paquete real según cargo es abraxas-publisher.
default_run = 'default-run = "abraxas-publisher"'

if default_run in text:
    print("✓ default-run ya estaba configurado.")

else:
    package_match = re.search(
        r'(?ms)^\[package\]\s*\n(.*?)(?=^\[|\Z)',
        text,
    )

    if not package_match:
        raise SystemExit(
            "ERROR: no encontré [package] en Cargo.toml."
        )

    block = package_match.group(0)

    # Si hubiera otro default-run, sustituirlo.
    if re.search(
        r'(?m)^\s*default-run\s*=',
        block,
    ):
        new_block = re.sub(
            r'(?m)^\s*default-run\s*=.*$',
            default_run,
            block,
            count=1,
        )

    else:
        # Insertarlo inmediatamente después de name.
        new_block, count = re.subn(
            r'(?m)^(name\s*=\s*"abraxas-publisher"\s*)$',
            r'\1\n' + default_run,
            block,
            count=1,
        )

        if count != 1:
            # Fallback: justo después de [package]
            new_block = block.replace(
                "[package]",
                "[package]\n" + default_run,
                1,
            )

    text = (
        text[:package_match.start()]
        + new_block
        + text[package_match.end():]
    )

    path.write_text(
        text,
        encoding="utf-8",
    )

    print("✓ default-run añadido.")

PY

echo
echo "Configuración package:"
echo

awk '
  /^\[package\]/ {show=1}
  show {print}
  show && /^\[/ && $0 != "[package]" {exit}
' src-tauri/Cargo.toml

###############################################################################
# 3. VERIFICAR TARGETS CARGO
###############################################################################

section "2/8 · VERIFICAR BINARIOS"

python3 <<'PY'
import json
import subprocess

raw = subprocess.check_output(
    [
        "cargo",
        "metadata",
        "--format-version",
        "1",
        "--no-deps",
        "--manifest-path",
        "src-tauri/Cargo.toml",
    ],
    text=True,
)

data = json.loads(raw)

package = next(
    p
    for p in data["packages"]
    if p["name"] == "abraxas-publisher"
)

print("Package:", package["name"])
print("Targets:")

names = []

for target in package["targets"]:
    print(
        " -",
        target["name"],
        "|",
        ",".join(target["kind"]),
    )

    if "bin" in target["kind"]:
        names.append(target["name"])

if "abraxas-publisher" not in names:
    raise SystemExit(
        "ERROR: no existe binario principal abraxas-publisher."
    )

print()
print("✓ Binario principal encontrado.")
PY

###############################################################################
# 4. PRE-BUILD CHECKS RÁPIDOS
###############################################################################

section "3/8 · PRE-BUILD QA"

npm run check \
  || fail "TypeScript falló."

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

echo "✓ TypeScript"
echo "✓ Rust"

###############################################################################
# 5. TAURI BUILD
###############################################################################

section "4/8 · TAURI BUILD"

npm run tauri:build \
  || fail "Tauri build volvió a fallar."

echo
echo "✓ Tauri build completado"

###############################################################################
# 6. ENCONTRAR APP
###############################################################################

section "5/8 · LOCALIZAR BUNDLE"

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

[ -n "${NEW_APP:-}" ] \
  || fail "No encontré ninguna .app generada."

[ -d "$NEW_APP" ] \
  || fail "La ruta del bundle no existe."

echo "Bundle:"
echo "$NEW_APP"

###############################################################################
# 7. INSTALACIÓN SEGURA
###############################################################################

section "6/8 · INSTALAR APP"

INSTALL_DIR="$HOME/Applications"

APP="$INSTALL_DIR/ABRAXAS Publisher.app"

BACKUP_APP="$INSTALL_DIR/ABRAXAS Publisher.before-v12-$STAMP.app"

STAGE="$INSTALL_DIR/.ABRAXAS Publisher.v12-$STAMP.app"

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

# Comprobar que el ejecutable existe ANTES de tocar la app instalada.
MAIN_BIN="$STAGE/Contents/MacOS/abraxas-publisher"

if [ ! -x "$MAIN_BIN" ]; then
  echo
  echo "Ejecutables encontrados:"
  find \
    "$STAGE/Contents/MacOS" \
    -maxdepth 1 \
    -type f \
    -print \
    2>/dev/null || true

  fail "El bundle no contiene el ejecutable principal esperado."
fi

echo "✓ Ejecutable principal verificado"

if [ -d "$APP" ]; then

  mv \
    "$APP" \
    "$BACKUP_APP"

  echo "✓ Backup de app anterior:"
  echo "$BACKUP_APP"

fi

if ! mv \
  "$STAGE" \
  "$APP"
then

  echo "ERROR instalando V1.2."

  if [ -d "$BACKUP_APP" ]; then
    mv \
      "$BACKUP_APP" \
      "$APP" \
      || true

    echo "✓ App anterior restaurada"
  fi

  fail "No se pudo instalar la nueva app."
fi

xattr -dr \
  com.apple.quarantine \
  "$APP" \
  >/dev/null 2>&1 \
  || true

echo "✓ Nueva app instalada:"
echo "$APP"

###############################################################################
# 8. INSTALAR CLI
###############################################################################

section "7/8 · CLI / MCP / POST-QA"

mkdir -p "$HOME/.local/bin"

PUBLISHERCTL="$ROOT/src-tauri/target/release/publisherctl"

if [ ! -x "$PUBLISHERCTL" ]; then

  cargo build \
    --release \
    --manifest-path src-tauri/Cargo.toml \
    --bin publisherctl

fi

[ -x "$PUBLISHERCTL" ] \
  || fail "publisherctl no existe."

cp \
  "$PUBLISHERCTL" \
  "$HOME/.local/bin/publisherctl"

chmod +x \
  "$HOME/.local/bin/publisherctl"

###############################################################################
# MCP
###############################################################################

MCP_DIR="$HOME/Library/Application Support/com.abraxas.publisher/tools"

mkdir -p "$MCP_DIR"

[ -f tools/publisher_mcp.py ] \
  || fail "Falta tools/publisher_mcp.py"

cp \
  tools/publisher_mcp.py \
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
# POST QA
###############################################################################

publisherctl doctor \
  || fail "publisherctl doctor falló."

publisherctl qa \
  || fail "publisherctl qa falló."

publisher-mcp --self-test \
  || fail "publisher-mcp self-test falló."

echo
echo "✓ CLI"
echo "✓ MCP"
echo "✓ QA post-install"

###############################################################################
# 9. GIT
###############################################################################

section "8/8 · GITHUB"

git switch "$BRANCH" 2>/dev/null \
  || git switch -c "$BRANCH"

git add -A

if ! git diff \
  --cached \
  --quiet
then

  git commit \
    -m "Configure Tauri main binary and complete V1.2"

fi

git push \
  -u origin \
  "$BRANCH"

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.2 · COMPLETADA"
echo "=============================================================="
echo
echo "Aplicación:"
echo "  $APP"
echo
echo "Backup anterior:"
echo "  ${BACKUP_APP:-ninguno}"
echo
echo "CLI:"
echo "  $(command -v publisherctl)"
echo
echo "MCP:"
echo "  $(command -v publisher-mcp)"
echo
echo "Rama GitHub:"
echo "  $BRANCH"
echo
echo "Log:"
echo "  $LOG"
echo
echo "Estado:"
echo "  ✓ TypeScript"
echo "  ✓ Rust"
echo "  ✓ Tauri"
echo "  ✓ publisherctl"
echo "  ✓ MCP"
echo "  ✓ QA"
echo
echo "Publicación social real:"
echo "  DESACTIVADA"
echo

open "$APP" || true

