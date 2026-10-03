#!/bin/bash
set -Eeuo pipefail

###############################################################################
# ABRAXAS Publisher V1.3.2
#
# Desktop + Web/PWA + Sync Foundation
#
# Objetivos:
# - una sola base de código
# - Tauri Desktop nativo
# - Web/PWA en GitHub Pages
# - WebBackend separado de NativeBackend
# - arquitectura Cloud/Desktop/Manual
# - Sync Center
# - guía completa Desktop vs Web/PWA
# - GitHub Pages workflow
# - manifest + service worker
# - icono/acceso en Desktop
#
# IMPORTANTE:
# GitHub Pages NO es una base de datos.
# Cross-device sync real requiere VITE_ABRAXAS_SYNC_API.
###############################################################################

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

BRANCH="v1.3-publishing-center"
STAMP="$(date +%Y%m%d_%H%M%S)"

LOG_DIR="$ROOT/logs"
LOG="$LOG_DIR/v132_desktop_pwa_$STAMP.log"

mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS PUBLISHER V1.3.2 · FALLO"
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
# 1. PRECHECK
###############################################################################

section "1/13 · PRECHECK"

git switch "$BRANCH"

if [ -n "$(git status --porcelain)" ]; then
  echo "Guardando snapshot previo..."

  git add -A

  git commit \
    -m "Snapshot before V1.3.2 Desktop PWA Sync $STAMP" \
    || true
fi

BASE_SHA="$(git rev-parse HEAD)"

echo "Base:"
echo "$BASE_SHA"

###############################################################################
# 2. BACKUP
###############################################################################

section "2/13 · BACKUP"

BACKUP="$ROOT/.v132-backup/$STAMP"

mkdir -p "$BACKUP"

for FILE in \
  package.json \
  src-tauri/Cargo.toml \
  src-tauri/tauri.conf.json \
  src/lib/backend.ts \
  src/lib/store.ts \
  src/main.tsx \
  src/App.tsx \
  src/components/Sidebar.tsx \
  src/views/HelpView.tsx \
  src/styles.css \
  vite.config.ts \
  index.html \
  README.md
do
  if [ -f "$FILE" ]; then
    mkdir -p "$BACKUP/$(dirname "$FILE")"
    cp "$FILE" "$BACKUP/$FILE"
  fi
done

echo "✓ Backup:"
echo "$BACKUP"

###############################################################################
# 3. VERSION
###############################################################################

section "3/13 · VERSION 0.4.2"

python3 <<'PY'
from pathlib import Path
import json
import re

p = Path("package.json")
data = json.loads(p.read_text())
data["version"] = "0.4.2"
data.setdefault("scripts", {})
data["scripts"]["build:web"] = "tsc && vite build"
p.write_text(json.dumps(data, indent=2) + "\n")

p = Path("src-tauri/Cargo.toml")
s = p.read_text()
s = re.sub(
    r'(?m)^version\s*=\s*"[^"]+"',
    'version = "0.4.2"',
    s,
    count=1,
)
p.write_text(s)

p = Path("src-tauri/tauri.conf.json")
data = json.loads(p.read_text())
data["version"] = "0.4.2"
p.write_text(json.dumps(data, indent=2) + "\n")

print("✓ 0.4.2")
PY

###############################################################################
# 4. RUNTIME ADAPTER
###############################################################################

section "4/13 · DESKTOP / WEB BACKENDS"

###############################################################################
# Convertir backend actual en NativeBackend
###############################################################################

if [ ! -f src/lib/nativeBackend.ts ]; then
  cp \
    src/lib/backend.ts \
    src/lib/nativeBackend.ts
fi

python3 <<'PY'
from pathlib import Path

p = Path("src/lib/nativeBackend.ts")
s = p.read_text()

s = s.replace(
    "export const backend = {",
    "export const nativeBackend = {",
    1,
)

p.write_text(s)

print("✓ nativeBackend.ts")
PY

###############################################################################
# Runtime detection
###############################################################################

cat > src/lib/runtime.ts <<'TS'
export type RuntimeSurface =
  | 'desktop'
  | 'web'
  | 'pwa'

export type ExecutionHost =
  | 'DESKTOP'
  | 'CLOUD'
  | 'MANUAL'

export function isTauriRuntime() {
  return (
    typeof window !== 'undefined'
    && (
      '__TAURI_INTERNALS__' in window
      || '__TAURI__' in window
    )
  )
}

export function isStandalonePwa() {
  if (
    typeof window === 'undefined'
  ) {
    return false
  }

  return (
    window.matchMedia(
      '(display-mode: standalone)',
    ).matches
    || (
      'standalone' in navigator
      && Boolean(
        (
          navigator as Navigator
          & {
            standalone?: boolean
          }
        ).standalone,
      )
    )
  )
}

export function runtimeSurface():
  RuntimeSurface {
  if (isTauriRuntime()) {
    return 'desktop'
  }

  if (isStandalonePwa()) {
    return 'pwa'
  }

  return 'web'
}

export function cloudEndpoint() {
  return (
    import.meta.env
      .VITE_ABRAXAS_SYNC_API
    || ''
  ).replace(
    /\/$/,
    '',
  )
}

export function cloudConfigured() {
  return Boolean(
    cloudEndpoint(),
  )
}
TS

###############################################################################
# WebBackend
###############################################################################

cat > src/lib/webBackend.ts <<'TS'
import type {
  ActivityEvent,
  Brand,
  ConnectedAccount,
  ContentItem,
  EnqueueInput,
  ExternalPublication,
  HealthReport,
  PreflightReport,
  PublishJob,
  SaveAccountInput,
  ScheduleChange,
  SimulationReport,
} from '../types'

const PREFIX =
  'abraxas.web.'

function read<T>(
  key: string,
  fallback: T,
): T {
  try {
    const raw =
      localStorage.getItem(
        PREFIX + key,
      )

    return raw
      ? JSON.parse(raw)
      : fallback
  } catch {
    return fallback
  }
}

function write<T>(
  key: string,
  value: T,
) {
  localStorage.setItem(
    PREFIX + key,
    JSON.stringify(value),
  )
}

const defaultBrands:
  Brand[] = [
    {
      id: 'brand-joc',
      name: 'JOC',
      createdAt:
        new Date()
          .toISOString(),
    },
  ]

function contents() {
  return read<ContentItem[]>(
    'contents',
    [],
  )
}

function brands() {
  return read<Brand[]>(
    'brands',
    defaultBrands,
  )
}

function accounts() {
  return read<
    ConnectedAccount[]
  >(
    'accounts',
    [],
  )
}

function jobs() {
  return read<PublishJob[]>(
    'jobs',
    [],
  )
}

function unsupported(
  feature: string,
): never {
  throw new Error(
    `${feature} requiere ABRAXAS Desktop o una integración cloud configurada.`,
  )
}

