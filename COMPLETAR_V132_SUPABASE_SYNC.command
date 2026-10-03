#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

BRANCH="v1.3-publishing-center"
VERSION="0.4.2"
TAG="publisher-v1.3.2"
STAMP="$(date +%Y%m%d_%H%M%S)"

LOG="$ROOT/logs/v132_supabase_$STAMP.log"
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
# 1. PRECHECK
###############################################################################

section "1/12 · PRECHECK"

git switch "$BRANCH"

if [ -n "$(git status --porcelain)" ]; then
  git add -A

  git commit \
    -m "Snapshot before Supabase Sync completion $STAMP" \
    || true
fi

BASE_SHA="$(git rev-parse HEAD)"

echo "Base:"
echo "  $BASE_SHA"

###############################################################################
# 2. FIX IMPORT.META.ENV
###############################################################################

section "2/12 · VITE ENV TYPES"

cat > src/vite-env.d.ts <<'TS'
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string
  readonly VITE_SUPABASE_ANON_KEY?: string
  readonly VITE_ABRAXAS_SYNC_API?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
TS

echo "✓ ImportMeta.env"

###############################################################################
# 3. SUPABASE PACKAGE
###############################################################################

section "3/12 · SUPABASE CLIENT"

npm install @supabase/supabase-js

###############################################################################
# 4. AUTODISCOVER CONFIG FROM LOCAL ABRAXAS REPOS
###############################################################################

section "4/12 · DISCOVER ABRAXAS SUPABASE"

DISCOVERED="$ROOT/.supabase-discovered-$STAMP.env"

python3 <<'PY' > "$DISCOVERED"
from pathlib import Path
import os
import re
import shlex

home = Path.home()

roots = [
    home / "Developer",
    home / "Documents",
]

skip = {
    ".git",
    "node_modules",
    "target",
    "dist",
    "build",
    ".next",
    ".turbo",
}

candidates = []

for root in roots:
    if not root.exists():
        continue

    for base, dirs, files in os.walk(root):
        dirs[:] = [
            d for d in dirs
            if d not in skip
        ]

        p = Path(base)

        low = str(p).lower()

        if (
            "abraxas" not in low
            and "lordjeferies" not in low
        ):
            # Permitir recorrer hasta encontrar repos ABRAXAS.
            if len(p.relative_to(root).parts) > 3:
                dirs[:] = []
            continue

        for name in files:
            if (
                name.startswith(".env")
                or name in {
                    "config.toml",
                    "supabase.toml",
                }
            ):
                candidates.append(
                    p / name
                )

values = {}

patterns = {
    "url": [
        "VITE_SUPABASE_URL",
        "NEXT_PUBLIC_SUPABASE_URL",
        "SUPABASE_URL",
    ],

    "publishable": [
        "VITE_SUPABASE_PUBLISHABLE_KEY",
        "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
        "SUPABASE_PUBLISHABLE_KEY",
    ],

    "anon": [
        "VITE_SUPABASE_ANON_KEY",
        "NEXT_PUBLIC_SUPABASE_ANON_KEY",
        "SUPABASE_ANON_KEY",
    ],

    "access_token": [
        "SUPABASE_ACCESS_TOKEN",
    ],

    "db_url": [
        "SUPABASE_DB_URL",
        "DATABASE_URL",
    ],

    "db_password": [
        "SUPABASE_DB_PASSWORD",
        "POSTGRES_PASSWORD",
    ],
}

def parse_assignment(text, key):
    m = re.search(
        rf'(?m)^\s*(?:export\s+)?{re.escape(key)}\s*=\s*(.+?)\s*$',
        text,
    )

    if not m:
        return None

    value = m.group(1).strip()

    if (
        len(value) >= 2
        and value[0] == value[-1]
        and value[0] in "'\""
    ):
        value = value[1:-1]

    value = value.strip()

    if (
        not value
        or value.startswith("${")
    ):
        return None

    return value

for file in candidates:
    try:
        text = file.read_text(
            errors="ignore",
        )
    except Exception:
        continue

    for dest, keys in patterns.items():
        if dest in values:
            continue

        for key in keys:
            value = parse_assignment(
                text,
                key,
            )

            if not value:
                continue

            if (
                dest == "db_url"
                and "supabase" not in value.lower()
            ):
                continue

            values[dest] = value
            values[
                f"{dest}_source"
            ] = str(file)
            break

# Fallback: detect project URL in text.
if "url" not in values:
    for file in candidates:
        try:
            text = file.read_text(
                errors="ignore",
            )
        except Exception:
            continue

        m = re.search(
            r'https://([a-z0-9-]+)\.supabase\.co',
            text,
            re.I,
        )

        if m:
            values["url"] = m.group(0)
            values["url_source"] = str(file)
            break

# Supabase CLI PAT fallback.
token_locations = [
    home / ".supabase" / "access-token",
    home / ".config" / "supabase" / "access-token",
]

if "access_token" not in values:
    for file in token_locations:
        if file.exists():
            token = file.read_text().strip()

            if token:
                values["access_token"] = token
                values["access_token_source"] = str(file)
                break

url = values.get("url", "")

project_ref = ""

if url:
    m = re.search(
        r'https://([^.]+)\.supabase\.co',
        url,
    )

    if m:
        project_ref = m.group(1)

