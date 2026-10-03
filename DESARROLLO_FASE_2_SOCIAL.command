#!/bin/bash
set -Eeuo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

REPO="LordJeferies/abraxas-publisher"
BRANCH="v1.4-provider-adapters"
STAMP="$(date +%Y%m%d_%H%M%S)"
ROOT="$HOME/Developer/abraxas-publisher-v14-$STAMP"
APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP="$HOME/Applications/ABRAXAS Publisher.pre-v14-$STAMP.app"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Falta $1"; exit 1; }; }
need git
need gh
need node
need npm
need cargo

gh auth status >/dev/null 2>&1 || gh auth login

echo "1/7 · Clon limpio"
gh repo clone "$REPO" "$ROOT"
cd "$ROOT"
git switch main
git pull --ff-only origin main
git switch -c "$BRANCH"

echo "2/7 · Provider contracts"
mkdir -p src/lib/providers docs
cat > src/lib/providers/types.ts <<'EOF'
export type ProviderId =
  | 'META'
  | 'YOUTUBE'
  | 'LINKEDIN'
  | 'TIKTOK'

export type ProviderReadiness =
  | 'READY_FOR_OAUTH'
  | 'NEEDS_DEVELOPER_APP'
  | 'NEEDS_REVIEW'
  | 'CONNECTED'
  | 'DISABLED'

export type ProviderCapability = {
  key: string
  label: string
  supported: boolean
  note?: string
}

export type ProviderDefinition = {
  id: ProviderId
  label: string
  executionHost: 'CLOUD' | 'DESKTOP'
  readiness: ProviderReadiness
  oauthRequired: boolean
  env: string[]
  capabilities: ProviderCapability[]
  notes: string[]
}
EOF

cat > src/lib/providers/catalog.ts <<'EOF'
import type { ProviderDefinition } from './types'

export const providerCatalog: ProviderDefinition[] = [
  {
    id: 'META',
    label: 'Meta · Instagram / Facebook',
    executionHost: 'CLOUD',
    readiness: 'NEEDS_DEVELOPER_APP',
    oauthRequired: true,
    env: [
      'ABRAXAS_META_APP_ID',
      'ABRAXAS_META_APP_SECRET',
      'ABRAXAS_META_REDIRECT_URI',
    ],
    capabilities: [
      { key: 'instagram', label: 'Instagram publishing', supported: true },
      { key: 'facebook', label: 'Facebook Page publishing', supported: true },
      { key: 'verify', label: 'Remote verification', supported: true },
    ],
    notes: [
      'Requiere una Meta developer app y permisos aprobados para los destinos usados.',
      'Los secretos no deben ir al frontend ni al repositorio.',
    ],
  },
  {
    id: 'YOUTUBE',
    label: 'YouTube',
    executionHost: 'DESKTOP',
    readiness: 'READY_FOR_OAUTH',
    oauthRequired: true,
    env: [
      'ABRAXAS_YOUTUBE_CLIENT_ID',
      'ABRAXAS_YOUTUBE_CLIENT_SECRET',
    ],
    capabilities: [
      { key: 'video-upload', label: 'Video upload', supported: true },
      { key: 'metadata', label: 'Title / description / privacy', supported: true },
      { key: 'verify', label: 'Remote verification', supported: true },
    ],
    notes: [
      'Los proyectos no verificados pueden tener restricciones de visibilidad en uploads.',
      'El token debe almacenarse fuera de Git; Desktop puede usar almacenamiento seguro local.',
    ],
  },
  {
    id: 'LINKEDIN',
    label: 'LinkedIn',
    executionHost: 'CLOUD',
    readiness: 'NEEDS_DEVELOPER_APP',
    oauthRequired: true,
    env: [
      'ABRAXAS_LINKEDIN_CLIENT_ID',
      'ABRAXAS_LINKEDIN_CLIENT_SECRET',
      'ABRAXAS_LINKEDIN_REDIRECT_URI',
    ],
    capabilities: [
      { key: 'text', label: 'Text posts', supported: true },
      { key: 'image', label: 'Image posts', supported: true },
      { key: 'video', label: 'Video posts', supported: true },
      { key: 'document', label: 'Document posts', supported: true },
    ],
    notes: [
      'La integración debe usar Posts API versionada y los scopes aprobados para miembro u organización.',
    ],
  },
  {
    id: 'TIKTOK',
    label: 'TikTok',
    executionHost: 'CLOUD',
    readiness: 'NEEDS_REVIEW',
    oauthRequired: true,
    env: [
      'ABRAXAS_TIKTOK_CLIENT_KEY',
      'ABRAXAS_TIKTOK_CLIENT_SECRET',
      'ABRAXAS_TIKTOK_REDIRECT_URI',
    ],
    capabilities: [
      { key: 'direct-post', label: 'Direct Post', supported: true },
      { key: 'upload-draft', label: 'Upload as draft', supported: true },
      { key: 'photo', label: 'Photo posting', supported: true },
    ],
    notes: [
      'Direct Post sin auditoría puede quedar limitado a privado.',
      'La UI debe consultar creator info antes de un Direct Post.',
    ],
  },
]
EOF

