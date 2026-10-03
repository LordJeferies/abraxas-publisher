#!/bin/bash
set -Eeuo pipefail

###############################################################################
# ABRAXAS Publisher V1.3.2
#
# Shared Supabase + Desktop + Web/PWA + Google Drive Web
#
# CANON:
# - mismo Supabase que Editorial OS
# - public.editorial_state
# - workspace_key = abraxas-publisher
# - NO tocar editorial-os
# - local-first
# - Supabase Auth compartido
# - Desktop + PWA comparten dominio portable
# - Desktop conserva backend nativo adicional
# - Drive Web basado en Abrxs Review / Google Identity Services
# - sin force push
###############################################################################

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

BRANCH="v1.3-publishing-center"
STAMP="$(date +%Y%m%d_%H%M%S)"
VERSION="0.4.2"

LOG="$ROOT/logs/v132_final_$STAMP.log"
mkdir -p "$ROOT/logs"

exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS PUBLISHER V1.3.2 · FALLO"
  echo "=============================================================="
  echo "$*"
  echo
  echo "Log:"
  echo "  $LOG"
  exit 1
}

section() {
  echo
  echo "=============================================================="
  echo " $*"
  echo "=============================================================="
}

###############################################################################
# 1. PRECHECK / SNAPSHOT
###############################################################################

section "1/14 · PRECHECK"

git switch "$BRANCH"

if [ -n "$(git status --porcelain)" ]; then
  git add -A

  git commit \
    -m "Snapshot before final V1.3.2 shared cloud $STAMP" \
    || true
fi

BASE_SHA="$(git rev-parse HEAD)"

echo "Base:"
echo "  $BASE_SHA"

BACKUP="$ROOT/.v132-final-backup/$STAMP"
mkdir -p "$BACKUP"

for FILE in \
  src/lib/backend.ts \
  src/lib/webBackend.ts \
  src/lib/nativeBackend.ts \
  src/lib/runtime.ts \
  src/main.tsx \
  src/App.tsx \
  src/views/ImportView.tsx \
  src/views/SyncView.tsx \
  src/views/HomeView.tsx \
  src/styles.css \
  package.json
do
  if [ -f "$FILE" ]; then
    mkdir -p "$BACKUP/$(dirname "$FILE")"
    cp "$FILE" "$BACKUP/$FILE"
  fi
done

echo "✓ Backup $BACKUP"

###############################################################################
# 2. VITE TYPES + SUPABASE SDK
###############################################################################

section "2/14 · TYPES / DEPENDENCIES"

cat > src/vite-env.d.ts <<'TS'
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string
  readonly VITE_SUPABASE_ANON_KEY?: string
  readonly VITE_GOOGLE_DRIVE_WEB_CLIENT_ID?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
TS

npm install @supabase/supabase-js

echo "✓ Vite env"
echo "✓ Supabase JS"

###############################################################################
# 3. REUSE EDITORIAL OS / EMULATOR SUPABASE
###############################################################################

section "3/14 · SHARED SUPABASE CONFIG"

[ -f .env.local ] \
  || fail ".env.local no existe."

set -a
source .env.local
set +a

SUPABASE_URL="${VITE_SUPABASE_URL:-}"
SUPABASE_KEY="${VITE_SUPABASE_PUBLISHABLE_KEY:-${VITE_SUPABASE_ANON_KEY:-}}"

[ -n "$SUPABASE_URL" ] \
  || fail "VITE_SUPABASE_URL vacío."

[ -n "$SUPABASE_KEY" ] \
  || fail "VITE_SUPABASE_PUBLISHABLE_KEY vacío."

echo "✓ mismo Supabase de Editorial OS"
echo "✓ tabla: public.editorial_state"
echo "✓ workspace: abraxas-publisher"

if command -v gh >/dev/null 2>&1 \
  && gh auth status >/dev/null 2>&1
then
  printf "%s" "$SUPABASE_URL" \
    | gh secret set \
        VITE_SUPABASE_URL \
        --repo LordJeferies/abraxas-publisher \
        >/dev/null

  printf "%s" "$SUPABASE_KEY" \
    | gh secret set \
        VITE_SUPABASE_PUBLISHABLE_KEY \
        --repo LordJeferies/abraxas-publisher \
        >/dev/null

  echo "✓ GitHub Actions secrets"
fi


section "4/14 · SUPABASE CLIENT"

cat > src/lib/supabase.ts <<'TS'
import {
  createClient,
  type RealtimeChannel,
  type SupabaseClient,
  type User,
} from '@supabase/supabase-js'

const url =
  import.meta.env
    .VITE_SUPABASE_URL
  || ''

const key =
  import.meta.env
    .VITE_SUPABASE_PUBLISHABLE_KEY
  || import.meta.env
    .VITE_SUPABASE_ANON_KEY
  || ''

let client:
  SupabaseClient | null =
    null

let channel:
  RealtimeChannel | null =
    null

export const PUBLISHER_WORKSPACE =
  'abraxas-publisher'

export function supabaseConfigured() {
  return Boolean(
    url && key,
  )
}

export function supabaseClient() {
  if (
    !supabaseConfigured()
  ) {
    return null
  }

  if (!client) {
    client =
      createClient(
        url,
        key,
        {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true,
          },
        },
      )
  }

  return client
}

export async function cloudUser():
  Promise<User | null> {
  const supabase =
    supabaseClient()

  if (!supabase) {
    return null
  }

  const {
    data,
  } =
    await supabase
      .auth
      .getSession()

  return (
    data.session?.user
    || null
  )
}

export async function cloudSignIn(
  email: string,
  password: string,
) {
  const supabase =
    supabaseClient()

  if (!supabase) {
    throw new Error(
      'Supabase no está configurado.',
    )
  }

  const {
    data,
    error,
  } =
    await supabase
      .auth
      .signInWithPassword({
        email,
        password,
      })

  if (error) {
    throw error
  }

  return data.session
}

export async function cloudSignUp(
  email: string,
  password: string,
) {
  const supabase =
    supabaseClient()

  if (!supabase) {
    throw new Error(
      'Supabase no está configurado.',
    )
  }

  const {
    data,
    error,
  } =
    await supabase
      .auth
      .signUp({
        email,
        password,
      })

  if (error) {
    throw error
  }

  return data
}

export async function cloudSignOut() {
  const supabase =
    supabaseClient()

  if (!supabase) {
    return
  }

  if (channel) {
    await supabase
      .removeChannel(
        channel,
      )

    channel = null
  }

  await supabase
    .auth
    .signOut()
}

export function setPublisherChannel(
  value:
    RealtimeChannel | null,
) {
  channel = value
}

export function getPublisherChannel() {
  return channel
}
TS

###############################################################################
# 5. PORTABLE WEB BACKEND
###############################################################################

section "5/14 · PORTABLE DOMAIN BACKEND"

cat > src/lib/webBackend.ts <<'TS'
import type {
  ActivityEvent,
  Brand,
  ConnectedAccount,
  ContentItem,
  CorrectionNote,
  DriveAuthResult,
  DriveItem,
  EnqueueInput,
  ExternalPublication,
  HealthReport,
  ImportPreview,
  PreflightReport,
  PublishJob,
  RefreshResult,
  SaveAccountInput,
  ScanResult,
  ScheduleChange,
  SimulationReport,
} from '../types'

import {
  webDrive,
} from './webDrive'

const PREFIX =
  'abraxas.publisher.'

export interface PortableSnapshot {
  version: number
  brands: Brand[]
  contents: ContentItem[]
  accounts: ConnectedAccount[]
  publicationJobs: PublishJob[]
  activity: ActivityEvent[]

  syncMeta: {
    revision: number
    baseRevision: number
    deviceId: string
    productVersion: string
    updatedAt: string
  }
}

