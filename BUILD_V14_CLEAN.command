#!/bin/bash
set -Eeuo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

REPO="LordJeferies/abraxas-publisher"
STAMP="$(date +%Y%m%d_%H%M%S)"
ROOT="$HOME/Developer/abraxas-publisher-v14-clean-$STAMP"
BRANCH="v1.4-provider-adapters-clean-$STAMP"
APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP="$HOME/Applications/ABRAXAS Publisher.pre-v14-clean-$STAMP.app"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: falta $1"; exit 1; }; }
need git
need gh
need node
need npm
need cargo
need python3

gh auth status >/dev/null 2>&1 || gh auth login

echo "1/9 · Clon limpio desde origin/main"
gh repo clone "$REPO" "$ROOT"
cd "$ROOT"
git switch main
git pull --ff-only origin main
git switch -c "$BRANCH"

echo "2/9 · Generando Provider contracts"
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
      'Requiere una Meta developer app y permisos aprobados.',
      'Los secretos nunca deben ir al frontend ni al repositorio.',
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
      'OAuth y tokens deben almacenarse fuera de Git.',
      'La publicación automática sólo se habilita tras verificar permisos reales.',
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
      'Usar Posts API versionada y scopes autorizados.',
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
      'La UI debe consultar creator info antes de Direct Post.',
    ],
  },
]
EOF

cat > src/lib/providers/index.ts <<'EOF'
export * from './types'
export * from './catalog'
EOF

echo "3/9 · Generando Provider Center"
cat > src/views/ProvidersView.tsx <<'EOF'
import { useEffect, useMemo, useState } from 'react'
import {
  CheckCircle2,
  CircleAlert,
  Plug,
  ShieldCheck,
} from 'lucide-react'

import { backend } from '../lib/backend'
import { providerCatalog } from '../lib/providers'
import type { ConnectedAccount } from '../types'

export function ProvidersView() {
  const [accounts, setAccounts] =
    useState<ConnectedAccount[]>([])

  useEffect(() => {
    backend
      .listConnectedAccounts()
      .then(setAccounts)
      .catch(() => setAccounts([]))
  }, [])

  const connected = useMemo(
    () => new Set(
      accounts
        .filter((account) =>
          account.connectionStatus === 'CONNECTED'
        )
        .map((account) =>
          account.provider.toUpperCase()
        ),
    ),
    [accounts],
  )

  return (
    <div className="page scrollable provider-center">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            FASE 2 · PROVIDERS
          </span>
          <h1>Conexiones de publicación</h1>
          <p>
            Configura qué redes pueden publicar automáticamente
            y cuáles deben seguir en modo manual.
          </p>
        </div>
      </header>

      <section className="provider-summary panel">
        <ShieldCheck size={20}/>
        <div>
          <strong>Publisher no simula conexiones.</strong>
          <p>
            Hasta completar OAuth y permisos reales, el destino
            permanece MANUAL_REQUIRED o NEEDS_AUTH.
          </p>
        </div>
      </section>

      <div className="provider-grid">
        {providerCatalog.map((provider) => {
          const isConnected = connected.has(provider.id)

          return (
            <article
              className="panel provider-card"
              key={provider.id}
            >
              <div className="provider-card-head">
                <div className="provider-icon">
                  <Plug size={19}/>
                </div>

                <div>
                  <strong>{provider.label}</strong>
                  <small>{provider.executionHost}</small>
                </div>

                <span
                  className={
                    isConnected
                      ? 'provider-pill ok'
                      : 'provider-pill pending'
                  }
                >
                  {isConnected
                    ? <CheckCircle2 size={13}/>
                    : <CircleAlert size={13}/>
                  }
                  {isConnected
                    ? 'Conectado'
                    : provider.readiness
                  }
                </span>
              </div>

              <div className="provider-capabilities">
                {provider.capabilities.map((capability) => (
                  <div key={capability.key}>
                    <span>{capability.label}</span>
                    <b>
                      {capability.supported ? 'Disponible' : 'No'}
                    </b>
                  </div>
                ))}
              </div>

              <div className="provider-notes">
                {provider.notes.map((note) => (
                  <p key={note}>{note}</p>
                ))}
              </div>

              <small className="provider-env-title">
                Configuración esperada
              </small>
              <code className="provider-env">
                {provider.env.join('\n')}
              </code>
            </article>
          )
        })}
      </div>
    </div>
  )
}
EOF