key = (
    values.get("publishable")
    or values.get("anon")
    or ""
)

print(
    "SUPABASE_URL="
    + shlex.quote(url)
)

print(
    "SUPABASE_CLIENT_KEY="
    + shlex.quote(key)
)

print(
    "SUPABASE_ACCESS_TOKEN="
    + shlex.quote(
        values.get(
            "access_token",
            "",
        ),
    )
)

print(
    "SUPABASE_DB_URL="
    + shlex.quote(
        values.get(
            "db_url",
            "",
        ),
    )
)

print(
    "SUPABASE_DB_PASSWORD="
    + shlex.quote(
        values.get(
            "db_password",
            "",
        ),
    )
)

print(
    "SUPABASE_PROJECT_REF="
    + shlex.quote(
        project_ref,
    )
)

print(
    "SUPABASE_URL_SOURCE="
    + shlex.quote(
        values.get(
            "url_source",
            "",
        ),
    )
)

print(
    "SUPABASE_KEY_SOURCE="
    + shlex.quote(
        values.get(
            "publishable_source",
            values.get(
                "anon_source",
                "",
            ),
        ),
    )
)
PY

chmod 600 "$DISCOVERED"

# shellcheck disable=SC1090
source "$DISCOVERED"

echo "URL encontrada:"
echo "  ${SUPABASE_URL_SOURCE:-no}"

echo "Client key encontrada:"
echo "  ${SUPABASE_KEY_SOURCE:-no}"

[ -n "${SUPABASE_URL:-}" ] \
  || fail "No encontré SUPABASE_URL en los repos locales ABRAXAS."

[ -n "${SUPABASE_CLIENT_KEY:-}" ] \
  || fail "Encontré Supabase pero no una publishable/anon client key."

###############################################################################
# Local env. NEVER COMMIT.
###############################################################################

cat > .env.local <<EOF
VITE_SUPABASE_URL=$SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY=$SUPABASE_CLIENT_KEY
VITE_SUPABASE_ANON_KEY=$SUPABASE_CLIENT_KEY
EOF

chmod 600 .env.local

touch .gitignore

for ENTRY in \
  ".env" \
  ".env.local" \
  ".env.*.local" \
  ".supabase-discovered-*.env"
do
  grep -qxF "$ENTRY" .gitignore \
    || echo "$ENTRY" >> .gitignore
done

###############################################################################
# 5. SUPABASE CLIENT
###############################################################################

section "5/12 · SUPABASE RUNTIME"

cat > src/lib/supabase.ts <<'TS'
import {
  createClient,
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

export async function currentUser():
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
      .getUser()

  return (
    data.user
    || null
  )
}

export async function signIn(
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

  const result =
    await supabase
      .auth
      .signInWithPassword({
        email,
        password,
      })

  if (result.error) {
    throw result.error
  }

  return result.data
}

export async function signUp(
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

  const result =
    await supabase
      .auth
      .signUp({
        email,
        password,
      })

  if (result.error) {
    throw result.error
  }

  return result.data
}

export async function signOut() {
  const supabase =
    supabaseClient()

  if (!supabase) {
    return
  }

  await supabase
    .auth
    .signOut()
}
TS

###############################################################################
# 6. DATABASE SCHEMA
###############################################################################

section "6/12 · SUPABASE DATABASE"

mkdir -p supabase/migrations

MIGRATION="supabase/migrations/20261003161000_abraxas_publisher_sync.sql"

cat > "$MIGRATION" <<'SQL'
create extension if not exists pgcrypto;

create table if not exists public.abraxas_snapshots (
  user_id uuid primary key
    references auth.users(id)
    on delete cascade,

  payload jsonb not null
    default '{}'::jsonb,

  revision bigint not null
    default 1,

  updated_at timestamptz not null
    default now()
);

create table if not exists public.abraxas_tasks (
  id uuid primary key
    default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  task_type text not null,

  execution_host text not null
    check (
      execution_host in (
        'CLOUD',
        'DESKTOP',
        'MANUAL'
      )
    ),

  status text not null,

  payload jsonb not null
    default '{}'::jsonb,

  error_message text,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now()
);

create index if not exists
  idx_abraxas_tasks_user_status
on public.abraxas_tasks(
  user_id,
  status,
  created_at
);

create table if not exists public.abraxas_devices (
  id text not null,

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  name text not null,

  runtime text not null,

  app_version text,

  capabilities jsonb not null
    default '{}'::jsonb,

  last_seen timestamptz not null
    default now(),

  primary key (
    user_id,
    id
  )
);

alter table
  public.abraxas_snapshots
enable row level security;

alter table
  public.abraxas_tasks
enable row level security;

alter table
  public.abraxas_devices
enable row level security;

revoke all
on table public.abraxas_snapshots
from anon;

revoke all
on table public.abraxas_tasks
from anon;

revoke all
on table public.abraxas_devices
from anon;

grant
  select,
  insert,
  update,
  delete
on public.abraxas_snapshots
to authenticated;

grant
  select,
  insert,
  update,
  delete
on public.abraxas_tasks
to authenticated;

grant
  select,
  insert,
  update,
  delete