export const webBackend = {
  listConnectedAccounts:
    async () =>
      accounts(),

  saveConnectedAccount:
    async (
      input:
        SaveAccountInput,
    ) => {
      const now =
        new Date()
          .toISOString()

      const current =
        accounts()

      const id =
        input.id
        || `web-acct-${crypto.randomUUID()}`

      const account:
        ConnectedAccount = {
          id,
          provider:
            input.provider,
          brand:
            input.brand,
          displayName:
            input.displayName,
          handle:
            input.handle,
          accountKind:
            input.accountKind,

          // Una cuenta guardada en PWA
          // no se inventa como autorizada.
          connectionStatus:
            input.connectionStatus,

          authState:
            input.authState,

          capabilitiesJson:
            input.capabilitiesJson,

          externalReference:
            input.externalReference,

          lastVerifiedAt:
            null,

          lastError:
            null,

          createdAt:
            current.find(
              (x) =>
                x.id === id,
            )?.createdAt
            || now,

          updatedAt:
            now,
        }

      write(
        'accounts',
        [
          ...current.filter(
            (x) =>
              x.id !== id,
          ),
          account,
        ],
      )

      return account
    },

  removeConnectedAccount:
    async (
      accountId: string,
    ) => {
      const current =
        accounts()

      const next =
        current.filter(
          (x) =>
            x.id
            !== accountId,
        )

      write(
        'accounts',
        next,
      )

      return (
        next.length
        !== current.length
      )
    },

  listPublicationJobs:
    async () =>
      jobs(),

  publishingPreflight:
    async (
      targetId: string,
      accountId?:
        string | null,
    ): Promise<
      PreflightReport
    > => {
      const content =
        contents()
          .find(
            (item) =>
              item.targets
                .some(
                  (target) =>
                    target.id
                    === targetId,
                ),
          )

      const target =
        content?.targets
          .find(
            (item) =>
              item.id
              === targetId,
          )

      if (
        !content
        || !target
      ) {
        throw new Error(
          'Destino no encontrado.',
        )
      }

      const account =
        accounts()
          .find(
            (item) =>
              item.id
              === accountId,
          )

      /*
       * Por seguridad:
       * PWA local sin cloud bridge
       * nunca asume AUTO_API.
       */
      const executionMode =
        'MANUAL'

      const checks = [
        {
          key:
            'editorial',
          label:
            'Contenido aprobado',
          ok:
            content.status
              === 'LISTO_POR_PROGRAMAR'
            || content.status
              === 'PROGRAMADO',
          blocking: true,
          detail:
            content.status,
        },

        {
          key:
            'media',
          label:
            'Medio referenciado',
          ok:
            content.media.length
            > 0,
          blocking: true,
          detail:
            `${content.media.length} asset(s)`,
        },

        {
          key:
            'schedule',
          label:
            'Fecha/hora definida',
          ok:
            Boolean(
              target.scheduledAt,
            ),
          blocking: true,
          detail:
            target.scheduledAt,
        },

        {
          key:
            'runtime',
          label:
            account
              ? 'Cuenta registrada'
              : 'Publicación manual',
          ok: true,
          blocking: false,
          detail:
            account
              ? `${account.displayName} · PWA`
              : 'Sin API web autorizada',
        },
      ]

      return {
        targetId,
        accountId,
        provider:
          target.platform,
        executionMode,
        needsManualAction:
          true,
        ready:
          checks
            .filter(
              (x) =>
                x.blocking,
            )
            .every(
              (x) =>
                x.ok,
            ),
        checks,
      }
    },

  enqueuePublications:
    async (
      inputs:
        EnqueueInput[],
    ) => {
      const current =
        jobs()

      const allContent =
        contents()

      const now =
        new Date()
          .toISOString()

      const next =
        [...current]

      for (
        const input
        of inputs
      ) {
        const content =
          allContent.find(
            (item) =>
              item.targets
                .some(
                  (target) =>
                    target.id
                    === input.targetId,
                ),
          )

        const target =
          content?.targets
            .find(
              (item) =>
                item.id
                === input.targetId,
            )

        if (
          !content
          || !target
        ) {
          continue
        }

        const mode =
          input.mode
          === 'AUTO_API'
            ? 'MANUAL'
            : input.mode

        const id =
          `web-job-${input.targetId}-${mode}`

        const job:
          PublishJob = {
            id,
            targetId:
              input.targetId,
            contentId:
              content.id,
            provider:
              target.platform,
            accountId:
              input.accountId,
            mode,
            scheduledFor:
              target.scheduledAt,
            status:
              mode === 'EXTERNAL'
                ? 'SCHEDULED_EXTERNAL'
                : 'MANUAL_REQUIRED',
            idempotencyKey:
              id,
            attempt: 0,
            maxAttempts: 4,
            remoteId: null,
            remoteUrl: null,
            lastErrorCode: null,
            lastErrorMessage: null,
            createdAt:
              current.find(
                (x) =>
                  x.id === id,
              )?.createdAt
              || now,
            updatedAt:
              now,
          }

        const index =
          next.findIndex(
            (x) =>
              x.id === id,
          )

        if (
          index >= 0
        ) {
          next[index] =
            job
        } else {
          next.push(job)
        }
      }

      write(
        'jobs',
        next,
      )

      return next
    },

  markScheduledExternal:
    async (
      targetId: string,
      method: string,
      scheduledAt?:
        string | null,
      remoteUrl?:
        string | null,
      note?:
        string | null,
    ): Promise<
      ExternalPublication
    > => {
      const result:
        ExternalPublication = {
          id:
            `web-ext-${crypto.randomUUID()}`,
          targetId,
          provider: '',
          method,
          scheduledAt,
          remoteUrl,
          note,
          createdAt:
            new Date()
              .toISOString(),
        }

      return result
    },

  health:
    async (): Promise<
      HealthReport
    > => ({
      database: true,
      ffmpeg: false,
      ffprobe: false,
      appDataDir:
        'Browser storage',
    }),

  listBrands:
    async () =>
      brands(),

  createBrand:
    async (
      name: string,
    ) => {
      const current =
        brands()

      const brand:
        Brand = {
          id:
            `brand-${crypto.randomUUID()}`,
          name:
            name.trim(),
          createdAt:
            new Date()
              .toISOString(),
        }

      write(
        'brands',
        [
          ...current,
          brand,
        ],
      )

      return brand
    },

  previewImportLocal:
    async () =>
      unsupported(
        'Importación local',
      ),

  commitImportLocal:
    async () =>
      unsupported(
        'Importación local',
      ),

  importFolder:
    async () =>
      unsupported(
        'Importación local',
      ),

  listContents:
    async () =>
      contents(),

  updateSchedule:
    async (
      targetId: string,
      scheduledAt:
        string | null,
    ) => {
      const current =
        contents()

      let changed =
        false

      const next =
        current.map(
          (content) => ({
            ...content,
            targets:
              content.targets.map(
                (target) => {
                  if (
                    target.id
                    !== targetId
                  ) {
                    return target
                  }

                  changed =
                    true

                  return {
                    ...target,
                    scheduledAt,
                  }
                },
              ),
          }),
        )

      write(
        'contents',
        next,
      )

      return changed
    },

  updateSchedules:
    async (
      changes:
        ScheduleChange[],
    ) => {
      let count = 0

      for (
        const change
        of changes
      ) {
        if (
          await webBackend
            .updateSchedule(
              change.targetId,
              change.scheduledAt,
            )
        ) {
          count += 1
        }
      }

      return count
    },

  updateWorkflowStatus:
    async (
      contentId: string,
      status: string,
    ) => {
      const current =
        contents()

      let changed =
        false

      const next =
        current.map(
          (content) => {
            if (
              content.id
              !== contentId
            ) {
              return content
            }

            changed =
              true

            return {
              ...content,
              status,
            }
          },
        )

      write(
        'contents',
        next,
      )

      return changed
    },

  saveCorrectionNote:
    async () =>
      unsupported(
        'CORRECCION.txt local',
      ),

  refreshContent:
    async () =>
      unsupported(
        'Refresh de archivos locales',
      ),

  listActivity:
    async (): Promise<
      ActivityEvent[]
    > =>
      read<
        ActivityEvent[]
      >(
        'activity',
        [],
      ),

  undo:
    async () =>
      null,

  redo:
    async () =>
      null,

  getDriveClientId:
    async () =>
      localStorage.getItem(
        PREFIX
        + 'driveClientId',
      ),

  setDriveClientId:
    async (
      clientId: string,
    ) => {
      localStorage.setItem(
        PREFIX
        + 'driveClientId',
        clientId,
      )

      return true
    },

  driveStatus:
    async () =>
      false,

  driveConnect:
    async () =>
      unsupported(
        'OAuth Drive Desktop. Para PWA se necesita OAuth Web.',
      ),

  driveList:
    async () =>
      unsupported(
        'Google Drive Web',
      ),

  drivePreviewFolder:
    async () =>
      unsupported(
        'Google Drive Web',
      ),

  driveImportFolder:
    async () =>
      unsupported(
        'Google Drive Web',
      ),

  simulateBatch:
    async (): Promise<
      SimulationReport
    > => {
      const all =
        contents()

      const targets =
        all.flatMap(
          (content) =>
            content.targets,
        )

      return {
        totalTargets:
          targets.length,
        ready:
          targets.filter(
            (target) =>
              Boolean(
                target.scheduledAt,
              ),
          ).length,
        warnings:
          targets.filter(
            (target) =>
              !target.scheduledAt,
          ).length,
        errors: 0,
        generatedAt:
          new Date()
            .toISOString(),
        platforms: [],
        note:
          'Simulación Web/PWA local.',
      }
    },

  clearWorkspace:
    async () => {
      for (
        const key
        of Object.keys(
          localStorage,
        )
      ) {
        if (
          key.startsWith(
            PREFIX,
          )
        ) {
          localStorage
            .removeItem(
              key,
            )
        }
      }

      return true
    },
  }
