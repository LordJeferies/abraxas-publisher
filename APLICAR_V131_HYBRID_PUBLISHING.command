#!/bin/bash
set -Eeuo pipefail

###############################################################################
# ABRAXAS Publisher V1.3.1
# Hybrid Publishing
#
# AUTO_API + MANUAL + EXTERNAL
###############################################################################

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

BRANCH="v1.3-publishing-center"
STAMP="$(date +%Y%m%d_%H%M%S)"

LOG_DIR="$ROOT/logs"
LOG="$LOG_DIR/v131_hybrid_$STAMP.log"

mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS PUBLISHER V1.3.1 · FALLO"
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

section "1/11 · PRECHECK"

git switch "$BRANCH"

echo "Branch:"
git branch --show-current

echo
echo "HEAD:"
git log -1 --oneline

if [ -n "$(git status --porcelain)" ]; then
  echo
  echo "Guardando cambios locales antes del parche..."

  git add -A

  git commit \
    -m "Snapshot before V1.3.1 Hybrid Publishing $STAMP" \
    || true
fi

BASE_SHA="$(git rev-parse HEAD)"

echo
echo "Base:"
echo "$BASE_SHA"

###############################################################################
# 2. BACKUP
###############################################################################

section "2/11 · BACKUP"

BACKUP="$ROOT/.v131-backup/$STAMP"

mkdir -p "$BACKUP/src-tauri/src"
mkdir -p "$BACKUP/src/views"

for FILE in \
  src-tauri/src/publishing.rs \
  src/types.ts \
  src/views/PublishView.tsx \
  src/views/QueueView.tsx \
  src/views/TodayView.tsx \
  src/views/AccountsView.tsx \
  src/styles.css \
  package.json \
  src-tauri/Cargo.toml \
  src-tauri/tauri.conf.json
do
  if [ -f "$FILE" ]; then
    mkdir -p "$BACKUP/$(dirname "$FILE")"
    cp "$FILE" "$BACKUP/$FILE"
  fi
done

echo "✓ $BACKUP"

###############################################################################
# 3. VERSION 0.4.1
###############################################################################

section "3/11 · VERSION"

python3 <<'PY'
from pathlib import Path
import json
import re

p = Path("package.json")
data = json.loads(p.read_text())
data["version"] = "0.4.1"
p.write_text(json.dumps(data, indent=2) + "\n")

p = Path("src-tauri/Cargo.toml")
s = p.read_text()
s = re.sub(
    r'(?m)^version\s*=\s*"[^"]+"',
    'version = "0.4.1"',
    s,
    count=1,
)
p.write_text(s)

p = Path("src-tauri/tauri.conf.json")
data = json.loads(p.read_text())
data["version"] = "0.4.1"
p.write_text(json.dumps(data, indent=2) + "\n")

print("✓ 0.4.1")
PY

###############################################################################
# 4. RUST · HYBRID PREFLIGHT + QUEUE
###############################################################################

section "4/11 · HYBRID PUBLISHING CORE"

python3 <<'PY'
from pathlib import Path

p = Path("src-tauri/src/publishing.rs")
src = p.read_text()


def replace_function(text, name, replacement):
    needle = f"pub fn {name}("
    start = text.find(needle)

    if start < 0:
        raise SystemExit(
            f"ERROR: no encontré {name}()"
        )

    brace = text.find("{", start)

    if brace < 0:
        raise SystemExit(
            f"ERROR: no encontré apertura de {name}()"
        )

    depth = 0
    i = brace
    in_string = False
    raw_string = False
    escape = False

    while i < len(text):
        # raw Rust string r#" ... "#
        if not in_string and text.startswith('r#"', i):
            raw_string = True
            in_string = True
            i += 3
            continue

        if raw_string:
            if text.startswith('"#', i):
                in_string = False
                raw_string = False
                i += 2
                continue

            i += 1
            continue

        ch = text[i]

        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False

            i += 1
            continue

        if ch == '"':
            in_string = True

        elif ch == "{":
            depth += 1

        elif ch == "}":
            depth -= 1

            if depth == 0:
                end = i + 1

                return (
                    text[:start]
                    + replacement.strip()
                    + "\n\n"
                    + text[end:].lstrip()
                )

        i += 1

    raise SystemExit(
        f"ERROR: cierre no encontrado para {name}()"
    )


# ---------------------------------------------------------------------------
# PreflightReport
# ---------------------------------------------------------------------------

old_start = src.find(
    "pub struct PreflightReport {"
)

if old_start < 0:
    raise SystemExit(
        "ERROR: no encontré PreflightReport"
    )

brace = src.find("{", old_start)
depth = 0
i = brace

while i < len(src):
    if src[i] == "{":
        depth += 1
    elif src[i] == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
    i += 1
else:
    raise SystemExit(
        "ERROR cerrando PreflightReport"
    )

new_struct = r'''
pub struct PreflightReport {
    pub target_id: String,
    pub account_id: Option<String>,
    pub provider: String,

    // true = el target puede continuar.
    // Un target MANUAL también puede estar ready.
    pub ready: bool,

    // AUTO_API | MANUAL
    pub execution_mode: String,

    // true si Publisher debe recordar al usuario
    // que la publicación necesita intervención humana.
    pub needs_manual_action: bool,

    pub checks: Vec<PreflightCheck>,
}
'''

src = (
    src[:old_start]
    + new_struct.strip()
    + src[end:]
)


# ---------------------------------------------------------------------------
# PRE-FLIGHT
# ---------------------------------------------------------------------------

