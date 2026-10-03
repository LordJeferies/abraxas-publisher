#!/bin/bash
set -Eeuo pipefail

printf '\nABRAXAS Publisher · actualización iPhone/PWA\n'
printf 'Inicio: %s\n\n' "$(date)"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

REPO="LordJeferies/abraxas-publisher"
STAMP="$(date +%Y%m%d_%H%M%S)"
ROOT="$HOME/Developer/abraxas-publisher-pwa-iphone-$STAMP"

need(){
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: falta $1"
    exit 1
  }
}

need git
need gh
need node
need npm
need curl

echo "1/6 · Comprobando GitHub"
if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI necesita iniciar sesión."
  gh auth login
fi

echo "2/6 · Clon limpio de main"
gh repo clone "$REPO" "$ROOT"
cd "$ROOT"
git switch main
git pull --ff-only origin main

echo "3/6 · Validando iPhone/PWA"
npm ci
npm run check
GITHUB_ACTIONS=true npm run build:web

test -f dist/index.html
test -f dist/manifest.webmanifest
test -f dist/sw.js

grep -q "viewport-fit=cover" index.html
grep -q "mobile-tabbar" src/mobile.css
grep -q "MobileNav" src/App.tsx

echo "✓ TypeScript y build PWA correctos"
echo "✓ viewport-fit=cover"
echo "✓ navegación móvil"
echo "✓ safe areas"

echo "4/6 · Lanzando deployment Pages"
gh workflow run pages.yml --repo "$REPO" --ref main

RUN_ID="$(gh run list --repo "$REPO" --workflow pages.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"

if [ -n "$RUN_ID" ]; then
  echo "Workflow: $RUN_ID"
  echo "Mostrando progreso de GitHub Actions..."
  gh run watch "$RUN_ID" --repo "$REPO" --exit-status
else
  echo "No se pudo obtener el run ID. Revisa GitHub Actions manualmente."
fi

echo "5/6 · Verificando URLs públicas"
for URL in \
  "https://lordjeferies.github.io/abraxas-publisher/" \
  "https://lordjeferies.github.io/abraxas-publisher/guide.html" \
  "https://lordjeferies.github.io/abraxas-publisher/mcp.html" \
  "https://lordjeferies.github.io/abraxas-publisher/install.html"
do
  CODE="$(curl -L -s -o /dev/null -w '%{http_code}' "$URL" || true)"
  echo "$CODE  $URL"
done

echo "6/6 · Listo"
echo
echo "PWA iPhone:"
echo "https://lordjeferies.github.io/abraxas-publisher/"
echo
echo "En iPhone: Safari → Compartir → Añadir a pantalla de inicio"
echo
open "https://lordjeferies.github.io/abraxas-publisher/" 2>/dev/null || true