function read<T>(
  key: string,
  fallback: T,
): T {
  try {
    const value =
      localStorage.getItem(
        PREFIX + key,
      )

    return value
      ? JSON.parse(value)
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

function now() {
  return new Date()
    .toISOString()
}

function uid(
  prefix: string,
) {
  return (
    `${prefix}-${crypto.randomUUID()}`
  )
}

function deviceId() {
  const key =
    PREFIX + 'deviceId'

  let value =
    localStorage.getItem(
      key,
    )

  if (!value) {
    value =
      crypto.randomUUID()

    localStorage.setItem(
      key,
      value,
    )
  }

  return value
}

export function getPortableSnapshot():
  PortableSnapshot {
  const meta =
    read(
      'syncMeta',
      {
        revision: 0,
        baseRevision: 0,
        deviceId:
          deviceId(),
        productVersion:
          'publisher-1.3.2',
        updatedAt:
          now(),
      },
    )

  return {
    version: 1,

    brands:
      read<Brand[]>(
        'brands',
        [],
      ),

    contents:
      read<ContentItem[]>(
        'contents',
        [],
      ),

    accounts:
      read<ConnectedAccount[]>(
        'accounts',
        [],
      ),

    publicationJobs:
      read<PublishJob[]>(
        'jobs',
        [],
      ),

    activity:
      read<ActivityEvent[]>(
        'activity',
        [],
      ),

    syncMeta:
      meta,
  }
}

export function replacePortableSnapshot(
  snapshot:
    PortableSnapshot,
) {
  write(
    'brands',
    snapshot.brands || [],
  )

  write(
    'contents',
    snapshot.contents || [],
  )

  write(
    'accounts',
    snapshot.accounts || [],
  )

  write(
    'jobs',
    snapshot.publicationJobs || [],
  )

  write(
    'activity',
    snapshot.activity || [],
  )

  write(
    'syncMeta',
    snapshot.syncMeta,
  )

  window.dispatchEvent(
    new CustomEvent(
      'abraxas-portable-updated',
    ),
  )
}

export function mergePortableContents(
  incoming:
    ContentItem[],
) {
  const snapshot =
    getPortableSnapshot()

  const map =
    new Map(
      snapshot.contents.map(
        (item) => [
          item.id,
          item,
        ],
      ),
    )

  for (
    const content
    of incoming
  ) {
    map.set(
      content.id,
      {
        ...map.get(
          content.id,
        ),
        ...content,
      },
    )
  }

  snapshot.contents =
    [...map.values()]

  snapshot.syncMeta.updatedAt =
    now()

  replacePortableSnapshot(
    snapshot,
  )
}

export function mergePortableBrands(
  incoming:
    Brand[],
) {
  const snapshot =
    getPortableSnapshot()

  const map =
    new Map(
      snapshot.brands.map(
        (brand) => [
          brand.id,
          brand,
        ],
      ),
    )

  for (
    const brand
    of incoming
  ) {
    map.set(
      brand.id,
      brand,
    )
  }

  snapshot.brands =
    [...map.values()]

  replacePortableSnapshot(
    snapshot,
  )
}

function logActivity(
  action: string,
  entityType: string,
  entityId: string,
  label: string,
) {
  const list =
    read<ActivityEvent[]>(
      'activity',
      [],
    )

  list.unshift({
    id:
      uid('activity'),
    action,
    entityType,
    entityId,
    label,
    beforeJson: null,
    afterJson: null,
    reversible: false,
    remote: false,
    undone: false,
    createdAt:
      now(),
  })

  write(
    'activity',
    list.slice(
      0,
      500,
    ),
  )
}

function updateContent(
  id: string,
  fn:
    (
      value:
        ContentItem,
    ) => ContentItem,
) {
  const list =
    read<ContentItem[]>(
      'contents',
      [],
    )

  let changed =
    false

  const next =
    list.map(
      (item) => {
        if (
          item.id !== id
        ) {
          return item
        }

        changed = true

        return fn(item)
      },
    )

  write(
    'contents',
    next,
  )

  return changed
}

export const webBackend = {
  listConnectedAccounts:
    async () =>
      read<
        ConnectedAccount[]
      >(
        'accounts',
        [],
      ),

  saveConnectedAccount:
    async (
      input:
        SaveAccountInput,
    ) => {
      const list =
        read<
          ConnectedAccount[]
        >(
          'accounts',
          [],
        )

      const id =
        input.id
        || uid('account')

      const previous =
        list.find(
          (item) =>
            item.id === id,
        )

      const item:
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
          connectionStatus:
            input.connectionStatus,
          authState:
            input.authState,
          capabilitiesJson:
            input.capabilitiesJson,
          externalReference:
            input.externalReference,
          lastVerifiedAt:
            previous
              ?.lastVerifiedAt
            || null,
          lastError:
            previous
              ?.lastError
            || null,
          createdAt:
            previous
              ?.createdAt
            || now(),
          updatedAt:
            now(),
        }

      write(
        'accounts',
        [
          ...list.filter(
            (x) =>
              x.id !== id,
          ),
          item,
        ],
      )

      return item
    },

  removeConnectedAccount:
    async (
      accountId: string,
    ) => {
      const list =
        read<
          ConnectedAccount[]
        >(
          'accounts',
          [],
        )

      const next =
        list.filter(
          (item) =>
            item.id
            !== accountId,
        )

      write(
        'accounts',
        next,
      )

      return (
        next.length
        !== list.length
      )
    },

  listPublicationJobs:
    async () =>
      read<
        PublishJob[]
      >(
        'jobs',
        [],
      ),

  publishingPreflight:
    async (
      targetId: string,
      accountId?:
        string | null,
    ):
      Promise<
        PreflightReport
      > => {
      const contents =
        read<ContentItem[]>(
          'contents',
          [],
        )

      const content =
        contents.find(
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

      const accounts =
        read<
          ConnectedAccount[]
        >(
          'accounts',
          [],
        )

      const account =
        accounts.find(
          (item) =>
            item.id
            === accountId,
        )

      const auto =
        Boolean(
          account
          && account.connectionStatus
            === 'CONNECTED'
          && account.authState
            === 'AUTHORIZED',
        )

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
          blocking:
            true,
          detail:
            content.status,
        },

        {
          key:
            'media',
          label:
            'Medio disponible',
          ok:
            content.media.length
            > 0,
          blocking:
            true,
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
          blocking:
            true,
          detail:
            target.scheduledAt,
        },

        {
          key:
            'account',
          label:
            auto
              ? 'API autorizada'
              : 'Publicación manual válida',
          ok:
            true,
          blocking:
            false,
          detail:
            account?.displayName
            || 'Sin API',
        },
      ]

      return {
        targetId,
        accountId,
        provider:
          target.platform,
        ready:
          checks
            .filter(
              (check) =>
                check.blocking,
            )
            .every(
              (check) =>
                check.ok,
            ),
        executionMode:
          auto
            ? 'AUTO_API'
            : 'MANUAL',
        needsManualAction:
          !auto,
        checks,
      }
    },

  enqueuePublications:
    async (
      inputs:
        EnqueueInput[],
    ) => {
      const contents =
        read<ContentItem[]>(
          'contents',
          [],
        )

      const existing =
        read<PublishJob[]>(
          'jobs',
          [],
        )

      const map =
        new Map(
          existing.map(
            (job) => [
              job.idempotencyKey,
              job,
            ],
          ),
        )

      for (
        const input
        of inputs
      ) {
        const content =
          contents.find(
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

        const key =
          [
            input.targetId,
            input.accountId || '',
            target.scheduledAt || '',
            content.sourceFingerprint || '',
            input.mode,
          ].join(':')

        const existingJob =
          map.get(key)

        const mode =
          input.mode
          || 'MANUAL'

        const item:
          PublishJob = {
          id:
            existingJob?.id
            || uid('job'),
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
            mode === 'AUTO_API'
              ? 'QUEUED'
              : mode === 'EXTERNAL'
                ? 'SCHEDULED_EXTERNAL'
                : 'MANUAL_REQUIRED',
          idempotencyKey:
            key,
          attempt:
            existingJob?.attempt
            || 0,
          maxAttempts: 4,
          remoteId:
            existingJob?.remoteId
            || null,
          remoteUrl:
            existingJob?.remoteUrl
            || null,
          lastErrorCode:
            null,
          lastErrorMessage:
            null,
          createdAt:
            existingJob
              ?.createdAt
            || now(),
          updatedAt:
            now(),
        }

        map.set(
          key,
          item,
        )
      }

      const jobs =
        [...map.values()]

      write(
        'jobs',
        jobs,
      )

      return jobs
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
    ):
      Promise<
        ExternalPublication
      > => {
      const contents =
        read<ContentItem[]>(
          'contents',
          [],
        )

      let provider = ''

      const next =
        contents.map(
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

                  provider =
                    target.platform

                  return {
                    ...target,
                    status:
                      'SCHEDULED_EXTERNAL',
                    scheduledAt:
                      scheduledAt
                      || target
                        .scheduledAt,
                    scheduleSource:
                      'EXTERNAL',
                  }
                },
              ),
          }),
        )

      write(
        'contents',
        next,
      )

      return {
        id:
          uid('external'),
        targetId,
        provider,
        method,
        scheduledAt,
        remoteUrl,
        note,
        createdAt:
          now(),
      }
    },

  health:
    async ():
      Promise<
        HealthReport
      > => ({
      database: true,
      ffmpeg: false,
      ffprobe: false,
      appDataDir:
        'Portable browser workspace',
    }),

  listBrands:
    async () =>
      read<Brand[]>(
        'brands',
        [],
      ),

  createBrand:
    async (
      name: string,
    ) => {
      const brands =
        read<Brand[]>(
          'brands',
          [],
        )

      const existing =
        brands.find(
          (item) =>
            item.name
              .toLowerCase()
            === name
              .trim()
              .toLowerCase(),
        )

      if (existing) {
        return existing
      }

      const brand:
        Brand = {
        id:
          uid('brand'),
        name:
          name.trim(),
        createdAt:
          now(),
      }

      write(
        'brands',
        [
          ...brands,
          brand,
        ],
      )

      return brand
    },

  previewImportLocal:
    async (
      _path: string,
      _brand: string,
    ) => {
      throw new Error(
        'La importación desde carpetas locales requiere Desktop.',
      )
    },

  commitImportLocal:
    async (
      _path: string,
      _brand: string,
      _duplicatePolicy:
        'replace'
        | 'keep'
        | 'skip',
    ) => {
      throw new Error(
        'La importación local requiere Desktop.',
      )
    },

  importFolder:
    async (
      _path: string,
    ) => {
      throw new Error(
        'La importación local requiere Desktop.',
      )
    },

  listContents:
    async () =>
      read<ContentItem[]>(
        'contents',
        [],
      ),

  updateSchedule:
    async (
      targetId: string,
      scheduledAt:
        string | null,
    ) => {
      const list =
        read<ContentItem[]>(
          'contents',
          [],
        )

      let changed =
        false

      const next =
        list.map(
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

                  changed = true

                  return {
                    ...target,
                    scheduledAt,
                    scheduleSource:
                      scheduledAt
                        ? 'LOCAL'
                        : null,
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
      let total = 0

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
          total += 1
        }
      }

      return total
    },

  updateWorkflowStatus:
    async (
      contentId: string,
      status: string,
    ) => {
      const changed =
        updateContent(
          contentId,
          (content) => ({
            ...content,
            status,
          }),
        )

      if (changed) {
        logActivity(
          'STATUS',
          'content',
          contentId,
          status,
        )
      }

      return changed
    },

  saveCorrectionNote:
    async (
      contentId: string,
      note: string,
      status: string,
    ):
      Promise<
        CorrectionNote
      > => {
      const correction:
        CorrectionNote = {
        id:
          uid('note'),
        body:
          note,
        createdAt:
          now(),
      }

      updateContent(
        contentId,
        (content) => ({
          ...content,
          status,
          latestNote:
            correction,
        }),
      )

      return correction
    },

  refreshContent:
    async (
      contentId: string,
    ):
      Promise<
        RefreshResult
      > => {
      const content =
        read<ContentItem[]>(
          'contents',
          [],
        ).find(
          (item) =>
            item.id
            === contentId,
        )

      if (!content) {
        throw new Error(
          'Contenido no encontrado.',
        )
      }

      return {
        content,
        changed: false,
        previousVersion:
          content.version,
        currentVersion:
          content.version,
        message:
          'En Web/PWA la referencia cloud no requiere refresh local.',
      }
    },

  listActivity:
    async () =>
      read<ActivityEvent[]>(
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
        + 'driveWebClientId',
      ),

  setDriveClientId:
    async (
      clientId: string,
    ) => {
      localStorage.setItem(
        PREFIX
        + 'driveWebClientId',
        clientId,
      )

      return true
    },

  driveStatus:
    async () =>
      webDrive.connected(),

  driveConnect:
    async (
      clientId: string,
    ):
      Promise<
        DriveAuthResult
      > => {
      await webDrive.prepare()

      await webDrive.connect(
        clientId,
      )

      return {
        connected: true,
        message:
          'Google Drive conectado.',
      }
    },

  driveList:
    async (
      folderId =
        'root',
    ):
      Promise<
        DriveItem[]
      > =>
      webDrive.list(
        folderId,
      ),

  drivePreviewFolder:
    async (
      folderId: string,
      brand: string,
    ):
      Promise<
        ImportPreview
      > =>
      webDrive.previewFolder(
        folderId,
        brand,
      ),

  driveImportFolder:
    async (
      folderId: string,
      brand: string,
      duplicatePolicy:
        'replace'
        | 'keep'
        | 'skip',
    ):
      Promise<
        ScanResult
      > => {
      const preview =
        await webDrive
          .previewFolder(
            folderId,
            brand,
          )

      const existing =
        read<ContentItem[]>(
          'contents',
          [],
        )

      const map =
        new Map(
          existing.map(
            (item) => [
              item.id,
              item,
            ],
          ),
        )

      let imported = 0

      for (
        const item
        of preview.contents
      ) {
        const found =
          map.get(
            item.id,
          )

        if (
          found
          && duplicatePolicy
            === 'skip'
        ) {
          continue
        }

        if (
          found
          && duplicatePolicy
            === 'keep'
        ) {
          const copy = {
            ...item,
            id:
              uid('drive'),
            title:
              `${item.title} · copia`,
          }

          map.set(
            copy.id,
            copy,
          )
        } else {
          map.set(
            item.id,
            item,
          )
        }

        imported += 1
      }

      const contents =
        [...map.values()]

      write(
        'contents',
        contents,
      )

      return {
        rootPath:
          `drive://${folderId}`,
        importedCount:
          imported,
        contents,
        warnings:
          preview.warnings,
        errors:
          preview.errors,
      }
    },

  simulateBatch:
    async ():
      Promise<
        SimulationReport
      > => {
      const targets =
        read<ContentItem[]>(
          'contents',
          [],
        )
          .flatMap(
            (item) =>
              item.targets,
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
          now(),
        platforms: [],
        note:
          'Simulación portable.',
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
            .removeItem(key)
        }
      }

      return true
    },
}
TS