preflight = r'''
pub fn preflight(
    db: &Path,
    target_id: &str,
    account_id: Option<&str>,
) -> Result<PreflightReport, String> {
    let conn = open(db)?;

    let target: Option<(
        String,
        String,
        String,
        Option<String>,
        String,
    )> = conn
        .query_row(
            r#"
            SELECT
              p.content_id,
              p.platform,
              p.status,
              p.scheduled_at,
              c.workflow_status
            FROM publication_targets p
            JOIN contents c
              ON c.id=p.content_id
            WHERE p.id=?1
            "#,
            params![target_id],
            |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                ))
            },
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let Some((
        content_id,
        provider,
        target_status,
        scheduled_at,
        editorial_status,
    )) = target
    else {
        return Err(
            "Destino no encontrado."
                .into(),
        );
    };

    let media_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM media_assets WHERE content_id=?1",
            params![content_id],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    let blocking_issue_count: i64 = conn
        .query_row(
            r#"
            SELECT COUNT(*)
            FROM validation_issues
            WHERE content_id=?1
              AND LOWER(severity)='error'
            "#,
            params![content_id],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    let account = if let Some(id) = account_id {
        conn.query_row(
            r#"
            SELECT
              provider,
              connection_status,
              auth_state
            FROM connected_accounts
            WHERE id=?1
            "#,
            params![id],
            |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| e.to_string())?
    } else {
        None
    };

    let auto_api = match &account {
        Some((
            account_provider,
            connection_status,
            auth_state,
        )) => {
            account_provider == &provider
                && connection_status == "CONNECTED"
                && auth_state == "AUTHORIZED"
        }

        None => false,
    };

    let execution_mode =
        if auto_api {
            "AUTO_API"
        } else {
            "MANUAL"
        };

    let mut checks = Vec::new();

    let editorial_ok =
        editorial_status == "LISTO_POR_PROGRAMAR"
        || editorial_status == "PROGRAMADO";

    checks.push(PreflightCheck {
        key: "editorial".into(),
        label:
            "Contenido aprobado editorialmente"
                .into(),
        ok: editorial_ok,
        blocking: true,
        detail:
            Some(editorial_status.clone()),
    });

    checks.push(PreflightCheck {
        key: "media".into(),
        label:
            "Medio disponible"
                .into(),
        ok: media_count > 0,
        blocking: true,
        detail:
            Some(
                format!(
                    "{media_count} asset(s)"
                ),
            ),
    });

    checks.push(PreflightCheck {
        key: "validation".into(),
        label:
            "Sin errores técnicos bloqueantes"
                .into(),
        ok:
            blocking_issue_count == 0,
        blocking: true,
        detail:
            Some(
                if blocking_issue_count == 0 {
                    "Sin errores".into()
                } else {
                    format!(
                        "{blocking_issue_count} error(es)"
                    )
                },
            ),
    });

    checks.push(PreflightCheck {
        key: "schedule".into(),
        label:
            "Fecha/hora definida"
                .into(),
        ok:
            scheduled_at.is_some(),
        blocking: true,
        detail:
            scheduled_at.clone(),
    });

    let editable =
        target_status
            != "SCHEDULED_REMOTE"
        && target_status
            != "SCHEDULED_EXTERNAL"
        && target_status
            != "PUBLISHED"
        && target_status
            != "PUBLISHED_EXTERNAL";

    checks.push(PreflightCheck {
        key: "remote-lock".into(),
        label:
            "Destino disponible"
                .into(),
        ok: editable,
        blocking: true,
        detail:
            Some(
                target_status.clone(),
            ),
    });

    /*
     * IMPORTANTE:
     *
     * Cuenta API no conectada NO es un error.
     *
     * Convierte el target a MANUAL.
     */
    let account_detail =
        match account {
            Some((
                account_provider,
                connection_status,
                auth_state,
            )) => {
                Some(
                    format!(
                        "{} · {} · {}",
                        account_provider,
                        connection_status,
                        auth_state
                    ),
                )
            }

            None => {
                Some(
                    "Sin API conectada · publicación manual"
                        .into(),
                )
            }
        };

    checks.push(PreflightCheck {
        key: "account".into(),

        label:
            if auto_api {
                "API lista para publicación automática"
                    .into()
            } else {
                "Publicación manual necesaria"
                    .into()
            },

        // true significa:
        // el workflow tiene solución válida.
        ok: true,

        // jamás bloquea sólo por faltar API.
        blocking: false,

        detail:
            account_detail,
    });

    let ready =
        checks.iter()
            .filter(
                |check|
                    check.blocking,
            )
            .all(
                |check|
                    check.ok,
            );

    Ok(PreflightReport {
        target_id:
            target_id.into(),

        account_id:
            account_id.map(
                |x| x.into(),
            ),

        provider,

        ready,

        execution_mode:
            execution_mode.into(),

        needs_manual_action:
            !auto_api,

        checks,
    })
}
'''

src = replace_function(
    src,
    "preflight",
    preflight,
)


# ---------------------------------------------------------------------------
# ENQUEUE
# ---------------------------------------------------------------------------

enqueue = r'''
pub fn enqueue(
    db: &Path,
    inputs: &[EnqueueInput],
) -> Result<Vec<PublishJob>, String> {
    let conn = open(db)?;

    let now =
        Utc::now()
            .to_rfc3339();

    for input in inputs {
        let target: Option<(
            String,
            String,
            Option<String>,
            Option<String>,
        )> = conn
            .query_row(
                r#"
                SELECT
                  p.content_id,
                  p.platform,
                  p.scheduled_at,
                  c.source_fingerprint
                FROM publication_targets p
                JOIN contents c
                  ON c.id=p.content_id
                WHERE p.id=?1
                "#,
                params![
                    input.target_id
                ],
                |r| {
                    Ok((
                        r.get(0)?,
                        r.get(1)?,
                        r.get(2)?,
                        r.get(3)?,
                    ))
                },
            )
            .optional()
            .map_err(
                |e| e.to_string(),
            )?;

        let Some((
            content_id,
            provider,
            scheduled_for,
            fingerprint,
        )) = target
        else {
            continue;
        };

        let mode =
            match input.mode.as_str() {
                "AUTO_API" =>
                    "AUTO_API",

                "MANUAL" =>
                    "MANUAL",

                "EXTERNAL" =>
                    "EXTERNAL",

                _ =>
                    "MANUAL",
            };

        let initial_status =
            match mode {
                "AUTO_API" =>
                    "QUEUED",

                "MANUAL" =>
                    "MANUAL_REQUIRED",

                "EXTERNAL" =>
                    "SCHEDULED_EXTERNAL",

                _ =>
                    "MANUAL_REQUIRED",
            };

        let identity =
            format!(
                "{}:{}:{}:{}:{}",
                input.target_id,
                input.account_id
                    .clone()
                    .unwrap_or_default(),
                scheduled_for
                    .clone()
                    .unwrap_or_default(),
                fingerprint
                    .unwrap_or_default(),
                mode,
            );

        let idempotency_key =
            hash_id(
                &identity,
            );

        let id =
            format!(
                "job-{}",
                idempotency_key
            );

        conn.execute(
            r#"
            INSERT INTO publication_jobs(
              id,
              target_id,
              content_id,
              provider,
              account_id,
              mode,
              scheduled_for,
              status,
              idempotency_key,
              attempt,
              max_attempts,
              created_at,
              updated_at
            )
            VALUES(
              ?1,?2,?3,?4,?5,?6,
              ?7,?8,?9,
              0,4,?10,?11
            )
            ON CONFLICT(idempotency_key)
            DO UPDATE SET
              account_id=excluded.account_id,
              mode=excluded.mode,
              scheduled_for=excluded.scheduled_for,
              status=CASE
                WHEN publication_jobs.status IN (
                  'PUBLISHED',
                  'PUBLISHED_EXTERNAL',
                  'SCHEDULED_REMOTE',
                  'SCHEDULED_EXTERNAL'
                )
                THEN publication_jobs.status
                ELSE excluded.status
              END,
              updated_at=excluded.updated_at
            "#,
            params![
                id,
                input.target_id,
                content_id,
                provider,
                input.account_id,
                mode,
                scheduled_for,
                initial_status,
                idempotency_key,
                now,
                now,
            ],
        )
        .map_err(
            |e| e.to_string(),
        )?;
    }

    list_jobs(db)
}
'''

src = replace_function(
    src,
    "enqueue",
    enqueue,
)

p.write_text(src)

print("✓ publishing.rs")
PY

###############################################################################
# 5. TYPESCRIPT CONTRACT
###############################################################################

section "5/11 · TYPES"

python3 <<'PY'
from pathlib import Path
import re

p = Path("src/types.ts")
s = p.read_text()

pattern = re.compile(
    r'''export interface PreflightReport \{
.*?
\}''',
    re.S,
)

replacement = '''export interface PreflightReport {
  targetId: string
  accountId?: string | null
  provider: string

  // AUTO_API | MANUAL
  executionMode: string

  needsManualAction: boolean

  // true también puede significar
  // "listo para publicación manual".
  ready: boolean

  checks: PreflightCheck[]
}'''

s, count = pattern.subn(
    replacement,
    s,
    count=1,
)

if count != 1:
    raise SystemExit(
        "ERROR: PreflightReport no reemplazado."
    )

p.write_text(s)

print("✓ types.ts")
PY

###############################################################################
# 6. PUBLISH WIZARD HYBRID
###############################################################################

section "6/11 · PUBLISHING WIZARD"

cat > src/views/PublishView.tsx <<'TS'
import {
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Cloud,
  ExternalLink,
  Hand,
  Send,
} from 'lucide-react'

