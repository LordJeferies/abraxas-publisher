#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f "$HOME/.cargo/env" ]]; then source "$HOME/.cargo/env"; fi
if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
if [[ ! -d node_modules ]]; then npm install; fi
npm run tauri:dev