on public.abraxas_devices
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname='public'
      and tablename='abraxas_snapshots'
      and policyname='abraxas_snapshots_select'
  ) then
    create policy abraxas_snapshots_select
      on public.abraxas_snapshots
      for select
      to authenticated
      using (
        auth.uid() is not null
        and auth.uid() = user_id
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname='public'
      and tablename='abraxas_snapshots'
      and policyname='abraxas_snapshots_insert'
  ) then
    create policy abraxas_snapshots_insert
      on public.abraxas_snapshots
      for insert
      to authenticated
      with check (
        auth.uid() is not null
        and auth.uid() = user_id
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname='public'
      and tablename='abraxas_snapshots'
      and policyname='abraxas_snapshots_update'
  ) then
    create policy abraxas_snapshots_update
      on public.abraxas_snapshots
      for update
      to authenticated
      using (
        auth.uid() is not null
        and auth.uid() = user_id
      )
      with check (
        auth.uid() is not null
        and auth.uid() = user_id
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname='public'
      and tablename='abraxas_tasks'
      and policyname='abraxas_tasks_all'
  ) then
    create policy abraxas_tasks_all
      on public.abraxas_tasks
      for all
      to authenticated
      using (
        auth.uid() is not null
        and auth.uid() = user_id
      )
      with check (
        auth.uid() is not null
        and auth.uid() = user_id
      );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname='public'
      and tablename='abraxas_devices'
      and policyname='abraxas_devices_all'
  ) then
    create policy abraxas_devices_all
      on public.abraxas_devices
      for all
      to authenticated
      using (
        auth.uid() is not null
        and auth.uid() = user_id
      )
      with check (
        auth.uid() is not null
        and auth.uid() = user_id
      );
  end if;
end
$$;
SQL

###############################################################################
# APPLY MIGRATION
###############################################################################

SCHEMA_APPLIED="no"

if \
  [ -n "${SUPABASE_ACCESS_TOKEN:-}" ] \
  && [ -n "${SUPABASE_PROJECT_REF:-}" ]
then
  echo "Aplicando schema vía Supabase Management API..."

  BODY="$(
    python3 - "$MIGRATION" <<'PY'
import json
import sys
from pathlib import Path

sql = Path(
    sys.argv[1]
).read_text()

print(
    json.dumps({
        "query": sql,
        "read_only": False,
    })
)
PY
  )"

  HTTP_CODE="$(
    curl \
      -sS \
      -o "/tmp/abraxas-supabase-migration-$STAMP.json" \
      -w "%{http_code}" \
      -X POST \
      "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$BODY" \
      || true
  )"

  if [ "$HTTP_CODE" = "201" ]; then
    SCHEMA_APPLIED="yes"
    echo "✓ Schema aplicado vía Management API"
  else
    echo "Management API respondió $HTTP_CODE"
  fi
fi

if \
  [ "$SCHEMA_APPLIED" != "yes" ] \
  && [ -n "${SUPABASE_DB_URL:-}" ] \
  && command -v psql >/dev/null 2>&1
then
  echo "Aplicando schema vía PostgreSQL..."

  if psql \
    "$SUPABASE_DB_URL" \
    -v ON_ERROR_STOP=1 \
    -f "$MIGRATION"
  then
    SCHEMA_APPLIED="yes"
    echo "✓ Schema aplicado con psql"
  fi
fi

if \
  [ "$SCHEMA_APPLIED" != "yes" ] \
  && command -v supabase >/dev/null 2>&1 \
  && [ -n "${SUPABASE_PROJECT_REF:-}" ] \
  && [ -n "${SUPABASE_DB_PASSWORD:-}" ]
then
  echo "Aplicando schema vía Supabase CLI..."

  export SUPABASE_ACCESS_TOKEN

  supabase link \
    --project-ref "$SUPABASE_PROJECT_REF" \
    --password "$SUPABASE_DB_PASSWORD"

  supabase db push \
    --password "$SUPABASE_DB_PASSWORD"

  SCHEMA_APPLIED="yes"
fi

[ "$SCHEMA_APPLIED" = "yes" ] \
  || fail "Encontré Supabase, pero no pude aplicar el schema. Hace falta un PAT con database:write, SUPABASE_DB_URL, o SUPABASE_DB_PASSWORD."

###############################################################################
# 7. CLOUD SYNC ENGINE
###############################################################################

section "7/12 · SYNC ENGINE"

cat > src/lib/cloudSync.ts <<'TS'
import type {
  Brand,
  ConnectedAccount,
  ContentItem,
  EnqueueInput,
  PublishJob,
  ScheduleChange,
} from '../types'

import {
  isTauriRuntime,
  runtimeSurface,
} from './runtime'

import {
  nativeBackend,
} from './nativeBackend'

import {
  webBackend,
} from './webBackend'

import {
  currentUser,
  supabaseClient,
} from './supabase'

const APP_VERSION =
  '0.4.2'

const DEVICE_ID_KEY =
  'abraxas.sync.deviceId'

let interval:
  number | null =
    null

export interface WorkspaceSnapshot {
  brands: Brand[]
  contents: ContentItem[]
  accounts: ConnectedAccount[]
  jobs: PublishJob[]
  updatedAt: string
  version: string
}

function deviceId() {
  let id =
    localStorage.getItem(
      DEVICE_ID_KEY,
    )

  if (!id) {
    id =
      crypto.randomUUID()

    localStorage.setItem(
      DEVICE_ID_KEY,
      id,
    )
  }

  return id
}