import {
  useEffect,
  useMemo,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import {
  PlatformPreview,
} from '../components/PlatformPreview'

import type {
  ConnectedAccount,
  PreflightReport,
  PublicationTarget,
} from '../types'

export function PublishView() {
  const {
    contents,
    selectedBrand,
    setContents,
    setView,
  } = useAppStore()

  const [
    accounts,
    setAccounts,
  ] =
    useState<
      ConnectedAccount[]
    >([])

  const [
    step,
    setStep,
  ] =
    useState(1)

  const [
    selectedTargets,
    setSelectedTargets,
  ] =
    useState<string[]>([])

  const [
    accountFor,
    setAccountFor,
  ] =
    useState<
      Record<string,string>
    >({})

  const [
    forceMode,
    setForceMode,
  ] =
    useState<
      Record<
        string,
        'AUTO'
        | 'MANUAL'
      >
    >({})

  const [
    preflight,
    setPreflight,
  ] =
    useState<
      Record<
        string,
        PreflightReport
      >
    >({})

  const [
    previewId,
    setPreviewId,
  ] =
    useState<string | null>(
      null,
    )

  const [
    externalMethod,
    setExternalMethod,
  ] =
    useState('Edits')

  const [
    message,
    setMessage,
  ] =
    useState('')

  useEffect(
    () => {
      backend
        .listConnectedAccounts()
        .then(setAccounts)
        .catch(console.error)
    },
    [],
  )

  const candidates =
    useMemo(
      () =>
        contents
          .filter(
            (content) =>
              (
                selectedBrand
                === 'ALL'
                || content.client
                === selectedBrand
              )
              && (
                content.status
                === 'LISTO_POR_PROGRAMAR'
                || content.status
                === 'PROGRAMADO'
              ),
          )
          .flatMap(
            (content) =>
              content.targets.map(
                (target) => ({
                  content,
                  target,
                }),
              ),
          ),
      [
        contents,
        selectedBrand,
      ],
    )

  const selected =
    candidates.filter(
      ({ target }) =>
        selectedTargets
          .includes(
            target.id,
          ),
    )

  const toggle =
    (
      id: string,
    ) => {
      setSelectedTargets(
        (previous) =>
          previous.includes(id)
            ? previous.filter(
                (x) => x !== id,
              )
            : [
                ...previous,
                id,
              ],
      )
    }

  const compatibleAccounts =
    (
      target:
        PublicationTarget,
      brand?:
        string | null,
    ) =>
      accounts.filter(
        (account) =>
          account.provider
            === target.platform
          && (
            !account.brand
            || !brand
            || account.brand
              === brand
          ),
      )

  const accountIsAutomatic =
    (
      target:
        PublicationTarget,
    ) => {
      const accountId =
        accountFor[
          target.id
        ]

      const account =
        accounts.find(
          (item) =>
            item.id
            === accountId,
        )

      return Boolean(
        account
        && account.provider
          === target.platform
        && account.connectionStatus
          === 'CONNECTED'
        && account.authState
          === 'AUTHORIZED',
      )
    }

  const intendedMode =
    (
      target:
        PublicationTarget,
    ) => {
      if (
        forceMode[
          target.id
        ] === 'MANUAL'
      ) {
        return 'MANUAL'
      }

      return accountIsAutomatic(
        target,
      )
        ? 'AUTO_API'
        : 'MANUAL'
    }

  const runPreflight =
    async () => {
      const next:
        Record<
          string,
          PreflightReport
        > = {}

      for (
        const {
          target,
        }
        of selected
      ) {
        /*
         * Si el usuario obliga Manual,
         * no pasamos la cuenta API.
         */
        const accountId =
          forceMode[
            target.id
          ] === 'MANUAL'
            ? null
            : (
                accountFor[
                  target.id
                ]
                || null
              )

        const report =
          await backend
            .publishingPreflight(
              target.id,
              accountId,
            )

        if (
          forceMode[
            target.id
          ] === 'MANUAL'
        ) {
          report.executionMode =
            'MANUAL'

          report.needsManualAction =
            true
        }

        next[target.id] =
          report
      }

      setPreflight(next)
      setStep(3)
    }

  /*
   * Sólo bloqueamos por problemas reales.
   *
   * Una publicación MANUAL puede estar ready.
   */
  const allReady =
    selected.length > 0
    && selected.every(
      ({ target }) =>
        preflight[
          target.id
        ]?.ready,
    )

  const autoCount =
    selected.filter(
      ({ target }) =>
        (
          preflight[
            target.id
          ]?.executionMode
          || intendedMode(
            target,
          )
        ) === 'AUTO_API',
    ).length

  const manualCount =
    selected.length
    - autoCount

  const enqueue =
    async () => {
      if (!allReady) {
        setMessage(
          'Hay destinos bloqueados por problemas reales de contenido o calendario.',
        )

        return
      }

      await backend
        .enqueuePublications(
          selected.map(
            ({ target }) => ({
              targetId:
                target.id,

              accountId:
                (
                  preflight[
                    target.id
                  ]?.executionMode
                  === 'AUTO_API'
                )
                  ? (
                      accountFor[
                        target.id
                      ]
                      || null
                    )
                  : null,

              mode:
                preflight[
                  target.id
                ]?.executionMode
                || intendedMode(
                  target,
                ),
            }),
          ),
        )

      setMessage(
        `${autoCount} automática(s) · ${manualCount} manual(es) añadidas a la cola.`,
      )

      setStep(5)
    }

  const markExternal =
    async (
      targetId: string,
    ) => {
      const entry =
        candidates.find(
          ({ target }) =>
            target.id
            === targetId,
        )

      if (!entry) {
        return
      }

      await backend
        .markScheduledExternal(
          targetId,
          externalMethod,
          entry.target
            .scheduledAt
          || null,
          null,
          `Programado fuera de Publisher mediante ${externalMethod}.`,
        )

      setContents(
        await backend
          .listContents(),
      )

      setMessage(
        `SCHEDULED_EXTERNAL · ${externalMethod}`,
      )
    }

  const previewEntry =
    previewId
      ? candidates.find(
          ({ target }) =>
            target.id
            === previewId,
        )
      : selected[0]

  return (
    <div
      className={
        previewEntry
          ? `page scrollable publish-page theme-${previewEntry.target.platform}`
          : 'page scrollable publish-page'
      }
    >
      <header className="page-header publish-header">
        <div>
          <span className="eyebrow">
            ÁREA DE PUBLICACIÓN
          </span>

          <h1>
            Preparar publicación
          </h1>

          <p>
            Automático cuando hay API. Manual asistido cuando no la hay.
          </p>
        </div>

        <div className="publish-step-number">
          {step}/5
        </div>
      </header>

      <div className="hybrid-info-banner">
        <Cloud size={16}/>

        <div>
          <strong>
            Publicación híbrida
          </strong>

          <span>
            No necesitas tener todas las APIs conectadas. Publisher automatiza las disponibles y mantiene el resto como tareas manuales.
          </span>
        </div>
      </div>

      <div className="wizard-steps">
        {
          [
            'Contenido',
            'Cuentas',
            'Verificar',
            'Preview',
            'Confirmar',
          ].map(
            (
              label,
              index,
            ) => (
              <div
                className={
                  step === index + 1
                    ? 'wizard-step active'
                    : step > index + 1
                      ? 'wizard-step done'
                      : 'wizard-step'
                }
                key={label}
              >
                <span>
                  {index + 1}
                </span>

                {label}
              </div>
            ),
          )
        }
      </div>

      {
        step === 1
        && (
          <section className="publish-stage">
            <div className="stage-title">
              <div>
                <h2>
                  ¿Qué vas a publicar?
                </h2>

                <p>
                  Selecciona destinos individuales. Una misma pieza puede ser automática en una red y manual en otra.
                </p>
              </div>

              <button
                className="secondary-btn"
                onClick={() =>
                  setSelectedTargets(
                    candidates.map(
                      ({ target }) =>
                        target.id,
                    ),
                  )
                }
              >
                Seleccionar todos
              </button>
            </div>

            <div className="publish-selection-list">
              {
                candidates.map(
                  ({
                    content,
                    target,
                  }) => (
                    <label
                      className={
                        selectedTargets
                          .includes(
                            target.id,
                          )
                          ? 'publish-select-row selected'
                          : 'publish-select-row'
                      }
                      key={target.id}
                    >
                      <input
                        type="checkbox"
                        checked={
                          selectedTargets
                            .includes(
                              target.id,
                            )
                        }
                        onChange={() =>
                          toggle(
                            target.id,
                          )
                        }
                      />

                      <div>
                        <small>
                          {
                            content.client
                            || 'Sin marca'
                          }
                        </small>

                        <strong>
                          {
                            content.title
                          }
                        </strong>

                        <span>
                          {
                            target.platform
                          }
                          {' · '}
                          {
                            target.scheduledAt
                              ? new Date(
                                  target.scheduledAt,
                                ).toLocaleString()
                              : 'Sin calendarizar'
                          }
                        </span>
                      </div>

                      <b>
                        {
                          content.contentType
                        }
                      </b>
                    </label>
                  ),
                )
              }
            </div>
          </section>
        )
      }

      {
        step === 2
        && (
          <section className="publish-stage">
            <div className="stage-title">
              <div>
                <h2>
                  ¿Cómo sale cada publicación?
                </h2>

                <p>
                  La falta de API no bloquea el workflow.
                </p>
              </div>
            </div>

            <div className="destination-list">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => {
                    const compatible =
                      compatibleAccounts(
                        target,
                        content.client,
                      )

                    const automatic =
                      accountIsAutomatic(
                        target,
                      )
                      && forceMode[
                        target.id
                      ] !== 'MANUAL'

                    return (
                      <article
                        className={
                          `destination-card provider-${target.platform}`
                        }
                        key={target.id}
                      >
                        <div>
                          <small>
                            {
                              target.platform
                                .toUpperCase()
                            }
                          </small>

                          <strong>
                            {
                              content.title
                            }
                          </strong>

                          <span>
                            {
                              target.scheduledAt
                                ? new Date(
                                    target.scheduledAt,
                                  ).toLocaleString()
                                : 'Sin fecha'
                            }
                          </span>
                        </div>

                        <div className="destination-account-stack">
                          <select
                            className="field"
                            value={
                              accountFor[
                                target.id
                              ]
                              || ''
                            }
                            onChange={(e) =>
                              setAccountFor(
                                (previous) => ({
                                  ...previous,
                                  [
                                    target.id
                                  ]:
                                    e.target.value,
                                }),
                              )
                            }
                          >
                            <option value="">
                              Sin API · manual
                            </option>

                            {
                              compatible.map(
                                (account) => (
                                  <option
                                    value={
                                      account.id
                                    }
                                    key={
                                      account.id
                                    }
                                  >
                                    {
                                      account.displayName
                                    }
                                    {' · '}
                                    {
                                      account.connectionStatus
                                    }
                                  </option>
                                ),
                              )
                            }
                          </select>

                          <div
                            className={
                              automatic
                                ? 'execution-mode auto'
                                : 'execution-mode manual'
                            }
                          >
                            {
                              automatic
                                ? (
                                  <>
                                    <Cloud size={13}/>
                                    AUTO_API
                                  </>
                                )
                                : (
                                  <>
                                    <Hand size={13}/>
                                    MANUAL
                                  </>
                                )
                            }
                          </div>
                        </div>

                        <div className="destination-actions">
                          {
                            automatic
                            && (
                              <button
                                className="secondary-btn small"
                                onClick={() =>
                                  setForceMode(
                                    (previous) => ({
                                      ...previous,
                                      [
                                        target.id
                                      ]:
                                        'MANUAL',
                                    }),
                                  )
                                }
                              >
                                Hacer manual
                              </button>
                            )
                          }

                          {
                            !automatic
                            && accountIsAutomatic(
                              target,
                            )
                            && (
                              <button
                                className="secondary-btn small"
                                onClick={() =>
                                  setForceMode(
                                    (previous) => ({
                                      ...previous,
                                      [
                                        target.id
                                      ]:
                                        'AUTO',
                                    }),
                                  )
                                }
                              >
                                Usar API
                              </button>
                            )
                          }

                          <button
                            className="secondary-btn small"
                            onClick={() =>
                              markExternal(
                                target.id,
                              )
                            }
                          >
                            <ExternalLink size={14}/>
                            Ya programado fuera
                          </button>
                        </div>
                      </article>
                    )
                  },
                )
              }
            </div>

            <div className="external-method-row">
              <span>
                Scheduler externo:
              </span>

              <select
                className="field"
                value={
                  externalMethod
                }
                onChange={(e) =>
                  setExternalMethod(
                    e.target.value,
                  )
                }
              >
                <option>
                  Edits
                </option>

                <option>
                  Meta Business Suite
                </option>

                <option>
                  YouTube Studio
                </option>

                <option>
                  LinkedIn
                </option>

                <option>
                  TikTok
                </option>

                <option>
                  Buffer
                </option>

                <option>
                  Later
                </option>

                <option>
                  Otra herramienta
                </option>
              </select>
            </div>
          </section>
        )
      }

      {
        step === 3
        && (
          <section className="publish-stage">
            <div className="stage-title">
              <div>
                <h2>
                  Verificador
                </h2>

                <p>
                  Amarillo significa manual. Rojo sólo significa bloqueo real.
                </p>
              </div>
            </div>

            <div className="hybrid-counts">
              <div>
                <Cloud/>
                <strong>
                  {autoCount}
                </strong>
                <span>
                  Automáticas
                </span>
              </div>

              <div>
                <Hand/>
                <strong>
                  {manualCount}
                </strong>
                <span>
                  Manuales
                </span>
              </div>
            </div>

            <div className="preflight-grid">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => {
                    const report =
                      preflight[
                        target.id
                      ]

                    const manual =
                      report
                        ?.executionMode
                      === 'MANUAL'

                    return (
                      <article
                        className={
                          !report?.ready
                            ? 'preflight-card blocked'
                            : manual
                              ? 'preflight-card manual-ready'
                              : 'preflight-card ready'
                        }
                        key={target.id}
                      >
                        <header>
                          <div>
                            <small>
                              {
                                target.platform
                              }
                            </small>

                            <strong>
                              {
                                content.title
                              }
                            </strong>
                          </div>

                          {
                            !report?.ready
                              ? (
                                <CircleAlert/>
                              )
                              : manual
                                ? (
                                  <Hand/>
                                )
                                : (
                                  <CheckCircle2/>
                                )
                          }
                        </header>

                        <div
                          className={
                            manual
                              ? 'execution-callout manual'
                              : 'execution-callout auto'
                          }
                        >
                          {
                            manual
                              ? '✋ LISTO · PUBLICACIÓN MANUAL'
                              : '☁ LISTO · PUBLICACIÓN AUTOMÁTICA'
                          }
                        </div>

                        {
                          report?.checks
                            .map(
                              (check) => (
                                <div
                                  className={
                                    check.ok
                                      ? 'preflight-check ok'
                                      : (
                                          check.blocking
                                            ? 'preflight-check fail'
                                            : 'preflight-check warning'
                                        )
                                  }
                                  key={
                                    check.key
                                  }
                                >
                                  <span>
                                    {
                                      check.ok
                                        ? '✓'
                                        : (
                                            check.blocking
                                              ? '✕'
                                              : '!'
                                          )
                                    }
                                  </span>

                                  <div>
                                    <strong>
                                      {
                                        check.label
                                      }
                                    </strong>

                                    <small>
                                      {
                                        check.detail
                                      }
                                    </small>
                                  </div>
                                </div>
                              ),
                            )
                        }
                      </article>
                    )
                  },
                )
              }
            </div>
          </section>
        )
      }

      {
        step === 4
        && (
          <section className="publish-stage preview-stage">
            <aside className="preview-target-list">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => (
                    <button
                      className={
                        previewEntry
                          ?.target.id
                        === target.id
                          ? 'active'
                          : ''
                      }
                      key={target.id}
                      onClick={() =>
                        setPreviewId(
                          target.id,
                        )
                      }
                    >
                      <strong>
                        {
                          target.platform
                        }
                      </strong>

                      <span>
                        {
                          content.title
                        }
                      </span>

                      <small>
                        {
                          preflight[
                            target.id
                          ]?.executionMode
                          === 'AUTO_API'
                            ? '☁ Automático'
                            : '✋ Manual'
                        }
                      </small>
                    </button>
                  ),
                )
              }
            </aside>

            <div className="preview-workbench">
              {
                previewEntry
                && (
                  <>
                    <div className="preview-toolbar">
                      <div>
                        <span className="eyebrow">
                          PREVIEW
                        </span>

                        <h2>
                          {
                            previewEntry
                              .target
                              .platform
                          }
                        </h2>
                      </div>

                      <div className="preview-type-badge">
                        {
                          previewEntry
                            .content
                            .contentType
                        }
                      </div>
                    </div>

                    <PlatformPreview
                      item={
                        previewEntry
                          .content
                      }
                      target={
                        previewEntry
                          .target
                      }
                    />
                  </>
                )
              }
            </div>
          </section>
        )
      }

      {
        step === 5
        && (
          <section className="publish-stage confirmation-stage">
            <span className="eyebrow">
              CONFIRMAR LOTE
            </span>

            <h2>
              {
                selected.length
              } destinos
            </h2>

            <div className="hybrid-confirm-summary">
              <div className="auto">
                <Cloud size={22}/>

                <strong>
                  {autoCount}
                </strong>

                <span>
                  Publisher se encargará automáticamente
                </span>
              </div>

              <div className="manual">
                <Hand size={22}/>

                <strong>
                  {manualCount}
                </strong>

                <span>
                  Permanecerán en tu agenda para publicación manual
                </span>
              </div>
            </div>

            <div className="confirmation-summary">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => (
                    <div key={target.id}>
                      <span>
                        {
                          target.platform
                        }
                      </span>

                      <strong>
                        {
                          content.title
                        }
                      </strong>

                      <small>
                        {
                          preflight[
                            target.id
                          ]?.executionMode
                          === 'AUTO_API'
                            ? '☁ AUTO'
                            : '✋ MANUAL'
                        }
                        {' · '}
                        {
                          target.scheduledAt
                            ? new Date(
                                target.scheduledAt,
                              ).toLocaleString()
                            : 'Sin fecha'
                        }
                      </small>
                    </div>
                  ),
                )
              }
            </div>

            <button
              className="publish-confirm-btn"
              disabled={!allReady}
              onClick={enqueue}
            >
              <Send size={18}/>
              CONFIRMAR {
                selected.length
              } PUBLICACIÓN(ES)
            </button>

            {
              message
              && (
                <div className="hybrid-success">
                  {message}

                  <button
                    onClick={() =>
                      setView('queue')
                    }
                  >
                    Ver cola
                  </button>
                </div>
              )
            }

            {
              !allReady
              && (
                <div className="account-warning">
                  Hay contenido bloqueado por un problema real. La falta de API por sí sola no bloquea.
                </div>
              )
            }
          </section>
        )
      }

      <footer className="wizard-footer">
        <button
          className="secondary-btn"
          disabled={step === 1}
          onClick={() =>
            setStep(
              Math.max(
                1,
                step - 1,
              ),
            )
          }
        >
          <ChevronLeft size={15}/>
          Atrás
        </button>

        <span>
          {message}
        </span>

        {
          step < 5
          && (
            <button
              className="primary-btn"
              disabled={
                step === 1
                && !selected.length
              }
              onClick={() => {
                if (
                  step === 2
                ) {
                  runPreflight()
                } else {
                  setStep(
                    step + 1,
                  )
                }
              }}
            >
              Continuar
              <ChevronRight size={15}/>
            </button>
          )
        }
      </footer>
    </div>
  )
}
TS