cat > src/lib/providers/index.ts <<'EOF'
export * from './types'
export * from './catalog'
EOF

echo "3/7 · Provider Center UI"
cat > src/views/ProvidersView.tsx <<'EOF'
import { useEffect, useMemo, useState } from 'react'
import { CheckCircle2, CircleAlert, Plug, ShieldCheck } from 'lucide-react'
import { backend } from '../lib/backend'
import { providerCatalog } from '../lib/providers'
import type { ConnectedAccount } from '../types'

export function ProvidersView() {
  const [accounts, setAccounts] = useState<ConnectedAccount[]>([])

  useEffect(() => {
    backend.listConnectedAccounts().then(setAccounts).catch(() => setAccounts([]))
  }, [])

  const connected = useMemo(
    () => new Set(accounts.filter((a) => a.connectionStatus === 'CONNECTED').map((a) => a.provider.toUpperCase())),
    [accounts],
  )

  return (
    <div className="page scrollable provider-center">
      <header className="page-header">
        <div>
          <span className="eyebrow">FASE 2 · PROVIDERS</span>
          <h1>Conexiones de publicación</h1>
          <p>Configura qué redes pueden publicar automáticamente y cuáles deben seguir en modo manual.</p>
        </div>
      </header>

      <section className="provider-summary panel">
        <ShieldCheck size={20}/>
        <div>
          <strong>Publisher no simula conexiones.</strong>
          <p>Hasta completar OAuth y permisos reales, el destino permanece MANUAL_REQUIRED o NEEDS_AUTH.</p>
        </div>
      </section>

      <div className="provider-grid">
        {providerCatalog.map((provider) => {
          const isConnected = connected.has(provider.id)
          return (
            <article className="panel provider-card" key={provider.id}>
              <div className="provider-card-head">
                <div className="provider-icon"><Plug size={19}/></div>
                <div>
                  <strong>{provider.label}</strong>
                  <small>{provider.executionHost}</small>
                </div>
                <span className={isConnected ? 'provider-pill ok' : 'provider-pill pending'}>
                  {isConnected ? <CheckCircle2 size={13}/> : <CircleAlert size={13}/>} 
                  {isConnected ? 'Conectado' : provider.readiness}
                </span>
              </div>

              <div className="provider-capabilities">
                {provider.capabilities.map((capability) => (
                  <div key={capability.key}>
                    <span>{capability.label}</span>
                    <b>{capability.supported ? 'Disponible' : 'No'}</b>
                  </div>
                ))}
              </div>

              <div className="provider-notes">
                {provider.notes.map((note) => <p key={note}>{note}</p>)}
              </div>

              <small className="provider-env-title">Configuración esperada</small>
              <code className="provider-env">{provider.env.join('\n')}</code>
            </article>
          )
        })}
      </div>
    </div>
  )
}
EOF

cat >> src/styles.css <<'EOF'

/* V1.4 · Provider Center */
.provider-center{padding-bottom:48px}.provider-summary{display:flex;gap:12px;align-items:flex-start;margin-bottom:12px}.provider-summary p{margin:4px 0 0;color:var(--muted)}.provider-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.provider-card{padding:16px}.provider-card-head{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center}.provider-icon{width:38px;height:38px;border-radius:12px;display:grid;place-items:center;background:rgba(120,150,255,.1)}.provider-card-head strong,.provider-card-head small{display:block}.provider-card-head small{color:var(--muted);margin-top:2px}.provider-pill{display:inline-flex;gap:5px;align-items:center;border-radius:999px;padding:5px 8px;font-size:9px}.provider-pill.ok{background:rgba(40,170,95,.12)}.provider-pill.pending{background:rgba(230,155,35,.12)}.provider-capabilities{margin-top:14px}.provider-capabilities>div{display:flex;justify-content:space-between;gap:12px;padding:7px 0;border-top:1px solid var(--line);font-size:10px}.provider-notes{margin-top:10px;color:var(--muted);font-size:9px;line-height:1.5}.provider-notes p{margin:5px 0}.provider-env-title{display:block;margin-top:12px;color:var(--muted)}.provider-env{display:block;white-space:pre-wrap;margin-top:6px;padding:10px;border:1px solid var(--line);border-radius:10px;font-size:9px;background:rgba(0,0,0,.04)}@media(max-width:800px){.provider-grid{grid-template-columns:1fr}.provider-card-head{grid-template-columns:auto 1fr}.provider-pill{grid-column:1/-1;width:max-content}}
EOF

