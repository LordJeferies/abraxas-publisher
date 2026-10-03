#!/bin/bash
set -Eeuo pipefail

###############################################################################
# ABRAXAS PUBLISHER V1.3
# Publishing Center
#
# V1.2 -> V1.3
#
# - Accounts Center
# - Publishing Review Wizard
# - Publishing Basket
# - Platform Preview Engine
# - Persistent Publication Jobs
# - Preflight
# - SCHEDULED_EXTERNAL
# - Capability Registry
# - Queue
# - Provider adapter contracts
#
# NO inventa conexiones OAuth.
# NO publica si el provider no está realmente preparado.
###############################################################################

SOURCE="$HOME/Developer/abraxas-publisher"
WORKTREE="$HOME/Developer/abraxas-publisher-v1.3-build"
BRANCH="v1.3-publishing-center"
STAMP="$(date +%Y%m%d_%H%M%S)"

LOG_DIR="$SOURCE/logs"
LOG="$LOG_DIR/v13_$STAMP.log"

mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS PUBLISHER V1.3 · FALLO"
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

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

###############################################################################
# 1. SOURCE OF TRUTH / SNAPSHOT
###############################################################################

section "1/14 · SOURCE OF TRUTH"

cd "$SOURCE"

git fetch origin --prune

echo
echo "Branch local:"
git branch --show-current

echo
echo "HEAD:"
git log -1 --oneline

echo
echo "Estado:"
git status --short

# No perder nunca cambios del usuario.
if [ -n "$(git status --porcelain)" ]; then
  echo
  echo "Hay cambios locales."
  echo "Creando snapshot de seguridad antes de V1.3..."

  git add -A

  git commit \
    -m "Snapshot before ABRAXAS Publisher V1.3 $STAMP" \
    || true
fi

BASE_SHA="$(git rev-parse HEAD)"

echo
echo "Base V1.3:"
echo "$BASE_SHA"

###############################################################################
# 2. WORKTREE
###############################################################################

section "2/14 · WORKTREE V1.3"

if [ -d "$WORKTREE" ]; then
  git worktree remove \
    --force \
    "$WORKTREE" \
    2>/dev/null || true

  rm -rf "$WORKTREE"
fi

if git show-ref \
  --verify \
  --quiet \
  "refs/heads/$BRANCH"
then
  git branch \
    -D "$BRANCH"
fi

git worktree add \
  -b "$BRANCH" \
  "$WORKTREE" \
  "$BASE_SHA"

cd "$WORKTREE"

echo "✓ Worktree:"
echo "$WORKTREE"

###############################################################################
# 3. VERSIÓN
###############################################################################

section "3/14 · VERSIONAR"

python3 <<'PY'
from pathlib import Path
import json
import re

# package.json
p = Path("package.json")
data = json.loads(p.read_text())
data["version"] = "0.4.0"
p.write_text(
    json.dumps(data, indent=2)
    + "\n"
)

# Cargo.toml
p = Path("src-tauri/Cargo.toml")
s = p.read_text()

s = re.sub(
    r'(?m)^version\s*=\s*"[^"]+"',
    'version = "0.4.0"',
    s,
    count=1,
)

p.write_text(s)

# Tauri
p = Path("src-tauri/tauri.conf.json")
data = json.loads(p.read_text())
data["version"] = "0.4.0"
p.write_text(
    json.dumps(data, indent=2)
    + "\n"
)

print("✓ version 0.4.0")
PY

###############################################################################
# 4. BACKEND · PUBLISHING CORE
###############################################################################

section "4/14 · PUBLISHING CORE"

cat > src-tauri/src/publishing.rs <<'RS'
use chrono::Utc;
use rusqlite::{
    params,
    Connection,
    OptionalExtension,
};
use serde::{
    Deserialize,
    Serialize,
};
use sha2::{
    Digest,
    Sha256,
};
use std::path::Path;

fn open(
    path: &Path,
) -> Result<Connection, String> {
    Connection::open(path)
        .map_err(|e| e.to_string())
}