TS

###############################################################################
# backend router
###############################################################################

cat > src/lib/backend.ts <<'TS'
import {
  nativeBackend,
} from './nativeBackend'

import {
  webBackend,
} from './webBackend'

import {
  isTauriRuntime,
} from './runtime'

export const backend =
  (
    isTauriRuntime()
      ? nativeBackend
      : webBackend
  ) as unknown as
    typeof nativeBackend
TS

###############################################################################
# 5. SYNC FOUNDATION
###############################################################################

section "5/13 · SYNC FOUNDATION"

cat > src/lib/sync.ts <<'TS'
import {
  cloudConfigured,
  cloudEndpoint,
  runtimeSurface,
} from './runtime'

export interface DeviceInfo {
  id: string
  name: string
  runtime:
    'desktop'
    | 'web'
    | 'pwa'
  lastSeen: string
  online: boolean
}

export interface RemoteTask {
  id: string
  type: string

  executionHost:
    'DESKTOP'
    | 'CLOUD'
    | 'MANUAL'

  status:
    | 'WAITING_FOR_DESKTOP'
    | 'QUEUED_CLOUD'
    | 'MANUAL_REQUIRED'
    | 'RUNNING'
    | 'DONE'
    | 'FAILED'

  payload:
    Record<
      string,
      unknown
    >

  createdAt: string
}

const DEVICE_KEY =
  'abraxas.deviceId'

export function deviceId() {
  let value =
    localStorage.getItem(
      DEVICE_KEY,
    )

  if (!value) {
    value =
      crypto.randomUUID()

    localStorage.setItem(
      DEVICE_KEY,
      value,
    )
  }

  return value
}

export function localDevice():
  DeviceInfo {
  return {
    id:
      deviceId(),

    name:
      runtimeSurface()
      === 'desktop'
        ? 'ABRAXAS Desktop'
        : runtimeSurface()
          === 'pwa'
          ? 'ABRAXAS PWA'
          : 'ABRAXAS Web',

    runtime:
      runtimeSurface(),

    lastSeen:
      new Date()
        .toISOString(),

    online:
      navigator.onLine,
  }
}

export async function syncHealth() {
  if (
    !cloudConfigured()
  ) {
    return {
      configured: false,
      online:
        navigator.onLine,
      cloud: false,
      message:
        'Cloud Sync todavía no está configurado.',
    }
  }

  try {
    const response =
      await fetch(
        `${cloudEndpoint()}/health`,
        {
          headers: {
            Accept:
              'application/json',
          },
        },
      )

    return {
      configured: true,
      online:
        navigator.onLine,
      cloud:
        response.ok,
      message:
        response.ok
          ? 'Cloud conectado.'
          : `Cloud respondió ${response.status}.`,
    }
  } catch (
    error
  ) {
    return {
      configured: true,
      online:
        navigator.onLine,
      cloud: false,
      message:
        String(error),
    }
  }
}

export async function submitRemoteTask(
  task:
    Omit<
      RemoteTask,
      'id'
      | 'createdAt'
    >,
) {
  const complete:
    RemoteTask = {
    ...task,
    id:
      crypto.randomUUID(),
    createdAt:
      new Date()
        .toISOString(),
  }

  if (
    !cloudConfigured()
  ) {
    const current =
      JSON.parse(
        localStorage.getItem(
          'abraxas.pendingRemoteTasks',
        )
        || '[]',
      ) as
        RemoteTask[]

    current.push(
      complete,
    )

    localStorage.setItem(
      'abraxas.pendingRemoteTasks',
      JSON.stringify(
        current,
      ),
    )

    return complete
  }

  const response =
    await fetch(
      `${cloudEndpoint()}/tasks`,
      {
        method:
          'POST',

        headers: {
          'Content-Type':
            'application/json',
        },

        body:
          JSON.stringify(
            complete,
          ),
      },
    )

  if (
    !response.ok
  ) {
    throw new Error(
      `Sync API respondió ${response.status}`,
    )
  }

  return complete
}
TS

###############################################################################
# 6. SYNC CENTER
###############################################################################

section "6/13 · SYNC CENTER"

cat > src/views/SyncView.tsx <<'TS'
import {
  CheckCircle2,
  Cloud,
  CloudOff,
  Laptop,
  RefreshCcw,
  Smartphone,
} from 'lucide-react'

import {
  useEffect,
  useState,
} from 'react'