###############################################################################
# 7. QUEUE · AUTO/MANUAL/EXTERNAL
###############################################################################

section "7/11 · HYBRID QUEUE"

cat > src/views/QueueView.tsx <<'TS'
import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  Cloud,
  ExternalLink,
  Hand,
  LoaderCircle,
  RefreshCcw,
} from 'lucide-react'

import {
  useEffect,
  useMemo,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  PublishJob,
} from '../types'

function manualTemporalStatus(
  job: PublishJob,
) {
  if (
    job.mode !== 'MANUAL'
    || !job.scheduledFor
  ) {
    return job.status
  }

  if (
    job.status
    === 'PUBLISHED_EXTERNAL'
    || job.status
      === 'SCHEDULED_EXTERNAL'
  ) {
    return job.status
  }

  const when =
    new Date(
      job.scheduledFor,
    ).getTime()

  const now =
    Date.now()

  if (
    !Number.isFinite(
      when,
    )
  ) {
    return 'MANUAL_REQUIRED'
  }

  if (
    now >= when
  ) {
    return 'MANUAL_OVERDUE'
  }

  if (
    when - now
    <= 30 * 60 * 1000
  ) {
    return 'MANUAL_DUE'
  }

  return 'MANUAL_REQUIRED'
}

function JobIcon({
  job,
}: {
  job: PublishJob
}) {
  const status =
    manualTemporalStatus(
      job,
    )

  if (
    status === 'FAILED'
  ) {
    return (
      <AlertTriangle/>
    )
  }

  if (
    status === 'PUBLISHED'
    || status
      === 'PUBLISHED_EXTERNAL'
  ) {
    return (
      <CheckCircle2/>
    )
  }

  if (
    status
      === 'SCHEDULED_EXTERNAL'
  ) {
    return (
      <ExternalLink/>
    )
  }

  if (
    job.mode === 'MANUAL'
  ) {
    return (
      <Hand/>
    )
  }

  if (
    status === 'DISPATCHING'
    || status
      === 'PROCESSING_REMOTE'
    || status
      === 'VERIFYING'
  ) {
    return (
      <LoaderCircle/>
    )
  }

  if (
    job.mode === 'AUTO_API'
  ) {
    return (
      <Cloud/>
    )
  }

  return (
    <Clock3/>
  )
}

