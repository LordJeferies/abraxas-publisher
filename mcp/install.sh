#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

command -v node >/dev/null || { echo "ERROR: Node 20+ es requerido."; exit 1; }
command -v cargo >/dev/null || { echo "ERROR: Rust/Cargo es requerido."; exit 1; }

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 20 ] || { echo "ERROR: Node 20+ es requerido."; exit 1; }

echo "Construyendo bridge MCP nativo..."
cargo build --release --manifest-path src-tauri/Cargo.toml --bin publisher_mcp_bridge

BRIDGE="$ROOT/src-tauri/target/release/publisher_mcp_bridge"
[ -x "$BRIDGE" ] || { echo "ERROR: bridge no fue construido."; exit 1; }

node "$ROOT/mcp/server.mjs" --self-test

INSTALL_DIR="$HOME/.local/share/abraxas-publisher-mcp"
mkdir -p "$INSTALL_DIR"

cp "$ROOT/mcp/server.mjs" "$INSTALL_DIR/server.mjs"
cp "$BRIDGE" "$INSTALL_DIR/publisher_mcp_bridge"
chmod +x "$INSTALL_DIR/publisher_mcp_bridge"

cat > "$INSTALL_DIR/mcp-config.json" <<EOF
{
  "mcpServers": {
    "abraxas-publisher": {
      "command": "node",
      "args": ["$INSTALL_DIR/server.mjs"],
      "env": {
        "ABRAXAS_PUBLISHER_MCP_BRIDGE": "$INSTALL_DIR/publisher_mcp_bridge"
      }
    }
  }
}
EOF

cat <<EOF

ABRAXAS Publisher MCP listo.

Instalación estable:
  $INSTALL_DIR

Servidor:
  $INSTALL_DIR/server.mjs

Bridge:
  $INSTALL_DIR/publisher_mcp_bridge

Configuración MCP:
  $INSTALL_DIR/mcp-config.json

Copia el objeto de mcp-config.json en el cliente MCP que uses.
Consulta docs/MCP.md para criterios y ejemplos.
EOF