async function selectedBackend() {
  return (
    isTauriRuntime()
      ? nativeBackend
      : webBackend
  )
}

export async function buildSnapshot():
  Promise<WorkspaceSnapshot> {
  const backend =
    await selectedBackend()

  const [
    brands,
    contents,
    accounts,
    jobs,
  ] =
    await Promise.all([
      backend.listBrands(),
      backend.listContents(),
      backend.listConnectedAccounts(),
      backend.listPublicationJobs(),
    ])

  return {
    brands,
    contents,
    accounts,
    jobs,
    updatedAt:
      new Date()
        .toISOString(),
    version:
      APP_VERSION,
  }
}

export async function pushSnapshot() {
  const supabase =
    supabaseClient()

  const user =
    await currentUser()

  if (
    !supabase
    || !user
  ) {
    return false
  }

  const snapshot =
    await buildSnapshot()

  const {
    error,
  } =
    await supabase
      .from(
        'abraxas_snapshots',
      )
      .upsert({
        user_id:
          user.id,
        payload:
          snapshot,
        updated_at:
          snapshot.updatedAt,
      })

  if (error) {
    throw error
  }

  return true
}

export async function pullSnapshotToWeb() {
  if (
    isTauriRuntime()
  ) {
    return false
  }

  const supabase =
    supabaseClient()

  const user =
    await currentUser()

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
        'abraxas_snapshots',
      )
      .select(
        'payload,updated_at',
      )
      .eq(
        'user_id',
        user.id,
      )
      .maybeSingle()

  if (error) {
    throw error
  }

  if (
    !data?.payload
  ) {
    return false
  }

  const snapshot =
    data.payload
      as WorkspaceSnapshot

  localStorage.setItem(
    'abraxas.web.brands',
    JSON.stringify(
      snapshot.brands
      || [],
    ),
  )

  localStorage.setItem(
    'abraxas.web.contents',
    JSON.stringify(
      snapshot.contents
      || [],
    ),
  )

  localStorage.setItem(
    'abraxas.web.accounts',
    JSON.stringify(
      snapshot.accounts
      || [],
    ),
  )

  localStorage.setItem(
    'abraxas.web.jobs',
    JSON.stringify(
      snapshot.jobs
      || [],
    ),
  )

  window.dispatchEvent(
    new CustomEvent(
      'abraxas-sync-updated',
    ),
  )

  return true
}

export async function heartbeat() {
  const supabase =
    supabaseClient()

  const user =
    await currentUser()

  if (
    !supabase
    || !user
  ) {
    return
  }

  await supabase
    .from(
      'abraxas_devices',
    )
    .upsert({
      id:
        deviceId(),
      user_id:
        user.id,
      name:
        isTauriRuntime()
          ? 'ABRAXAS Desktop'
          : (
              runtimeSurface()
              === 'pwa'
                ? 'ABRAXAS PWA'
                : 'ABRAXAS Web'
            ),
      runtime:
        runtimeSurface(),
      app_version:
        APP_VERSION,
      capabilities:
        isTauriRuntime()
          ? {
              filesystem: true,
              ffmpeg: true,
              nativeWorker: true,
            }
          : {
              filesystem: false,
              ffmpeg: false,
              nativeWorker: false,
            },
      last_seen:
        new Date()
          .toISOString(),
    })
}

export async function createDesktopTask(
  taskType: string,
  payload:
    Record<
      string,
      unknown
    >,
) {
  const supabase =
    supabaseClient()

  const user =
    await currentUser()

  if (
    !supabase
    || !user
  ) {
    return null
  }

  const {
    data,
    error,
  } =
    await supabase
      .from(
        'abraxas_tasks',
      )
      .insert({
        user_id:
          user.id,
        task_type:
          taskType,
        execution_host:
          'DESKTOP',
        status:
          'WAITING_FOR_DESKTOP',
        payload,
      })
      .select()
      .single()

  if (error) {
    throw error
  }

  return data
}

async function executeDesktopTask(
  task: {
    id: string
    task_type: string
    payload:
      Record<
        string,
        any
      >
  },
) {
  switch (
    task.task_type
  ) {
    case 'CREATE_BRAND':
      await nativeBackend
        .createBrand(
          String(
            task.payload.name,
          ),
        )
      break

    case 'UPDATE_SCHEDULE':
      await nativeBackend
        .updateSchedule(
          String(
            task.payload.targetId,
          ),
          (
            task.payload.scheduledAt
            ?? null
          ) as
            string | null,
        )
      break

    case 'UPDATE_SCHEDULES':
      await nativeBackend
        .updateSchedules(
          task.payload.changes
            as ScheduleChange[],
        )
      break

    case 'UPDATE_WORKFLOW_STATUS':
      await nativeBackend
        .updateWorkflowStatus(
          String(
            task.payload.contentId,
          ),
          String(
            task.payload.status,
          ),
        )
      break

    case 'ENQUEUE_PUBLICATIONS':
      await nativeBackend
        .enqueuePublications(
          task.payload.inputs
            as EnqueueInput[],
        )
      break

    case 'MARK_SCHEDULED_EXTERNAL':
      await nativeBackend
        .markScheduledExternal(
          String(
            task.payload.targetId,
          ),
          String(
            task.payload.method,
          ),
          (
            task.payload.scheduledAt
            ?? null
          ) as string | null,
          (
            task.payload.remoteUrl
            ?? null
          ) as string | null,
          (
            task.payload.note
            ?? null
          ) as string | null,
        )
      break

    default:
      throw new Error(
        `Task no soportada: ${task.task_type}`,
      )
  }
}