export function QueueView() {
  const [
    jobs,
    setJobs,
  ] =
    useState<
      PublishJob[]
    >([])

  const contents =
    useAppStore(
      (s) => s.contents,
    )

  const openDetail =
    useAppStore(
      (s) => s.openDetail,
    )

  const load =
    async () => {
      setJobs(
        await backend
          .listPublicationJobs(),
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

  const counts =
    useMemo(
      () => ({
        automatic:
          jobs.filter(
            (job) =>
              job.mode
              === 'AUTO_API',
          ).length,

        manual:
          jobs.filter(
            (job) =>
              job.mode
              === 'MANUAL'
              && ![
                'PUBLISHED_EXTERNAL',
                'SCHEDULED_EXTERNAL',
              ].includes(
                job.status,
              ),
          ).length,

        due:
          jobs.filter(
            (job) =>
              [
                'MANUAL_DUE',
                'MANUAL_OVERDUE',
              ].includes(
                manualTemporalStatus(
                  job,
                ),
              ),
          ).length,

        external:
          jobs.filter(
            (job) =>
              job.mode
              === 'EXTERNAL'
              || job.status
              === 'SCHEDULED_EXTERNAL',
          ).length,

        failed:
          jobs.filter(
            (job) =>
              job.status
              === 'FAILED',
          ).length,
      }),
      [
        jobs,
      ],
    )

  return (
    <div className="page scrollable queue-page">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            PUBLICACIÓN
          </span>

          <h1>
            Cola
          </h1>

          <p>
            Automáticas, manuales y programadas externamente en una sola agenda.
          </p>
        </div>

        <button
          className="secondary-btn"
          onClick={load}
        >
          <RefreshCcw size={15}/>
          Actualizar
        </button>
      </header>

      <div className="queue-summary hybrid">
        <div>
          <Cloud/>
          <strong>
            {counts.automatic}
          </strong>
          <span>
            automáticas
          </span>
        </div>

        <div>
          <Hand/>
          <strong>
            {counts.manual}
          </strong>
          <span>
            manuales
          </span>
        </div>

        <div
          className={
            counts.due
              ? 'attention'
              : ''
          }
        >
          <Clock3/>
          <strong>
            {counts.due}
          </strong>
          <span>
            requieren atención
          </span>
        </div>

        <div>
          <ExternalLink/>
          <strong>
            {counts.external}
          </strong>
          <span>
            externas
          </span>
        </div>

        <div>
          <AlertTriangle/>
          <strong>
            {counts.failed}
          </strong>
          <span>
            errores
          </span>
        </div>
      </div>

      <section className="panel job-list">
        {
          jobs.map(
            (job) => {
              const content =
                contents.find(
                  (x) =>
                    x.id
                    === job.contentId,
                )

              const displayStatus =
                manualTemporalStatus(
                  job,
                )

              return (
                <button
                  className={
                    displayStatus
                    === 'MANUAL_OVERDUE'
                      ? 'job-row manual-overdue'
                      : displayStatus
                        === 'MANUAL_DUE'
                        ? 'job-row manual-due'
                        : 'job-row'
                  }
                  key={job.id}
                  onClick={() => {
                    if (
                      content
                    ) {
                      openDetail(
                        content.id,
                      )
                    }
                  }}
                >
                  <div
                    className={
                      `job-icon status-${displayStatus}`
                    }
                  >
                    <JobIcon
                      job={job}
                    />
                  </div>

                  <div className="job-main">
                    <small>
                      {
                        job.provider
                          .toUpperCase()
                      }
                      {' · '}
                      {
                        job.mode
                      }
                    </small>

                    <strong>
                      {
                        content?.title
                        || job.contentId
                      }
                    </strong>

                    <span>
                      {
                        job.scheduledFor
                          ? new Date(
                              job.scheduledFor,
                            ).toLocaleString()
                          : 'Sin fecha'
                      }
                    </span>
                  </div>

                  <div className="job-state">
                    <b>
                      {
                        displayStatus
                      }
                    </b>

                    {
                      job.mode
                      === 'MANUAL'
                      && (
                        <small>
                          Publicar manualmente
                        </small>
                      )
                    }

                    {
                      job.mode
                      === 'AUTO_API'
                      && (
                        <small>
                          Publisher se encargará
                        </small>
                      )
                    }
                  </div>
                </button>
              )
            },
          )
        }

        {
          !jobs.length
          && (
            <div className="empty-state">
              La cola está vacía. Ve a Preparar publicación.
            </div>
          )
        }
      </section>
    </div>
  )
}
TS

###############################################################################
# 8. TODAY · RECORDATORIOS MANUALES
###############################################################################

section "8/11 · TODAY"

cat > src/views/TodayView.tsx <<'TS'
import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  Cloud,
  Hand,
  MessageSquareText,
} from 'lucide-react'

import {
  useEffect,
  useMemo,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  PublishJob,
} from '../types'

function isToday(
  value?: string | null,
) {
  if (!value) {
    return false
  }

  const d =
    new Date(value)

  const now =
    new Date()

  return (
    d.getFullYear()
      === now.getFullYear()
    && d.getMonth()
      === now.getMonth()
    && d.getDate()
      === now.getDate()
  )
}

export function TodayView() {
  const {
    contents,
    openDetail,
    setView,
  } =
    useAppStore()

  const [
    jobs,
    setJobs,
  ] =
    useState<
      PublishJob[]
    >([])

  useEffect(
    () => {
      backend
        .listPublicationJobs()
        .then(setJobs)
        .catch(
          console.error,
        )
    },
    [],
  )

  const targets =
    contents.flatMap(
      (content) =>
        content.targets.map(
          (target) => ({
            content,
            target,
          }),
        ),
    )

  const scheduled =
    targets
      .filter(
        (x) =>
          x.target
            .scheduledAt,
      )
      .sort(
        (a,b) =>
          String(
            a.target
              .scheduledAt,
          ).localeCompare(
            String(
              b.target
                .scheduledAt,
            ),
          ),
      )
      .slice(0,6)

  const corrections =
    contents.filter(
      (content) =>
        content.status
        === 'CON_CORRECCION',
    )

  const issues =
    contents.flatMap(
      (content) =>
        content.issues.map(
          (issue) => ({
            content,
            issue,
          }),
        ),
    ).slice(
      0,
      5,
    )

  const todayJobs =
    jobs.filter(
      (job) =>
        isToday(
          job.scheduledFor,
        ),
    )

  const manualToday =
    todayJobs.filter(
      (job) =>
        job.mode === 'MANUAL'
        && ![
          'PUBLISHED_EXTERNAL',
          'SCHEDULED_EXTERNAL',
        ].includes(
          job.status,
        ),
    )

  const autoToday =
    todayJobs.filter(
      (job) =>
        job.mode
        === 'AUTO_API',
    )

  const externalToday =
    todayJobs.filter(
      (job) =>
        job.mode
        === 'EXTERNAL'
        || job.status
        === 'SCHEDULED_EXTERNAL',
    )

  const overdue =
    useMemo(
      () =>
        manualToday.filter(
          (job) => {
            if (
              !job.scheduledFor
            ) {
              return false
            }

            const time =
              new Date(
                job.scheduledFor,
              ).getTime()

            return (
              Number.isFinite(
                time,
              )
              && time
                <= Date.now()
            )
          },
        ),
      [
        manualToday,
      ],
    )

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            OPERACIONES
          </span>

          <h1>
            Hoy
          </h1>

          <p>
            Qué se publica automáticamente y qué requiere tu intervención.
          </p>
        </div>
      </header>

      <div className="metric-grid">
        <div className="metric">
          <span>
            Hoy
          </span>

          <strong>
            {
              todayJobs.length
            }
          </strong>

          <small>
            publicaciones
          </small>
        </div>

        <div className="metric">
          <span>
            Automáticas
          </span>

          <strong>
            {
              autoToday.length
            }
          </strong>

          <small>
            Publisher se encarga
          </small>
        </div>

        <div className="metric">
          <span>
            Manuales
          </span>

          <strong>
            {
              manualToday.length
            }
          </strong>

          <small>
            requieren publicación
          </small>
        </div>

        <div
          className={
            overdue.length
              ? 'metric danger'
              : 'metric'
          }
        >
          <span>
            Atención ahora
          </span>

          <strong>
            {
              overdue.length
            }
          </strong>

          <small>
            manuales vencidas
          </small>
        </div>
      </div>

      {
        manualToday.length
        > 0
        && (
          <section className="panel manual-attention-panel">
            <div className="panel-title-row">
              <h3>
                <Hand size={17}/>
                Requieren publicación manual
              </h3>

              <button
                className="secondary-btn small"
                onClick={() =>
                  setView(
                    'queue',
                  )
                }
              >
                Ver cola
              </button>
            </div>

            {
              manualToday.map(
                (job) => {
                  const content =
                    contents.find(
                      (x) =>
                        x.id
                        === job.contentId,
                    )

                  const due =
                    job.scheduledFor
                    && new Date(
                      job.scheduledFor,
                    ).getTime()
                      <= Date.now()

                  return (
                    <button
                      className={
                        due
                          ? 'manual-task overdue'
                          : 'manual-task'
                      }
                      key={job.id}
                      onClick={() => {
                        if (
                          content
                        ) {
                          openDetail(
                            content.id,
                          )
                        }
                      }}
                    >
                      <Hand size={16}/>

                      <div>
                        <small>
                          {
                            job.provider
                              .toUpperCase()
                          }
                        </small>

                        <strong>
                          {
                            content?.title
                            || job.contentId
                          }
                        </strong>
                      </div>

                      <span>
                        {
                          job.scheduledFor
                            ? new Date(
                                job.scheduledFor,
                              ).toLocaleTimeString(
                                [],
                                {
                                  hour:
                                    '2-digit',
                                  minute:
                                    '2-digit',
                                },
                              )
                            : 'Sin hora'
                        }
                      </span>

                      <b>
                        {
                          due
                            ? 'PUBLICAR AHORA'
                            : 'MANUAL'
                        }
                      </b>
                    </button>
                  )
                },
              )
            }
          </section>
        )
      }

      <div className="two-col">
        <section className="panel">
          <h3>
            <Clock3 size={17}/>
            Próximas
          </h3>

          {
            scheduled.length
              ? scheduled.map(
                  ({
                    content,
                    target,
                  }) => (
                    <button
                      className="list-row clickable"
                      key={target.id}
                      onClick={() =>
                        openDetail(
                          content.id,
                        )
                      }
                    >
                      <div>
                        <strong>
                          {
                            content.title
                          }
                        </strong>

                        <span>
                          {
                            target.platform
                          }
                        </span>
                      </div>

                      <small>
                        {
                          new Date(
                            target.scheduledAt!,
                          ).toLocaleString()
                        }
                      </small>
                    </button>
                  ),
                )
              : (
                  <div className="empty-state">
                    Todavía no hay horarios locales.
                  </div>
                )
          }
        </section>

        <section className="panel">
          <h3>
            <MessageSquareText size={17}/>
            Correcciones
          </h3>

          {
            corrections.length
              ? corrections
                  .slice(
                    0,
                    6,
                  )
                  .map(
                    (content) => (
                      <button
                        className="list-row clickable"
                        key={content.id}
                        onClick={() =>
                          openDetail(
                            content.id,
                          )
                        }
                      >
                        <div>
                          <strong>
                            {
                              content.title
                            }
                          </strong>

                          <span>
                            {
                              content.latestNote
                                ?.body
                              || 'Pendiente de corrección'
                            }
                          </span>
                        </div>

                        <small>
                          v{
                            content.version
                          }
                        </small>
                      </button>
                    ),
                  )
              : (
                  <div className="empty-state">
                    <CheckCircle2 size={18}/>
                    Sin correcciones pendientes.
                  </div>
                )
          }

          {
            issues.length
            > 0
            && (
              <div className="today-warning">
                <AlertTriangle size={14}/>
                {
                  issues.length
                } incidencias técnicas
              </div>
            )
          }
        </section>
      </div>

      {
        autoToday.length
        > 0
        && (
          <div className="auto-status-strip">
            <Cloud size={15}/>

            <strong>
              {
                autoToday.length
              } automática(s) hoy
            </strong>

            <span>
              No requieren publicación manual mientras sus APIs sigan saludables.
            </span>
          </div>
        )
      }

      {
        externalToday.length
        > 0
        && (
          <div className="external-status-strip">
            {
              externalToday.length
            } publicación(es) registradas como programadas fuera de Publisher.
          </div>
        )
      }
    </div>
  )
}
TS