echo "4/9 · Reescribiendo Sidebar completo y navegación"
cat > src/components/Sidebar.tsx <<'EOF'
import {
  Activity,
  CalendarDays,
  Columns3,
  FileStack,
  House,
  LayoutDashboard,
  ListChecks,
  Plug,
  Send,
  Settings,
  RefreshCw,
  Upload,
  UsersRound,
  CircleHelp,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

import { useAppStore } from '../lib/store'
import type { View } from '../lib/store'

type Item = [
  View,
  LucideIcon,
  string,
]

const contentItems: Item[] = [
  ['content', FileStack, 'Biblioteca'],
  ['kanban', Columns3, 'Estados'],
  ['calendar', CalendarDays, 'Calendario'],
]

const publishingItems: Item[] = [
  ['publish', Send, 'Preparar publicación'],
  ['queue', ListChecks, 'Cola'],
]

const operationsItems: Item[] = [
  ['accounts', UsersRound, 'Cuentas'],
  ['providers', Plug, 'Proveedores'],
  ['import', Upload, 'Importar'],
  ['activity', Activity, 'Actividad'],
  ['sync', RefreshCw, 'Sincronización'],
]

function NavGroup({
  label,
  items,
}: {
  label: string
  items: Item[]
}) {
  const view = useAppStore((state) => state.view)
  const setView = useAppStore((state) => state.setView)

  return (
    <div className="nav-group">
      <small className="nav-group-label">{label}</small>
      {items.map(([id, Icon, text]) => (
        <button
          key={id}
          className={view === id ? 'nav-item active' : 'nav-item'}
          onClick={() => setView(id)}
        >
          <Icon size={17} strokeWidth={1.8}/>
          <span>{text}</span>
        </button>
      ))}
    </div>
  )
}

export function Sidebar() {
  const {
    view,
    setView,
    brands,
    selectedBrand,
    setSelectedBrand,
  } = useAppStore()

  return (
    <aside className="sidebar">
      <div className="brand-row">
        <div className="brand-mark">A</div>
        <div>
          <strong>ABRAXAS</strong>
          <span>Publisher · v1.4</span>
        </div>
      </div>

      <div className="brand-switcher">
        <small>MARCA</small>
        <select
          value={selectedBrand}
          onChange={(event) =>
            setSelectedBrand(event.target.value)
          }
        >
          <option value="ALL">Todas</option>
          {brands.map((brand) => (
            <option key={brand.id} value={brand.name}>
              {brand.name}
            </option>
          ))}
        </select>
      </div>

      <nav>
        <div className="nav-group">
          <small className="nav-group-label">INICIO</small>

          <button
            className={view === 'home' ? 'nav-item active' : 'nav-item'}
            onClick={() => setView('home')}
          >
            <House size={17}/>
            Inicio
          </button>

          <button
            className={view === 'today' ? 'nav-item active' : 'nav-item'}
            onClick={() => setView('today')}
          >
            <LayoutDashboard size={17}/>
            Hoy
          </button>
        </div>

        <NavGroup label="CONTENIDO" items={contentItems}/>
        <NavGroup label="PUBLICACIÓN" items={publishingItems}/>
        <NavGroup label="OPERACIONES" items={operationsItems}/>
      </nav>

      <div className="sidebar-spacer"/>

      <nav>
        <button
          className={view === 'help' ? 'nav-item active' : 'nav-item'}
          onClick={() => setView('help')}
        >
          <CircleHelp size={17}/>
          Cómo usar
        </button>

        <button
          className={view === 'settings' ? 'nav-item active' : 'nav-item'}
          onClick={() => setView('settings')}
        >
          <Settings size={17}/>
          Ajustes
        </button>
      </nav>

      <div className="sidebar-foot publishing-ready">
        <Send size={14}/>
        Publishing Center
      </div>
    </aside>
  )
}
EOF

python3 <<'PY'
from pathlib import Path

store = Path('src/lib/store.ts')
s = store.read_text()
if "  | 'providers'" not in s:
    anchor = "  | 'accounts'\n  | 'sync'"
    if anchor not in s:
        raise SystemExit('ERROR: store.ts no coincide con main esperado')
    s = s.replace(anchor, "  | 'accounts'\n  | 'providers'\n  | 'sync'", 1)
store.write_text(s)

app = Path('src/App.tsx')
s = app.read_text()
if "import { ProvidersView }" not in s:
    anchor = "import { AccountsView } from './views/AccountsView'"
    if anchor not in s:
        raise SystemExit('ERROR: App.tsx no coincide con main esperado')
    s = s.replace(anchor, anchor + "\nimport { ProvidersView } from './views/ProvidersView'", 1)
if "v === 'providers'" not in s:
    anchor = "  if (v === 'accounts') return <AccountsView/>"
    if anchor not in s:
        raise SystemExit('ERROR: no se encontró ruta accounts en App.tsx')
    s = s.replace(anchor, anchor + "\n  if (v === 'providers') return <ProvidersView/>", 1)
app.write_text(s)
PY

cat >> src/styles.css <<'EOF'

/* V1.4 · Provider Center */
.provider-center{padding-bottom:48px}
.provider-summary{display:flex;gap:12px;align-items:flex-start;margin-bottom:12px}
.provider-summary p{margin:4px 0 0;color:var(--muted)}
.provider-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
.provider-card{padding:16px}
.provider-card-head{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center}
.provider-icon{width:38px;height:38px;border-radius:12px;display:grid;place-items:center;background:rgba(120,150,255,.1)}
.provider-card-head strong,.provider-card-head small{display:block}
.provider-card-head small{color:var(--muted);margin-top:2px}
.provider-pill{display:inline-flex;gap:5px;align-items:center;border-radius:999px;padding:5px 8px;font-size:9px}
.provider-pill.ok{background:rgba(40,170,95,.12)}
.provider-pill.pending{background:rgba(230,155,35,.12)}
.provider-capabilities{margin-top:14px}
.provider-capabilities>div{display:flex;justify-content:space-between;gap:12px;padding:7px 0;border-top:1px solid var(--line);font-size:10px}
.provider-notes{margin-top:10px;color:var(--muted);font-size:9px;line-height:1.5}
.provider-notes p{margin:5px 0}
.provider-env-title{display:block;margin-top:12px;color:var(--muted)}
.provider-env{display:block;white-space:pre-wrap;margin-top:6px;padding:10px;border:1px solid var(--line);border-radius:10px;font-size:9px;background:rgba(0,0,0,.04)}
@media(max-width:800px){.provider-grid{grid-template-columns:1fr}.provider-card-head{grid-template-columns:auto 1fr}.provider-pill{grid-column:1/-1;width:max-content}}
EOF

cat > docs/PHASE_2_PROVIDER_ADAPTERS.md <<'EOF'
# ABRAXAS Publisher · V1.4 Provider Adapters

Esta fase añade el contrato y la UI de proveedores sin fingir conexiones remotas.

Reglas:
- OAuth real antes de AUTO_API.
- Preflight antes de dispatch.
- Verificación remota antes de SCHEDULED_REMOTE/PUBLISHED.
- MANUAL_REQUIRED no es un error.
- Nunca guardar secretos o tokens en Git.
- Reintentos futuros deben ser idempotentes.

Prioridad Fase 2B:
1. YouTube OAuth + upload + verify.
2. Meta OAuth + Instagram/Facebook.
3. LinkedIn.
4. TikTok.
EOF

echo "5/9 · Validación estructural previa"
python3 <<'PY'
from pathlib import Path
s = Path('src/components/Sidebar.tsx').read_text()
checks = [
    "LucideIcon",
    "['providers', Plug, 'Proveedores']",
    "const operationsItems: Item[]",
]
for check in checks:
    if check not in s:
        raise SystemExit(f'ERROR estructural: falta {check}')
print('✓ Sidebar determinista válido')
PY

echo "6/9 · QA frontend"
npm ci
npm run check
npm run build
GITHUB_ACTIONS=true npm run build:web
unset GITHUB_ACTIONS

echo "7/9 · QA Rust + MCP"
cargo fmt --manifest-path src-tauri/Cargo.toml --all --check
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
npm run mcp:test

echo "8/9 · Build Tauri"
npm run tauri:build
NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"
[ -d "$NEW_APP" ] || { echo "ERROR: no se encontró .app compilada"; exit 1; }

echo "9/9 · Commit, push e instalación atómica"
git add src/lib/providers src/views/ProvidersView.tsx src/components/Sidebar.tsx src/lib/store.ts src/App.tsx src/styles.css docs/PHASE_2_PROVIDER_ADAPTERS.md
git commit -m "ABRAXAS Publisher V1.4 provider adapter clean foundation"
git push -u origin "$BRANCH"

mkdir -p "$HOME/Applications"
STAGE="$HOME/Applications/.ABRAXAS Publisher.v14-$STAMP.app"
rm -rf "$STAGE"
ditto "$NEW_APP" "$STAGE"
xattr -dr com.apple.quarantine "$STAGE" >/dev/null 2>&1 || true

if [ -d "$APP" ]; then
  mv "$APP" "$BACKUP"
fi

if mv "$STAGE" "$APP"; then
  rm -f "$HOME/Desktop/ABRAXAS Publisher.app"
  ln -s "$APP" "$HOME/Desktop/ABRAXAS Publisher.app"
else
  [ -d "$BACKUP" ] && mv "$BACKUP" "$APP" || true
  echo "ERROR: instalación falló; se restauró backup"
  exit 1
fi

echo
echo "V1.4 CLEAN COMPLETADA"
echo "Rama: $BRANCH"
echo "Fuente: $ROOT"
echo "App: $APP"
echo "Backup: $BACKUP"
echo "Todas las validaciones pasaron antes de reemplazar la app."
open "$APP" 2>/dev/null || true