import {
  cloudConfigured,
  runtimeSurface,
} from '../lib/runtime'

import {
  localDevice,
  syncHealth,
} from '../lib/sync'

export function SyncView() {
  const [
    status,
    setStatus,
  ] =
    useState<{
      configured: boolean
      online: boolean
      cloud: boolean
      message: string
    } | null>(
      null,
    )

  const load =
    async () => {
      setStatus(
        await syncHealth(),
      )
    }

  useEffect(
    () => {
      load()
        .catch(
          console.error,
        )
    },
    [],
  )

  const runtime =
    runtimeSurface()

  const device =
    localDevice()

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            SINCRONIZACIÓN
          </span>

          <h1>
            Sync Center
          </h1>

          <p>
            Desktop, Web y PWA comparten el mismo modelo de trabajo; las capacidades dependen del dispositivo.
          </p>
        </div>

        <button
          className="secondary-btn"
          onClick={load}
        >
          <RefreshCcw size={15}/>
          Comprobar
        </button>
      </header>

      <div className="sync-grid">
        <section className="panel sync-card">
          <div className="sync-card-icon">
            {
              runtime
              === 'desktop'
                ? <Laptop/>
                : <Smartphone/>
            }
          </div>

          <span className="eyebrow">
            ESTE DISPOSITIVO
          </span>

          <h2>
            {
              device.name
            }
          </h2>

          <p>
            Runtime: {
              runtime.toUpperCase()
            }
          </p>

          <small>
            Device ID:
            {' '}
            {
              device.id
                .slice(
                  0,
                  12,
                )
            }
          </small>
        </section>

        <section className="panel sync-card">
          <div className="sync-card-icon">
            {
              status?.cloud
                ? <Cloud/>
                : <CloudOff/>
            }
          </div>

          <span className="eyebrow">
            ABRAXAS CLOUD
          </span>

          <h2>
            {
              status?.cloud
                ? 'Conectado'
                : (
                    cloudConfigured()
                      ? 'Sin conexión'
                      : 'No configurado'
                  )
            }
          </h2>

          <p>
            {
              status
                ?.message
            }
          </p>
        </section>
      </div>

      <section className="panel sync-explainer">
        <h3>
          Qué sucede según el origen
        </h3>

        <div className="sync-flow-row">
          <span>
            PWA / móvil
          </span>

          <b>
            Revisa · aprueba · calendariza
          </b>

          <span>
            →
          </span>

          <b>
            Cloud job
          </b>

          <span>
            →
          </span>

          <b>
            Cloud o Desktop
          </b>
        </div>

        <div className="sync-flow-row">
          <span>
            Desktop
          </span>

          <b>
            archivos · ffmpeg · adapters locales
          </b>

          <span>
            →
          </span>

          <b>
            receipt
          </b>

          <span>
            →
          </span>

          <b>
            Web ve resultado
          </b>
        </div>
      </section>

      {
        !cloudConfigured()
        && (
          <section className="panel cloud-foundation-warning">
            <CloudOff size={18}/>

            <div>
              <strong>
                Sync Foundation instalada
              </strong>

              <p>
                GitHub Pages puede ejecutar la PWA, pero la sincronización automática entre dispositivos necesita configurar VITE_ABRAXAS_SYNC_API. Hasta entonces Web/PWA usa almacenamiento local del navegador.
              </p>
            </div>
          </section>
        )
      }

      <section className="panel">
        <h3>
          Capacidad actual
        </h3>

        <div className="capability-table">
          <div>
            <span>
              Revisión y calendario
            </span>
            <b>
              <CheckCircle2 size={14}/>
              Desktop + Web
            </b>
          </div>

          <div>
            <span>
              Archivos locales Mac
            </span>
            <b>
              Desktop
            </b>
          </div>

          <div>
            <span>
              ffmpeg / ffprobe
            </span>
            <b>
              Desktop
            </b>
          </div>

          <div>
            <span>
              Publicación cloud
            </span>
            <b>
              Provider + OAuth + Sync API
            </b>
          </div>

          <div>
            <span>
              Jobs para Desktop
            </span>
            <b>
              Cloud Sync requerido
            </b>
          </div>
        </div>
      </section>
    </div>
  )
}
TS

###############################################################################
# 7. HELP VIEW COMPLETA
###############################################################################

section "7/13 · CÓMO USAR"

cat > src/views/HelpView.tsx <<'TS'
const comparison = [
  [
    'Revisar contenido',
    '✓',
    '✓',
  ],
  [
    'Calendario',
    '✓',
    '✓',
  ],
  [
    'Copies y notas',
    '✓',
    '✓',
  ],
  [
    'Preview por red',
    '✓',
    '✓',
  ],
  [
    'Crear jobs',
    '✓',
    '✓',
  ],
  [
    'Trabajar desde móvil',
    '—',
    '✓',
  ],
  [
    'Archivos locales del Mac',
    '✓',
    '—',
  ],
  [
    'ffmpeg / ffprobe',
    '✓',
    '—',
  ],
  [
    'Worker / daemon local',
    '✓',
    '—',
  ],
  [
    'Publicar vía cloud',
    'según provider',
    'según provider',
  ],
  [
    'Delegar a Desktop',
    'recibe',
    'crea tarea',
  ],
]

const scenarios = [
  [
    'Estoy en el móvil y quiero aprobar contenido',
    'Abre la PWA → revisa preview, copy, destino y fecha → aprueba. Si el provider puede publicarse desde Cloud/Web y el asset está disponible, puede ejecutarse sin Desktop. Si requiere el Mac, se crea una tarea WAITING_FOR_DESKTOP.',
  ],

  [
    'El archivo está en Google Drive',
    'Web/PWA puede trabajar con referencias cloud cuando esté configurado OAuth Web. Si el provider admite asset remoto o ABRAXAS Cloud puede transferirlo, no es necesario que el Mac suba manualmente el archivo.',
  ],

  [
    'El archivo sólo existe en mi Mac',
    'Web puede planificar y aprobar, pero la ejecución queda DESKTOP_REQUIRED. Publisher Desktop localizará el asset y ejecutará el job.',
  ],

  [
    'No tengo API de una red',
    'No bloquea Publisher. Ese destino queda MANUAL_REQUIRED y aparece en Hoy/Cola cuando llegue su hora.',
  ],

  [
    'Ya lo programé desde Edits, Studio u otra app',
    'Usa “Ya programado fuera”. El target queda SCHEDULED_EXTERNAL y continúa visible en el calendario y auditoría.',
  ],

  [
    '¿Desktop y PWA son la misma app?',
    'Comparten interfaz, modelo y repositorio. Desktop tiene capacidades nativas adicionales; Web/PWA está orientada a movilidad, revisión, planificación, cloud y delegación.',
  ],

  [
    '¿Cómo se sincronizan?',
    'Los cambios cloud-safe se guardan en ABRAXAS Cloud. Desktop reporta heartbeat, descarga jobs que requieren capacidades locales, ejecuta y devuelve receipts. La PWA ve el resultado actualizado.',
  ],

  [
    '¿Qué pasa sin Internet?',
    'La PWA puede cargar su shell y datos cacheados. Los cambios permanecen pendientes hasta recuperar conexión. Nunca se debe asumir que una publicación remota ocurrió durante el modo offline.',
  ],
]