###############################################################################
# 6. GOOGLE DRIVE WEB
###############################################################################

section "6/14 · GOOGLE DRIVE WEB"

cat > src/lib/webDrive.ts <<'TS'
import type {
  ContentItem,
  DriveItem,
  ImportPreview,
  MediaAsset,
  PublicationTarget,
} from '../types'

let token = ''
let expires = 0
let authClient:
  any = null

const READ_SCOPE =
  'https://www.googleapis.com/auth/drive.readonly'

function readyToken() {
  if (
    !token
    || Date.now() >= expires
  ) {
    throw new Error(
      'La sesión de Google Drive ha caducado. Conecta Drive nuevamente.',
    )
  }

  return token
}

async function loadGoogleIdentity() {
  if (
    (window as any)
      .google
      ?.accounts
      ?.oauth2
  ) {
    return
  }

  if (
    document
      .getElementById(
        'abraxas-google-gis',
      )
  ) {
    await new Promise(
      (resolve) =>
        setTimeout(
          resolve,
          700,
        ),
    )

    return
  }

  await new Promise<
    void
  >(
    (
      resolve,
      reject,
    ) => {
      const script =
        document
          .createElement(
            'script',
          )

      script.id =
        'abraxas-google-gis'

      script.src =
        'https://accounts.google.com/gsi/client'

      script.async =
        true

      const timeout =
        window.setTimeout(
          () => {
            script.remove()

            reject(
              new Error(
                'Google Identity Services no respondió.',
              ),
            )
          },
          15000,
        )

      script.onload =
        () => {
          clearTimeout(
            timeout,
          )

          resolve()
        }

      script.onerror =
        () => {
          clearTimeout(
            timeout,
          )

          reject(
            new Error(
              'No se pudo cargar Google Identity Services.',
            ),
          )
        }

      document.head
        .appendChild(
          script,
        )
    },
  )
}

async function api(
  path: string,
  params:
    Record<
      string,
      string
    > = {},
) {
  const url =
    new URL(
      `https://www.googleapis.com/drive/v3/${path}`,
    )

  for (
    const [
      key,
      value,
    ]
    of Object.entries(
      params,
    )
  ) {
    url.searchParams
      .set(
        key,
        value,
      )
  }

  const response =
    await fetch(
      url,
      {
        headers: {
          Authorization:
            `Bearer ${readyToken()}`,
        },

        cache:
          'no-store',

        referrerPolicy:
          'no-referrer',
      },
    )

  if (
    response.status
    === 401
  ) {
    token = ''
    expires = 0

    throw new Error(
      'La sesión de Drive caducó.',
    )
  }

  if (!response.ok) {
    throw new Error(
      `Google Drive ${response.status}`,
    )
  }

  return response.json()
}

function kindFromMime(
  mime: string,
) {
  if (
    mime.startsWith(
      'video/',
    )
  ) {
    return 'video'
  }

  if (
    mime.startsWith(
      'image/',
    )
  ) {
    return 'image'
  }

  return 'file'
}

function contentType(
  files:
    Array<{
      mimeType: string
      name: string
    }>,
) {
  if (
    files.some(
      (file) =>
        file.mimeType
          .startsWith(
            'video/',
          ),
    )
  ) {
    const name =
      files
        .map(
          (file) =>
            file.name
              .toLowerCase(),
        )
        .join(' ')

    if (
      name.includes(
        'reel',
      )
      || name.includes(
        'short',
      )
    ) {
      return 'reel'
    }

    return 'video'
  }

  if (
    files.filter(
      (file) =>
        file.mimeType
          .startsWith(
            'image/',
          ),
    ).length > 1
  ) {
    return 'carousel'
  }

  if (
    files.some(
      (file) =>
        file.mimeType
          .startsWith(
            'image/',
          ),
    )
  ) {
    return 'image'
  }

  return 'unknown'
}

function defaultTargets(
  contentId: string,
):
  PublicationTarget[] {
  return [
    'instagram',
    'facebook',
    'linkedin',
    'youtube',
    'tiktok',
  ].map(
    (platform) => ({
      id:
        `${contentId}-${platform}`,
      platform,
      account: null,
      status:
        'UNSCHEDULED',
      scheduledAt:
        null,
      sourceTxt:
        null,
      copy:
        null,
      scheduleSource:
        null,
    }),
  )
}

