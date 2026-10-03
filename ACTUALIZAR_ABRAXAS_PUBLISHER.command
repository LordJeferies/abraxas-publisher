#!/bin/bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/INSTALAR_ABRAXAS_PUBLISHER.command"