###############################################################################
# 9. ACCOUNTS COPY + UI
###############################################################################

section "9/11 · ACCOUNTS / UI"

python3 <<'PY'
from pathlib import Path

p = Path(
    "src/views/AccountsView.tsx"
)

s = p.read_text()

s = s.replace(
    """Un único lugar para cuentas API, cuentas externas y capacidades de publicación.""",
    """Conecta las APIs que quieras. Las redes sin API siguen funcionando en modo manual asistido.""",
)

s = s.replace(
    """Falta completar OAuth para habilitar publicación API real.""",
    """OAuth pendiente. Hasta conectarla, Publisher usará publicación manual asistida para esta cuenta.""",
)

p.write_text(s)
PY

cat >> src/styles.css <<'CSS'

/* ============================================================
   V1.3.1 · Hybrid Publishing
   ============================================================ */

.hybrid-info-banner{
  display:grid;
  grid-template-columns:auto 1fr;
  gap:9px;
  align-items:center;
  border:1px solid var(--line);
  background:rgba(70,100,170,.07);
  border-radius:12px;
  padding:9px 11px;
  margin-bottom:10px;
}

.hybrid-info-banner strong,
.hybrid-info-banner span{
  display:block;
}

.hybrid-info-banner strong{
  font-size:10px;
}

