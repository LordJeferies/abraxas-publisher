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

cat <<EOF

ABRAXAS Publisher MCP listo.

Servidor:
  $ROOT/mcp/server.mjs

Bridge:
  $BRIDGE

Configuración MCP genérica:

{
  "mcpServers": {
    "abraxas-publisher": {
      "command": "node",
      "args": ["$ROOT/mcp/server.mjs"],
      "env": {
        "ABRAXAS_PUBLISHER_MCP_BRIDGE": "$BRIDGE"
      }
    }
  }
}

Consulta docs/MCP.md para ChatGPT/Codex/Claude y criterios de seguridad.
EOF