export const webDrive = {
  async prepare() {
    await loadGoogleIdentity()
  },

  connected() {
    return Boolean(
      token
      && Date.now()
        < expires,
    )
  },

  async connect(
    clientId: string,
  ) {
    if (
      !/^[\w.-]+\.apps\.googleusercontent\.com$/
        .test(
          clientId,
        )
    ) {
      throw new Error(
        'Introduce un OAuth Client ID Web público válido.',
      )
    }

    await loadGoogleIdentity()

    const google =
      (window as any)
        .google

    return new Promise<
      void
    >(
      (
        resolve,
        reject,
      ) => {
        authClient =
          google.accounts
            .oauth2
            .initTokenClient({
              client_id:
                clientId,

              scope:
                READ_SCOPE,

              callback:
                (
                  response:
                    any,
                ) => {
                  if (
                    response.error
                  ) {
                    reject(
                      new Error(
                        `Google rechazó la conexión: ${response.error}`,
                      ),
                    )

                    return
                  }

                  token =
                    response
                      .access_token

                  expires =
                    Date.now()
                    + Math.max(
                        0,
                        Number(
                          response
                            .expires_in,
                        )
                        - 60,
                      )
                      * 1000

                  resolve()
                },

              error_callback:
                (
                  response:
                    any,
                ) => {
                  reject(
                    new Error(
                      `Ventana de Google: ${response.type}`,
                    ),
                  )
                },
            })

        authClient
          .requestAccessToken({
            prompt:
              'consent',
          })
      },
    )
  },

  async disconnect() {
    const previous =
      token

    token = ''
    expires = 0

    const google =
      (window as any)
        .google

    if (
      previous
      && google?.accounts
        ?.oauth2
    ) {
      google.accounts
        .oauth2
        .revoke(
          previous,
          () => {},
        )
    }
  },

  async list(
    folderId =
      'root',
  ):
    Promise<
      DriveItem[]
    > {
    const files:
      any[] = []

    let pageToken = ''

    do {
      const data =
        await api(
          'files',
          {
            q:
              `'${folderId}' in parents and trashed = false`,

            fields:
              'nextPageToken,files(id,name,mimeType,size,parents,videoMediaMetadata(durationMillis,width,height))',

            orderBy:
              'folder,name',

            pageSize:
              '100',

            supportsAllDrives:
              'true',

            includeItemsFromAllDrives:
              'true',

            ...(pageToken
              ? {
                  pageToken,
                }
              : {}),
          },
        )

      files.push(
        ...(data.files || []),
      )

      pageToken =
        data.nextPageToken
        || ''
    } while (
      pageToken
      && files.length < 2000
    )

    return files.map(
      (file) => ({
        id:
          file.id,
        name:
          file.name,
        mimeType:
          file.mimeType,
        isFolder:
          file.mimeType
          === 'application/vnd.google-apps.folder',
        size:
          file.size
            ? Number(
                file.size,
              )
            : null,
      }),
    )
  },

  async previewFolder(
    folderId: string,
    brand: string,
  ):
    Promise<
      ImportPreview
    > {
    const folder =
      folderId === 'root'
        ? {
            id: 'root',
            name:
              'Mi Drive',
          }
        : await api(
            `files/${encodeURIComponent(folderId)}`,
            {
              fields:
                'id,name,mimeType',
              supportsAllDrives:
                'true',
            },
          )

    const children:
      any[] =
      await this.list(
        folderId,
      )

    const mediaFiles =
      children.filter(
        (file) =>
          !file.isFolder
          && (
            file.mimeType
              .startsWith(
                'video/',
              )
            || file.mimeType
              .startsWith(
                'image/',
              )
          ),
      )

    const subfolders =
      children.filter(
        (file) =>
          file.isFolder,
      )

    const contents:
      ContentItem[] = []

    /*
     * Si la carpeta actual tiene media,
     * la carpeta completa es una ficha.
     */
    if (
      mediaFiles.length
      > 0
    ) {
      const id =
        `drive-${folderId}`

      const media:
        MediaAsset[] =
        mediaFiles.map(
          (file) => ({
            id:
              `drive-media-${file.id}`,
            path:
              `drive://${file.id}`,
            kind:
              kindFromMime(
                file.mimeType,
              ),
            sizeBytes:
              file.size
                ? Number(
                    file.size,
                  )
                : 0,
            durationSeconds:
              null,
            sha256:
              null,
            modifiedAt:
              null,
          }),
        )

      contents.push({
        id,
        folderPath:
          `drive://${folderId}`,
        title:
          folder.name
          || 'Contenido Drive',
        client:
          brand,
        contentType:
          contentType(
            mediaFiles,
          ),
        status:
          'EN_CONFIRMACION',
        validationStatus:
          'VALID',
        version: 1,
        sourceFingerprint:
          `drive:${folderId}`,
        refreshedAt:
          new Date()
            .toISOString(),
        latestNote:
          null,
        sourceKind:
          'GOOGLE_DRIVE',
        sourceRef:
          folderId,
        media,
        targets:
          defaultTargets(id),
        issues: [],
      })
    }

    /*
     * Subcarpetas aparecen como
     * fichas importables independientes.
     */
    for (
      const child
      of subfolders
    ) {
      const id =
        `drive-${child.id}`

      contents.push({
        id,
        folderPath:
          `drive://${child.id}`,
        title:
          child.name,
        client:
          brand,
        contentType:
          'unknown',
        status:
          'EN_CONFIRMACION',
        validationStatus:
          'VALID',
        version: 1,
        sourceFingerprint:
          `drive:${child.id}`,
        refreshedAt:
          new Date()
            .toISOString(),
        latestNote:
          null,
        sourceKind:
          'GOOGLE_DRIVE',
        sourceRef:
          child.id,
        media: [],
        targets:
          defaultTargets(id),
        issues: [],
      })
    }

    return {
      rootPath:
        `drive://${folderId}`,
      contents,
      duplicates: [],
      warnings:
        contents.length
          ? 0
          : 1,
      errors: 0,
    }
  },

  async mediaBlobUrl(
    fileId: string,
  ) {
    const response =
      await fetch(
        `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media`,
        {
          headers: {
            Authorization:
              `Bearer ${readyToken()}`,
          },

          cache:
            'no-store',
        },
      )

    if (!response.ok) {
      throw new Error(
        `Drive ${response.status}`,
      )
    }

    const blob =
      await response.blob()

    return URL
      .createObjectURL(
        blob,
      )
  },
}
TS

###############################################################################
# 7. SHARED SUPABASE SYNC
###############################################################################

section "7/14 · SHARED WORKSPACE SYNC"

cat > src/lib/publisherSync.ts <<'TS'
import {
  getPortableSnapshot,
  replacePortableSnapshot,
  type PortableSnapshot,
} from './webBackend'

import {
  cloudUser,
  getPublisherChannel,
  PUBLISHER_WORKSPACE,
  setPublisherChannel,
  supabaseClient,
} from './supabase'

let timer:
  number | null =
    null

let pushing =
  false

let applyingRemote =
  false

function mergeById<
  T extends {
    id: string
  }
>(
  remote:
    T[] = [],
  local:
    T[] = [],
) {
  const map =
    new Map<
      string,
      T
    >()

  for (
    const item
    of remote
  ) {
    map.set(
      item.id,
      item,
    )
  }

  for (
    const item
    of local
  ) {
    map.set(
      item.id,
      {
        ...map.get(
          item.id,
        ),
        ...item,
      },
    )
  }

  return [...map.values()]
}

function mergeContents(
  remote:
    PortableSnapshot['contents'],
  local:
    PortableSnapshot['contents'],
) {
  const map =
    new Map(
      remote.map(
        (item) => [
          item.id,
          item,
        ],
      ),
    )

  for (
    const localItem
    of local
  ) {
    const remoteItem =
      map.get(
        localItem.id,
      )

    if (!remoteItem) {
      map.set(
        localItem.id,
        localItem,
      )

      continue
    }

    const targetMap =
      new Map(
        remoteItem.targets.map(
          (target) => [
            target.id,
            target,
          ],
        ),
      )

    for (
      const target
      of localItem.targets
    ) {
      targetMap.set(
        target.id,
        {
          ...targetMap.get(
            target.id,
          ),
          ...target,
        },
      )
    }

    const mediaMap =
      new Map(
        remoteItem.media.map(
          (media) => [
            media.id,
            media,
          ],
        ),
      )

    for (
      const media
      of localItem.media
    ) {
      mediaMap.set(
        media.id,
        {
          ...mediaMap.get(
            media.id,
          ),
          ...media,
        },
      )
    }

    map.set(
      localItem.id,
      {
        ...remoteItem,
        ...localItem,
        media:
          [...mediaMap.values()],
        targets:
          [...targetMap.values()],
      },
    )
  }

  return [...map.values()]
}

function mergePayload(
  remote:
    Partial<
      PortableSnapshot
    > | null,
  local:
    PortableSnapshot,
):
  PortableSnapshot {
  const remoteMeta =
    remote?.syncMeta

  const nextRevision =
    Math.max(
      Number(
        local.syncMeta
          ?.revision
        || 0,
      ),

      Number(
        local.syncMeta
          ?.baseRevision
        || 0,
      ),

      Number(
        remoteMeta
          ?.revision
        || 0,
      ),

      Number(
        remoteMeta
          ?.baseRevision
        || 0,
      ),
    ) + 1

  /*
   * Preserve unknown future root fields
   * conceptually by starting from remote,
   * but PortableSnapshot only exposes
   * Publisher-owned branches.
   */
  return {
    version: 1,

    brands:
      mergeById(
        remote?.brands,
        local.brands,
      ),

    contents:
      mergeContents(
        remote?.contents
        || [],
        local.contents,
      ),

    accounts:
      mergeById(
        remote?.accounts,
        local.accounts,
      ),

    publicationJobs:
      mergeById(
        remote
          ?.publicationJobs,
        local
          .publicationJobs,
      ),

    activity:
      mergeById(
        remote?.activity,
        local.activity,
      )
        .sort(
          (a,b) =>
            b.createdAt
              .localeCompare(
                a.createdAt,
              ),
        )
        .slice(
          0,
          500,
        ),

    syncMeta: {
      revision:
        nextRevision,

      baseRevision:
        Number(
          remoteMeta
            ?.revision
          || 0,
        ),

      deviceId:
        local.syncMeta
          .deviceId,

      productVersion:
        'publisher-1.3.2',

      updatedAt:
        new Date()
          .toISOString(),
    },
  }
}

export async function pullPublisher(
  silent = false,
) {
  const supabase =
    supabaseClient()

  const user =
    await cloudUser()

  if (
    !supabase
    || !user
  ) {
    return false
  }

  const {
    data,
    error,
  } =
    await supabase
      .from(
        'editorial_state',
      )
      .select(
        'payload,updated_at',
      )
      .eq(
        'user_id',
        user.id,
      )
      .eq(
        'workspace_key',
        PUBLISHER_WORKSPACE,
      )
      .maybeSingle()

  if (error) {
    if (!silent) {
      throw error
    }

    console.error(
      error,
    )

    return false
  }

  if (
    !data?.payload
  ) {
    return false
  }

  applyingRemote = true

  try {
    const remote =
      data.payload
        as PortableSnapshot

    /*
     * On pull remote revision is respected.
     * Remote is the portable cross-device
     * source of truth.
     */
    replacePortableSnapshot({
      ...remote,

      version: 1,

      syncMeta: {
        ...remote.syncMeta,

        deviceId:
          getPortableSnapshot()
            .syncMeta
            .deviceId,

        baseRevision:
          remote.syncMeta
            ?.revision
          || 0,
      },
    })
  } finally {
    applyingRemote =
      false
  }

  return true
}