export function HelpView() {
  return (
    <div className="page scrollable help-v132">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            GUÍA
          </span>

          <h1>
            Cómo usar ABRAXAS Publisher
          </h1>

          <p>
            Desktop y Web/PWA son dos superficies del mismo workspace, con responsabilidades diferentes.
          </p>
        </div>
      </header>

      <section className="panel help-architecture">
        <span className="eyebrow">
          ARQUITECTURA
        </span>

        <h2>
          Un workspace · varios dispositivos
        </h2>

        <div className="architecture-diagram">
          <div>
            <strong>
              Web / PWA
            </strong>

            <span>
              revisar · aprobar · calendarizar · delegar
            </span>
          </div>

          <b>
            ↕
          </b>

          <div>
            <strong>
              ABRAXAS Cloud
            </strong>

            <span>
              workspace · jobs · devices · receipts
            </span>
          </div>

          <b>
            ↕
          </b>

          <div>
            <strong>
              Desktop
            </strong>

            <span>
              archivos · ffmpeg · adapters · ejecución local
            </span>
          </div>
        </div>
      </section>

      <section className="panel">
        <span className="eyebrow">
          DESKTOP VS WEB/PWA
        </span>

        <h2>
          Qué puede hacer cada versión
        </h2>

        <div className="help-comparison">
          <div className="help-comparison-head">
            <b>
              Función
            </b>

            <b>
              Desktop
            </b>

            <b>
              Web/PWA
            </b>
          </div>

          {
            comparison.map(
              ([
                feature,
                desktop,
                web,
              ]) => (
                <div key={feature}>
                  <span>
                    {feature}
                  </span>

                  <b>
                    {desktop}
                  </b>

                  <b>
                    {web}
                  </b>
                </div>
              ),
            )
          }
        </div>
      </section>

      <section className="panel">
        <span className="eyebrow">
          EJECUCIÓN
        </span>

        <h2>
          Cómo decide Publisher dónde ejecutar
        </h2>

        <div className="execution-doc-grid">
          <article>
            <strong>
              CLOUD
            </strong>

            <p>
              API compatible + OAuth web/cloud + asset accesible desde Drive/storage/cloud.
            </p>
          </article>

          <article>
            <strong>
              DESKTOP
            </strong>

            <p>
              El job requiere un archivo local, ffmpeg, Keychain, DaVinci u otra capacidad de macOS.
            </p>
          </article>

          <article>
            <strong>
              MANUAL
            </strong>

            <p>
              No existe integración automática o el usuario decide publicar manualmente.
            </p>
          </article>
        </div>
      </section>

      <section className="panel">
        <span className="eyebrow">
          SINCRONIZACIÓN
        </span>

        <h2>
          Web → Desktop
        </h2>

        <ol className="help-steps">
          <li>
            Modificas o apruebas una publicación desde Web/PWA.
          </li>

          <li>
            El cambio se guarda en ABRAXAS Cloud.
          </li>

          <li>
            Si puede ejecutarse en Cloud, el provider adapter continúa allí.
          </li>

          <li>
            Si necesita el Mac, el job queda WAITING_FOR_DESKTOP.
          </li>

          <li>
            Desktop recibe el job cuando está online.
          </li>

          <li>
            Desktop ejecuta, verifica y genera receipt.
          </li>

          <li>
            Cloud actualiza el workspace y la PWA muestra el resultado.
          </li>
        </ol>
      </section>

      <div className="help-grid">
        {
          scenarios.map(
            ([
              title,
              text,
            ]) => (
              <section
                className="panel help-card"
                key={title}
              >
                <h3>
                  {title}
                </h3>

                <p>
                  {text}
                </p>
              </section>
            ),
          )
        }
      </div>
    </div>
  )
}
TS

###############################################################################
# 8. ROUTING SYNC
###############################################################################

section "8/13 · ROUTING"

python3 <<'PY'
from pathlib import Path

# STORE
p = Path(
    "src/lib/store.ts"
)
s = p.read_text()

if "| 'sync'" not in s:
    s = s.replace(
        "  | 'accounts'\n",
        "  | 'accounts'\n  | 'sync'\n",
        1,
    )

p.write_text(s)

# APP
p = Path("src/App.tsx")
s = p.read_text()

if "SyncView" not in s:
    s = s.replace(
        "import { AccountsView } from './views/AccountsView'\n",
        "import { AccountsView } from './views/AccountsView'\nimport { SyncView } from './views/SyncView'\n",
        1,
    )

    s = s.replace(
        "  if (v === 'accounts') return <AccountsView/>\n",
        "  if (v === 'accounts') return <AccountsView/>\n  if (v === 'sync') return <SyncView/>\n",
        1,
    )

p.write_text(s)

# SIDEBAR
p = Path(
    "src/components/Sidebar.tsx"
)

s = p.read_text()

if "RefreshCw" not in s:
    s = s.replace(
        "  Settings,\n",
        "  Settings,\n  RefreshCw,\n",
        1,
    )

if "'sync'," not in s:
    marker = """    [
      'activity',
      Activity,
      'Actividad',
    ],"""

    replacement = marker + """
    [
      'sync',
      RefreshCw,
      'Sincronización',
    ],"""

    s = s.replace(
        marker,
        replacement,
        1,
    )

s = s.replace(
    "Publisher · v1.3",
    "Publisher · v1.3.2",
)

p.write_text(s)

print("✓ routing")
PY

###############################################################################
# 9. PWA
###############################################################################

section "9/13 · PWA"

mkdir -p public
mkdir -p .github/workflows

cat > public/abraxas-icon.svg <<'SVG'
<svg
  xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 512 512"
>
  <defs>
    <linearGradient
      id="g"
      x1="0"
      y1="0"
      x2="1"
      y2="1"
    >
      <stop
        offset="0"
        stop-color="#17253c"
      />
      <stop
        offset="1"
        stop-color="#586b91"
      />
    </linearGradient>
  </defs>

  <rect
    width="512"
    height="512"
    rx="118"
    fill="url(#g)"
  />

  <path
    d="
      M256 104
      L392 392
      H329
      L296 319
      H215
      L183 392
      H120
      Z

      M256 191
      L235 267
      H276
      Z
    "
    fill="#fff"
  />
</svg>
SVG

cat > public/manifest.webmanifest <<'JSON'
{
  "name": "ABRAXAS Publisher",
  "short_name": "ABRAXAS",
  "description": "Content operations, review, scheduling and publishing workspace.",
  "start_url": "./",
  "scope": "./",
  "display": "standalone",
  "background_color": "#f3f3f5",
  "theme_color": "#17253c",
  "orientation": "any",
  "icons": [
    {
      "src": "./abraxas-icon.svg",
      "sizes": "any",
      "type": "image/svg+xml",
      "purpose": "any maskable"
    }
  ]
}
JSON

cat > public/sw.js <<'JS'
const CACHE =
  'abraxas-publisher-v132'

const SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './abraxas-icon.svg',
]

self.addEventListener(
  'install',
  (event) => {
    event.waitUntil(
      caches
        .open(CACHE)
        .then(
          (cache) =>
            cache.addAll(
              SHELL,
            ),
        ),
    )

    self.skipWaiting()
  },
)

self.addEventListener(
  'activate',
  (event) => {
    event.waitUntil(
      caches
        .keys()
        .then(
          (keys) =>
            Promise.all(
              keys
                .filter(
                  (key) =>
                    key !== CACHE,
                )
                .map(
                  (key) =>
                    caches.delete(
                      key,
                    ),
                ),
            ),
        ),
    )

    self.clients.claim()
  },
)

self.addEventListener(
  'fetch',
  (event) => {
    if (
      event.request.method
      !== 'GET'
    ) {
      return
    }

    event.respondWith(
      fetch(
        event.request,
      )
        .then(
          (response) => {
            const copy =
              response.clone()

            caches
              .open(CACHE)
              .then(
                (cache) =>
                  cache.put(
                    event.request,
                    copy,
                  ),
              )

            return response
          },
        )
        .catch(
          () =>
            caches.match(
              event.request,
            )
            .then(
              (cached) =>
                cached
                || caches.match(
                  './index.html',
                ),
            ),
        ),
    )
  },
)
JS

cat > src/pwa.ts <<'TS'
import {
  isTauriRuntime,
} from './lib/runtime'

export function registerPwa() {
  if (
    isTauriRuntime()
    || !(
      'serviceWorker'
      in navigator
    )
  ) {
    return
  }

  window.addEventListener(
    'load',
    () => {
      navigator
        .serviceWorker
        .register(
          `${import.meta.env.BASE_URL}sw.js`,
        )
        .catch(
          console.error,
        )
    },
  )
}
TS

python3 <<'PY'
from pathlib import Path

p = Path("src/main.tsx")
s = p.read_text()

if "registerPwa" not in s:
    s = s.replace(
        "import './styles.css'",
        """import './styles.css'
import { registerPwa } from './pwa'""",
        1,
    )

    s += """

registerPwa()
"""

p.write_text(s)

# INDEX
p = Path("index.html")
s = p.read_text()

if "manifest.webmanifest" not in s:
    s = s.replace(
        "</head>",
        """  <link rel="manifest" href="./manifest.webmanifest">
  <meta name="theme-color" content="#17253c">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="default">
  <meta name="apple-mobile-web-app-title" content="ABRAXAS">
  <link rel="icon" href="./abraxas-icon.svg">
</head>""",
        1,
    )

p.write_text(s)
PY

###############################################################################
# VITE BASE
###############################################################################

cat > vite.config.ts <<'TS'
import {
  defineConfig,
} from 'vite'

import react
  from '@vitejs/plugin-react'

const githubPages =
  process.env
    .GITHUB_ACTIONS
  === 'true'

export default defineConfig({
  base:
    githubPages
      ? '/abraxas-publisher/'
      : '/',

  plugins: [
    react(),
  ],

  clearScreen:
    false,

  server: {
    port: 1420,
    strictPort: true,
    host:
      '127.0.0.1',
  },

  envPrefix: [
    'VITE_',
    'TAURI_',
  ],
})
TS

###############################################################################
# 10. GITHUB PAGES WORKFLOW
###############################################################################

section "10/13 · GITHUB PAGES"

cat > .github/workflows/pages.yml <<'YAML'
name: Deploy ABRAXAS Publisher PWA

on:
  push:
    branches:
      - main
      - v1.3-publishing-center

  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Node
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - name: Install
        run: npm ci

      - name: Typecheck
        run: npm run check

      - name: Build PWA
        run: npm run build:web

      - name: Configure Pages
        uses: actions/configure-pages@v5

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./dist

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    runs-on: ubuntu-latest
    needs: build

    steps:
      - name: Deploy
        id: deployment
        uses: actions/deploy-pages@v4
YAML

###############################################################################
# 11. DOCUMENTACIÓN DEL REPO
###############################################################################

section "11/13 · DOCUMENTACIÓN REPO"

mkdir -p docs

cat > docs/DESKTOP_WEB_PWA_SYNC.md <<'MD'
# ABRAXAS Publisher
## Desktop + Web/PWA + Sync Architecture

### Una aplicación, varias superficies

ABRAXAS Publisher usa un solo producto y un solo modelo conceptual.

Existen dos superficies principales:

1. Desktop / Tauri
2. Web / PWA

No tienen exactamente las mismas capacidades porque el navegador y macOS
tienen permisos y recursos diferentes.

---

# Desktop

Desktop es el ejecutor nativo.

Puede:

- leer carpetas locales;
- trabajar con SQLite nativo;
- usar ffmpeg;
- usar ffprobe;
- trabajar con Keychain;
- ejecutar adapters locales;
- localizar assets del Mac;
- ejecutar trabajos que requieren procesos locales;
- mantener workers/daemons;
- generar receipts después de una acción remota.

---

# Web / PWA

Web/PWA está optimizada para:

- móvil;
- iPad/tablet;
- navegador;
- revisión remota;
- aprobación;
- calendarización;
- copies;
- notas;
- previews;
- selección de destinos;
- creación de jobs;
- visualización de actividad;
- seguimiento de jobs.

Cuando un provider puede ejecutarse directamente desde Cloud/Web,
la PWA puede solicitar la ejecución sin necesidad de Desktop.

---

# Execution Host

Cada operación puede tener uno de estos hosts:

CLOUD
DESKTOP
MANUAL

## CLOUD

Usar cuando:

- provider tiene API compatible;
- OAuth válido;
- asset accesible desde cloud;
- no necesita recursos locales.

## DESKTOP

Usar cuando:

- asset sólo está en Mac;
- requiere ffmpeg;
- requiere filesystem local;
- requiere Keychain local;
- requiere herramienta nativa.

Status:

WAITING_FOR_DESKTOP

## MANUAL

Usar cuando:

- no existe API;
- usuario elige manual;
- provider no está configurado.

---

# Drive

Drive puede ser una fuente común de assets.

Desktop usa OAuth Desktop.

Web/PWA debe usar OAuth Web.

No reutilizar secretos Desktop en frontend Web.

Una referencia Drive puede permitir:

Web/PWA
→ revisar asset
→ aprobar
→ crear job

Después:

- Cloud puede obtener el asset si la arquitectura lo permite; o
- Desktop puede descargar/localizar el asset y ejecutar.

---

# Publicación móvil

Publicar desde móvil NO depende simplemente de que sea móvil.

Depende de:

1. Provider.
2. OAuth.
3. permisos/scopes.
4. tipo de contenido.
5. disponibilidad del asset.
6. política de ejecución.

Ejemplos:

TikTok + OAuth Web + asset accesible
→ CLOUD posible

YouTube + OAuth + asset accesible
→ CLOUD posible

Asset sólo en /Users/... del Mac
→ DESKTOP_REQUIRED

API no configurada
→ MANUAL_REQUIRED

---

# Sync

GitHub Pages NO es el backend de sincronización.

