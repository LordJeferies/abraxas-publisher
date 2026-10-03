#!/bin/bash
set -Eeuo pipefail

printf '\nABRAXAS Publisher · V1.4 clean build launcher\n'
printf 'Inicio: %s\n\n' "$(date)"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

for cmd in git gh node npm cargo python3 curl; do
  printf 'Comprobando %-8s ... ' "$cmd"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo 'OK'
  else
    echo 'FALTA'
    exit 1
  fi
done

echo
echo 'Comprobando sesión GitHub...'
if gh auth status >/dev/null 2>&1; then
  echo '✓ GitHub CLI autenticado'
else
  echo 'GitHub CLI necesita iniciar sesión.'
  gh auth login
fi

echo
echo 'Descargando build limpio V1.4...'
TARGET="/tmp/BUILD_V14_CLEAN.command"
curl --connect-timeout 15 --max-time 60 -fsSL \
  "https://raw.githubusercontent.com/LordJeferies/abraxas-publisher/main/BUILD_V14_CLEAN.command" \
  -o "$TARGET"
chmod +x "$TARGET"

echo '✓ Script descargado'
echo 'Ejecutando V1.4 clean build con trazas de etapa...'
echo

bash "$TARGET"