export async function pushPublisher(
  silent = false,
) {
  if (
    pushing
    || applyingRemote
    || !navigator.onLine
  ) {
    return false
  }

  const supabase =
    supabaseClient()

  const user =
    await cloudUser()

  if (
    !supabase
    || !user
  ) {
    return false
  }

  pushing = true

  try {
    const {
      data,
      error,
    } =
      await supabase
        .from(
          'editorial_state',
        )
        .select(
          'payload,updated_at',
        )
        .eq(
          'user_id',
          user.id,
        )
        .eq(
          'workspace_key',
          PUBLISHER_WORKSPACE,
        )
        .maybeSingle()

    if (error) {
      if (!silent) {
        throw error
      }

      console.error(
        error,
      )

      return false
    }

    const local =
      getPortableSnapshot()

    const merged =
      mergePayload(
        data?.payload
          || null,
        local,
      )

    const {
      error:
        upsertError,
    } =
      await supabase
        .from(
          'editorial_state',
        )
        .upsert(
          {
            user_id:
              user.id,

            workspace_key:
              PUBLISHER_WORKSPACE,

            payload:
              merged,

            updated_at:
              new Date()
                .toISOString(),
          },
          {
            onConflict:
              'user_id,workspace_key',
          },
        )

    if (upsertError) {
      if (!silent) {
        throw upsertError
      }

      console.error(
        upsertError,
      )

      return false
    }

    replacePortableSnapshot(
      merged,
    )

    return true
  } finally {
    pushing = false
  }
}

export function schedulePublisherPush() {
  if (applyingRemote) {
    return
  }

  if (timer) {
    clearTimeout(
      timer,
    )
  }

  timer =
    window.setTimeout(
      () => {
        pushPublisher(
          true,
        ).catch(
          console.error,
        )
      },
      900,
    )
}

export async function subscribePublisher() {
  const supabase =
    supabaseClient()

  const user =
    await cloudUser()

  if (
    !supabase
    || !user
  ) {
    return
  }

  const previous =
    getPublisherChannel()

  if (previous) {
    await supabase
      .removeChannel(
        previous,
      )
  }

  const channel =
    supabase
      .channel(
        `abraxas-publisher-${user.id}`,
      )
      .on(
        'postgres_changes',
        {
          event:
            '*',
          schema:
            'public',
          table:
            'editorial_state',
          filter:
            `user_id=eq.${user.id}`,
        },
        (
          payload:
            any,
        ) => {
          const row =
            payload.new

          if (
            row?.workspace_key
              !==
              PUBLISHER_WORKSPACE
          ) {
            return
          }

          const remote =
            row?.payload
              as
              PortableSnapshot
              | undefined

          if (!remote) {
            return
          }

          const local =
            getPortableSnapshot()

          const remoteRevision =
            Number(
              remote.syncMeta
                ?.revision
              || 0,
            )

          const localRevision =
            Number(
              local.syncMeta
                ?.revision
              || 0,
            )

          if (
            remoteRevision
            <= localRevision
          ) {
            return
          }

          applyingRemote =
            true

          try {
            replacePortableSnapshot({
              ...remote,

              syncMeta: {
                ...remote.syncMeta,

                deviceId:
                  local
                    .syncMeta
                    .deviceId,

                baseRevision:
                  remoteRevision,
              },
            })
          } finally {
            applyingRemote =
              false
          }
        },
      )
      .subscribe()

  setPublisherChannel(
    channel,
  )
}

export async function initializePublisherSync() {
  const user =
    await cloudUser()

  if (!user) {
    return false
  }

  await pullPublisher(
    true,
  )

  await subscribePublisher()

  return true
}

window.addEventListener(
  'online',
  () => {
    pushPublisher(
      true,
    ).catch(
      console.error,
    )
  },
)

window.addEventListener(
  'abraxas-portable-changed',
  () => {
    schedulePublisherPush()
  },
)
TS

###############################################################################
# Make portable writes emit sync event
###############################################################################

python3 <<'PY'
from pathlib import Path

p = Path("src/lib/webBackend.ts")
s = p.read_text()

old = """function write<T>(
  key: string,
  value: T,
) {
  localStorage.setItem(
    PREFIX + key,
    JSON.stringify(value),
  )
}"""

new = """function write<T>(
  key: string,
  value: T,
) {
  localStorage.setItem(
    PREFIX + key,
    JSON.stringify(value),
  )

  window.dispatchEvent(
    new CustomEvent(
      'abraxas-portable-changed',
    ),
  )
}"""

if old not in s:
    raise SystemExit(
        "No encontré write() en webBackend.ts"
    )

s = s.replace(
    old,
    new,
    1,
)

p.write_text(s)
PY

###############################################################################
# 8. DESKTOP + PORTABLE ROUTER
###############################################################################

section "8/14 · UNIFIED BACKEND"

if [ ! -f src/lib/nativeBackend.ts ]; then
  cp \
    "$BACKUP/src/lib/backend.ts" \
    src/lib/nativeBackend.ts

  python3 <<'PY'
from pathlib import Path

p = Path(
    "src/lib/nativeBackend.ts"
)

s = p.read_text()

s = s.replace(
    "export const backend = {",
    "export const nativeBackend = {",
    1,
)

p.write_text(s)
PY
fi

cat > src/lib/backend.ts <<'TS'
import {
  isTauriRuntime,
} from './runtime'

import {
  nativeBackend,
} from './nativeBackend'

import {
  mergePortableBrands,
  mergePortableContents,
  webBackend,
} from './webBackend'

import {
  schedulePublisherPush,
} from './publisherSync'

async function syncNativePortable() {
  if (
    !isTauriRuntime()
  ) {
    return
  }

  const [
    contents,
    brands,
    accounts,
    jobs,
  ] =
    await Promise.all([
      nativeBackend
        .listContents(),

      nativeBackend
        .listBrands(),

      nativeBackend
        .listConnectedAccounts(),

      nativeBackend
        .listPublicationJobs(),
    ])

  mergePortableContents(
    contents,
  )

  mergePortableBrands(
    brands,
  )

  for (
    const account
    of accounts
  ) {
    await webBackend
      .saveConnectedAccount({
        id:
          account.id,
        provider:
          account.provider,
        brand:
          account.brand,
        displayName:
          account.displayName,
        handle:
          account.handle,
        accountKind:
          account.accountKind,
        connectionStatus:
          account.connectionStatus,
        authState:
          account.authState,
        capabilitiesJson:
          account.capabilitiesJson,
        externalReference:
          account.externalReference,
      })
  }

  /*
   * Native jobs are mirrored by re-enqueueing
   * only when the portable queue is empty.
   * Existing portable cloud jobs remain.
   */
  if (
    (
      await webBackend
        .listPublicationJobs()
    ).length === 0
  ) {
    const inputs =
      jobs.map(
        (job) => ({
          targetId:
            job.targetId,
          accountId:
            job.accountId,
          mode:
            job.mode,
        }),
      )

    if (inputs.length) {
      await webBackend
        .enqueuePublications(
          inputs,
        )
    }
  }

  schedulePublisherPush()
}

export async function initializeBackend() {
  if (
    isTauriRuntime()
  ) {
    await syncNativePortable()
  }
}