GitHub Pages sirve únicamente:

- HTML
- JS
- CSS
- manifest
- service worker

La sincronización real necesita ABRAXAS Sync API.

Variable:

VITE_ABRAXAS_SYNC_API

La Sync API será responsable de:

- auth;
- workspace;
- content metadata;
- publication jobs;
- devices;
- heartbeat;
- receipts;
- conflict resolution;
- realtime updates.

---

# Device heartbeat

Desktop debe registrar:

deviceId
deviceName
appVersion
lastSeen
capabilities

Web puede saber:

Desktop Online
Desktop Offline

y decidir si un job puede ejecutarse.

---

# Seguridad

Nunca publicar secretos en GitHub.

Nunca poner refresh tokens privados en el bundle Web.

Nunca marcar un job PUBLISHED si no existe verificación.

Nunca considerar GitHub Pages una base de datos segura.

---

# Offline

PWA puede cachear el shell y almacenar cambios locales.

Los cambios remotos deben marcarse como pendientes hasta sincronización.

Offline nunca significa que una publicación externa ocurrió.

---

# Source of truth

El repositorio contiene:

- frontend compartido;
- NativeBackend;
- WebBackend;
- contratos Sync;
- documentación;
- Pages workflow;
- Tauri desktop.

Desktop y Web/PWA evolucionan desde la misma base de código.
MD

cat > docs/MOBILE_PUBLISHING.md <<'MD'
# Mobile Publishing

## Regla

ABRAXAS puede publicar desde móvil cuando:

- el provider admite el flujo;
- OAuth está autorizado;
- el asset es accesible;
- no existe una dependencia local.

## Ejecuciones

### MOBILE → CLOUD

La PWA aprueba y publica mediante backend cloud.

### MOBILE → DESKTOP

La PWA aprueba.

Job:
WAITING_FOR_DESKTOP

Desktop recibe el job y ejecuta.

### MOBILE → MANUAL

La PWA mantiene:

MANUAL_REQUIRED

y recuerda al usuario publicar.

## Drive

Un archivo visible en Drive puede revisarse desde móvil.

Para publicar directamente desde Web:

- ABRAXAS Cloud debe poder leer/transferir el asset; o
- el provider debe aceptar una fuente remota compatible.

Si esto no está disponible:

PWA aprueba
→ Desktop ejecuta.

## Principle

No duplicar el mismo archivo innecesariamente.

Usar:

CONTENT_ID
ASSET_ID
Drive reference
fingerprint

en lugar de depender de paths absolutos.
MD

cat >> README.md <<'MD'

---

# Desktop + Web/PWA

ABRAXAS Publisher dispone de dos superficies:

- **Desktop/Tauri**: ejecución nativa, filesystem, ffmpeg, SQLite y workers.
- **Web/PWA**: revisión, planificación, aprobación, previews y coordinación remota.

Ambas comparten el mismo modelo de producto y repositorio.

La PWA se despliega mediante GitHub Pages.

## Execution hosts

- `CLOUD`
- `DESKTOP`
- `MANUAL`

La ausencia de una API nunca invalida el workspace.

## Sync

GitHub Pages sirve la aplicación, pero no es la base de datos.

Para sincronización cross-device se configura:

