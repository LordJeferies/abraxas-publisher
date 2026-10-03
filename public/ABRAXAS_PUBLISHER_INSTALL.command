#!/bin/bash
set -Eeuo pipefail

EXPECTED_HASH="ad2933fb937d4aff05e49bfc9f2349255c1ca7e5eb354ce75e3dc34a2bbc2ee0"
REPO_URL="https://github.com/LordJeferies/abraxas-publisher.git"
SOURCE_ROOT="$HOME/.local/share/abraxas-publisher"
SOURCE_DIR="$SOURCE_ROOT/source"
MCP_DIR="$HOME/.local/share/abraxas-publisher-mcp"
APP="$HOME/Applications/ABRAXAS Publisher.app"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$HOME/Library/Logs/ABRAXAS Publisher"
LOG="$LOG_DIR/install-$STAMP.log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1

fail(){
  echo
  echo "INSTALACIÓN DETENIDA"
  echo "$*"
  echo
  echo "Log: $LOG"
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "Este instalador es sólo para macOS."

printf "Clave de instalación: "
IFS= read -rs INSTALL_KEY
echo

KEY_HASH="$(printf '%s' "$INSTALL_KEY" | shasum -a 256 | awk '{print $1}')"
unset INSTALL_KEY

[ "$KEY_HASH" = "$EXPECTED_HASH" ] || fail "Clave incorrecta."

echo
printf '%s\n' "ABRAXAS Publisher · instalación limpia"
printf '%s\n' "La instalación puede pedir la contraseña de administrador de tu Mac para instalar dependencias."

if ! xcode-select -p >/dev/null 2>&1; then
  echo
  echo "Faltan las Command Line Tools de Apple."
  echo "Se abrirá el instalador oficial de macOS."
  xcode-select --install >/dev/null 2>&1 || true
  fail "Termina de instalar las Command Line Tools y vuelve a abrir este instalador."
fi

if ! command -v brew >/dev/null 2>&1; then
  echo
  echo "Instalando Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail "No se pudo instalar Homebrew."
fi

if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$PATH"

install_brew_pkg(){
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo
    echo "Instalando $pkg..."
    brew install "$pkg" || fail "No se pudo instalar $pkg."
  fi
}

install_brew_pkg git git
install_brew_pkg node node
install_brew_pkg ffmpeg ffmpeg

if ! command -v cargo >/dev/null 2>&1; then
  echo
  echo "Instalando Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal || fail "No se pudo instalar Rust."
  [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
fi

command -v git >/dev/null || fail "Git no está disponible."
command -v node >/dev/null || fail "Node no está disponible."
command -v npm >/dev/null || fail "npm no está disponible."
command -v cargo >/dev/null || fail "Cargo no está disponible."
command -v ffmpeg >/dev/null || fail "FFmpeg no está disponible."

mkdir -p "$SOURCE_ROOT"

if [ -d "$SOURCE_DIR/.git" ]; then
  echo
  echo "Actualizando código fuente..."
  git -C "$SOURCE_DIR" fetch origin main
  git -C "$SOURCE_DIR" reset --hard origin/main
  git -C "$SOURCE_DIR" clean -fdx
else
  echo
  echo "Descargando ABRAXAS Publisher..."
  rm -rf "$SOURCE_DIR"
  git clone --depth 1 --branch main "$REPO_URL" "$SOURCE_DIR" || fail "No se pudo descargar Publisher."
fi

cd "$SOURCE_DIR"

echo
echo "Instalando dependencias del proyecto..."
npm ci || fail "npm ci falló."

echo
echo "Verificando frontend..."
npm run check || fail "TypeScript falló."

echo
echo "Verificando backend nativo..."
cargo check --manifest-path src-tauri/Cargo.toml || fail "cargo check falló."
cargo test --manifest-path src-tauri/Cargo.toml || fail "cargo test falló."

echo
echo "Instalando MCP..."
npm run mcp:build || fail "No se pudo compilar MCP."
npm run mcp:test || fail "El self-test MCP falló."
chmod +x mcp/install.sh
./mcp/install.sh || fail "No se pudo instalar MCP."

echo
echo "Construyendo aplicación Mac..."
npm run tauri:build || fail "No se pudo construir la aplicación."

NEW_APP="$SOURCE_DIR/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"
if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(find "$SOURCE_DIR/src-tauri/target/release/bundle" -type d -name '*.app' -print -quit)"
fi

[ -d "$NEW_APP" ] || fail "No se encontró la aplicación compilada."

mkdir -p "$HOME/Applications"

if [ -d "$APP" ]; then
  BACKUP="$HOME/Applications/ABRAXAS Publisher.backup-$STAMP.app"
  echo "Guardando backup anterior en: $BACKUP"
  mv "$APP" "$BACKUP"
fi

ditto "$NEW_APP" "$APP" || fail "No se pudo instalar la aplicación."
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true

rm -f "$HOME/Desktop/ABRAXAS Publisher.app"
ln -s "$APP" "$HOME/Desktop/ABRAXAS Publisher.app"

[ -f "$MCP_DIR/server.mjs" ] || fail "MCP server no quedó instalado."
[ -x "$MCP_DIR/publisher_mcp_bridge" ] || fail "MCP bridge no quedó instalado."

ABRAXAS_PUBLISHER_MCP_BRIDGE="$MCP_DIR/publisher_mcp_bridge" node "$MCP_DIR/server.mjs" --self-test || fail "MCP final self-test falló."

echo
echo "Verificando servicios web..."
for URL in \
  "https://lordjeferies.github.io/abraxas-publisher/" \
  "https://lordjeferies.github.io/abraxas-publisher/guide.html" \
  "https://lordjeferies.github.io/abraxas-publisher/mcp.html" \
  "https://lordjeferies.github.io/abraxas-publisher/install.html"
do
  CODE="$(curl -L -s -o /dev/null -w '%{http_code}' "$URL" || true)"
  echo "$CODE  $URL"
done

echo
echo "ABRAXAS Publisher instalado correctamente."
echo "App: $APP"
echo "MCP: $MCP_DIR"
echo "Código fuente local: $SOURCE_DIR"
echo "Log: $LOG"
echo

open "$APP" || true