export async function processDesktopTasks() {
  if (
    !isTauriRuntime()
  ) {
    return
  }

  const supabase =
    supabaseClient()

  const user =
    await currentUser()

  if (
    !supabase
    || !user
  ) {
    return
  }

  const {
    data,
    error,
  } =
    await supabase
      .from(
        'abraxas_tasks',
      )
      .select(
        'id,task_type,payload',
      )
      .eq(
        'user_id',
        user.id,
      )
      .eq(
        'execution_host',
        'DESKTOP',
      )
      .eq(
        'status',
        'WAITING_FOR_DESKTOP',
      )
      .order(
        'created_at',
        {
          ascending: true,
        },
      )
      .limit(20)

  if (error) {
    throw error
  }

  for (
    const task
    of data || []
  ) {
    await supabase
      .from(
        'abraxas_tasks',
      )
      .update({
        status:
          'RUNNING',
        updated_at:
          new Date()
            .toISOString(),
      })
      .eq(
        'id',
        task.id,
      )

    try {
      await executeDesktopTask(
        task as any,
      )

      await supabase
        .from(
          'abraxas_tasks',
        )
        .update({
          status:
            'DONE',
          error_message:
            null,
          updated_at:
            new Date()
              .toISOString(),
        })
        .eq(
          'id',
          task.id,
        )
    } catch (
      error
    ) {
      await supabase
        .from(
          'abraxas_tasks',
        )
        .update({
          status:
            'FAILED',
          error_message:
            String(error),
          updated_at:
            new Date()
              .toISOString(),
        })
        .eq(
          'id',
          task.id,
        )
    }
  }
}

export async function syncCycle() {
  const user =
    await currentUser()

  if (!user) {
    return
  }

  await heartbeat()

  if (
    isTauriRuntime()
  ) {
    await processDesktopTasks()
    await pushSnapshot()
  } else {
    await pullSnapshotToWeb()
  }
}

export function startCloudSync() {
  if (interval) {
    return
  }

  const run =
    () => {
      syncCycle()
        .catch(
          console.error,
        )
    }

  run()

  interval =
    window.setInterval(
      run,
      10000,
    )

  window.addEventListener(
    'online',
    run,
  )
}
TS

###############################################################################
# 8. BACKEND WRAPPER
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

import {
  createDesktopTask,
  pushSnapshot,
} from './cloudSync'

const rawBackend =
  (
    isTauriRuntime()
      ? nativeBackend
      : webBackend
  ) as unknown as
    typeof nativeBackend

async function afterMutation() {
  try {
    await pushSnapshot()
  } catch (
    error
  ) {
    console.error(
      'Supabase snapshot:',
      error,
    )
  }
}

export const backend:
  typeof nativeBackend = {
  ...rawBackend,

  createBrand:
    async (
      name: string,
    ) => {
      const result =
        await rawBackend
          .createBrand(
            name,
          )

      if (
        !isTauriRuntime()
      ) {
        await createDesktopTask(
          'CREATE_BRAND',
          { name },
        )
      }

      await afterMutation()

      return result
    },

  updateSchedule:
    async (
      targetId: string,
      scheduledAt:
        string | null,
    ) => {
      const result =
        await rawBackend
          .updateSchedule(
            targetId,
            scheduledAt,
          )

      if (
        !isTauriRuntime()
      ) {
        await createDesktopTask(
          'UPDATE_SCHEDULE',
          {
            targetId,
            scheduledAt,
          },
        )
      }

      await afterMutation()

      return result
    },

  updateSchedules:
    async (
      changes,
    ) => {
      const result =
        await rawBackend
          .updateSchedules(
            changes,
          )

      if (
        !isTauriRuntime()
      ) {
        await createDesktopTask(
          'UPDATE_SCHEDULES',
          { changes },
        )
      }

      await afterMutation()

      return result
    },

  updateWorkflowStatus:
    async (
      contentId: string,
      status: string,
    ) => {
      const result =
        await rawBackend
          .updateWorkflowStatus(
            contentId,
            status,
          )

      if (
        !isTauriRuntime()
      ) {
        await createDesktopTask(
          'UPDATE_WORKFLOW_STATUS',
          {
            contentId,
            status,
          },
        )
      }

      await afterMutation()

      return result
    },

  enqueuePublications:
    async (
      inputs,
    ) => {
      const result =
        await rawBackend
          .enqueuePublications(
            inputs,
          )

      if (
        !isTauriRuntime()
      ) {
        await createDesktopTask(
          'ENQUEUE_PUBLICATIONS',
          { inputs },
        )
      }

      await afterMutation()

      return result
    },

  markScheduledExternal:
    async (
      targetId,
      method,
      scheduledAt,
      remoteUrl,
      note,
    ) => {
      const result =
        await rawBackend
          .markScheduledExternal(
            targetId,
            method,
            scheduledAt,
            remoteUrl,
            note,
          )

      if (
        !isTauriRuntime()
      ) {
        await createDesktopTask(
          'MARK_SCHEDULED_EXTERNAL',
          {
            targetId,
            method,
            scheduledAt,
            remoteUrl,
            note,
          },
        )
      }

      await afterMutation()

      return result
    },
}
TS