.hybrid-info-banner span{
  color:var(--muted);
  font-size:9px;
  margin-top:2px;
}

.destination-account-stack{
  display:grid;
  gap:5px;
}

.destination-actions{
  display:flex;
  gap:5px;
  justify-content:flex-end;
  flex-wrap:wrap;
}

.execution-mode{
  display:flex;
  align-items:center;
  gap:4px;
  width:max-content;
  border-radius:999px;
  padding:4px 7px;
  font-size:8px;
  font-weight:700;
}

.execution-mode.auto{
  background:rgba(40,140,75,.12);
  color:#2b8649;
}

.execution-mode.manual{
  background:rgba(220,145,20,.13);
  color:#9b6810;
}

.hybrid-counts{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
  margin-bottom:10px;
}

.hybrid-counts>div{
  display:grid;
  grid-template-columns:auto auto 1fr;
  align-items:center;
  gap:8px;
  border:1px solid var(--line);
  border-radius:11px;
  padding:9px 12px;
  background:var(--panel);
}

.hybrid-counts svg{
  width:16px;
}

.hybrid-counts strong{
  font-size:20px;
}

.hybrid-counts span{
  color:var(--muted);
  font-size:9px;
}

.preflight-card.manual-ready{
  border-color:rgba(210,145,30,.5);
}

.execution-callout{
  border-radius:8px;
  padding:7px;
  font-size:9px;
  font-weight:700;
  margin-bottom:5px;
}

.execution-callout.auto{
  color:#2b8649;
  background:rgba(40,140,75,.1);
}

.execution-callout.manual{
  color:#9b6810;
  background:rgba(220,145,20,.12);
}

.preflight-check.warning>span{
  color:#b97812;
}

.preview-target-list small{
  display:block;
  margin-top:3px;
  font-size:8px;
  color:var(--muted);
}

.hybrid-confirm-summary{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
  margin:15px 0;
}

.hybrid-confirm-summary>div{
  border:1px solid var(--line);
  border-radius:13px;
  padding:13px;
  display:grid;
  grid-template-columns:auto auto 1fr;
  gap:9px;
  align-items:center;
}

.hybrid-confirm-summary .auto{
  border-color:rgba(40,140,75,.4);
}

.hybrid-confirm-summary .manual{
  border-color:rgba(220,145,20,.42);
}

.hybrid-confirm-summary strong{
  font-size:24px;
}

.hybrid-confirm-summary span{
  color:var(--muted);
  font-size:9px;
}

.hybrid-success{
  margin-top:10px;
  border-radius:10px;
  background:rgba(40,140,75,.1);
  padding:10px;
  display:flex;
  justify-content:space-between;
  align-items:center;
  gap:8px;
  font-size:10px;
}

.hybrid-success button{
  border:0;
  background:transparent;
  font-weight:700;
  cursor:pointer;
}

.queue-summary.hybrid>div{
  display:grid;
  grid-template-columns:auto 1fr;
  align-items:center;
  column-gap:6px;
}

.queue-summary.hybrid svg{
  grid-row:1 / span 2;
  width:15px;
}

.queue-summary.hybrid strong{
  line-height:1;
}

.queue-summary.hybrid .attention{
  border-color:rgba(210,70,55,.45);
  background:rgba(210,70,55,.07);
}

.manual-due{
  background:rgba(220,145,20,.07);
}