```bash
VITE_ABRAXAS_SYNC_API=https://...Más información:
- docs/DESKTOP_WEB_PWA_SYNC.md
- docs/MOBILE_PUBLISHING.md
- docs/V13_1_HYBRID_PUBLISHING.md
  MD
###############################################################################
12. CSS
###############################################################################
cat >> src/styles.css <<'CSS'
/* ==========================================================
   V1.3.2 · Desktop / Web / PWA / Sync
   ========================================================== */
.sync-grid{
  display:grid;
  grid-template-columns:repeat(2,minmax(0,1fr));
  gap:10px;
  margin-bottom:10px;
}
.sync-card{
  position:relative;
}
.sync-card-icon{
  width:38px;
  height:38px;
  border-radius:11px;
  display:grid;
  place-items:center;
  margin-bottom:10px;
  background:rgba(60,90,150,.09);
}
.sync-card h2{
  margin:4px 0;
}
.sync-card p,
.sync-card small{
  color:var(--muted);
}
.sync-explainer{
  margin-bottom:10px;
}
.sync-flow-row{
  display:grid;
  grid-template-columns:100px 1fr auto 1fr auto 1fr;
  gap:8px;
  align-items:center;
  border-top:1px solid var(--line);
  padding:10px 0;
  font-size:9px;
}
.cloud-foundation-warning{
  display:grid;
  grid-template-columns:auto 1fr;
  gap:10px;
  align-items:flex-start;
  margin-bottom:10px;
  background:rgba(220,145,20,.07);
  border-color:rgba(220,145,20,.3);
}
.cloud-foundation-warning p{
  color:var(--muted);
  margin-bottom:0;
}
.capability-table{
  display:grid;
}
.capability-table>div{
  display:flex;
  justify-content:space-between;
  gap:15px;
  padding:8px 0;
  border-top:1px solid var(--line);
}
.capability-table b{
  display:flex;
  gap:5px;
  align-items:center;
  text-align:right;
}
.help-architecture{
  margin-bottom:10px;
}
.architecture-diagram{
  display:grid;
  grid-template-columns:1fr auto 1fr auto 1fr;
  gap:10px;
  align-items:center;
  margin-top:14px;
}
.architecture-diagram>div{
  border:1px solid var(--line);
  border-radius:12px;
  padding:12px;
}
.architecture-diagram strong,
.architecture-diagram span{
  display:block;
}
.architecture-diagram span{
  color:var(--muted);
  margin-top:4px;
  font-size:9px;
}
.help-comparison{
  display:grid;
}
.help-comparison>div{
  display:grid;
  grid-template-columns:minmax(180px,1fr) 120px 120px;
  gap:10px;
  padding:7px 0;
  border-top:1px solid var(--line);
}
.help-comparison-head{
  border-top:0 !important;
}
.execution-doc-grid{
  display:grid;
  grid-template-columns:repeat(3,1fr);
  gap:8px;
  margin-top:10px;
}
.execution-doc-grid article{
  border:1px solid var(--line);
  border-radius:11px;
  padding:11px;
}
.execution-doc-grid p{
  color:var(--muted);
  font-size:9px;
  line-height:1.5;
}
.help-steps{
  color:var(--muted);
  line-height:1.7;
}
@media(max-width:800px){
  .sync-grid{
    grid-template-columns:1fr;
  }
  .sync-flow-row{
    grid-template-columns:1fr;
  }
  .architecture-diagram{
    grid-template-columns:1fr;
  }
  .architecture-diagram>b{
    transform:rotate(90deg);
    justify-self:center;
  }
  .help-comparison{
    overflow-x:auto;
  }
  .help-comparison>div{
    min-width:520px;
  }
  .execution-doc-grid{
    grid-template-columns:1fr;
  }
}
CSS
###############################################################################
13. QA
###############################################################################
section "12/13 · QA"
npm install
npm run check 
  || fail "TypeScript falló."
npm run build 
  || fail "Desktop frontend build falló."
cargo fmt 
  --manifest-path src-tauri/Cargo.toml 
  --all
cargo check 
  --manifest-path src-tauri/Cargo.toml 
  || fail "cargo check falló."
cargo test 
  --manifest-path src-tauri/Cargo.toml 
  || fail "cargo test falló."
###############################################################################
WEB BUILD TEST
###############################################################################
echo
echo "Probando Web/PWA..."
GITHUB_ACTIONS=true 
npm run build:web 
  || fail "PWA build falló."
[ -f dist/manifest.webmanifest ] 
  || fail "manifest.webmanifest no llegó al build."
[ -f dist/sw.js ] 
  || fail "service worker no llegó al build."
echo "✓ Web/PWA"
###############################################################################
DESKTOP BUILD
###############################################################################
echo
echo "Construyendo Desktop..."
unset GITHUB_ACTIONS
npm run tauri:build 
  || fail "Tauri build falló."
NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"
if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(
    find 
      "$ROOT/src-tauri/target/release/bundle" 
      -type d 
      -name "*.app" 
      -print 
      -quit
  )"
fi
[ -d "$NEW_APP" ] 
  || fail "No se encontró .app."
###############################################################################
INSTALL DESKTOP
###############################################################################
APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP_APP="$HOME/Applications/ABRAXAS Publisher.V131.backup.$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.V132.$STAMP.app"
mkdir -p 
  "$HOME/Applications"
rm -rf 
  "$STAGE"
ditto 
  "$NEW_APP" 
  "$STAGE"
xattr -dr 
  com.apple.quarantine 
  "$STAGE" \
/dev/null 2>&1 
  || true

if [ -d "$APP" ]; then
  mv 
    "$APP" 
    "$BACKUP_APP"
fi
if ! mv 
  "$STAGE" 
  "$APP"
then
  if [ -d "$BACKUP_APP" ]; then
    mv 
      "$BACKUP_APP" 
      "$APP" 
      || true
  fi
  fail "Instalación Desktop falló."
fi
###############################################################################
DESKTOP SHORTCUT
###############################################################################
rm -f 
  "$HOME/Desktop/ABRAXAS Publisher.app"
ln -s 
  "$APP" 
  "$HOME/Desktop/ABRAXAS Publisher.app"
echo "✓ Acceso de Escritorio"
###############################################################################
COMMIT / PUSH
###############################################################################
section "13/13 · RELEASE / GITHUB"
git add -A
git commit 
  -m "ABRAXAS Publisher V1.3.2 Desktop Web PWA Sync Foundation"
RELEASE_SHA="$(
  git rev-parse HEAD
)"
git tag 
  -f 
  publisher-v1.3.2
git push 
  -u origin 
  "$BRANCH"
git push 
  origin 
  publisher-v1.3.2 
  --force
###############################################################################
Intentar actualizar main de forma segura.
NO force.
###############################################################################
if git push 
  origin 
  "Branch: Main"
then
  echo "✓ main actualizado"
else
  echo
  echo "AVISO:"
  echo "main no pudo actualizarse por fast-forward."
  echo "La rama v1.3-publishing-center sí quedó actualizada."
fi
###############################################################################
Intentar activar GitHub Pages Actions
###############################################################################
echo
echo "Configurando GitHub Pages..."
if gh api 
  repos/LordJeferies/abraxas-publisher/pages \
/dev/null 2>&1
then
  gh api 
    --method PUT 
    repos/LordJeferies/abraxas-publisher/pages 
    -f build_type=workflow 
    >/dev/null 2>&1 
    || true
else
  gh api 
    --method POST 
    repos/LordJeferies/abraxas-publisher/pages 
    -f build_type=workflow 
    >/dev/null 2>&1 
    || true
fi

###############################################################################
SNAPSHOTS
###############################################################################
RELEASE_DIR="$HOME/Developer/abraxas-publisher/releases/v1.3.2"
mkdir -p 
  "$RELEASE_DIR"
FULL_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.2_FULL.zip"
git archive 
  --format=zip 
  --output="$FULL_ZIP" 
  HEAD
PATCH_TMP="$(
  mktemp -d
)"
mkdir -p 
  "$PATCH_TMP/files"
git diff 
  --name-only 
  "$BASE_SHA" 
  "$RELEASE_SHA" \
"$PATCH_TMP/FILES.txt"

while IFS= read -r FILE
do
  [ -n "$FILE" ] || continue
  [ -e "$FILE" ] || continue
  mkdir -p 
    "$PATCH_TMP/files/$(dirname "$FILE")"
  cp -R 
    "$FILE" 
    "$PATCH_TMP/files/$FILE"
done < "$PATCH_TMP/FILES.txt"
cat > "$PATCH_TMP/PATCH_MANIFEST.json" <<EOF
{
  "app": "ABRAXAS Publisher",
  "version": "1.3.2",
  "packageVersion": "0.4.2",
  "baseCommit": "$BASE_SHA",
  "releaseCommit": "$RELEASE_SHA",
  "surfaces": [
    "desktop",
    "web",
    "pwa"
  ],
  "executionHosts": [
    "CLOUD",
    "DESKTOP",
    "MANUAL"
  ],
  "sync": {
    "foundation": true,
    "cloudBackendRequiredForCrossDeviceSync": true
  }
}
EOF
PATCH_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.2_PATCH.zip"
ditto 
  -c 
  -k 
  --sequesterRsrc 
  "$PATCH_TMP" 
  "$PATCH_ZIP"
rm -rf 
  "$PATCH_TMP"
###############################################################################
FINAL
###############################################################################
echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.3.2 · COMPLETADA"
echo "=============================================================="
echo
echo "Desktop:"
echo "  $APP"
echo
echo "Acceso Escritorio:"
echo "  $HOME/Desktop/ABRAXAS Publisher.app"
echo
echo "Backup V1.3.1:"
echo "  $BACKUP_APP"
echo
echo "Branch:"
echo "  $BRANCH"
echo
echo "Commit:"
echo "  $RELEASE_SHA"
echo
echo "PWA esperada:"
echo "  https://lordjeferies.github.io/abraxas-publisher/"
echo
echo "FULL:"
echo "  $FULL_ZIP"
echo
echo "PATCH:"
echo "  $PATCH_ZIP"
echo
echo "Log:"
echo "  $LOG"
echo
echo "Capacidades:"
echo "  ✓ Desktop/Tauri"
echo "  ✓ Web build"
echo "  ✓ PWA manifest"
echo "  ✓ Service Worker"
echo "  ✓ GitHub Pages workflow"
echo "  ✓ NativeBackend"
echo "  ✓ WebBackend"
echo "  ✓ Sync Center"
echo "  ✓ documentación Desktop/Web/PWA"
echo "  ✓ execution host CLOUD/DESKTOP/MANUAL"
echo "  ✓ acceso en Escritorio"
echo
echo "Sync real entre dispositivos:"
echo "  requiere VITE_ABRAXAS_SYNC_API"
echo
echo "No se finge una sincronización inexistente."
echo
open "$APP" || true