echo "4/7 · Navegación"
python3 <<'PY'
from pathlib import Path

store = Path('src/lib/store.ts')
s = store.read_text()
needle = "  | 'accounts'\n  | 'sync'"
if "| 'providers'" not in s:
    s = s.replace(needle, "  | 'accounts'\n  | 'providers'\n  | 'sync'")
store.write_text(s)

app = Path('src/App.tsx')
s = app.read_text()
if "ProvidersView" not in s:
    s = s.replace("import { AccountsView } from './views/AccountsView'", "import { AccountsView } from './views/AccountsView'\nimport { ProvidersView } from './views/ProvidersView'")
    s = s.replace("  if (v === 'accounts') return <AccountsView/>", "  if (v === 'accounts') return <AccountsView/>\n  if (v === 'providers') return <ProvidersView/>")
app.write_text(s)

side = Path('src/components/Sidebar.tsx')
s = side.read_text()
if "Plug," not in s:
    s = s.replace("  UsersRound,\n", "  UsersRound,\n  Plug,\n")
if "'providers'" not in s:
    marker = "    [\n      'accounts',\n      UsersRound,\n      'Cuentas',\n    ],\n"
    insert = marker + "    [\n      'providers',\n      Plug,\n      'Proveedores',\n    ],\n"
    s = s.replace(marker, insert)
s = s.replace('Publisher · v1.3.2', 'Publisher · v1.4')
side.write_text(s)
PY

echo "5/7 · Documentación"
cat > docs/PHASE_2_PROVIDER_ADAPTERS.md <<'EOF'
# ABRAXAS Publisher · Fase 2 · Provider Adapters

Objetivo: pasar de preparación/manual/external a publicación real verificable sin romper el workflow existente.

## Orden

1. Provider contract + capability catalog.
2. Provider Center UI.
3. OAuth por proveedor.
4. Almacenamiento seguro de tokens.
5. Preflight específico por red.
6. Idempotency key por publication job.
7. Dispatch.
8. Verificación remota.
9. Retry con backoff sólo donde sea seguro.
10. Receipt/audit.

## Reglas

- `PROGRAMADO` editorial no equivale a `SCHEDULED_REMOTE`.
- Nunca marcar `SCHEDULED_REMOTE` sin receipt remoto verificable.
- Si faltan permisos/API, usar `MANUAL_REQUIRED`.
- Tokens y secretos nunca van al frontend público ni a Git.
- Antes de dispatch: preflight.
- Después de dispatch: verify.
- Reintentos deben ser idempotentes.

## Prioridad

### YouTube
Primero por tener un flujo de upload bien definido. Requiere OAuth y `youtube.upload`.

### Meta
Instagram/Facebook después de crear y aprobar la developer app/permisos requeridos.

### LinkedIn
Usar Posts API versionada y scopes autorizados.

### TikTok
Direct Post/Upload API; respetar creator-info y auditoría/privacidad.

## Fase 2B

La siguiente ejecución debe conectar credenciales reales de developer apps y desarrollar OAuth + dispatch por proveedor. No se deben inventar credenciales ni guardar secretos en el repo.
EOF

echo "6/7 · QA"
npm ci
npm run check
npm run build
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
npm run mcp:test

echo "7/7 · Commit, push e instalación local"
git add src/lib/providers src/views/ProvidersView.tsx src/lib/store.ts src/App.tsx src/components/Sidebar.tsx src/styles.css docs/PHASE_2_PROVIDER_ADAPTERS.md
git commit -m "ABRAXAS Publisher V1.4 provider adapter foundation"
git push -u origin "$BRANCH"

npm run tauri:build
NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"
[ -d "$NEW_APP" ] || { echo "No se encontró la app compilada"; exit 1; }
mkdir -p "$HOME/Applications"
if [ -d "$APP" ]; then mv "$APP" "$BACKUP"; fi
ditto "$NEW_APP" "$APP"
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
rm -f "$HOME/Desktop/ABRAXAS Publisher.app"
ln -s "$APP" "$HOME/Desktop/ABRAXAS Publisher.app"

echo
echo "FASE 2A COMPLETADA"
echo "Rama: $BRANCH"
echo "App: $APP"
echo "Backup: $BACKUP"
echo "Siguiente fase: OAuth + credenciales reales + dispatch/verify por proveedor"
echo
open "$APP" 2>/dev/null || true