export const backend = {
  /*
   * PORTABLE DOMAIN
   *
   * Siempre se usa para que Desktop/Web/PWA
   * compartan el mismo workspace.
   */
  listConnectedAccounts:
    webBackend
      .listConnectedAccounts,

  saveConnectedAccount:
    async (
      input:
        Parameters<
          typeof webBackend
            .saveConnectedAccount
        >[0],
    ) => {
      const portable =
        await webBackend
          .saveConnectedAccount(
            input,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .saveConnectedAccount(
              input,
            )
        } catch (
          error
        ) {
          console.error(
            'Native account mirror:',
            error,
          )
        }
      }

      schedulePublisherPush()

      return portable
    },

  removeConnectedAccount:
    async (
      accountId: string,
    ) => {
      const result =
        await webBackend
          .removeConnectedAccount(
            accountId,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .removeConnectedAccount(
              accountId,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listPublicationJobs:
    webBackend
      .listPublicationJobs,

  publishingPreflight:
    webBackend
      .publishingPreflight,

  enqueuePublications:
    async (
      inputs:
        Parameters<
          typeof webBackend
            .enqueuePublications
        >[0],
    ) => {
      const result =
        await webBackend
          .enqueuePublications(
            inputs,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .enqueuePublications(
              inputs,
            )
        } catch (
          error
        ) {
          console.error(
            'Native queue mirror:',
            error,
          )
        }
      }

      schedulePublisherPush()

      return result
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
    ) => {
      const result =
        await webBackend
          .markScheduledExternal(
            targetId,
            method,
            scheduledAt,
            remoteUrl,
            note,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .markScheduledExternal(
              targetId,
              method,
              scheduledAt,
              remoteUrl,
              note,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listBrands:
    webBackend
      .listBrands,

  createBrand:
    async (
      name: string,
    ) => {
      const result =
        await webBackend
          .createBrand(
            name,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          const native =
            await nativeBackend
              .createBrand(
                name,
              )

          mergePortableBrands([
            native,
          ])
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listContents:
    webBackend
      .listContents,

  updateSchedule:
    async (
      targetId: string,
      scheduledAt:
        string | null,
    ) => {
      const result =
        await webBackend
          .updateSchedule(
            targetId,
            scheduledAt,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .updateSchedule(
              targetId,
              scheduledAt,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  updateSchedules:
    async (
      changes:
        Parameters<
          typeof webBackend
            .updateSchedules
        >[0],
    ) => {
      const result =
        await webBackend
          .updateSchedules(
            changes,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .updateSchedules(
              changes,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  updateWorkflowStatus:
    async (
      contentId: string,
      status: string,
    ) => {
      const result =
        await webBackend
          .updateWorkflowStatus(
            contentId,
            status,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .updateWorkflowStatus(
              contentId,
              status,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  saveCorrectionNote:
    async (
      contentId: string,
      note: string,
      status: string,
    ) => {
      const result =
        await webBackend
          .saveCorrectionNote(
            contentId,
            note,
            status,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .saveCorrectionNote(
              contentId,
              note,
              status,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listActivity:
    webBackend
      .listActivity,

  /*
   * NATIVE-ONLY operations
   */
  health:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .health()
        : webBackend
            .health(),

  previewImportLocal:
    async (
      path: string,
      brand: string,
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .previewImportLocal(
            path,
            brand,
          )
      }

      return nativeBackend
        .previewImportLocal(
          path,
          brand,
        )
    },

  commitImportLocal:
    async (
      path: string,
      brand: string,
      policy:
        'replace'
        | 'keep'
        | 'skip',
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .commitImportLocal(
            path,
            brand,
            policy,
          )
      }

      const result =
        await nativeBackend
          .commitImportLocal(
            path,
            brand,
            policy,
          )

      mergePortableContents(
        result.contents,
      )

      schedulePublisherPush()

      return result
    },

  importFolder:
    async (
      path: string,
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .importFolder(
            path,
          )
      }

      const result =
        await nativeBackend
          .importFolder(
            path,
          )

      mergePortableContents(
        result.contents,
      )

      schedulePublisherPush()

      return result
    },

  refreshContent:
    async (
      contentId: string,
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .refreshContent(
            contentId,
          )
      }

      const result =
        await nativeBackend
          .refreshContent(
            contentId,
          )

      mergePortableContents([
        result.content,
      ])

      schedulePublisherPush()

      return result
    },

  undo:
    async () => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .undo()
      }

      const result =
        await nativeBackend
          .undo()

      await syncNativePortable()

      return result
    },

  redo:
    async () => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .redo()
      }

      const result =
        await nativeBackend
          .redo()

      await syncNativePortable()

      return result
    },

  /*
   * DRIVE:
   * Desktop usa Tauri OAuth.
   * Web/PWA usa GIS OAuth.
   */
  getDriveClientId:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .getDriveClientId()
        : webBackend
            .getDriveClientId(),

  setDriveClientId:
    (
      clientId: string,
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .setDriveClientId(
              clientId,
            )
        : webBackend
            .setDriveClientId(
              clientId,
            ),

  driveStatus:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .driveStatus()
        : webBackend
            .driveStatus(),

  driveConnect:
    (
      clientId: string,
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .driveConnect(
              clientId,
            )
        : webBackend
            .driveConnect(
              clientId,
            ),

  driveList:
    (
      folderId =
        'root',
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .driveList(
              folderId,
            )
        : webBackend
            .driveList(
              folderId,
            ),

  drivePreviewFolder:
    (
      folderId: string,
      brand: string,
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .drivePreviewFolder(
              folderId,
              brand,
            )
        : webBackend
            .drivePreviewFolder(
              folderId,
              brand,
            ),

  driveImportFolder:
    async (
      folderId: string,
      brand: string,
      policy:
        'replace'
        | 'keep'
        | 'skip',
    ) => {
      const result =
        isTauriRuntime()
          ? await nativeBackend
              .driveImportFolder(
                folderId,
                brand,
                policy,
              )
          : await webBackend
              .driveImportFolder(
                folderId,
                brand,
                policy,
              )

      mergePortableContents(
        result.contents,
      )

      schedulePublisherPush()

      return result
    },

  simulateBatch:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .simulateBatch()
        : webBackend
            .simulateBatch(),

  clearWorkspace:
    async () => {
      await webBackend
        .clearWorkspace()

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .clearWorkspace()
        } catch {}
      }

      schedulePublisherPush()

      return true
    },
}
TS

###############################################################################
# 9. IMPORT UI RUNTIME AWARE
###############################################################################

section "9/14 · DRIVE UI DESKTOP / WEB"

python3 <<'PY'
from pathlib import Path

p = Path(
    "src/views/ImportView.tsx"
)

s = p.read_text()

if "isTauriRuntime" not in s:
    anchor = """import {
  backend,
} from '../lib/backend'
"""

    s = s.replace(
        anchor,
        anchor + """
import {
  isTauriRuntime,
} from '../lib/runtime'
""",
        1,
    )

s = s.replace(
    "'Primero introduce el OAuth Client ID de Google tipo Desktop.'",
    """isTauriRuntime()
            ? 'Introduce el OAuth Client ID de Google tipo Desktop.'
            : 'Introduce el OAuth Client ID Web de Google.'""",
)

s = s.replace(
    """Usa un OAuth Client ID de tipo Desktop. El login se abre en tu navegador, no dentro del WebView.""",
    """{isTauriRuntime()
                      ? 'Usa el OAuth Client ID de tipo Desktop. El login se abre en tu navegador.'
                      : 'Usa el OAuth Client ID Web público autorizado para https://lordjeferies.github.io.'}""",
)

s = s.replace(
    """<p>
            Desde este Mac o directamente desde Google Drive.
          </p>""",
    """<p>
            {isTauriRuntime()
              ? 'Desde este Mac o directamente desde Google Drive.'
              : 'Desde Google Drive. Las carpetas locales del Mac sólo están disponibles en Desktop.'}
          </p>""",
)

# Hide local source tab on Web.
s = s.replace(
    """        <button
          className={
            mode === 'local'
              ? 'source-tab active'
              : 'source-tab'
          }""",
    """        <button
          hidden={!isTauriRuntime()}
          className={
            mode === 'local'
              ? 'source-tab active'
              : 'source-tab'
          }""",
    1,
)

# Default to Drive on Web after mount.
needle = """  const [mode, setMode] =
    useState<Mode>('local')"""

replacement = """  const [mode, setMode] =
    useState<Mode>(
      isTauriRuntime()
        ? 'local'
        : 'drive',
    )"""

s = s.replace(
    needle,
    replacement,
    1,
)

p.write_text(s)
print("✓ ImportView")
PY

###############################################################################
# 10. SYNC CENTER
###############################################################################

section "10/14 · CLOUD LOGIN / SYNC CENTER"

cat > src/views/SyncView.tsx <<'TS'
import {
  CheckCircle2,
  Cloud,
  Laptop,
  LogIn,
  LogOut,
  RefreshCcw,
  Smartphone,
} from 'lucide-react'

import {
  useEffect,
  useState,
} from 'react'

import {
  runtimeSurface,
} from '../lib/runtime'

import {
  cloudSignIn,
  cloudSignOut,
  cloudSignUp,
  cloudUser,
  supabaseConfigured,
} from '../lib/supabase'

import {
  initializePublisherSync,
  pullPublisher,
  pushPublisher,
} from '../lib/publisherSync'

export function SyncView() {
  const [
    email,
    setEmail,
  ] =
    useState('')

  const [
    password,
    setPassword,
  ] =
    useState('')

  const [
    userEmail,
    setUserEmail,
  ] =
    useState<
      string | null
    >(null)

  const [
    message,
    setMessage,
  ] =
    useState('')

  const [
    syncing,
    setSyncing,
  ] =
    useState(false)

  const load =
    async () => {
      const user =
        await cloudUser()

      setUserEmail(
        user?.email
        || null,
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

  const login =
    async () => {
      try {
        setMessage(
          'Conectando…',
        )

        await cloudSignIn(
          email,
          password,
        )

        await initializePublisherSync()

        await load()

        setMessage(
          'ABRAXAS Cloud conectado y sincronizado.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      }
    }

  const register =
    async () => {
      try {
        const data =
          await cloudSignUp(
            email,
            password,
          )

        if (
          data.session
        ) {
          await initializePublisherSync()
          await load()
        }

        setMessage(
          data.session
            ? 'Cuenta creada y conectada.'
            : 'Cuenta creada. Revisa el email si Supabase exige confirmación.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      }
    }

  const sync =
    async () => {
      setSyncing(true)

      try {
        await pushPublisher()
        await pullPublisher()

        setMessage(
          'Sincronización completada.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      } finally {
        setSyncing(false)
      }
    }

  const logout =
    async () => {
      await cloudSignOut()

      setUserEmail(
        null,
      )

      setMessage(
        'Sesión cerrada.',
      )
    }

  const runtime =
    runtimeSurface()

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            ABRAXAS CLOUD
          </span>

          <h1>
            Sincronización
          </h1>

          <p>
            El mismo workspace de Publisher en Mac, Web y PWA.
          </p>
        </div>

        {
          userEmail
          && (
            <button
              className="secondary-btn"
              disabled={syncing}
              onClick={sync}
            >
              <RefreshCcw size={15}/>
              {
                syncing
                  ? 'Sincronizando…'
                  : 'Sincronizar'
              }
            </button>
          )
        }
      </header>

      {
        !supabaseConfigured()
        ? (
          <section className="panel">
            Supabase no está configurado.
          </section>
        )
        : !userEmail
          ? (
            <section className="panel sync-login-card">
              <Cloud size={25}/>

              <span className="eyebrow">
                MISMO LOGIN ABRAXAS
              </span>

              <h2>
                Entrar
              </h2>

              <p>
                Usa el mismo usuario Supabase de Editorial OS en Desktop, iPhone y navegador.
              </p>

              <input
                className="field full-field"
                type="email"
                placeholder="Email"
                value={email}
                onChange={(event) =>
                  setEmail(
                    event.target.value,
                  )
                }
              />

              <input
                className="field full-field"
                type="password"
                placeholder="Contraseña"
                value={password}
                onChange={(event) =>
                  setPassword(
                    event.target.value,
                  )
                }
              />

              <div className="sync-login-actions">
                <button
                  className="primary-btn"
                  onClick={login}
                >
                  <LogIn size={15}/>
                  Entrar
                </button>

                <button
                  className="secondary-btn"
                  onClick={register}
                >
                  Crear cuenta
                </button>
              </div>

              {
                message
                && (
                  <small>
                    {message}
                  </small>
                )
              }
            </section>
          )
          : (
            <>
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
                    DISPOSITIVO
                  </span>

                  <h2>
                    {
                      runtime
                      === 'desktop'
                        ? 'Publisher Desktop'
                        : 'Publisher Web/PWA'
                    }
                  </h2>

                  <p>
                    {
                      runtime
                        .toUpperCase()
                    }
                  </p>
                </section>

                <section className="panel sync-card">
                  <div className="sync-card-icon">
                    <CheckCircle2/>
                  </div>

                  <span className="eyebrow">
                    SUPABASE
                  </span>

                  <h2>
                    Conectado
                  </h2>

                  <p>
                    {userEmail}
                  </p>

                  <small>
                    workspace_key:
                    {' '}
                    abraxas-publisher
                  </small>
                </section>
              </div>

              <section className="panel">
                <h3>
                  Qué se comparte
                </h3>

                <div className="capability-table">
                  <div>
                    <span>
                      Marcas y contenidos
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Estados y correcciones
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Calendario
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Cuentas metadata
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Cola de publicación
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Paths locales / ffmpeg
                    </span>
                    <b>
                      Sólo Desktop
                    </b>
                  </div>
                </div>
              </section>

              <button
                className="danger-text-btn"
                onClick={logout}
              >
                <LogOut size={14}/>
                Cerrar sesión
              </button>

              {
                message
                && (
                  <div className="hybrid-success">
                    {message}
                  </div>
                )
              }
            </>
          )
      }
    </div>
  )
}
TS

###############################################################################
# 11. INITIALIZATION
###############################################################################

section "11/14 · STARTUP"

python3 <<'PY'
from pathlib import Path

p = Path("src/main.tsx")
s = p.read_text()

# Remove obsolete cloud sync import if present.
s = s.replace(
    "import { startCloudSync } from './lib/cloudSync'\n",
    "",
)

s = s.replace(
    "\nstartCloudSync()\n",
    "\n",
)

if "initializePublisherSync" not in s:
    anchor = """import { registerPwa } from './pwa'"""

    if anchor in s:
        s = s.replace(
            anchor,
            anchor + """
import {
  initializePublisherSync,
} from './lib/publisherSync'

import {
  initializeBackend,
} from './lib/backend'
""",
            1,
        )
    else:
        s = """import {
  initializePublisherSync,
} from './lib/publisherSync'

import {
  initializeBackend,
} from './lib/backend'
""" + s

    s += """

initializeBackend()
  .then(
    () =>
      initializePublisherSync(),
  )
  .catch(
    console.error,
  )
"""

p.write_text(s)
PY

python3 <<'PY'
from pathlib import Path

p = Path("src/App.tsx")
s = p.read_text()

# Ensure Sync route.
if "SyncView" not in s:
    s = s.replace(
        "import { SettingsView } from './views/SettingsView'",
        """import { SettingsView } from './views/SettingsView'
import { SyncView } from './views/SyncView'""",
        1,
    )

if "v === 'sync'" not in s:
    s = s.replace(
        "  if (v === 'settings') return <SettingsView/>",
        """  if (v === 'settings') return <SettingsView/>
  if (v === 'sync') return <SyncView/>""",
        1,
    )

# Reload store when portable state changes.
if "abraxas-portable-updated" not in s:
    old = """  useEffect(() => {
    Promise.all([
      backend.listContents(),
      backend.listBrands(),
    ])
      .then(([content, brandList]) => {
        setContents(content)
        setBrands(brandList)
      })
      .catch(console.error)
  }, [setContents, setBrands])"""

    new = """  useEffect(() => {
    const load = () => {
      Promise.all([
        backend.listContents(),
        backend.listBrands(),
      ])
        .then(([content, brandList]) => {
          setContents(content)
          setBrands(brandList)
        })
        .catch(console.error)
    }

    load()

    window.addEventListener(
      'abraxas-portable-updated',
      load,
    )

    return () =>
      window.removeEventListener(
        'abraxas-portable-updated',
        load,
      )
  }, [setContents, setBrands])"""

    if old in s:
        s = s.replace(
            old,
            new,
            1,
        )

p.write_text(s)
PY

###############################################################################
# 12. DOWNLOAD DESKTOP + DOCS
###############################################################################

section "12/14 · PWA DESKTOP DOWNLOAD"

cat > src/components/DesktopDownload.tsx <<'TS'
import {
  Download,
  Laptop,
} from 'lucide-react'

import {
  isTauriRuntime,
} from '../lib/runtime'

const URL =
  'https://github.com/LordJeferies/abraxas-publisher/releases/latest/download/ABRAXAS-Publisher-macOS.zip'

export function DesktopDownload() {
  if (
    isTauriRuntime()
  ) {
    return null
  }

  return (
    <a
      className="desktop-download-card"
      href={URL}
    >
      <Laptop size={22}/>

      <div>
        <strong>
          Descargar ABRAXAS Publisher para Mac
        </strong>

        <span>
          La versión Desktop comparte este mismo workspace y añade archivos locales, ffmpeg y worker nativo.
        </span>
      </div>

      <Download size={18}/>
    </a>
  )
}
TS

python3 <<'PY'
from pathlib import Path

p = Path(
    "src/views/HomeView.tsx"
)

s = p.read_text()

if "DesktopDownload" not in s:
    anchor = """import {
  useAppStore,
} from '../lib/store'
"""

    s = s.replace(
        anchor,
        anchor + """
import {
  DesktopDownload,
} from '../components/DesktopDownload'
""",
        1,
    )

    marker = """      <section className="panel recent-panel">"""

    s = s.replace(
        marker,
        """      <DesktopDownload/>

"""
        + marker,
        1,
    )

s = s.replace(
    "ABRAXAS PUBLISHER · V1.2",
    "ABRAXAS PUBLISHER · V1.3.2",
)

p.write_text(s)
PY

mkdir -p docs

cat > docs/SHARED_CLOUD_CONTRACT.md <<'MD'
# ABRAXAS Publisher · Shared Cloud Contract

## Supabase

Publisher uses the same Supabase project and Auth as Editorial OS.

Table:

public.editorial_state

Workspace:

abraxas-publisher

Never use editorial-os for Publisher.

## Row identity

user_id + workspace_key

## Publisher portable payload

{
  version,
  brands,
  contents,
  accounts,
  publicationJobs,
  activity,
  syncMeta
}

## Sync

Desktop and Web/PWA use the same portable domain state.

Desktop additionally mirrors native operations into:

- SQLite
- filesystem
- Tauri
- ffmpeg/ffprobe
- future local publishing worker

Supabase is the cross-device source of truth for portable metadata.

## Conflict model

syncMeta includes:

revision
baseRevision
deviceId
productVersion
updatedAt

Next revision is based on the maximum local/base/remote revision.

## Google Drive

Desktop:
OAuth Desktop via Tauri.

Web/PWA:
Google Identity Services OAuth Web.

Web token:
memory only.

Scope:
drive.readonly.

A separate explicit write authorization should be used if Publisher later writes
receipts/corrections back to Drive.

## Security

Never expose:

service_role
database password
OAuth client secrets
refresh tokens

Browser may use:

Supabase project URL
publishable/anon key
Google OAuth Web Client ID
MD

cat >> CHANGELOG.md <<'MD'

## 0.4.2 · Final shared Desktop/PWA architecture

- Same Supabase project as Editorial OS.
- `public.editorial_state`.
- `workspace_key = abraxas-publisher`.
- Same Supabase Auth across Mac/Web/PWA.
- Local-first portable Publisher workspace.
- Realtime synchronization.
- revision/baseRevision/deviceId conflict contract.
- Desktop mirrors portable state with native backend.
- Google Drive Web OAuth based on Abrxs Review.
- Drive token remains in memory.
- Desktop keeps native Google Drive OAuth.
- PWA download button for macOS Desktop.
MD

###############################################################################
# CSS
###############################################################################

if ! grep -q \
  "desktop-download-card" \
  src/styles.css
then
cat >> src/styles.css <<'CSS'

.desktop-download-card{
  margin:12px 0;
  border:1px solid rgba(55,85,145,.32);
  border-radius:14px;
  padding:13px;
  display:grid;
  grid-template-columns:auto 1fr auto;
  align-items:center;
  gap:10px;
  text-decoration:none;
  color:inherit;
  background:linear-gradient(
    135deg,
    rgba(50,80,145,.10),
    rgba(95,115,165,.04)
  );
}

.desktop-download-card strong,
.desktop-download-card span{
  display:block;
}

.desktop-download-card span{
  color:var(--muted);
  font-size:9px;
  margin-top:3px;
}

.sync-login-card{
  width:min(520px,100%);
  margin:30px auto;
  display:grid;
  gap:10px;
}

.sync-login-actions{
  display:flex;
  gap:7px;
}
CSS
fi

###############################################################################
# 13. PAGES WORKFLOW
###############################################################################

section "13/14 · GITHUB PAGES"

mkdir -p .github/workflows

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
  group: abraxas-publisher-pages
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
        env:
          VITE_SUPABASE_URL: ${{ secrets.VITE_SUPABASE_URL }}
          VITE_SUPABASE_PUBLISHABLE_KEY: ${{ secrets.VITE_SUPABASE_PUBLISHABLE_KEY }}
        run: npm run build:web

      - name: Configure Pages
        uses: actions/configure-pages@v5

      - name: Upload Pages
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./dist

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    needs: build
    runs-on: ubuntu-latest

    steps:
      - name: Deploy
        id: deployment
        uses: actions/deploy-pages@v4
YAML

###############################################################################
# 14. QA
###############################################################################

section "14/14 · QA / BUILD / RELEASE"

echo
echo "Validando contrato ABRAXAS Cloud..."

grep -q "abraxas-publisher" src/lib/supabase.ts \
  || fail "Falta workspace_key abraxas-publisher."

grep -q "editorial_state" src/lib/publisherSync.ts \
  || fail "Publisher no apunta a public.editorial_state."

if grep -R \
  --exclude-dir=node_modules \
  --exclude-dir=target \
  --exclude='*.command' \
  -n "abraxas_snapshots\|abraxas_tasks" \
  src \
  >/tmp/abraxas_old_sync_refs.txt 2>/dev/null
then
  echo
  echo "AVISO: encontré referencias a la arquitectura provisional:"
  cat /tmp/abraxas_old_sync_refs.txt
  echo
fi

rm -f /tmp/abraxas_old_sync_refs.txt

echo "✓ public.editorial_state"
echo "✓ workspace_key = abraxas-publisher"

npm install

echo
echo "→ TypeScript"

npm run check \
  || fail "TypeScript falló."

echo
echo "→ Desktop frontend"

npm run build \
  || fail "Vite Desktop falló."

echo
echo "→ Rust"

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

echo
echo "→ PWA"

rm -rf dist

GITHUB_ACTIONS=true \
npm run build:web \
  || fail "PWA build falló."

[ -f dist/index.html ] \
  || fail "Falta dist/index.html"

[ -f dist/manifest.webmanifest ] \
  || fail "Falta manifest.webmanifest"

[ -f dist/sw.js ] \
  || fail "Falta service worker"

echo "✓ PWA"

###############################################################################
# TAURI
###############################################################################

unset GITHUB_ACTIONS

echo
echo "→ Tauri"

npm run tauri:build \
  || fail "Tauri build falló."

NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"

if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(
    find \
      "$ROOT/src-tauri/target/release/bundle" \
      -type d \
      -name "*.app" \
      -print \
      -quit
  )"
fi

[ -d "$NEW_APP" ] \
  || fail "No encontré ABRAXAS Publisher.app"

###############################################################################
# INSTALL MAC
###############################################################################

APP="$HOME/Applications/ABRAXAS Publisher.app"
OLD="$HOME/Applications/ABRAXAS Publisher.pre-final-v132.$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.final-v132.$STAMP.app"

mkdir -p \
  "$HOME/Applications"

rm -rf "$STAGE"

ditto \
  "$NEW_APP" \
  "$STAGE"

xattr -dr \
  com.apple.quarantine \
  "$STAGE" \
  >/dev/null 2>&1 \
  || true

if [ -d "$APP" ]; then
  mv \
    "$APP" \
    "$OLD"
fi

if ! mv \
  "$STAGE" \
  "$APP"
then
  [ -d "$OLD" ] \
    && mv "$OLD" "$APP" \
    || true

  fail "No se pudo instalar Desktop."
fi

###############################################################################
# DESKTOP SHORTCUT
###############################################################################

rm -f \
  "$HOME/Desktop/ABRAXAS Publisher.app"

ln -s \
  "$APP" \
  "$HOME/Desktop/ABRAXAS Publisher.app"

###############################################################################
# RELEASE ZIP
###############################################################################

RELEASE_ASSET="$ROOT/ABRAXAS-Publisher-macOS.zip"

rm -f \
  "$RELEASE_ASSET"

ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$APP" \
  "$RELEASE_ASSET"

###############################################################################
# GIT · CLEAN RELEASE
###############################################################################

# Nunca subir archivos de descubrimiento/configuración privada.
rm -f \
  .supabase-discovered-*.env \
  .v132-runtime.env

touch .gitignore

for ITEM in \
  ".env" \
  ".env.local" \
  ".env.*.local" \
  ".supabase-discovered-*.env" \
  ".v132-runtime.env"
do
  grep -qxF "$ITEM" .gitignore \
    || echo "$ITEM" >> .gitignore
done

###############################################################################
# Los intentos anteriores crearon commits LOCALES no publicados.
# Uno contenía un archivo .supabase-discovered-*.env.
#
# Como no llegó a origin, reconstruimos esos commits limpiamente encima de
# origin/v1.3-publishing-center antes de publicar.
###############################################################################

if git rev-parse \
  --verify \
  "origin/$BRANCH" \
  >/dev/null 2>&1
then

  if git log \
      --name-only \
      --pretty=format: \
      "origin/$BRANCH..HEAD" \
      | grep -q '^\.supabase-discovered-'
  then
    echo
    echo "Limpiando archivo de configuración del historial LOCAL..."

    git reset \
      --soft \
      "origin/$BRANCH"

    echo "✓ commits locales preservados como cambios"
    echo "✓ archivo sensible eliminado antes del push"
  fi
fi

###############################################################################
# Limpiar scripts temporales de reparación del producto final.
###############################################################################

rm -f \
  APLICAR_V132_DESKTOP_PWA_SYNC.command \
  CONTINUAR_V132_DESKTOP_PWA.command \
  COMPLETAR_V132_SUPABASE_SYNC.command \
  REPARAR_Y_FINALIZAR_V132.command

git add -A

if ! git diff \
  --cached \
  --quiet
then
  git commit \
    -m "Finalize V1.3.2 shared Supabase and Web Drive"
fi

SHA="$(git rev-parse HEAD)"

git push \
  -u origin \
  "$BRANCH"

###############################################################################
# MAIN FAST FORWARD ONLY
###############################################################################

MAIN_UPDATED="no"

if git push \
  origin \
  "$BRANCH:main"
then
  MAIN_UPDATED="yes"
else
  echo
  echo "AVISO:"
  echo "main no aceptó fast-forward."
  echo "No se hizo force push."
fi

###############################################################################
# VERSION TAG — NEVER FORCE
###############################################################################

BASE_TAG="publisher-v1.3.2"

if git rev-parse \
  "$BASE_TAG" \
  >/dev/null 2>&1 \
  || git ls-remote \
    --tags origin \
    "refs/tags/$BASE_TAG" \
    | grep -q .
then
  RELEASE_TAG="publisher-v1.3.2-final-$STAMP"
else
  RELEASE_TAG="$BASE_TAG"
fi

git tag \
  "$RELEASE_TAG" \
  "$SHA"

git push \
  origin \
  "$RELEASE_TAG"

###############################################################################
# GITHUB RELEASE
###############################################################################

if command -v gh >/dev/null 2>&1 \
  && gh auth status >/dev/null 2>&1
then
  gh release create \
    "$RELEASE_TAG" \
    "$RELEASE_ASSET" \
    --repo LordJeferies/abraxas-publisher \
    --title "ABRAXAS Publisher V1.3.2" \
    --notes "Desktop + Web/PWA + shared Editorial Supabase + Google Drive Web." \
    --latest \
    || true

  ###########################################################################
  # Enable Pages using Actions
  ###########################################################################

  if gh api \
    repos/LordJeferies/abraxas-publisher/pages \
    >/dev/null 2>&1
  then
    gh api \
      --method PUT \
      repos/LordJeferies/abraxas-publisher/pages \
      -f build_type=workflow \
      >/dev/null 2>&1 \
      || true
  else
    gh api \
      --method POST \
      repos/LordJeferies/abraxas-publisher/pages \
      -f build_type=workflow \
      >/dev/null 2>&1 \
      || true
  fi
fi

###############################################################################
# LOCAL RELEASE
###############################################################################

RELEASE_DIR="$HOME/Developer/abraxas-publisher/releases/v1.3.2-final"

mkdir -p \
  "$RELEASE_DIR"

git archive \
  --format=zip \
  --output="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.2_FULL.zip" \
  HEAD

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.3.2 · FINAL COMPLETADA"
echo "=============================================================="
echo
echo "Desktop:"
echo "  $APP"
echo
echo "Escritorio:"
echo "  $HOME/Desktop/ABRAXAS Publisher.app"
echo
echo "Web/PWA:"
echo "  https://lordjeferies.github.io/abraxas-publisher/"
echo
echo "Desktop Download:"
echo "  https://github.com/LordJeferies/abraxas-publisher/releases/latest/download/ABRAXAS-Publisher-macOS.zip"
echo
echo "Supabase:"
echo "  mismo proyecto Editorial OS"
echo "  table: public.editorial_state"
echo "  workspace: abraxas-publisher"
echo
echo "Sincronización:"
echo "  ✓ marcas"
echo "  ✓ contenidos"
echo "  ✓ estados"
echo "  ✓ notas"
echo "  ✓ calendario"
echo "  ✓ cuentas metadata"
echo "  ✓ publication jobs"
echo "  ✓ realtime"
echo "  ✓ revision/baseRevision/deviceId"
echo
echo "Google Drive:"
echo "  ✓ Desktop OAuth nativo"
echo "  ✓ Web/PWA Google Identity Services"
echo "  ✓ drive.readonly"
echo "  ✓ token Web sólo en memoria"
echo "  ✓ navegador de carpetas"
echo
echo "Desktop:"
echo "  ✓ Tauri"
echo "  ✓ SQLite"
echo "  ✓ filesystem"
echo "  ✓ backend nativo"
echo "  ✓ mirror portable"
echo
echo "Git:"
echo "  commit: $SHA"
echo "  tag: $RELEASE_TAG"
echo "  main actualizado: $MAIN_UPDATED"
echo
echo "Backup:"
echo "  $OLD"
echo
echo "Log:"
echo "  $LOG"
echo
echo "SIGUIENTE:"
echo "  OAuth social real + adapters Meta/TikTok/YouTube/LinkedIn."
echo

open "$APP" || true