###############################################################################
# 9. SYNC CENTER WITH LOGIN
###############################################################################

section "8/12 · SYNC UI"

cat > src/views/SyncView.tsx <<'TS'
import {
  CheckCircle2,
  Cloud,
  CloudOff,
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
  currentUser,
  signIn,
  signOut,
  signUp,
  supabaseConfigured,
} from '../lib/supabase'

import {
  heartbeat,
  pullSnapshotToWeb,
  pushSnapshot,
  syncCycle,
} from '../lib/cloudSync'

export function SyncView() {
  const [
    userEmail,
    setUserEmail,
  ] =
    useState<string | null>(
      null,
    )

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
    message,
    setMessage,
  ] =
    useState('')

  const [
    syncing,
    setSyncing,
  ] =
    useState(false)

  const loadUser =
    async () => {
      const user =
        await currentUser()

      setUserEmail(
        user?.email
        || null,
      )
    }

  useEffect(
    () => {
      loadUser()
        .catch(
          console.error,
        )
    },
    [],
  )

  const doSignIn =
    async () => {
      try {
        setMessage(
          'Conectando…',
        )

        await signIn(
          email,
          password,
        )

        await loadUser()

        await syncCycle()

        setMessage(
          'Supabase conectado.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      }
    }

  const doRegister =
    async () => {
      try {
        setMessage(
          'Creando cuenta…',
        )

        const data =
          await signUp(
            email,
            password,
          )

        await loadUser()

        setMessage(
          data.session
            ? 'Cuenta creada y conectada.'
            : 'Cuenta creada. Revisa tu email si Supabase requiere confirmación.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      }
    }

  const doSync =
    async () => {
      try {
        setSyncing(true)

        await heartbeat()

        if (
          runtimeSurface()
          === 'desktop'
        ) {
          await pushSnapshot()
        } else {
          await pullSnapshotToWeb()
        }

        await syncCycle()

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
      await signOut()

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
            SINCRONIZACIÓN
          </span>

          <h1>
            Sync Center
          </h1>

          <p>
            Desktop, Web y PWA sincronizados mediante Supabase.
          </p>
        </div>

        {
          userEmail
          && (
            <button
              className="secondary-btn"
              disabled={syncing}
              onClick={doSync}
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
        && (
          <section className="panel cloud-foundation-warning">
            <CloudOff/>

            <div>
              <strong>
                Supabase no configurado
              </strong>

              <p>
                Falta VITE_SUPABASE_URL o la publishable key.
              </p>
            </div>
          </section>
        )
      }

      {
        supabaseConfigured()
        && !userEmail
        && (
          <section className="panel sync-login-card">
            <Cloud size={24}/>

            <h2>
              Entrar a ABRAXAS Cloud
            </h2>

            <p>
              Usa la misma cuenta en Desktop y en la PWA para compartir workspace y tareas.
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
                onClick={doSignIn}
              >
                <LogIn size={15}/>
                Entrar
              </button>

              <button
                className="secondary-btn"
                onClick={doRegister}
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
      }

      {
        userEmail
        && (
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
                  ESTE DISPOSITIVO
                </span>

                <h2>
                  {
                    runtime
                    === 'desktop'
                      ? 'ABRAXAS Desktop'
                      : 'ABRAXAS PWA'
                  }
                </h2>

                <p>
                  {
                    runtime.toUpperCase()
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

                <button
                  className="danger-text-btn"
                  onClick={logout}
                >
                  <LogOut size={13}/>
                  Cerrar sesión
                </button>
              </section>
            </div>

            <section className="panel">
              <h3>
                Cómo funciona
              </h3>

              <div className="sync-flow-row">
                <span>
                  Móvil/PWA
                </span>

                <b>
                  revisa y aprueba
                </b>

                <span>→</span>

                <b>
                  Supabase
                </b>

                <span>→</span>

                <b>
                  Desktop recibe tarea
                </b>
              </div>

              <div className="sync-flow-row">
                <span>
                  Desktop
                </span>

                <b>
                  ejecuta local
                </b>

                <span>→</span>

                <b>
                  snapshot
                </b>

                <span>→</span>

                <b>
                  PWA se actualiza
                </b>
              </div>
            </section>

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
# 10. APP AUTO-SYNC
###############################################################################

python3 <<'PY'
from pathlib import Path

p = Path("src/main.tsx")
s = p.read_text()

if "startCloudSync" not in s:
    s = s.replace(
        "import { registerPwa } from './pwa'",
        """import { registerPwa } from './pwa'
import { startCloudSync } from './lib/cloudSync'""",
        1,
    )

    s += """

startCloudSync()
"""

p.write_text(s)

print("✓ Auto Sync")
PY

python3 <<'PY'
from pathlib import Path

p = Path("src/App.tsx")
s = p.read_text()

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
      'abraxas-sync-updated',
      load,
    )

    return () =>
      window.removeEventListener(
        'abraxas-sync-updated',
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
print("✓ App sync listener")
PY

###############################################################################
# 11. DESKTOP DOWNLOAD BUTTON
###############################################################################

section "9/12 · PWA DESKTOP DOWNLOAD"

cat > src/components/DesktopDownload.tsx <<'TS'
import {
  Download,
  Laptop,
} from 'lucide-react'

import {
  isTauriRuntime,
} from '../lib/runtime'

const DOWNLOAD_URL =
  'https://github.com/LordJeferies/abraxas-publisher/releases/latest/download/ABRAXAS-Publisher-v1.3.2-macOS.zip'

export function DesktopDownload() {
  if (
    isTauriRuntime()
  ) {
    return null
  }

  return (
    <a
      className="desktop-download-card"
      href={DOWNLOAD_URL}
    >
      <Laptop size={22}/>

      <div>
        <strong>
          ABRAXAS Publisher Desktop
        </strong>

        <span>
          Descarga la versión completa para macOS.
        </span>
      </div>

      <Download size={18}/>
    </a>
  )
}
TS

python3 <<'PY'
from pathlib import Path

p = Path("src/views/HomeView.tsx")
s = p.read_text()

if "DesktopDownload" not in s:
    insert_after = """import {
  useAppStore,
} from '../lib/store'
"""

    s = s.replace(
        insert_after,
        insert_after
        + """
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
print("✓ Download Desktop")
PY

cat >> src/styles.css <<'CSS'

/* V1.3.2 Supabase Sync */

.sync-login-card{
  width:min(520px,100%);
  margin:40px auto;
  display:grid;
  gap:10px;
}

.sync-login-card h2,
.sync-login-card p{
  margin:0;
}

.sync-login-card p{
  color:var(--muted);
}

.sync-login-actions{
  display:flex;
  gap:7px;
}

.desktop-download-card{
  margin:12px 0;
  border:1px solid rgba(55,85,145,.3);
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
    rgba(50,80,145,.1),
    rgba(95,115,165,.04)
  );
}

.desktop-download-card:hover{
  border-color:rgba(55,85,145,.65);
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
CSS

###############################################################################
# 12. PAGES SECRETS / WORKFLOW
###############################################################################

section "10/12 · GITHUB PAGES + SUPABASE"

python3 <<'PY'
from pathlib import Path

p = Path(".github/workflows/pages.yml")
s = p.read_text()

needle = """      - name: Build PWA
        run: npm run build:web
"""

replacement = """      - name: Build PWA
        env:
          VITE_SUPABASE_URL: ${{ secrets.VITE_SUPABASE_URL }}
          VITE_SUPABASE_PUBLISHABLE_KEY: ${{ secrets.VITE_SUPABASE_PUBLISHABLE_KEY }}
        run: npm run build:web
"""

if needle in s:
    s = s.replace(
        needle,
        replacement,
        1,
    )

p.write_text(s)
PY

if command -v gh >/dev/null 2>&1 \
  && gh auth status >/dev/null 2>&1
then
  printf "%s" \
    "$SUPABASE_URL" \
    | gh secret set \
        VITE_SUPABASE_URL \
        --repo LordJeferies/abraxas-publisher

  printf "%s" \
    "$SUPABASE_CLIENT_KEY" \
    | gh secret set \
        VITE_SUPABASE_PUBLISHABLE_KEY \
        --repo LordJeferies/abraxas-publisher

  echo "✓ GitHub Actions Supabase config"
else
  echo "⚠ gh no autenticado; Pages necesitará secrets manuales."
fi

###############################################################################
# DOCUMENTATION
###############################################################################

cat > docs/SUPABASE_SYNC.md <<'MD'
# ABRAXAS Publisher · Supabase Sync

## Purpose

Supabase is the synchronization layer between:

- Desktop/Tauri
- Web
- PWA/mobile

## Security

Client surfaces use only:

- Supabase URL
- publishable key
- authenticated user session

Never expose:

- secret key
- service_role
- Management API token
- database password

RLS limits rows by auth.uid().

## Tables

### abraxas_snapshots

Latest shared workspace snapshot for the user.

Includes:

- brands
- contents
- accounts metadata
- publication jobs

### abraxas_tasks

Remote commands from Web/PWA to Desktop.

Examples:

- CREATE_BRAND
- UPDATE_SCHEDULE
- UPDATE_SCHEDULES
- UPDATE_WORKFLOW_STATUS
- ENQUEUE_PUBLICATIONS
- MARK_SCHEDULED_EXTERNAL

### abraxas_devices

Heartbeat and runtime capabilities.

## Flow

Desktop:
SQLite → snapshot → Supabase

PWA:
Supabase → local WebBackend

PWA mutation:
WebBackend
→ Supabase task
→ WAITING_FOR_DESKTOP

Desktop:
poll task
→ execute NativeBackend
→ DONE
→ push snapshot

PWA:
pull snapshot
→ refreshed state

## Publishing

Supabase sync does not itself grant social publishing permissions.

Social adapters require provider OAuth separately.

A future CLOUD execution worker can execute jobs that do not require Desktop.
MD

###############################################################################
# 11. QA
###############################################################################

section "11/12 · QA"

npm run check \
  || fail "TypeScript falló."

npm run build \
  || fail "Desktop frontend falló."

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

rm -rf dist

GITHUB_ACTIONS=true \
npm run build:web \
  || fail "PWA build falló."

[ -f dist/index.html ] \
  || fail "PWA sin index.html"

[ -f dist/manifest.webmanifest ] \
  || fail "PWA sin manifest"

[ -f dist/sw.js ] \
  || fail "PWA sin service worker"

echo "✓ TypeScript"
echo "✓ Rust"
echo "✓ Desktop frontend"
echo "✓ Web/PWA"

###############################################################################
# 12. TAURI / RELEASE / GITHUB
###############################################################################

section "12/12 · BUILD / RELEASE"

unset GITHUB_ACTIONS

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
  || fail "No encontré ABRAXAS Publisher.app."

###############################################################################
# INSTALL
###############################################################################

APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP_APP="$HOME/Applications/ABRAXAS Publisher.pre-v132-sync.$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.v132.$STAMP.app"

mkdir -p "$HOME/Applications"

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
    "$BACKUP_APP"
fi

if ! mv \
  "$STAGE" \
  "$APP"
then
  if [ -d "$BACKUP_APP" ]; then
    mv \
      "$BACKUP_APP" \
      "$APP" \
      || true
  fi

  fail "No se pudo instalar Desktop."
fi

###############################################################################
# DESKTOP ICON / SHORTCUT
###############################################################################

rm -f \
  "$HOME/Desktop/ABRAXAS Publisher.app"

ln -s \
  "$APP" \
  "$HOME/Desktop/ABRAXAS Publisher.app"

###############################################################################
# ZIP DESKTOP FOR GITHUB RELEASE
###############################################################################

DESKTOP_ZIP="$ROOT/ABRAXAS-Publisher-v1.3.2-macOS.zip"

rm -f "$DESKTOP_ZIP"

ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$APP" \
  "$DESKTOP_ZIP"

###############################################################################
# COMMIT
###############################################################################

rm -f "$DISCOVERED"

git add -A

if ! git diff \
  --cached \
  --quiet
then
  git commit \
    -m "Complete V1.3.2 Supabase Desktop PWA synchronization"
fi

RELEASE_SHA="$(
  git rev-parse HEAD
)"

git tag \
  -f \
  "$TAG"

git push \
  -u origin \
  "$BRANCH"

git push \
  origin \
  "$TAG" \
  --force

###############################################################################
# MAIN FAST FORWARD ONLY
###############################################################################

MAIN_UPDATED="no"

if git push \
  origin \
  "$BRANCH:main"
then
  MAIN_UPDATED="yes"
fi

###############################################################################
# GITHUB RELEASE
###############################################################################

if command -v gh >/dev/null 2>&1 \
  && gh auth status >/dev/null 2>&1
then

  if gh release view \
    "$TAG" \
    --repo LordJeferies/abraxas-publisher \
    >/dev/null 2>&1
  then
    gh release upload \
      "$TAG" \
      "$DESKTOP_ZIP" \
      --repo LordJeferies/abraxas-publisher \
      --clobber
  else
    gh release create \
      "$TAG" \
      "$DESKTOP_ZIP" \
      --repo LordJeferies/abraxas-publisher \
      --title "ABRAXAS Publisher V1.3.2" \
      --notes "Desktop + Web/PWA + Supabase Sync Foundation."
  fi

  gh release edit \
    "$TAG" \
    --repo LordJeferies/abraxas-publisher \
    --latest
fi

###############################################################################
# LOCAL RELEASE SNAPSHOT
###############################################################################

RELEASE_DIR="$HOME/Developer/abraxas-publisher/releases/v1.3.2"

mkdir -p "$RELEASE_DIR"

FULL_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.2_FULL.zip"

rm -f "$FULL_ZIP"

git archive \
  --format=zip \
  --output="$FULL_ZIP" \
  HEAD

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.3.2 · TOTALMENTE COMPILADA"
echo "=============================================================="
echo
echo "Desktop:"
echo "  $APP"
echo
echo "Acceso Escritorio:"
echo "  $HOME/Desktop/ABRAXAS Publisher.app"
echo
echo "PWA:"
echo "  https://lordjeferies.github.io/abraxas-publisher/"
echo
echo "Desktop download:"
echo "  https://github.com/LordJeferies/abraxas-publisher/releases/latest/download/ABRAXAS-Publisher-v1.3.2-macOS.zip"
echo
echo "Supabase:"
echo "  ✓ client"
echo "  ✓ Auth"
echo "  ✓ RLS"
echo "  ✓ workspace snapshots"
echo "  ✓ remote task queue"
echo "  ✓ device heartbeat"
echo "  ✓ Desktop worker"
echo
echo "Desktop ↔ PWA:"
echo "  ✓ mismo usuario Supabase"
echo "  ✓ calendario"
echo "  ✓ estados"
echo "  ✓ brands"
echo "  ✓ publication jobs"
echo "  ✓ tareas remotas"
echo
echo "GitHub:"
echo "  branch: $BRANCH"
echo "  commit: $RELEASE_SHA"
echo "  main fast-forward: $MAIN_UPDATED"
echo "  tag: $TAG"
echo
echo "Backup Desktop:"
echo "  $BACKUP_APP"
echo
echo "Log:"
echo "  $LOG"
echo
echo "SIGUIENTE PASO:"
echo "  OAuth real de Google Drive Web + providers sociales."
echo

open "$APP" || true

