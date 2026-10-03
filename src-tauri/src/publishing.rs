use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::Path;

fn open(path: &Path) -> Result<Connection, String> {
    Connection::open(path).map_err(|e| e.to_string())
}

fn hash_id(value: &str) -> String {
    let mut h = Sha256::new();

    h.update(value.as_bytes());

    hex::encode(h.finalize())[..24].to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
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

#[derive(Debug, Clone, Serialize, Deserialize)]
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

#[derive(Debug, Clone, Serialize, Deserialize)]
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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EnqueueInput {
    pub target_id: String,
    pub account_id: Option<String>,
    pub mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PreflightCheck {
    pub key: String,
    pub label: String,
    pub ok: bool,
    pub blocking: bool,
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PreflightReport {
    pub target_id: String,
    pub account_id: Option<String>,
    pub provider: String,
    pub ready: bool,
    pub checks: Vec<PreflightCheck>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
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

pub fn init(db: &Path) -> Result<(), String> {
    let conn = open(db)?;

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
    .map_err(|e| e.to_string())?;

    Ok(())
}

pub fn list_accounts(db: &Path) -> Result<Vec<ConnectedAccount>, String> {
    let conn = open(db)?;

    let mut stmt = conn
        .prepare(
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
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |r| {
            Ok(ConnectedAccount {
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
            })
        })
        .map_err(|e| e.to_string())?;

    let result = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    Ok(result)
}

pub fn save_account(db: &Path, input: SaveAccountInput) -> Result<ConnectedAccount, String> {
    let conn = open(db)?;

    let now = Utc::now().to_rfc3339();

    let id = input.id.unwrap_or_else(|| {
        format!(
            "acct-{}",
            hash_id(&format!(
                "{}:{}:{}:{}",
                input.provider,
                input.brand.clone().unwrap_or_default(),
                input.display_name,
                now
            ),),
        )
    });

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
    .map_err(|e| e.to_string())?;

    list_accounts(db)?
        .into_iter()
        .find(|x| x.id == id)
        .ok_or_else(|| "No se pudo releer la cuenta.".to_string())
}

pub fn remove_account(db: &Path, account_id: &str) -> Result<bool, String> {
    let conn = open(db)?;

    let count = conn
        .execute(
            "DELETE FROM connected_accounts WHERE id=?1",
            params![account_id],
        )
        .map_err(|e| e.to_string())?;

    Ok(count > 0)
}

pub fn list_jobs(db: &Path) -> Result<Vec<PublishJob>, String> {
    let conn = open(db)?;

    let mut stmt = conn
        .prepare(
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
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |r| {
            Ok(PublishJob {
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
            })
        })
        .map_err(|e| e.to_string())?;

    let result = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    Ok(result)
}

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
        Option<String>,
    )> = conn
        .query_row(
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
            params![target_id],
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
        .map_err(|e| e.to_string())?;

    let Some((content_id, provider, target_status, scheduled_at, editorial_status, _fingerprint)) =
        target
    else {
        return Err("Destino no encontrado.".into());
    };

    let media_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM media_assets WHERE content_id=?1",
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

    let mut checks = Vec::new();

    let editorial_ok =
        editorial_status == "LISTO_POR_PROGRAMAR" || editorial_status == "PROGRAMADO";

    checks.push(PreflightCheck {
        key: "editorial".into(),
        label: "Contenido aprobado editorialmente".into(),
        ok: editorial_ok,
        blocking: true,
        detail: Some(editorial_status.clone()),
    });

    checks.push(PreflightCheck {
        key: "media".into(),
        label: "Medio disponible".into(),
        ok: media_count > 0,
        blocking: true,
        detail: Some(format!("{media_count} asset(s)")),
    });

    checks.push(PreflightCheck {
        key: "schedule".into(),
        label: "Fecha/hora definida".into(),
        ok: scheduled_at.is_some(),
        blocking: true,
        detail: scheduled_at.clone(),
    });

    checks.push(PreflightCheck {
        key: "remote-lock".into(),
        label: "Destino editable".into(),
        ok: target_status != "SCHEDULED_REMOTE" && target_status != "PUBLISHED",
        blocking: true,
        detail: Some(target_status.clone()),
    });

    let (account_ok, account_detail) = match account {
        Some((account_provider, connection_status, auth_state)) => {
            let ok = account_provider == provider
                && connection_status == "CONNECTED"
                && auth_state == "AUTHORIZED";

            (
                ok,
                Some(format!(
                    "{} · {} · {}",
                    account_provider, connection_status, auth_state
                )),
            )
        }

        None => (false, Some("Sin cuenta API conectada".into())),
    };

    checks.push(PreflightCheck {
        key: "account".into(),
        label: "Cuenta y autorización válidas".into(),
        ok: account_ok,
        blocking: true,
        detail: account_detail,
    });

    let ready = checks.iter().filter(|x| x.blocking).all(|x| x.ok);

    Ok(PreflightReport {
        target_id: target_id.into(),
        account_id: account_id.map(|x| x.into()),
        provider,
        ready,
        checks,
    })
}

pub fn enqueue(db: &Path, inputs: &[EnqueueInput]) -> Result<Vec<PublishJob>, String> {
    let conn = open(db)?;

    let now = Utc::now().to_rfc3339();

    for input in inputs {
        let target: Option<(String, String, Option<String>, Option<String>)> = conn
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
                params![input.target_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
            )
            .optional()
            .map_err(|e| e.to_string())?;

        let Some((content_id, provider, scheduled_for, fingerprint)) = target else {
            continue;
        };

        let identity = format!(
            "{}:{}:{}:{}:{}",
            input.target_id,
            input.account_id.clone().unwrap_or_default(),
            scheduled_for.clone().unwrap_or_default(),
            fingerprint.unwrap_or_default(),
            input.mode,
        );

        let idempotency_key = hash_id(&identity);

        let id = format!("job-{}", idempotency_key);

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
        .map_err(|e| e.to_string())?;
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
) -> Result<ExternalPublication, String> {
    let conn = open(db)?;

    let provider: String = conn
        .query_row(
            "SELECT platform FROM publication_targets WHERE id=?1",
            params![target_id],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    let now = Utc::now().to_rfc3339();

    let id = format!(
        "external-{}",
        hash_id(&format!("{}:{}:{}", target_id, method, now),),
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
    .map_err(|e| e.to_string())?;

    conn.execute(
        r#"
        UPDATE publication_targets
        SET
          status='SCHEDULED_EXTERNAL',
          scheduled_at=COALESCE(?2,scheduled_at),
          schedule_source='EXTERNAL'
        WHERE id=?1
        "#,
        params![target_id, scheduled_at,],
    )
    .map_err(|e| e.to_string())?;

    Ok(ExternalPublication {
        id,
        target_id: target_id.into(),
        provider,
        method: method.into(),
        scheduled_at: scheduled_at.map(|x| x.into()),
        remote_url: remote_url.map(|x| x.into()),
        note: note.map(|x| x.into()),
        created_at: now,
    })
}