fn hash_id(
    value: &str,
) -> String {
    let mut h =
        Sha256::new();

    h.update(
        value.as_bytes(),
    );

    hex::encode(
        h.finalize(),
    )[..24]
        .to_string()
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
#[serde(rename_all = "camelCase")]
pub struct ConnectedAccount {
    pub id: String,
    pub provider: String,
    pub brand: Option<String>,
    pub display_name: String,
    pub handle: Option<String>,
    pub account_kind: String,
    pub connection_status: String,
    pub auth_state: String,
    pub capabilities_json: String,
    pub external_reference: Option<String>,
    pub last_verified_at: Option<String>,
    pub last_error: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
#[serde(rename_all = "camelCase")]
pub struct SaveAccountInput {
    pub id: Option<String>,
    pub provider: String,
    pub brand: Option<String>,
    pub display_name: String,
    pub handle: Option<String>,
    pub account_kind: String,
    pub connection_status: String,
    pub auth_state: String,
    pub capabilities_json: String,
    pub external_reference: Option<String>,
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
#[serde(rename_all = "camelCase")]
pub struct PublishJob {
    pub id: String,
    pub target_id: String,
    pub content_id: String,
    pub provider: String,
    pub account_id: Option<String>,
    pub mode: String,
    pub scheduled_for: Option<String>,
    pub status: String,
    pub idempotency_key: String,
    pub attempt: i64,
    pub max_attempts: i64,
    pub remote_id: Option<String>,
    pub remote_url: Option<String>,
    pub last_error_code: Option<String>,
    pub last_error_message: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
#[serde(rename_all = "camelCase")]
pub struct EnqueueInput {
    pub target_id: String,
    pub account_id: Option<String>,
    pub mode: String,
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
#[serde(rename_all = "camelCase")]
pub struct PreflightCheck {
    pub key: String,
    pub label: String,
    pub ok: bool,
    pub blocking: bool,
    pub detail: Option<String>,
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
#[serde(rename_all = "camelCase")]
pub struct PreflightReport {
    pub target_id: String,
    pub account_id: Option<String>,
    pub provider: String,
    pub ready: bool,
    pub checks: Vec<PreflightCheck>,
}

#[derive(
    Debug,
    Clone,
    Serialize,
    Deserialize,
)]
#[serde(rename_all = "camelCase")]
pub struct ExternalPublication {
    pub id: String,
    pub target_id: String,
    pub provider: String,
    pub method: String,
    pub scheduled_at: Option<String>,
    pub remote_url: Option<String>,
    pub note: Option<String>,
    pub created_at: String,
}

pub fn init(
    db: &Path,
) -> Result<(), String> {
    let conn =
        open(db)?;

    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS connected_accounts(
          id TEXT PRIMARY KEY,
          provider TEXT NOT NULL,
          brand TEXT,
          display_name TEXT NOT NULL,
          handle TEXT,
          account_kind TEXT NOT NULL,
          connection_status TEXT NOT NULL,
          auth_state TEXT NOT NULL,
          capabilities_json TEXT NOT NULL,
          external_reference TEXT,
          last_verified_at TEXT,
          last_error TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_accounts_provider
        ON connected_accounts(provider);

        CREATE INDEX IF NOT EXISTS idx_accounts_brand
        ON connected_accounts(brand);

        CREATE TABLE IF NOT EXISTS publication_jobs(
          id TEXT PRIMARY KEY,
          target_id TEXT NOT NULL,
          content_id TEXT NOT NULL,
          provider TEXT NOT NULL,
          account_id TEXT,
          mode TEXT NOT NULL,
          scheduled_for TEXT,
          status TEXT NOT NULL,
          idempotency_key TEXT NOT NULL UNIQUE,
          attempt INTEGER NOT NULL DEFAULT 0,
          max_attempts INTEGER NOT NULL DEFAULT 4,
          remote_id TEXT,
          remote_url TEXT,
          last_error_code TEXT,
          last_error_message TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_jobs_status
        ON publication_jobs(status);

        CREATE INDEX IF NOT EXISTS idx_jobs_scheduled
        ON publication_jobs(scheduled_for);

        CREATE TABLE IF NOT EXISTS external_publications(
          id TEXT PRIMARY KEY,
          target_id TEXT NOT NULL,
          provider TEXT NOT NULL,
          method TEXT NOT NULL,
          scheduled_at TEXT,
          remote_url TEXT,
          note TEXT,
          created_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_external_target
        ON external_publications(target_id);
        "#,
    )
    .map_err(
        |e| e.to_string(),
    )?;

    Ok(())
}

pub fn list_accounts(
    db: &Path,
) -> Result<
    Vec<ConnectedAccount>,
    String,
> {
    let conn =
        open(db)?;

    let mut stmt =
        conn.prepare(
            r#"
            SELECT
              id,provider,brand,
              display_name,handle,
              account_kind,
              connection_status,
              auth_state,
              capabilities_json,
              external_reference,
              last_verified_at,
              last_error,
              created_at,
              updated_at
            FROM connected_accounts
            ORDER BY provider,display_name
            "#,
        )
        .map_err(
            |e| e.to_string(),
        )?;

    let rows =
        stmt.query_map(
            [],
            |r| {
                Ok(
                    ConnectedAccount {
                        id: r.get(0)?,
                        provider: r.get(1)?,
                        brand: r.get(2)?,
                        display_name: r.get(3)?,
                        handle: r.get(4)?,
                        account_kind: r.get(5)?,
                        connection_status: r.get(6)?,
                        auth_state: r.get(7)?,
                        capabilities_json: r.get(8)?,
                        external_reference: r.get(9)?,
                        last_verified_at: r.get(10)?,
                        last_error: r.get(11)?,
                        created_at: r.get(12)?,
                        updated_at: r.get(13)?,
                    },
                )
            },
        )
        .map_err(
            |e| e.to_string(),
        )?;

    let result =
        rows.collect::<
            Result<Vec<_>, _>
        >()
        .map_err(
            |e| e.to_string(),
        )?;

    Ok(result)
}

pub fn save_account(
    db: &Path,
    input: SaveAccountInput,
) -> Result<
    ConnectedAccount,
    String,
> {
    let conn =
        open(db)?;

    let now =
        Utc::now()
            .to_rfc3339();

    let id =
        input.id
            .unwrap_or_else(
                || {
                    format!(
                        "acct-{}",
                        hash_id(
                            &format!(
                                "{}:{}:{}:{}",
                                input.provider,
                                input.brand
                                    .clone()
                                    .unwrap_or_default(),
                                input.display_name,
                                now
                            ),
                        ),
                    )
                },
            );

    conn.execute(
        r#"
        INSERT INTO connected_accounts(
          id,provider,brand,
          display_name,handle,
          account_kind,
          connection_status,
          auth_state,
          capabilities_json,
          external_reference,
          created_at,updated_at
        )
        VALUES(
          ?1,?2,?3,?4,?5,?6,
          ?7,?8,?9,?10,?11,?12
        )
        ON CONFLICT(id) DO UPDATE SET
          provider=excluded.provider,
          brand=excluded.brand,
          display_name=excluded.display_name,
          handle=excluded.handle,
          account_kind=excluded.account_kind,
          connection_status=excluded.connection_status,
          auth_state=excluded.auth_state,
          capabilities_json=excluded.capabilities_json,
          external_reference=excluded.external_reference,
          updated_at=excluded.updated_at
        "#,
        params![
            id,
            input.provider,
            input.brand,
            input.display_name,
            input.handle,
            input.account_kind,
            input.connection_status,
            input.auth_state,
            input.capabilities_json,
            input.external_reference,
            now,
            now,
        ],
    )
    .map_err(
        |e| e.to_string(),
    )?;

    list_accounts(db)?
        .into_iter()
        .find(
            |x| x.id == id,
        )
        .ok_or_else(
            || {
                "No se pudo releer la cuenta."
                    .to_string()
            },
        )
}

pub fn remove_account(
    db: &Path,
    account_id: &str,
) -> Result<bool, String> {
    let conn =
        open(db)?;

    let count =
        conn.execute(
            "DELETE FROM connected_accounts WHERE id=?1",
            params![
                account_id
            ],
        )
        .map_err(
            |e| e.to_string(),
        )?;

    Ok(count > 0)
}

pub fn list_jobs(
    db: &Path,
) -> Result<
    Vec<PublishJob>,
    String,
> {
    let conn =
        open(db)?;

    let mut stmt =
        conn.prepare(
            r#"
            SELECT
              id,target_id,content_id,
              provider,account_id,mode,
              scheduled_for,status,
              idempotency_key,
              attempt,max_attempts,
              remote_id,remote_url,
              last_error_code,
              last_error_message,
              created_at,updated_at
            FROM publication_jobs
            ORDER BY
              CASE
                WHEN scheduled_for IS NULL THEN 1
                ELSE 0
              END,
              scheduled_for,
              created_at
            "#,
        )
        .map_err(
            |e| e.to_string(),
        )?;

    let rows =
        stmt.query_map(
            [],
            |r| {
                Ok(
                    PublishJob {
                        id: r.get(0)?,
                        target_id: r.get(1)?,
                        content_id: r.get(2)?,
                        provider: r.get(3)?,
                        account_id: r.get(4)?,
                        mode: r.get(5)?,
                        scheduled_for: r.get(6)?,
                        status: r.get(7)?,
                        idempotency_key: r.get(8)?,
                        attempt: r.get(9)?,
                        max_attempts: r.get(10)?,
                        remote_id: r.get(11)?,
                        remote_url: r.get(12)?,
                        last_error_code: r.get(13)?,
                        last_error_message: r.get(14)?,
                        created_at: r.get(15)?,
                        updated_at: r.get(16)?,
                    },
                )
            },
        )
        .map_err(
            |e| e.to_string(),
        )?;

    let result =
        rows.collect::<
            Result<Vec<_>, _>
        >()
        .map_err(
            |e| e.to_string(),
        )?;

    Ok(result)
}

pub fn preflight(
    db: &Path,
    target_id: &str,
    account_id: Option<&str>,
) -> Result<
    PreflightReport,
    String,
> {
    let conn =
        open(db)?;

    let target: Option<(
        String,
        String,
        String,
        Option<String>,
        String,
        Option<String>,
    )> =
        conn.query_row(
            r#"
            SELECT
              p.content_id,
              p.platform,
              p.status,
              p.scheduled_at,
              c.workflow_status,
              c.source_fingerprint
            FROM publication_targets p
            JOIN contents c
              ON c.id=p.content_id
            WHERE p.id=?1
            "#,
            params![
                target_id
            ],
            |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
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
        target_status,
        scheduled_at,
        editorial_status,
        _fingerprint,
    )) = target
    else {
        return Err(
            "Destino no encontrado."
                .into(),
        );
    };

    let media_count: i64 =
        conn.query_row(
            "SELECT COUNT(*) FROM media_assets WHERE content_id=?1",
            params![
                content_id
            ],
            |r| r.get(0),
        )
        .map_err(
            |e| e.to_string(),
        )?;

    let account =
        if let Some(id) =
            account_id
        {
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
            .map_err(
                |e| e.to_string(),
            )?
        } else {
            None
        };

    let mut checks =
        Vec::new();

    let editorial_ok =
        editorial_status
            == "LISTO_POR_PROGRAMAR"
        || editorial_status
            == "PROGRAMADO";

    checks.push(
        PreflightCheck {
            key: "editorial".into(),
            label:
                "Contenido aprobado editorialmente"
                    .into(),
            ok: editorial_ok,
            blocking: true,
            detail:
                Some(
                    editorial_status
                        .clone(),
                ),
        },
    );

    checks.push(
        PreflightCheck {
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
        },
    );

    checks.push(
        PreflightCheck {
            key: "schedule".into(),
            label:
                "Fecha/hora definida"
                    .into(),
            ok:
                scheduled_at
                    .is_some(),
            blocking: true,
            detail:
                scheduled_at
                    .clone(),
        },
    );

    checks.push(
        PreflightCheck {
            key: "remote-lock".into(),
            label:
                "Destino editable"
                    .into(),
            ok:
                target_status
                    != "SCHEDULED_REMOTE"
                && target_status
                    != "PUBLISHED",
            blocking: true,
            detail:
                Some(
                    target_status
                        .clone(),
                ),
        },
    );

    let (
        account_ok,
        account_detail,
    ) =
        match account {
            Some((
                account_provider,
                connection_status,
                auth_state,
            )) => {
                let ok =
                    account_provider
                        == provider
                    && connection_status
                        == "CONNECTED"
                    && auth_state
                        == "AUTHORIZED";

                (
                    ok,
                    Some(
                        format!(
                            "{} · {} · {}",
                            account_provider,
                            connection_status,
                            auth_state
                        ),
                    ),
                )
            }

            None => (
                false,
                Some(
                    "Sin cuenta API conectada"
                        .into(),
                ),
            ),
        };

    checks.push(
        PreflightCheck {
            key: "account".into(),
            label:
                "Cuenta y autorización válidas"
                    .into(),
            ok: account_ok,
            blocking: true,
            detail:
                account_detail,
        },
    );

    let ready =
        checks.iter()
            .filter(
                |x| x.blocking,
            )
            .all(
                |x| x.ok,
            );

    Ok(
        PreflightReport {
            target_id:
                target_id.into(),
            account_id:
                account_id.map(
                    |x| x.into(),
                ),
            provider,
            ready,
            checks,
        },
    )
}

pub fn enqueue(
    db: &Path,
    inputs: &[EnqueueInput],
) -> Result<
    Vec<PublishJob>,
    String,
> {
    let conn =
        open(db)?;

    let now =
        Utc::now()
            .to_rfc3339();

    for input in inputs {
        let target: Option<(
            String,
            String,
            Option<String>,
            Option<String>,
        )> =
            conn.query_row(
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
                input.mode,
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
            INSERT OR IGNORE INTO publication_jobs(
              id,target_id,content_id,
              provider,account_id,mode,
              scheduled_for,status,
              idempotency_key,
              attempt,max_attempts,
              created_at,updated_at
            )
            VALUES(
              ?1,?2,?3,?4,?5,?6,
              ?7,'QUEUED',
              ?8,0,4,?9,?10
            )
            "#,
            params![
                id,
                input.target_id,
                content_id,
                provider,
                input.account_id,
                input.mode,
                scheduled_for,
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

pub fn mark_external(
    db: &Path,
    target_id: &str,
    method: &str,
    scheduled_at: Option<&str>,
    remote_url: Option<&str>,
    note: Option<&str>,
) -> Result<
    ExternalPublication,
    String,
> {
    let conn =
        open(db)?;

    let provider: String =
        conn.query_row(
            "SELECT platform FROM publication_targets WHERE id=?1",
            params![
                target_id
            ],
            |r| r.get(0),
        )
        .map_err(
            |e| e.to_string(),
        )?;

    let now =
        Utc::now()
            .to_rfc3339();

    let id =
        format!(
            "external-{}",
            hash_id(
                &format!(
                    "{}:{}:{}",
                    target_id,
                    method,
                    now
                ),
            ),
        );

    conn.execute(
        r#"
        INSERT INTO external_publications(
          id,target_id,provider,
          method,scheduled_at,
          remote_url,note,created_at
        )
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8)
        "#,
        params![
            id,
            target_id,
            provider,
            method,
            scheduled_at,
            remote_url,
            note,
            now,
        ],
    )
    .map_err(
        |e| e.to_string(),
    )?;

    conn.execute(
        r#"
        UPDATE publication_targets
        SET
          status='SCHEDULED_EXTERNAL',
          scheduled_at=COALESCE(?2,scheduled_at),
          schedule_source='EXTERNAL'
        WHERE id=?1
        "#,
        params![
            target_id,
            scheduled_at,
        ],
    )
    .map_err(
        |e| e.to_string(),
    )?;

    Ok(
        ExternalPublication {
            id,
            target_id:
                target_id.into(),
            provider,
            method:
                method.into(),
            scheduled_at:
                scheduled_at.map(
                    |x| x.into(),
                ),
            remote_url:
                remote_url.map(
                    |x| x.into(),
                ),
            note:
                note.map(
                    |x| x.into(),
                ),
            created_at: now,
        },
    )
}
RS

###############################################################################
# 5. PATCH LIB.RS
###############################################################################

section "5/14 · TAURI COMMANDS"

python3 <<'PY'
from pathlib import Path

p = Path(
    "src-tauri/src/lib.rs"
)

s = p.read_text()

if "pub mod publishing;" not in s:
    s = s.replace(
        "pub mod models;",
        "pub mod models;\npub mod publishing;",
        1,
    )

commands = r'''
#[tauri::command]
fn list_connected_accounts(
    state: State<'_, AppState>,
) -> Result<Vec<publishing::ConnectedAccount>, String> {
    publishing::list_accounts(&state.db_path)
}

#[tauri::command]
fn save_connected_account(
    input: publishing::SaveAccountInput,
    state: State<'_, AppState>,
) -> Result<publishing::ConnectedAccount, String> {
    publishing::save_account(&state.db_path, input)
}

#[tauri::command]
fn remove_connected_account(
    account_id: String,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    publishing::remove_account(&state.db_path, &account_id)
}

#[tauri::command]
fn list_publication_jobs(
    state: State<'_, AppState>,
) -> Result<Vec<publishing::PublishJob>, String> {
    publishing::list_jobs(&state.db_path)
}

#[tauri::command]
fn publishing_preflight(
    target_id: String,
    account_id: Option<String>,
    state: State<'_, AppState>,
) -> Result<publishing::PreflightReport, String> {
    publishing::preflight(
        &state.db_path,
        &target_id,
        account_id.as_deref(),
    )
}

#[tauri::command]
fn enqueue_publications(
    inputs: Vec<publishing::EnqueueInput>,
    state: State<'_, AppState>,
) -> Result<Vec<publishing::PublishJob>, String> {
    publishing::enqueue(
        &state.db_path,
        &inputs,
    )
}

#[tauri::command]
fn mark_scheduled_external(
    target_id: String,
    method: String,
    scheduled_at: Option<String>,
    remote_url: Option<String>,
    note: Option<String>,
    state: State<'_, AppState>,
) -> Result<publishing::ExternalPublication, String> {
    publishing::mark_external(
        &state.db_path,
        &target_id,
        &method,
        scheduled_at.as_deref(),
        remote_url.as_deref(),
        note.as_deref(),
    )
}
'''

needle = (
    "#[cfg_attr(mobile, "
    "tauri::mobile_entry_point)]"
)

if (
    "fn list_connected_accounts("
    not in s
):
    s = s.replace(
        needle,
        commands
        + "\n"
        + needle,
        1,
    )

s = s.replace(
    """db::init(&db_path).map_err(std::io::Error::other)?;""",
    """db::init(&db_path).map_err(std::io::Error::other)?;
            publishing::init(&db_path).map_err(std::io::Error::other)?;""",
    1,
)

handler_anchor = (
    "            health,\n"
)

if (
    "            list_connected_accounts,"
    not in s
):
    s = s.replace(
        handler_anchor,
        handler_anchor
        + """            list_connected_accounts,
            save_connected_account,
            remove_connected_account,
            list_publication_jobs,
            publishing_preflight,
            enqueue_publications,
            mark_scheduled_external,
""",
        1,
    )

p.write_text(s)

print("✓ lib.rs")
PY

###############################################################################
# 6. FRONTEND TYPES
###############################################################################

section "6/14 · FRONTEND CONTRACTS"

cat >> src/types.ts <<'TS'

export type Provider =
  | 'instagram'
  | 'facebook'
  | 'linkedin'
  | 'youtube'
  | 'tiktok'
  | string

export interface ConnectedAccount {
  id: string
  provider: Provider
  brand?: string | null
  displayName: string
  handle?: string | null
  accountKind: string
  connectionStatus: string
  authState: string
  capabilitiesJson: string
  externalReference?: string | null
  lastVerifiedAt?: string | null
  lastError?: string | null
  createdAt: string
  updatedAt: string
}

export interface SaveAccountInput {
  id?: string | null
  provider: string
  brand?: string | null
  displayName: string
  handle?: string | null
  accountKind: string
  connectionStatus: string
  authState: string
  capabilitiesJson: string
  externalReference?: string | null
}

export interface PublishJob {
  id: string
  targetId: string
  contentId: string
  provider: string
  accountId?: string | null
  mode: string
  scheduledFor?: string | null
  status: string
  idempotencyKey: string
  attempt: number
  maxAttempts: number
  remoteId?: string | null
  remoteUrl?: string | null
  lastErrorCode?: string | null
  lastErrorMessage?: string | null
  createdAt: string
  updatedAt: string
}

export interface EnqueueInput {
  targetId: string
  accountId?: string | null
  mode: string
}

export interface PreflightCheck {
  key: string
  label: string
  ok: boolean
  blocking: boolean
  detail?: string | null
}

export interface PreflightReport {
  targetId: string
  accountId?: string | null
  provider: string
  ready: boolean
  checks: PreflightCheck[]
}

export interface ExternalPublication {
  id: string
  targetId: string
  provider: string
  method: string
  scheduledAt?: string | null
  remoteUrl?: string | null
  note?: string | null
  createdAt: string
}
TS

###############################################################################
# 7. BACKEND TS
###############################################################################

python3 <<'PY'
from pathlib import Path

p = Path("src/lib/backend.ts")
s = p.read_text()

# Import types
s = s.replace(
    "  WorkflowStatus,\n",
    """  WorkflowStatus,
  ConnectedAccount,
  SaveAccountInput,
  PublishJob,
  EnqueueInput,
  PreflightReport,
  ExternalPublication,
""",
    1,
)

insert = r'''
  listConnectedAccounts: () =>
    invoke<ConnectedAccount[]>(
      'list_connected_accounts',
    ),

  saveConnectedAccount: (
    input: SaveAccountInput,
  ) =>
    invoke<ConnectedAccount>(
      'save_connected_account',
      { input },
    ),

  removeConnectedAccount: (
    accountId: string,
  ) =>
    invoke<boolean>(
      'remove_connected_account',
      { accountId },
    ),

  listPublicationJobs: () =>
    invoke<PublishJob[]>(
      'list_publication_jobs',
    ),

  publishingPreflight: (
    targetId: string,
    accountId?: string | null,
  ) =>
    invoke<PreflightReport>(
      'publishing_preflight',
      {
        targetId,
        accountId:
          accountId || null,
      },
    ),

  enqueuePublications: (
    inputs: EnqueueInput[],
  ) =>
    invoke<PublishJob[]>(
      'enqueue_publications',
      { inputs },
    ),

  markScheduledExternal: (
    targetId: string,
    method: string,
    scheduledAt?: string | null,
    remoteUrl?: string | null,
    note?: string | null,
  ) =>
    invoke<ExternalPublication>(
      'mark_scheduled_external',
      {
        targetId,
        method,
        scheduledAt:
          scheduledAt || null,
        remoteUrl:
          remoteUrl || null,
        note:
          note || null,
      },
    ),
'''

anchor = (
    "export const backend = {\n"
)

if (
    "listConnectedAccounts:"
    not in s
):
    s = s.replace(
        anchor,
        anchor + insert,
        1,
    )

p.write_text(s)

print("✓ backend.ts")
PY

###############################################################################
# 8. PLATFORM PREVIEW ENGINE
###############################################################################

mkdir -p src/components

cat > src/components/PlatformPreview.tsx <<'TS'
import {
  convertFileSrc,
} from '@tauri-apps/api/core'

import {
  Heart,
  MessageCircle,
  MoreHorizontal,
  Play,
  Send,
  Share2,
  ThumbsUp,
} from 'lucide-react'

import type {
  ContentItem,
  PublicationTarget,
} from '../types'

function Media({
  item,
}: {
  item: ContentItem
}) {
  const media =
    item.media[0]

  if (!media) {
    return (
      <div className="social-media-empty">
        Sin media
      </div>
    )
  }

  const src =
    convertFileSrc(
      media.path,
    )

  if (
    media.kind === 'video'
  ) {
    return (
      <video
        className="social-media"
        src={src}
        controls
        playsInline
      />
    )
  }

  return (
    <img
      className="social-media"
      src={src}
      alt={item.title}
    />
  )
}

export function PlatformPreview({
  item,
  target,
}: {
  item: ContentItem
  target: PublicationTarget
}) {
  const platform =
    target.platform
      .toLowerCase()

  const copy =
    target.copy
    || item.title

  if (
    platform === 'youtube'
  ) {
    const vertical =
      item.contentType
        .toLowerCase()
        .includes('short')
      || item.contentType
        .toLowerCase()
        .includes('reel')

    return (
      <div
        className={
          vertical
            ? 'network-preview youtube short-preview'
            : 'network-preview youtube'
        }
      >
        <div className="network-top">
          YouTube
        </div>

        <div className="youtube-player">
          <Media item={item}/>

          <div className="player-center">
            <Play size={30}/>
          </div>
        </div>

        <div className="youtube-meta">
          <strong>
            {item.title}
          </strong>

          <span>
            JOC · Publicación previa
          </span>

          <div className="network-actions">
            <ThumbsUp size={17}/>
            <Share2 size={17}/>
            <MoreHorizontal size={17}/>
          </div>

          <p>
            {copy}
          </p>
        </div>
      </div>
    )
  }

  if (
    platform === 'linkedin'
  ) {
    return (
      <div className="network-preview linkedin">
        <div className="network-top">
          LinkedIn
        </div>

        <div className="linkedin-author">
          <div className="fake-avatar">
            J
          </div>

          <div>
            <strong>
              Joc López
            </strong>

            <span>
              Ventas · Estrategia
            </span>
          </div>

          <MoreHorizontal size={17}/>
        </div>

        <p className="network-copy">
          {copy}
        </p>

        <Media item={item}/>

        <div className="network-actions spread">
          <span>
            <ThumbsUp size={16}/>
            Recomendar
          </span>

          <span>
            <MessageCircle size={16}/>
            Comentar
          </span>

          <span>
            <Share2 size={16}/>
            Compartir
          </span>
        </div>
      </div>
    )
  }

  if (
    platform === 'tiktok'
  ) {
    return (
      <div className="network-preview tiktok">
        <div className="network-top">
          TikTok · Para ti
        </div>

        <div className="vertical-stage">
          <Media item={item}/>

          <div className="vertical-caption">
            <strong>
              @jocventas
            </strong>

            <p>
              {copy}
            </p>
          </div>

          <div className="vertical-actions">
            <Heart/>
            <MessageCircle/>
            <Share2/>
          </div>
        </div>
      </div>
    )
  }

  if (
    platform === 'facebook'
  ) {
    return (
      <div className="network-preview facebook">
        <div className="network-top">
          Facebook
        </div>

        <div className="linkedin-author">
          <div className="fake-avatar">
            J
          </div>

          <div>
            <strong>
              JOC
            </strong>

            <span>
              Ahora · 🌐
            </span>
          </div>
        </div>

        <p className="network-copy">
          {copy}
        </p>

        <Media item={item}/>

        <div className="network-actions spread">
          <span>
            <ThumbsUp size={16}/>
            Me gusta
          </span>

          <span>
            <MessageCircle size={16}/>
            Comentar
          </span>

          <span>
            <Share2 size={16}/>
            Compartir
          </span>
        </div>
      </div>
    )
  }

  return (
    <div className="network-preview instagram">
      <div className="network-top">
        Instagram
      </div>

      <div className="ig-author">
        <div className="fake-avatar">
          J
        </div>

        <strong>
          jocventas
        </strong>

        <MoreHorizontal size={17}/>
      </div>

      <Media item={item}/>

      <div className="network-actions">
        <Heart size={20}/>
        <MessageCircle size={20}/>
        <Send size={20}/>
      </div>

      <div className="ig-copy">
        <strong>
          jocventas
        </strong>
        {' '}
        {copy}
      </div>

      {
        item.media.length > 1
        && (
          <div className="carousel-dots">
            {
              item.media.map(
                (_, index) => (
                  <span
                    key={index}
                    className={
                      index === 0
                        ? 'active'
                        : ''
                    }
                  />
                ),
              )
            }
          </div>
        )
      }
    </div>
  )
}
TS

###############################################################################
# 9. ACCOUNTS CENTER
###############################################################################

cat > src/views/AccountsView.tsx <<'TS'
import {
  CheckCircle2,
  Link2,
  Plus,
  ShieldAlert,
  Trash2,
  X,
} from 'lucide-react'

import {
  useEffect,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  ConnectedAccount,
} from '../types'

const PROVIDERS = [
  'instagram',
  'facebook',
  'linkedin',
  'youtube',
  'tiktok',
]

function capabilities(
  provider: string,
) {
  const matrix:
    Record<string, object> = {
      instagram: {
        image: true,
        video: true,
        multiImage: true,
        reel: true,
        story: false,
        dispatchStrategy:
          'LOCAL_DISPATCH',
      },

      facebook: {
        image: true,
        video: true,
        multiImage: true,
        dispatchStrategy:
          'PROVIDER_OR_LOCAL',
      },

      linkedin: {
        text: true,
        image: true,
        video: true,
        document: true,
        multiImage: true,
        organicCarousel: false,
        dispatchStrategy:
          'LOCAL_DISPATCH',
      },

      youtube: {
        video: true,
        short: true,
        nativePublishAt: true,
        dispatchStrategy:
          'NATIVE_OR_LOCAL',
      },

      tiktok: {
        video: true,
        photo: true,
        directPost: true,
        mediaUploadDraft: true,
        creatorInfoRequired: true,
        dispatchStrategy:
          'LOCAL_DISPATCH',
      },
    }

  return JSON.stringify(
    matrix[provider]
    || {},
  )
}

export function AccountsView() {
  const brands =
    useAppStore(
      (s) => s.brands,
    )

  const [
    accounts,
    setAccounts,
  ] =
    useState<
      ConnectedAccount[]
    >([])

  const [
    modal,
    setModal,
  ] =
    useState(false)

  const [
    provider,
    setProvider,
  ] =
    useState('instagram')

  const [
    brand,
    setBrand,
  ] =
    useState(
      brands[0]?.name
      || '',
    )

  const [
    name,
    setName,
  ] =
    useState('')

  const [
    handle,
    setHandle,
  ] =
    useState('')

  const [
    kind,
    setKind,
  ] =
    useState('creator')

  const [
    mode,
    setMode,
  ] =
    useState<
      'api'
      | 'external'
    >('api')

  const load =
    async () => {
      setAccounts(
        await backend
          .listConnectedAccounts(),
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

  const save =
    async () => {
      if (!name.trim()) {
        return
      }

      await backend
        .saveConnectedAccount({
          provider,
          brand:
            brand || null,
          displayName:
            name.trim(),
          handle:
            handle.trim()
            || null,
          accountKind:
            kind,

          // No fingimos OAuth.
          connectionStatus:
            mode === 'external'
              ? 'EXTERNAL_ONLY'
              : 'NEEDS_AUTH',

          authState:
            mode === 'external'
              ? 'NOT_REQUIRED'
              : 'PENDING',

          capabilitiesJson:
            capabilities(
              provider,
            ),

          externalReference:
            null,
        })

      await load()

      setModal(false)
      setName('')
      setHandle('')
    }

  const remove =
    async (
      id: string,
    ) => {
      await backend
        .removeConnectedAccount(
          id,
        )

      await load()
    }

  return (
    <div className="page scrollable accounts-page">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            CUENTAS
          </span>

          <h1>
            Cuentas conectadas
          </h1>

          <p>
            Un único lugar para cuentas API, cuentas externas y capacidades de publicación.
          </p>
        </div>

        <button
          className="primary-btn"
          onClick={() =>
            setModal(true)
          }
        >
          <Plus size={16}/>
          Conectar cuenta
        </button>
      </header>

      <div className="account-grid">
        {
          accounts.map(
            (account) => (
              <article
                className={
                  `account-card provider-${account.provider}`
                }
                key={account.id}
              >
                <div className="account-provider">
                  <div>
                    <span>
                      {
                        account.provider
                          .toUpperCase()
                      }
                    </span>

                    <strong>
                      {
                        account.displayName
                      }
                    </strong>

                    <small>
                      {
                        account.handle
                        || account.accountKind
                      }
                    </small>
                  </div>

                  {
                    account.connectionStatus
                    === 'CONNECTED'
                      ? (
                        <CheckCircle2
                          className="healthy"
                          size={20}
                        />
                      )
                      : (
                        <ShieldAlert
                          className="warning"
                          size={20}
                        />
                      )
                  }
                </div>

                <div className="account-health">
                  <span>
                    Marca
                    <b>
                      {
                        account.brand
                        || 'Todas'
                      }
                    </b>
                  </span>

                  <span>
                    Estado
                    <b>
                      {
                        account.connectionStatus
                      }
                    </b>
                  </span>

                  <span>
                    Auth
                    <b>
                      {
                        account.authState
                      }
                    </b>
                  </span>
                </div>

                {
                  account.connectionStatus
                  === 'NEEDS_AUTH'
                  && (
                    <div className="account-warning">
                      <Link2 size={14}/>

                      Falta completar OAuth para habilitar publicación API real.
                    </div>
                  )
                }

                {
                  account.connectionStatus
                  === 'EXTERNAL_ONLY'
                  && (
                    <div className="account-warning neutral">
                      Esta cuenta se usa para registrar publicaciones hechas fuera de Publisher.
                    </div>
                  )
                }

                <button
                  className="danger-text-btn"
                  onClick={() =>
                    remove(
                      account.id,
                    )
                  }
                >
                  <Trash2 size={13}/>
                  Quitar
                </button>
              </article>
            ),
          )
        }

        {
          !accounts.length
          && (
            <div className="hero-empty">
              <h2>
                Sin cuentas
              </h2>

              <p>
                Añade Instagram, Facebook, LinkedIn, YouTube o TikTok.
              </p>
            </div>
          )
        }
      </div>

      {
        modal
        && (
          <div className="modal-backdrop">
            <section className="account-modal">
              <header>
                <div>
                  <span className="eyebrow">
                    CUENTA NUEVA
                  </span>

                  <h3>
                    Conectar cuenta
                  </h3>
                </div>

                <button
                  onClick={() =>
                    setModal(false)
                  }
                >
                  <X size={18}/>
                </button>
              </header>

              <label>
                Plataforma
              </label>

              <select
                className="field full-field"
                value={provider}
                onChange={(e) =>
                  setProvider(
                    e.target.value,
                  )
                }
              >
                {
                  PROVIDERS.map(
                    (value) => (
                      <option
                        value={value}
                        key={value}
                      >
                        {value}
                      </option>
                    ),
                  )
                }
              </select>

              <label>
                Marca
              </label>

              <select
                className="field full-field"
                value={brand}
                onChange={(e) =>
                  setBrand(
                    e.target.value,
                  )
                }
              >
                <option value="">
                  Todas
                </option>

                {
                  brands.map(
                    (value) => (
                      <option
                        key={value.id}
                        value={value.name}
                      >
                        {value.name}
                      </option>
                    ),
                  )
                }
              </select>

              <label>
                Nombre visible
              </label>

              <input
                className="field full-field"
                value={name}
                onChange={(e) =>
                  setName(
                    e.target.value,
                  )
                }
                placeholder="Ej. Joc López"
              />

              <label>
                Handle
              </label>

              <input
                className="field full-field"
                value={handle}
                onChange={(e) =>
                  setHandle(
                    e.target.value,
                  )
                }
                placeholder="@jocventas"
              />

              <label>
                Tipo
              </label>

              <select
                className="field full-field"
                value={kind}
                onChange={(e) =>
                  setKind(
                    e.target.value,
                  )
                }
              >
                <option value="creator">
                  Creator / perfil
                </option>

                <option value="organization">
                  Organización / página
                </option>

                <option value="channel">
                  Canal
                </option>
              </select>

              <label>
                Uso
              </label>

              <div className="account-mode-grid">
                <button
                  className={
                    mode === 'api'
                      ? 'choice-card active'
                      : 'choice-card'
                  }
                  onClick={() =>
                    setMode('api')
                  }
                >
                  <strong>
                    API
                  </strong>

                  <span>
                    Preparar OAuth y publicación desde Publisher.
                  </span>
                </button>

                <button
                  className={
                    mode === 'external'
                      ? 'choice-card active'
                      : 'choice-card'
                  }
                  onClick={() =>
                    setMode('external')
                  }
                >
                  <strong>
                    Externa
                  </strong>

                  <span>
                    Edits, Studio, Business Suite u otra app.
                  </span>
                </button>
              </div>

              {
                mode === 'api'
                && (
                  <div className="account-warning">
                    La cuenta se guardará como OAuth pendiente. Publisher no la marcará como CONNECTED hasta verificar credenciales y permisos reales.
                  </div>
                )
              }

              <div className="modal-actions">
                <button
                  className="secondary-btn"
                  onClick={() =>
                    setModal(false)
                  }
                >
                  Cancelar
                </button>

                <button
                  className="primary-btn"
                  onClick={save}
                >
                  Guardar cuenta
                </button>
              </div>
            </section>
          </div>
        )
      }
    </div>
  )
}
TS

###############################################################################
# 10. PUBLISHING WIZARD
###############################################################################

cat > src/views/PublishView.tsx <<'TS'
import {
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  ExternalLink,
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
        (prev) =>
          prev.includes(id)
            ? prev.filter(
                (x) => x !== id,
              )
            : [...prev,id],
      )
    }

  const compatibleAccounts =
    (
      target: PublicationTarget,
      brand?: string | null,
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
        next[target.id] =
          await backend
            .publishingPreflight(
              target.id,
              accountFor[
                target.id
              ]
              || null,
            )
      }

      setPreflight(next)
      setStep(3)
    }

  const allReady =
    selected.length > 0
    && selected.every(
      ({ target }) =>
        preflight[
          target.id
        ]?.ready,
    )

  const enqueue =
    async () => {
      if (!allReady) {
        setMessage(
          'Hay destinos bloqueados por el preflight.',
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
                accountFor[
                  target.id
                ]
                || null,
              mode:
                'SCHEDULE',
            }),
          ),
        )

      setMessage(
        `${selected.length} destino(s) añadidos a la cola.`,
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
        `Marcado como SCHEDULED_EXTERNAL · ${externalMethod}`,
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
            Selecciona → destinos → preflight → preview → cola.
          </p>
        </div>

        <div className="publish-step-number">
          {step}/5
        </div>
      </header>

      <div className="wizard-steps">
        {
          [
            'Contenido',
            'Cuentas',
            'Verificar',
            'Preview',
            'Confirmar',
          ].map(
            (label,index) => (
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
                  ¿Qué vas a programar?
                </h2>

                <p>
                  Sólo aparece contenido editorialmente listo.
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
                        selectedTargets.includes(
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
                          selectedTargets.includes(
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
                  Cuentas de destino
                </h2>

                <p>
                  Una cuenta distinta puede usarse por cada red.
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
                              (prev) => ({
                                ...prev,
                                [
                                  target.id
                                ]:
                                  e.target.value,
                              }),
                            )
                          }
                        >
                          <option value="">
                            Seleccionar cuenta
                          </option>

                          {
                            compatible.map(
                              (account) => (
                                <option
                                  value={account.id}
                                  key={account.id}
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

                        <button
                          className="secondary-btn small"
                          onClick={() =>
                            markExternal(
                              target.id,
                            )
                          }
                        >
                          <ExternalLink size={14}/>
                          Programado fuera
                        </button>
                      </article>
                    )
                  },
                )
              }
            </div>

            <div className="external-method-row">
              <span>
                Si fue programado fuera:
              </span>

              <select
                className="field"
                value={externalMethod}
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
                  Ningún job sale a una API sin pasar esta fase.
                </p>
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

                    return (
                      <article
                        className={
                          report?.ready
                            ? 'preflight-card ready'
                            : 'preflight-card blocked'
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
                            report?.ready
                              ? <CheckCircle2/>
                              : <CircleAlert/>
                          }
                        </header>

                        {
                          report?.checks.map(
                            (check) => (
                              <div
                                className={
                                  check.ok
                                    ? 'preflight-check ok'
                                    : 'preflight-check fail'
                                }
                                key={check.key}
                              >
                                <span>
                                  {
                                    check.ok
                                      ? '✓'
                                      : '✕'
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
                        previewEntry?.target.id
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
                            previewEntry.target.platform
                          }
                        </h2>
                      </div>

                      <div className="preview-type-badge">
                        {
                          previewEntry.content.contentType
                        }
                      </div>
                    </div>

                    <PlatformPreview
                      item={
                        previewEntry.content
                      }
                      target={
                        previewEntry.target
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
              CONFIRMAR
            </span>

            <h2>
              {
                selected.length
              } publicación(es)
            </h2>

            <p>
              La confirmación añade jobs persistentes a la cola. Sólo los adapters realmente autorizados podrán ejecutar llamadas externas.
            </p>

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
              PROGRAMAR {
                selected.length
              } PUBLICACIÓN(ES)
            </button>

            {
              !allReady
              && (
                <div className="account-warning">
                  Existen destinos sin cuenta API autorizada o con preflight bloqueado.
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
          {
            message
          }
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
# 11. QUEUE V1.3
###############################################################################

cat > src/views/QueueView.tsx <<'TS'
import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
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

const groups = [
  'REVIEW_REQUIRED',
  'QUEUED',
  'DISPATCHING',
  'PROCESSING_REMOTE',
  'VERIFYING',
  'SCHEDULED_REMOTE',
  'SCHEDULED_EXTERNAL',
  'PUBLISHED',
  'FAILED',
]

function JobIcon({
  status,
}: {
  status: string
}) {
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
      === 'SCHEDULED_REMOTE'
  ) {
    return (
      <CheckCircle2/>
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

  const byStatus =
    useMemo(
      () =>
        Object.fromEntries(
          groups.map(
            (status) => [
              status,
              jobs.filter(
                (job) =>
                  job.status
                  === status,
              ),
            ],
          ),
        ) as
        Record<
          string,
          PublishJob[]
        >,
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
            Jobs persistentes, reintentos, verificación y estado remoto.
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

      <div className="queue-summary">
        {
          groups.map(
            (status) => (
              <div key={status}>
                <strong>
                  {
                    byStatus[
                      status
                    ]?.length
                    || 0
                  }
                </strong>

                <span>
                  {status}
                </span>
              </div>
            ),
          )
        }
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

              return (
                <button
                  className="job-row"
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
                      `job-icon status-${job.status}`
                    }
                  >
                    <JobIcon
                      status={
                        job.status
                      }
                    />
                  </div>

                  <div className="job-main">
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
                      {job.status}
                    </b>

                    <small>
                      intento {
                        job.attempt
                      } / {
                        job.maxAttempts
                      }
                    </small>
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
# 12. STORE / APP / SIDEBAR
###############################################################################

section "7/14 · ROUTING"

python3 <<'PY'
from pathlib import Path

# STORE
p = Path("src/lib/store.ts")
s = p.read_text()

if "| 'accounts'" not in s:
    s = s.replace(
        "  | 'queue'\n",
        """  | 'queue'
  | 'publish'
  | 'accounts'
""",
        1,
    )

p.write_text(s)

# APP
p = Path("src/App.tsx")
s = p.read_text()

if "AccountsView" not in s:
    s = s.replace(
        "import { QueueView } from './views/QueueView'\n",
        """import { QueueView } from './views/QueueView'
import { PublishView } from './views/PublishView'
import { AccountsView } from './views/AccountsView'
""",
        1,
    )

    s = s.replace(
        "  if (v === 'queue') return <QueueView/>\n",
        """  if (v === 'queue') return <QueueView/>
  if (v === 'publish') return <PublishView/>
  if (v === 'accounts') return <AccountsView/>
""",
        1,
    )

p.write_text(s)
PY

cat > src/components/Sidebar.tsx <<'TS'
import {
  Activity,
  CalendarDays,
  Columns3,
  FileStack,
  House,
  LayoutDashboard,
  ListChecks,
  Send,
  Settings,
  Upload,
  UsersRound,
  CircleHelp,
} from 'lucide-react'

import {
  useAppStore,
} from '../lib/store'

import type {
  View,
} from '../lib/store'

type Item = [
  View,
  typeof House,
  string,
]

const contentItems:
  Item[] = [
    [
      'content',
      FileStack,
      'Biblioteca',
    ],
    [
      'kanban',
      Columns3,
      'Estados',
    ],
    [
      'calendar',
      CalendarDays,
      'Calendario',
    ],
  ]

const publishingItems:
  Item[] = [
    [
      'publish',
      Send,
      'Preparar publicación',
    ],
    [
      'queue',
      ListChecks,
      'Cola',
    ],
  ]

const operationsItems:
  Item[] = [
    [
      'accounts',
      UsersRound,
      'Cuentas',
    ],
    [
      'import',
      Upload,
      'Importar',
    ],
    [
      'activity',
      Activity,
      'Actividad',
    ],
  ]

function NavGroup({
  label,
  items,
}: {
  label: string
  items: Item[]
}) {
  const view =
    useAppStore(
      (s) => s.view,
    )

  const setView =
    useAppStore(
      (s) => s.setView,
    )

  return (
    <div className="nav-group">
      <small className="nav-group-label">
        {label}
      </small>

      {
        items.map(
          ([
            id,
            Icon,
            text,
          ]) => (
            <button
              key={id}
              className={
                view === id
                  ? 'nav-item active'
                  : 'nav-item'
              }
              onClick={() =>
                setView(id)
              }
            >
              <Icon
                size={17}
                strokeWidth={1.8}
              />

              <span>
                {text}
              </span>
            </button>
          ),
        )
      }
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
        <div className="brand-mark">
          A
        </div>

        <div>
          <strong>
            ABRAXAS
          </strong>

          <span>
            Publisher · v1.3
          </span>
        </div>
      </div>

      <div className="brand-switcher">
        <small>
          MARCA
        </small>

        <select
          value={selectedBrand}
          onChange={(e) =>
            setSelectedBrand(
              e.target.value,
            )
          }
        >
          <option value="ALL">
            Todas
          </option>

          {
            brands.map(
              (brand) => (
                <option
                  key={brand.id}
                  value={brand.name}
                >
                  {brand.name}
                </option>
              ),
            )
          }
        </select>
      </div>

      <nav>
        <div className="nav-group">
          <small className="nav-group-label">
            INICIO
          </small>

          <button
            className={
              view === 'home'
                ? 'nav-item active'
                : 'nav-item'
            }
            onClick={() =>
              setView('home')
            }
          >
            <House size={17}/>
            Inicio
          </button>

          <button
            className={
              view === 'today'
                ? 'nav-item active'
                : 'nav-item'
            }
            onClick={() =>
              setView('today')
            }
          >
            <LayoutDashboard size={17}/>
            Hoy
          </button>
        </div>

        <NavGroup
          label="CONTENIDO"
          items={
            contentItems
          }
        />

        <NavGroup
          label="PUBLICACIÓN"
          items={
            publishingItems
          }
        />

        <NavGroup
          label="OPERACIONES"
          items={
            operationsItems
          }
        />
      </nav>

      <div className="sidebar-spacer"/>

      <nav>
        <button
          className={
            view === 'help'
              ? 'nav-item active'
              : 'nav-item'
          }
          onClick={() =>
            setView('help')
          }
        >
          <CircleHelp size={17}/>
          Cómo usar
        </button>

        <button
          className={
            view === 'settings'
              ? 'nav-item active'
              : 'nav-item'
          }
          onClick={() =>
            setView('settings')
          }
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
TS

###############################################################################
# 13. CSS
###############################################################################

section "8/14 · UI / PREVIEWS"

cat >> src/styles.css <<'CSS'

/* ============================================================
   ABRAXAS Publisher V1.3 · Publishing Center
   ============================================================ */

.nav-group{
  display:grid;
  gap:3px;
  margin-bottom:12px;
}

.nav-group-label{
  padding:7px 12px 3px;
  font-size:8px;
  letter-spacing:.12em;
  opacity:.48;
}

.publishing-ready{
  font-weight:600;
}

.account-grid{
  display:grid;
  grid-template-columns:repeat(auto-fill,minmax(260px,1fr));
  gap:10px;
}

.account-card{
  border:1px solid var(--line);
  border-radius:16px;
  padding:14px;
  background:var(--panel);
  position:relative;
  overflow:hidden;
}

.account-card::before{
  content:"";
  position:absolute;
  inset:0 0 auto 0;
  height:3px;
  background:var(--provider-color,#777);
}

.provider-instagram{
  --provider-color:#d9468d;
}

.provider-facebook{
  --provider-color:#1877f2;
}

.provider-linkedin{
  --provider-color:#0a66c2;
}

.provider-youtube{
  --provider-color:#ff0033;
}

.provider-tiktok{
  --provider-color:#22d3d5;
}

.account-provider{
  display:flex;
  justify-content:space-between;
  gap:12px;
}

.account-provider span,
.account-provider strong,
.account-provider small{
  display:block;
}

.account-provider span{
  color:var(--provider-color);
  font-size:9px;
  letter-spacing:.08em;
}

.account-provider strong{
  margin-top:4px;
}

.account-provider small{
  margin-top:3px;
  color:var(--muted);
}

.healthy{
  color:#34a853;
}

.warning{
  color:#d68c13;
}

.account-health{
  margin-top:14px;
  display:grid;
  gap:5px;
}

.account-health span{
  display:flex;
  justify-content:space-between;
  border-top:1px solid var(--line);
  padding-top:5px;
  font-size:9px;
  color:var(--muted);
}

.account-health b{
  color:var(--text);
  font-size:9px;
}

.account-warning{
  margin-top:10px;
  border-radius:10px;
  background:rgba(220,150,30,.12);
  padding:9px;
  font-size:10px;
  display:flex;
  gap:6px;
}

.account-warning.neutral{
  background:rgba(100,110,130,.09);
}

.danger-text-btn{
  border:0;
  background:transparent;
  color:#bc3d39;
  padding:8px 0 0;
  font-size:10px;
  display:flex;
  gap:4px;
  align-items:center;
  cursor:pointer;
}

.account-modal{
  width:min(520px,100%);
  max-height:90vh;
  overflow:auto;
  padding:18px;
  border-radius:18px;
  background:rgba(247,247,249,.97);
  box-shadow:0 30px 90px rgba(0,0,0,.25);
}

.account-modal>header{
  display:flex;
  justify-content:space-between;
  align-items:flex-start;
}

.account-modal>header button{
  background:transparent;
  border:0;
}

.account-modal label{
  display:block;
  font-size:9px;
  color:var(--muted);
  margin:11px 0 5px;
}

.account-mode-grid{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
}

.choice-card{
  text-align:left;
  border:1px solid var(--line);
  background:rgba(255,255,255,.5);
  border-radius:12px;
  padding:12px;
}

.choice-card.active{
  border-color:#4a73d8;
  box-shadow:0 0 0 2px rgba(74,115,216,.12);
}

.choice-card strong,
.choice-card span{
  display:block;
}

.choice-card span{
  color:var(--muted);
  font-size:9px;
  margin-top:4px;
}

.publish-page{
  --context-color:#697182;
}

.theme-instagram{
  --context-color:#d9468d;
}

.theme-facebook{
  --context-color:#1877f2;
}

.theme-linkedin{
  --context-color:#0a66c2;
}

.theme-youtube{
  --context-color:#ff0033;
}

.theme-tiktok{
  --context-color:#16c7c9;
}

.publish-header{
  border-bottom:2px solid var(--context-color);
}

.publish-step-number{
  width:48px;
  height:48px;
  border-radius:50%;
  display:grid;
  place-items:center;
  background:var(--context-color);
  color:#fff;
  font-weight:700;
}

.wizard-steps{
  display:grid;
  grid-template-columns:repeat(5,1fr);
  gap:4px;
  margin-bottom:14px;
}

.wizard-step{
  padding:8px;
  border-radius:10px;
  background:rgba(0,0,0,.035);
  font-size:9px;
  color:var(--muted);
  display:flex;
  gap:5px;
  align-items:center;
}

.wizard-step span{
  width:18px;
  height:18px;
  border-radius:50%;
  display:grid;
  place-items:center;
  background:rgba(0,0,0,.08);
  font-size:8px;
}

.wizard-step.active{
  color:var(--text);
  outline:1px solid var(--context-color);
}

.wizard-step.active span,
.wizard-step.done span{
  color:#fff;
  background:var(--context-color);
}

.publish-stage{
  min-height:420px;
}

.stage-title{
  display:flex;
  justify-content:space-between;
  align-items:flex-start;
  margin-bottom:12px;
}

.stage-title h2,
.stage-title p{
  margin:0;
}

.stage-title p{
  color:var(--muted);
  margin-top:3px;
  font-size:10px;
}

.publish-selection-list{
  display:grid;
  gap:5px;
}

.publish-select-row{
  display:grid;
  grid-template-columns:auto 1fr auto;
  gap:10px;
  align-items:center;
  border:1px solid var(--line);
  border-radius:11px;
  padding:10px;
  background:var(--panel);
}

.publish-select-row.selected{
  border-color:var(--context-color);
}

.publish-select-row strong,
.publish-select-row small,
.publish-select-row span{
  display:block;
}

.publish-select-row small,
.publish-select-row span{
  color:var(--muted);
  font-size:9px;
}

.destination-list{
  display:grid;
  gap:7px;
}

.destination-card{
  --provider-color:#777;
  border:1px solid var(--line);
  border-left:4px solid var(--provider-color);
  border-radius:12px;
  display:grid;
  grid-template-columns:minmax(0,1fr) 220px auto;
  align-items:center;
  gap:10px;
  padding:10px;
  background:var(--panel);
}

.destination-card strong,
.destination-card span,
.destination-card small{
  display:block;
}

.destination-card small{
  color:var(--provider-color);
  text-transform:uppercase;
  font-size:8px;
}

.destination-card span{
  color:var(--muted);
  font-size:9px;
}

.external-method-row{
  margin-top:12px;
  display:flex;
  justify-content:flex-end;
  align-items:center;
  gap:8px;
  font-size:10px;
}

.preflight-grid{
  display:grid;
  grid-template-columns:repeat(auto-fit,minmax(260px,1fr));
  gap:9px;
}

.preflight-card{
  border:1px solid var(--line);
  border-radius:14px;
  background:var(--panel);
  padding:12px;
}

.preflight-card.ready{
  border-color:rgba(52,168,83,.45);
}

.preflight-card.blocked{
  border-color:rgba(210,70,60,.4);
}

.preflight-card header{
  display:flex;
  justify-content:space-between;
  align-items:center;
  margin-bottom:8px;
}

.preflight-card header strong,
.preflight-card header small{
  display:block;
}

.preflight-card header small{
  color:var(--muted);
}

.preflight-check{
  display:grid;
  grid-template-columns:18px 1fr;
  padding:6px 0;
  border-top:1px solid var(--line);
  gap:5px;
}

.preflight-check strong,
.preflight-check small{
  display:block;
}

.preflight-check strong{
  font-size:10px;
}

.preflight-check small{
  color:var(--muted);
  font-size:8px;
}

.preflight-check.ok>span{
  color:#34a853;
}

.preflight-check.fail>span{
  color:#d54a43;
}

.preview-stage{
  display:grid;
  grid-template-columns:190px minmax(0,1fr);
  gap:12px;
}

.preview-target-list{
  display:grid;
  align-content:start;
  gap:5px;
}

.preview-target-list button{
  text-align:left;
  border:1px solid var(--line);
  border-radius:10px;
  background:var(--panel);
  padding:9px;
}

.preview-target-list button.active{
  border-color:var(--context-color);
}

.preview-target-list strong,
.preview-target-list span{
  display:block;
}

.preview-target-list span{
  color:var(--muted);
  font-size:9px;
  margin-top:2px;
}

.preview-workbench{
  min-width:0;
  display:grid;
  justify-items:center;
}

.preview-toolbar{
  width:min(500px,100%);
  display:flex;
  justify-content:space-between;
  align-items:center;
  margin-bottom:8px;
}

.preview-toolbar h2{
  margin:0;
}

.preview-type-badge{
  border-radius:999px;
  padding:5px 8px;
  background:rgba(0,0,0,.06);
  font-size:9px;
}

.network-preview{
  width:min(470px,100%);
  border-radius:18px;
  overflow:hidden;
  background:#fff;
  color:#171717;
  box-shadow:0 15px 50px rgba(0,0,0,.12);
  border:1px solid rgba(0,0,0,.12);
}

.network-top{
  height:45px;
  display:flex;
  align-items:center;
  padding:0 14px;
  font-weight:700;
  border-bottom:1px solid rgba(0,0,0,.1);
}

.instagram .network-top{
  background:linear-gradient(90deg,#833ab4,#fd1d1d,#fcb045);
  color:#fff;
}

.linkedin .network-top{
  background:#0a66c2;
  color:#fff;
}

.youtube .network-top{
  color:#ff0033;
}

.facebook .network-top{
  background:#1877f2;
  color:#fff;
}

.tiktok .network-top{
  background:#111;
  color:#fff;
}

.ig-author,
.linkedin-author{
  display:grid;
  grid-template-columns:34px 1fr auto;
  gap:8px;
  align-items:center;
  padding:10px;
}

.linkedin-author strong,
.linkedin-author span{
  display:block;
}

.linkedin-author span{
  color:#666;
  font-size:9px;
}

.fake-avatar{
  width:32px;
  height:32px;
  display:grid;
  place-items:center;
  border-radius:50%;
  background:#222;
  color:#fff;
}

.social-media{
  width:100%;
  display:block;
  max-height:620px;
  object-fit:contain;
  background:#050505;
}

.social-media-empty{
  height:280px;
  display:grid;
  place-items:center;
  background:#111;
  color:#777;
}

.network-actions{
  display:flex;
  gap:13px;
  padding:10px 12px;
}

.network-actions.spread{
  justify-content:space-around;
  border-top:1px solid #ddd;
}

.network-actions.spread span{
  display:flex;
  gap:4px;
  align-items:center;
  font-size:10px;
}

.ig-copy,
.network-copy{
  padding:0 12px 12px;
  font-size:11px;
  line-height:1.45;
}

.carousel-dots{
  display:flex;
  justify-content:center;
  gap:3px;
  padding-bottom:9px;
}

.carousel-dots span{
  width:5px;
  height:5px;
  border-radius:50%;
  background:#bbb;
}

.carousel-dots span.active{
  background:#3797f0;
}

.vertical-stage{
  position:relative;
  background:#000;
  min-height:600px;
}

.tiktok .social-media{
  min-height:600px;
  object-fit:contain;
}

.vertical-caption{
  position:absolute;
  left:12px;
  right:60px;
  bottom:18px;
  color:#fff;
  text-shadow:0 1px 3px #000;
}

.vertical-caption p{
  font-size:11px;
}

.vertical-actions{
  position:absolute;
  right:12px;
  bottom:30px;
  display:grid;
  gap:18px;
  color:#fff;
}

.youtube-player{
  position:relative;
  background:#000;
}

.player-center{
  position:absolute;
  inset:0;
  display:grid;
  place-items:center;
  pointer-events:none;
  color:#fff;
}

.youtube-meta{
  padding:12px;
}

.youtube-meta strong,
.youtube-meta span{
  display:block;
}

.youtube-meta span{
  color:#666;
  margin-top:4px;
}

.short-preview{
  max-width:330px;
}

.confirmation-stage{
  max-width:720px;
  margin:0 auto;
}

.confirmation-summary{
  display:grid;
  gap:5px;
  margin:16px 0;
}

.confirmation-summary>div{
  border:1px solid var(--line);
  border-radius:10px;
  display:grid;
  grid-template-columns:100px 1fr auto;
  gap:8px;
  padding:9px;
}

.confirmation-summary small{
  color:var(--muted);
}

.publish-confirm-btn{
  width:100%;
  min-height:52px;
  border:0;
  border-radius:14px;
  background:#17253c;
  color:#fff;
  display:flex;
  justify-content:center;
  align-items:center;
  gap:8px;
  font-weight:700;
  cursor:pointer;
}

.publish-confirm-btn:disabled{
  opacity:.35;
  cursor:not-allowed;
}

.wizard-footer{
  position:sticky;
  bottom:0;
  z-index:10;
  margin-top:16px;
  border-top:1px solid var(--line);
  background:rgba(244,244,246,.9);
  backdrop-filter:blur(18px);
  min-height:58px;
  display:grid;
  grid-template-columns:auto 1fr auto;
  gap:12px;
  align-items:center;
  padding:8px;
}

.wizard-footer>span{
  text-align:center;
  font-size:9px;
  color:var(--muted);
}

.queue-summary{
  display:grid;
  grid-template-columns:repeat(auto-fit,minmax(110px,1fr));
  gap:5px;
  margin-bottom:10px;
}

.queue-summary>div{
  border:1px solid var(--line);
  background:var(--panel);
  border-radius:10px;
  padding:8px;
}

.queue-summary strong,
.queue-summary span{
  display:block;
}

.queue-summary strong{
  font-size:18px;
}

.queue-summary span{
  color:var(--muted);
  font-size:7px;
  margin-top:2px;
  word-break:break-word;
}

.job-list{
  padding:0 12px;
}

.job-row{
  width:100%;
  display:grid;
  grid-template-columns:35px minmax(0,1fr) auto;
  align-items:center;
  gap:9px;
  border-bottom:1px solid var(--line);
  padding:9px 0;
  background:transparent;
  text-align:left;
}

.job-icon{
  width:32px;
  height:32px;
  display:grid;
  place-items:center;
  border-radius:9px;
  background:rgba(0,0,0,.05);
}

.job-icon svg{
  width:15px;
}

.status-FAILED{
  color:#c93b36;
}

.status-PUBLISHED,
.status-SCHEDULED_REMOTE{
  color:#30904a;
}

.job-main small,
.job-main strong,
.job-main span,
.job-state b,
.job-state small{
  display:block;
}

.job-main small{
  color:var(--muted);
  font-size:8px;
}

.job-main span,
.job-state small{
  color:var(--muted);
  font-size:9px;
}

.job-state{
  text-align:right;
}

.job-state b{
  font-size:9px;
}

@media(max-width:800px){
  .wizard-steps{
    grid-template-columns:repeat(5,minmax(90px,1fr));
    overflow:auto;
  }

  .preview-stage{
    grid-template-columns:1fr;
  }

  .preview-target-list{
    display:flex;
    overflow:auto;
  }

  .preview-target-list button{
    min-width:150px;
  }

  .destination-card{
    grid-template-columns:1fr;
  }

  .account-mode-grid{
    grid-template-columns:1fr;
  }
}

@media(prefers-color-scheme:dark){
  .account-modal{
    background:rgba(31,32,36,.97);
  }

  .network-preview{
    box-shadow:0 15px 50px rgba(0,0,0,.4);
  }

  .wizard-footer{
    background:rgba(27,28,31,.92);
  }
}
CSS

###############################################################################
# 14. DOCUMENTATION
###############################################################################

section "9/14 · DOCUMENTATION"

cat > docs/V13_PUBLISHING_CENTER.md <<'MD'
# ABRAXAS Publisher V1.3 · Publishing Center

## Objetivo

V1.3 transforma Publisher de planner editorial a centro operacional de publicación.

## Flujo

IMPORT
→ EDITORIAL REVIEW
→ LISTO_POR_PROGRAMAR
→ PRECALENDARIZED
→ PUBLISHING WIZARD
→ PREFLIGHT
→ PLATFORM PREVIEW
→ QUEUED
→ PROVIDER ADAPTER
→ VERIFY
→ SCHEDULED_REMOTE / PUBLISHED

## Estados externos

Cuando una publicación se realiza fuera de Publisher:

SCHEDULED_EXTERNAL

Ejemplos:

- Edits
- Meta Business Suite
- YouTube Studio
- LinkedIn
- TikTok
- otro scheduler

Nunca usar SCHEDULED_REMOTE para una acción que Publisher no verificó.

## Accounts

Estados:

NEEDS_AUTH
CONNECTED
EXTERNAL_ONLY
ERROR

Auth:

PENDING
AUTHORIZED
EXPIRED
REVOKED
NOT_REQUIRED

No se considera una cuenta CONNECTED sólo por guardar su nombre.

## Provider Strategies

YouTube:
NATIVE_OR_LOCAL

LinkedIn:
LOCAL_DISPATCH

TikTok:
LOCAL_DISPATCH

Instagram:
LOCAL_DISPATCH

Facebook:
PROVIDER_OR_LOCAL

Las capabilities deben validarse contra la cuenta real antes de publicar.

## OAuth

V1.3 incluye el Accounts Center y contratos de provider.

OAuth real sólo se marca autorizado después de:

1. OAuth provider.
2. token válido.
3. scopes.
4. account identity.
5. capability verification.

Tokens y secretos nunca deben guardarse en frontend ni Git.

## Queue

Los publication_jobs tienen idempotency_key.

Esto evita duplicados causados por reintentos.

Estados futuros:

REVIEW_REQUIRED
QUEUED
WAITING
DISPATCHING
UPLOADING
PROCESSING_REMOTE
VERIFYING
SCHEDULED_REMOTE
SCHEDULED_EXTERNAL
PUBLISHED
FAILED
CANCELLED

## Platform Preview Engine

Mockups contextuales:

- Instagram
- Facebook
- LinkedIn
- YouTube
- TikTok

El preview es editorial y visual.
No afirma reproducir píxel por píxel versiones futuras de las apps externas.

## Seguridad

V1.3 no incorpora secretos en el repo.

V1.3 no marca como publicada una publicación sin remote verification.

V1.3 no usa Undo para revertir una acción remota.
MD

cat >> CHANGELOG.md <<'MD'

## 0.4.0 · Publisher V1.3

### Publishing Center

- Accounts Center.
- Provider capability registry.
- Publishing wizard.
- Selection basket.
- Destination/account selection.
- Preflight.
- Platform mockups.
- Persistent publication jobs.
- Idempotency keys.
- Queue V1.3.
- SCHEDULED_EXTERNAL.
- External scheduler provenance.
- Publishing-specific navigation.
- Contextual network themes.

### Preserved

- V1.2 SQLite data.
- brands.
- content.
- calendar.
- notes.
- Drive.
- activity.
- publisherctl.
- MCP.
- existing scheduling.

### Safety

No provider is considered connected without verified auth.
No remote publishing is claimed without remote verification.
MD

###############################################################################
# 15. QA
###############################################################################

section "10/14 · NPM"

npm install

npm run check \
  || fail "TypeScript falló."

npm run build \
  || fail "Vite falló."

echo "✓ frontend"

###############################################################################
# 16. RUST
###############################################################################

section "11/14 · RUST"

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

echo "✓ rust"

###############################################################################
# 17. TAURI BUILD
###############################################################################

section "12/14 · TAURI BUILD"

npm run tauri:build \
  || fail "Tauri build falló."

NEW_APP="$WORKTREE/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"

if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(
    find \
      "$WORKTREE/src-tauri/target/release/bundle" \
      -type d \
      -name "*.app" \
      -print \
      -quit
  )"
fi

[ -d "$NEW_APP" ] \
  || fail "No se encontró .app"

echo "✓ $NEW_APP"

###############################################################################
# 18. INSTALL SAFE
###############################################################################

section "13/14 · INSTALL"

APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP_APP="$HOME/Applications/ABRAXAS Publisher.V12.backup.$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.V13.$STAMP.app"

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

  fail "Instalación falló."
fi

echo "✓ V1.3 instalada"

###############################################################################
# 19. COMMIT / SNAPSHOTS / PUSH
###############################################################################

section "14/14 · RELEASE"

git add -A

git commit \
  -m "ABRAXAS Publisher V1.3 Publishing Center"

V13_SHA="$(git rev-parse HEAD)"

git tag \
  -f \
  publisher-v1.3

RELEASE_DIR="$SOURCE/releases/v1.3"

mkdir -p "$RELEASE_DIR"

###############################################################################
# FULL SNAPSHOT
###############################################################################

FULL_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3_FULL.zip"

rm -f "$FULL_ZIP"

git archive \
  --format=zip \
  --output="$FULL_ZIP" \
  HEAD

###############################################################################
# PATCH SNAPSHOT
###############################################################################

PATCH_ROOT="$(mktemp -d)"
PATCH_FILES="$PATCH_ROOT/files"

mkdir -p "$PATCH_FILES"

git diff \
  --name-only \
  "$BASE_SHA" \
  "$V13_SHA" \
  > "$PATCH_ROOT/FILES.txt"

while IFS= read -r FILE
do
  [ -n "$FILE" ] || continue
  [ -e "$FILE" ] || continue

  mkdir -p \
    "$PATCH_FILES/$(dirname "$FILE")"

  cp -R \
    "$FILE" \
    "$PATCH_FILES/$FILE"
done < "$PATCH_ROOT/FILES.txt"

cat > "$PATCH_ROOT/PATCH_MANIFEST.json" <<EOF
{
  "app": "ABRAXAS Publisher",
  "version": "1.3",
  "packageVersion": "0.4.0",
  "baseCommit": "$BASE_SHA",
  "releaseCommit": "$V13_SHA",
  "branch": "$BRANCH",
  "preserves": [
    "SQLite user data",
    "Drive configuration",
    "brands",
    "calendar",
    "notes",
    "activity"
  ],
  "features": [
    "Accounts Center",
    "Publishing Wizard",
    "Platform Preview Engine",
    "Persistent Publication Jobs",
    "Preflight",
    "SCHEDULED_EXTERNAL",
    "Capability Registry"
  ]
}
EOF

cat > "$PATCH_ROOT/APPLY.txt" <<'EOF'
ABRAXAS Publisher V1.3

Preferir actualizar por Git:

git fetch origin
git switch v1.3-publishing-center

Luego:

npm install
npm run check
cargo check --manifest-path src-tauri/Cargo.toml
npm run tauri:build
EOF

PATCH_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3_PATCH.zip"

rm -f "$PATCH_ZIP"

ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$PATCH_ROOT" \
  "$PATCH_ZIP"

rm -rf "$PATCH_ROOT"

###############################################################################
# PUSH
###############################################################################

git push \
  -u origin \
  "$BRANCH"

git push \
  origin \
  publisher-v1.3 \
  --force

PR_URL="$(
  gh pr list \
    --repo LordJeferies/abraxas-publisher \
    --head "$BRANCH" \
    --base main \
    --json url \
    --jq '.[0].url' \
    2>/dev/null \
    || true
)"

if [ -z "$PR_URL" ]; then
  PR_URL="$(
    gh pr create \
      --repo LordJeferies/abraxas-publisher \
      --head "$BRANCH" \
      --base main \
      --title "ABRAXAS Publisher V1.3 · Publishing Center" \
      --body "Publishing Center: Accounts, review wizard, platform previews, persistent jobs, preflight, queue and external scheduling provenance. Real provider publishing remains capability/auth gated."
  )"
fi

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.3 · CREADA"
echo "=============================================================="
echo
echo "App:"
echo "  $APP"
echo
echo "Backup V1.2:"
echo "  $BACKUP_APP"
echo
echo "Branch:"
echo "  $BRANCH"
echo
echo "Commit:"
echo "  $V13_SHA"
echo
echo "PR:"
echo "  ${PR_URL:-No disponible}"
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
echo "V1.3 incluye:"
echo "  ✓ Accounts Center"
echo "  ✓ Publishing Wizard"
echo "  ✓ selección de publicaciones"
echo "  ✓ preflight"
echo "  ✓ previews Instagram/Facebook/LinkedIn/YouTube/TikTok"
echo "  ✓ color contextual por plataforma"
echo "  ✓ queue persistente"
echo "  ✓ idempotency keys"
echo "  ✓ SCHEDULED_EXTERNAL"
echo "  ✓ Edits / Studio / Business Suite / etc."
echo "  ✓ capability registry"
echo
echo "No se finge:"
echo "  ✕ OAuth no realizado"
echo "  ✕ publicación no verificada"
echo
echo "La siguiente capa es activar adapters OAuth reales"
echo "cuenta por cuenta una vez configuradas las apps de cada provider."
echo

open "$APP" || true