.manual-overdue{
  background:rgba(210,70,55,.08);
}

.status-MANUAL_REQUIRED,
.status-MANUAL_DUE{
  color:#ad7415;
}

.status-MANUAL_OVERDUE{
  color:#c73d35;
}

.manual-attention-panel{
  margin-bottom:10px;
}

.manual-task{
  width:100%;
  display:grid;
  grid-template-columns:28px minmax(0,1fr) auto auto;
  gap:8px;
  align-items:center;
  border-top:1px solid var(--line);
  padding:9px 0;
  background:transparent;
  text-align:left;
}

.manual-task small,
.manual-task strong{
  display:block;
}

.manual-task small{
  color:var(--muted);
  font-size:8px;
}

.manual-task>span{
  font-size:10px;
}

.manual-task>b{
  border-radius:999px;
  background:rgba(220,145,20,.12);
  color:#9b6810;
  padding:5px 7px;
  font-size:8px;
}

.manual-task.overdue>b{
  background:rgba(210,70,55,.12);
  color:#bd4038;
}

.auto-status-strip,
.external-status-strip{
  margin-top:10px;
  border:1px solid var(--line);
  border-radius:10px;
  padding:9px;
  font-size:9px;
}

.auto-status-strip{
  display:flex;
  align-items:center;
  gap:7px;
  background:rgba(40,140,75,.07);
}

.auto-status-strip span{
  color:var(--muted);
}

.external-status-strip{
  background:rgba(80,90,110,.06);
}

.metric.danger{
  border-color:rgba(210,70,55,.4);
}

@media(max-width:800px){
  .hybrid-confirm-summary{
    grid-template-columns:1fr;
  }

  .manual-task{
    grid-template-columns:28px 1fr;
  }

  .manual-task>span,
  .manual-task>b{
    grid-column:2;
  }
}
CSS

###############################################################################
# 10. DOCS
###############################################################################

section "10/11 · DOCS"

cat > docs/V13_1_HYBRID_PUBLISHING.md <<'MD'
# ABRAXAS Publisher V1.3.1

## Hybrid Publishing

Publisher no requiere tener todas las APIs conectadas.

Cada PublicationTarget determina independientemente su modo:

AUTO_API
MANUAL
EXTERNAL

## AUTO_API

Condiciones:

- cuenta del provider correcta;
- connection_status = CONNECTED;
- auth_state = AUTHORIZED;
- contenido válido;
- fecha válida.

Estado inicial:

QUEUED

## MANUAL

Se utiliza cuando:

- no hay cuenta;
- OAuth no está terminado;
- provider no está integrado;
- usuario fuerza publicación manual.

La ausencia de API no es un error.

Estado inicial:

MANUAL_REQUIRED

En UI puede representarse dinámicamente como:

MANUAL_REQUIRED
MANUAL_DUE
MANUAL_OVERDUE

## EXTERNAL

Cuando el usuario ya programó el contenido en:

- Edits;
- Meta Business Suite;
- YouTube Studio;
- LinkedIn;
- TikTok;
- Buffer;
- Later;
- otra herramienta.

Estado:

SCHEDULED_EXTERNAL

## Regla de preflight

Bloquean:

- contenido no aprobado;
- medio ausente;
- validation error;
- fecha ausente;
- destino remotamente bloqueado.

NO bloquea:

- ausencia de OAuth;
- ausencia de cuenta API;
- provider sin integración automática.

## Objetivo

Publisher debe seguir siendo completamente útil incluso con cero APIs:

- calendario;
- revisión;
- preview;
- cola;
- recordatorios;
- checklist;
- auditoría;
- programación externa.

Las APIs conectadas simplemente automatizan targets concretos.
MD

cat >> CHANGELOG.md <<'MD'

## 0.4.1 · V1.3.1 Hybrid Publishing

- AUTO_API / MANUAL / EXTERNAL por PublicationTarget.
- Sin API ya no bloquea preflight.
- MANUAL_REQUIRED.
- MANUAL_DUE.
- MANUAL_OVERDUE.
- Mixed batch confirmation.
- Dashboard Hoy con manual attention.
- Queue separa automatic/manual/external.
- Connected accounts pueden coexistir con redes manuales.
MD

###############################################################################
# 11. QA + BUILD + INSTALL + RELEASE
###############################################################################

section "11/11 · QA / BUILD / INSTALL"

npm install

npm run check \
  || fail "TypeScript falló."

npm run build \
  || fail "Vite falló."

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

npm run tauri:build \
  || fail "Tauri build falló."

###############################################################################
# APP
###############################################################################

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
  || fail "No se encontró la .app."

APP="$HOME/Applications/ABRAXAS Publisher.app"

BACKUP_APP="$HOME/Applications/ABRAXAS Publisher.V13.backup.$STAMP.app"

STAGE="$HOME/Applications/.ABRAXAS Publisher.V131.$STAMP.app"

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

  fail "No se pudo instalar V1.3.1."
fi

###############################################################################
# COMMIT / TAG / PUSH
###############################################################################

git add -A

git commit \
  -m "ABRAXAS Publisher V1.3.1 Hybrid Publishing"

RELEASE_SHA="$(
  git rev-parse HEAD
)"

git tag \
  -f \
  publisher-v1.3.1

git push \
  -u origin \
  "$BRANCH"

git push \
  origin \
  publisher-v1.3.1 \
  --force

###############################################################################
# PATCH + FULL
###############################################################################

RELEASE_DIR="$HOME/Developer/abraxas-publisher/releases/v1.3.1"

mkdir -p "$RELEASE_DIR"

FULL_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.1_FULL.zip"

git archive \
  --format=zip \
  --output="$FULL_ZIP" \
  HEAD

PATCH_DIR="$(
  mktemp -d
)"

mkdir -p \
  "$PATCH_DIR/files"

git diff \
  --name-only \
  "$BASE_SHA" \
  "$RELEASE_SHA" \
  > "$PATCH_DIR/FILES.txt"

while IFS= read -r FILE
do
  [ -n "$FILE" ] || continue
  [ -e "$FILE" ] || continue

  mkdir -p \
    "$PATCH_DIR/files/$(dirname "$FILE")"

  cp -R \
    "$FILE" \
    "$PATCH_DIR/files/$FILE"

done < "$PATCH_DIR/FILES.txt"

cat > "$PATCH_DIR/PATCH_MANIFEST.json" <<EOF
{
  "app": "ABRAXAS Publisher",
  "version": "1.3.1",
  "packageVersion": "0.4.1",
  "baseCommit": "$BASE_SHA",
  "releaseCommit": "$RELEASE_SHA",
  "feature": "Hybrid Publishing",
  "executionModes": [
    "AUTO_API",
    "MANUAL",
    "EXTERNAL"
  ]
}
EOF

PATCH_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.1_PATCH.zip"

ditto \
  -c \
  -k \
  --sequesterRsrc \
  "$PATCH_DIR" \
  "$PATCH_ZIP"

rm -rf "$PATCH_DIR"

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.3.1 · COMPLETADA"
echo "=============================================================="
echo
echo "App:"
echo "  $APP"
echo
echo "Backup V1.3:"
echo "  $BACKUP_APP"
echo
echo "Branch:"
echo "  $BRANCH"
echo
echo "Commit:"
echo "  $RELEASE_SHA"
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
echo "HYBRID PUBLISHING:"
echo
echo "  ☁ AUTO_API"
echo "     API conectada y autorizada"
echo
echo "  ✋ MANUAL"
echo "     sin API / OAuth / elección manual"
echo
echo "  ↗ EXTERNAL"
echo "     Edits / Studio / Business Suite / otro"
echo
echo "Una API ausente YA NO bloquea el lote."
echo
echo "Publisher sigue funcionando incluso con 0 APIs."
echo

open "$APP" || true

