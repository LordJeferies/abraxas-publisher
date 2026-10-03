use crate::models::*;
use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Path, PathBuf},
};

fn hash_id(value: &str) -> String {
    let mut h = Sha256::new();
    h.update(value.as_bytes());
    hex::encode(h.finalize())[..20].to_string()
}

fn open(path: &Path) -> Result<Connection, String> {
    Connection::open(path).map_err(|e| e.to_string())
}

fn has_column(conn: &Connection, table: &str, column: &str) -> Result<bool, String> {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table})"))
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |r| r.get::<_, String>(1))
        .map_err(|e| e.to_string())?;

    for row in rows {
        if row.map_err(|e| e.to_string())? == column {
            return Ok(true);
        }
    }

    Ok(false)
}

fn add_column_if_missing(
    conn: &Connection,
    table: &str,
    column: &str,
    ddl: &str,
) -> Result<(), String> {
    if !has_column(conn, table, column)? {
        conn.execute_batch(ddl).map_err(|e| e.to_string())?;
    }

    Ok(())
}

pub fn init(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let conn = open(path)?;

    conn.execute_batch(
        r#"
        PRAGMA journal_mode=WAL;
        PRAGMA foreign_keys=ON;

        CREATE TABLE IF NOT EXISTS contents(
          id TEXT PRIMARY KEY,
          folder_path TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          client TEXT,
          content_type TEXT NOT NULL,
          status TEXT NOT NULL,
          imported_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS media_assets(
          id TEXT PRIMARY KEY,
          content_id TEXT NOT NULL,
          path TEXT NOT NULL,
          kind TEXT NOT NULL,
          size_bytes INTEGER NOT NULL,
          duration_seconds REAL,
          FOREIGN KEY(content_id) REFERENCES contents(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS publication_targets(
          id TEXT PRIMARY KEY,
          content_id TEXT NOT NULL,
          platform TEXT NOT NULL,
          account TEXT,
          status TEXT NOT NULL,
          scheduled_at TEXT,
          source_txt TEXT,
          copy TEXT,
          FOREIGN KEY(content_id) REFERENCES contents(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS validation_issues(
          id TEXT PRIMARY KEY,
          content_id TEXT NOT NULL,
          severity TEXT NOT NULL,
          message TEXT NOT NULL,
          FOREIGN KEY(content_id) REFERENCES contents(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS correction_notes(
          id TEXT PRIMARY KEY,
          content_id TEXT NOT NULL,
          body TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY(content_id) REFERENCES contents(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS brands(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE,
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS settings(
          key TEXT PRIMARY KEY,
          value TEXT
        );

        CREATE TABLE IF NOT EXISTS content_sources(
          content_id TEXT PRIMARY KEY,
          source_kind TEXT NOT NULL,
          source_ref TEXT,
          FOREIGN KEY(content_id) REFERENCES contents(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS audit_events(
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          id TEXT NOT NULL UNIQUE,
          action TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          label TEXT NOT NULL,
          before_json TEXT,
          after_json TEXT,
          reversible INTEGER NOT NULL DEFAULT 0,
          remote INTEGER NOT NULL DEFAULT 0,
          undone INTEGER NOT NULL DEFAULT 0,
          undone_at TEXT,
          created_at TEXT NOT NULL
        );
        "#,
    )
    .map_err(|e| e.to_string())?;

    add_column_if_missing(
        &conn,
        "contents",
        "workflow_status",
        "ALTER TABLE contents ADD COLUMN workflow_status TEXT NOT NULL DEFAULT 'EN_CONFIRMACION';",
    )?;

    add_column_if_missing(
        &conn,
        "contents",
        "source_fingerprint",
        "ALTER TABLE contents ADD COLUMN source_fingerprint TEXT;",
    )?;

    add_column_if_missing(
        &conn,
        "contents",
        "version",
        "ALTER TABLE contents ADD COLUMN version INTEGER NOT NULL DEFAULT 1;",
    )?;

    add_column_if_missing(
        &conn,
        "contents",
        "refreshed_at",
        "ALTER TABLE contents ADD COLUMN refreshed_at TEXT;",
    )?;

    add_column_if_missing(
        &conn,
        "publication_targets",
        "schedule_source",
        "ALTER TABLE publication_targets ADD COLUMN schedule_source TEXT;",
    )?;

    add_column_if_missing(
        &conn,
        "media_assets",
        "sha256",
        "ALTER TABLE media_assets ADD COLUMN sha256 TEXT;",
    )?;

    add_column_if_missing(
        &conn,
        "media_assets",
        "modified_at",
        "ALTER TABLE media_assets ADD COLUMN modified_at TEXT;",
    )?;

    if list_brands(path)?.is_empty() {
        let _ = create_brand(path, "JOC");
    }

    Ok(())
}

pub fn create_brand(db: &Path, name: &str) -> Result<Brand, String> {
    let name = name.trim();

    if name.is_empty() {
        return Err("El nombre de la marca no puede estar vacío.".into());
    }

    let conn = open(db)?;
    let id = format!("brand-{}", hash_id(&name.to_ascii_lowercase()));
    let now = Utc::now().to_rfc3339();

    conn.execute(
        "INSERT OR IGNORE INTO brands(id,name,created_at) VALUES(?1,?2,?3)",
        params![id, name, now],
    )
    .map_err(|e| e.to_string())?;

    conn.query_row(
        "SELECT id,name,created_at FROM brands WHERE name=?1 COLLATE NOCASE",
        params![name],
        |r| {
            Ok(Brand {
                id: r.get(0)?,
                name: r.get(1)?,
                created_at: r.get(2)?,
            })
        },
    )
    .map_err(|e| e.to_string())
}

pub fn list_brands(db: &Path) -> Result<Vec<Brand>, String> {
    let conn = open(db)?;

    let mut stmt = conn
        .prepare(
            "SELECT id,name,created_at
             FROM brands
             ORDER BY name COLLATE NOCASE",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |r| {
            Ok(Brand {
                id: r.get(0)?,
                name: r.get(1)?,
                created_at: r.get(2)?,
            })
        })
        .map_err(|e| e.to_string())?;

    let result = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    Ok(result)
}

pub fn set_setting(db: &Path, key: &str, value: &str) -> Result<bool, String> {
    let conn = open(db)?;

    conn.execute(
        "INSERT INTO settings(key,value) VALUES(?1,?2)
         ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        params![key, value],
    )
    .map_err(|e| e.to_string())?;

    Ok(true)
}

pub fn get_setting(db: &Path, key: &str) -> Result<Option<String>, String> {
    let conn = open(db)?;

    conn.query_row(
        "SELECT value FROM settings WHERE key=?1",
        params![key],
        |r| r.get(0),
    )
    .optional()
    .map_err(|e| e.to_string())
}

fn latest_note(conn: &Connection, content_id: &str) -> Result<Option<CorrectionNote>, String> {
    conn.query_row(
        "SELECT id,body,created_at
         FROM correction_notes
         WHERE content_id=?1
         ORDER BY created_at DESC
         LIMIT 1",
        params![content_id],
        |r| {
            Ok(CorrectionNote {
                id: r.get(0)?,
                body: r.get(1)?,
                created_at: r.get(2)?,
            })
        },
    )
    .optional()
    .map_err(|e| e.to_string())
}

fn source_for(
    conn: &Connection,
    content_id: &str,
    folder: &str,
) -> Result<(String, Option<String>), String> {
    conn.query_row(
        "SELECT source_kind,source_ref
         FROM content_sources
         WHERE content_id=?1",
        params![content_id],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )
    .optional()
    .map_err(|e| e.to_string())
    .map(|x| x.unwrap_or_else(|| ("local".into(), Some(folder.into()))))
}

pub fn get_content_source(db: &Path, content_id: &str) -> Result<(String, Option<String>), String> {
    let conn = open(db)?;

    let folder: String = conn
        .query_row(
            "SELECT folder_path FROM contents WHERE id=?1",
            params![content_id],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    source_for(&conn, content_id, &folder)
}

pub fn upsert_scan(db: &Path, items: &[ContentItem]) -> Result<(), String> {
    let mut conn = open(db)?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;

    for item in items {
        let existing: Option<(String, Option<String>, i64)> = tx
            .query_row(
                "SELECT workflow_status,source_fingerprint,version
                 FROM contents
                 WHERE id=?1",
                params![item.id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()
            .map_err(|e| e.to_string())?;

        let workflow = existing
            .as_ref()
            .map(|x| x.0.clone())
            .unwrap_or_else(|| item.status.clone());

        let version = match &existing {
            Some((_, old_fp, v)) if old_fp != &item.source_fingerprint => v + 1,
            Some((_, _, v)) => *v,
            None => 1,
        };

        tx.execute(
            r#"
            INSERT INTO contents(
              id,folder_path,title,client,content_type,status,
              workflow_status,source_fingerprint,version,refreshed_at,imported_at
            )
            VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,datetime('now'))
            ON CONFLICT(id) DO UPDATE SET
              folder_path=excluded.folder_path,
              title=excluded.title,
              client=excluded.client,
              content_type=excluded.content_type,
              status=excluded.status,
              workflow_status=?7,
              source_fingerprint=excluded.source_fingerprint,
              version=?9,
              refreshed_at=excluded.refreshed_at,
              imported_at=excluded.imported_at
            "#,
            params![
                item.id,
                item.folder_path,
                item.title,
                item.client,
                item.content_type,
                item.validation_status,
                workflow,
                item.source_fingerprint,
                version,
                item.refreshed_at,
            ],
        )
        .map_err(|e| e.to_string())?;

        tx.execute(
            r#"
            INSERT INTO content_sources(content_id,source_kind,source_ref)
            VALUES(?1,?2,?3)
            ON CONFLICT(content_id) DO UPDATE SET
              source_kind=excluded.source_kind,
              source_ref=excluded.source_ref
            "#,
            params![item.id, item.source_kind, item.source_ref],
        )
        .map_err(|e| e.to_string())?;

        let mut old_targets = std::collections::HashMap::new();

        {
            let mut stmt = tx
                .prepare(
                    "SELECT platform,scheduled_at,status,schedule_source
                     FROM publication_targets
                     WHERE content_id=?1",
                )
                .map_err(|e| e.to_string())?;

            let rows = stmt
                .query_map(params![item.id], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, Option<String>>(1)?,
                        r.get::<_, String>(2)?,
                        r.get::<_, Option<String>>(3)?,
                    ))
                })
                .map_err(|e| e.to_string())?;

            for row in rows {
                let (platform, schedule, status, source) = row.map_err(|e| e.to_string())?;

                old_targets.insert(platform, (schedule, status, source));
            }
        }

        tx.execute(
            "DELETE FROM media_assets WHERE content_id=?1",
            params![item.id],
        )
        .map_err(|e| e.to_string())?;

        tx.execute(
            "DELETE FROM validation_issues WHERE content_id=?1",
            params![item.id],
        )
        .map_err(|e| e.to_string())?;

        tx.execute(
            "DELETE FROM publication_targets WHERE content_id=?1",
            params![item.id],
        )
        .map_err(|e| e.to_string())?;

        for m in &item.media {
            tx.execute(
                r#"
                INSERT INTO media_assets(
                  id,content_id,path,kind,size_bytes,duration_seconds,sha256,modified_at
                )
                VALUES(?1,?2,?3,?4,?5,?6,?7,?8)
                "#,
                params![
                    m.id,
                    item.id,
                    m.path,
                    m.kind,
                    m.size_bytes as i64,
                    m.duration_seconds,
                    m.sha256,
                    m.modified_at,
                ],
            )
            .map_err(|e| e.to_string())?;
        }

        for t in &item.targets {
            let old = old_targets.get(&t.platform);

            let remote_locked = old
                .map(|x| x.1 == "SCHEDULED_REMOTE" || x.1 == "PUBLISHED")
                .unwrap_or(false);

            let manual = old.and_then(|x| x.2.as_deref()) == Some("MANUAL");

            let scheduled_at = if remote_locked || manual {
                old.and_then(|x| x.0.clone())
            } else {
                t.scheduled_at.clone()
            };

            let schedule_source = if remote_locked {
                old.and_then(|x| x.2.clone())
            } else if manual {
                Some("MANUAL".into())
            } else {
                t.schedule_source.clone()
            };

            let status = if remote_locked {
                old.map(|x| x.1.clone()).unwrap_or_else(|| t.status.clone())
            } else if scheduled_at.is_some() {
                "PRECALENDARIZED".into()
            } else {
                "READY".into()
            };

            tx.execute(
                r#"
                INSERT INTO publication_targets(
                  id,content_id,platform,account,status,
                  scheduled_at,source_txt,copy,schedule_source
                )
                VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)
                "#,
                params![
                    t.id,
                    item.id,
                    t.platform,
                    t.account,
                    status,
                    scheduled_at,
                    t.source_txt,
                    t.copy,
                    schedule_source,
                ],
            )
            .map_err(|e| e.to_string())?;
        }

        for i in &item.issues {
            tx.execute(
                "INSERT INTO validation_issues(id,content_id,severity,message)
                 VALUES(?1,?2,?3,?4)",
                params![i.id, item.id, i.severity, i.message],
            )
            .map_err(|e| e.to_string())?;
        }
    }

    tx.commit().map_err(|e| e.to_string())?;

    Ok(())
}

pub fn list(db: &Path) -> Result<Vec<ContentItem>, String> {
    let conn = open(db)?;

    /*
     * Materializamos primero las filas base.
     *
     * Esto es deliberado: no mantenemos vivo un MappedRows/Statement
     * mientras hacemos nuevas consultas sobre la misma conexión.
     */
    let base = {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT
                  id,folder_path,title,client,content_type,status,
                  workflow_status,source_fingerprint,version,refreshed_at
                FROM contents
                ORDER BY imported_at DESC,title ASC
                "#,
            )
            .map_err(|e| e.to_string())?;

        let rows = stmt
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, Option<String>>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, String>(5)?,
                    r.get::<_, String>(6)?,
                    r.get::<_, Option<String>>(7)?,
                    r.get::<_, i64>(8)?,
                    r.get::<_, Option<String>>(9)?,
                ))
            })
            .map_err(|e| e.to_string())?;

        let result = rows
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;

        result
    };

    let mut out = Vec::with_capacity(base.len());

    for row in base {
        let (
            id,
            folder,
            title,
            client,
            ctype,
            validation_status,
            workflow_status,
            source_fingerprint,
            version,
            refreshed_at,
        ) = row;

        let media = {
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT
                      id,path,kind,size_bytes,
                      duration_seconds,sha256,modified_at
                    FROM media_assets
                    WHERE content_id=?1
                    ORDER BY path
                    "#,
                )
                .map_err(|e| e.to_string())?;

            let rows = stmt
                .query_map(params![id.clone()], |r| {
                    Ok(MediaAsset {
                        id: r.get(0)?,
                        path: r.get(1)?,
                        kind: r.get(2)?,
                        size_bytes: r.get::<_, i64>(3)? as u64,
                        duration_seconds: r.get(4)?,
                        sha256: r.get(5)?,
                        modified_at: r.get(6)?,
                    })
                })
                .map_err(|e| e.to_string())?;

            let result = rows
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())?;

            result
        };

        let targets = {
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT
                      id,platform,account,status,
                      scheduled_at,source_txt,copy,schedule_source
                    FROM publication_targets
                    WHERE content_id=?1
                    ORDER BY platform
                    "#,
                )
                .map_err(|e| e.to_string())?;

            let rows = stmt
                .query_map(params![id.clone()], |r| {
                    Ok(PublicationTarget {
                        id: r.get(0)?,
                        platform: r.get(1)?,
                        account: r.get(2)?,
                        status: r.get(3)?,
                        scheduled_at: r.get(4)?,
                        source_txt: r.get(5)?,
                        copy: r.get(6)?,
                        schedule_source: r.get(7)?,
                    })
                })
                .map_err(|e| e.to_string())?;

            let result = rows
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())?;

            result
        };

        let issues = {
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT id,severity,message
                    FROM validation_issues
                    WHERE content_id=?1
                    "#,
                )
                .map_err(|e| e.to_string())?;

            let rows = stmt
                .query_map(params![id.clone()], |r| {
                    Ok(ValidationIssue {
                        id: r.get(0)?,
                        severity: r.get(1)?,
                        message: r.get(2)?,
                    })
                })
                .map_err(|e| e.to_string())?;

            let result = rows
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())?;

            result
        };

        let (source_kind, source_ref) = source_for(&conn, &id, &folder)?;

        let latest_note = latest_note(&conn, &id)?;

        out.push(ContentItem {
            id,
            folder_path: folder,
            title,
            client,
            content_type: ctype,
            status: workflow_status,
            validation_status,
            version,
            source_fingerprint,
            refreshed_at,
            latest_note,
            source_kind,
            source_ref,
            media,
            targets,
            issues,
        });
    }

    Ok(out)
}

pub fn find_duplicate(db: &Path, incoming: &ContentItem) -> Result<Option<ContentItem>, String> {
    let contents = list(db)?;

    Ok(contents.into_iter().find(|existing| {
        existing.id == incoming.id
            || (incoming.source_fingerprint.is_some()
                && incoming.source_fingerprint == existing.source_fingerprint)
    }))
}

fn log_event_conn(
    conn: &Connection,
    action: &str,
    entity_type: &str,
    entity_id: &str,
    label: &str,
    before_json: Option<&str>,
    after_json: Option<&str>,
    reversible: bool,
    remote: bool,
) -> Result<(), String> {
    let now = Utc::now().to_rfc3339();

    let id = format!(
        "evt-{}",
        hash_id(&format!("{action}:{entity_type}:{entity_id}:{label}:{now}"))
    );

    conn.execute(
        r#"
        INSERT INTO audit_events(
          id,action,entity_type,entity_id,label,
          before_json,after_json,reversible,remote,created_at
        )
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
        "#,
        params![
            id,
            action,
            entity_type,
            entity_id,
            label,
            before_json,
            after_json,
            reversible as i64,
            remote as i64,
            now,
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(())
}

pub fn log_event(
    db: &Path,
    action: &str,
    entity_type: &str,
    entity_id: &str,
    label: &str,
    before_json: Option<&str>,
    after_json: Option<&str>,
    reversible: bool,
    remote: bool,
) -> Result<(), String> {
    let conn = open(db)?;

    log_event_conn(
        &conn,
        action,
        entity_type,
        entity_id,
        label,
        before_json,
        after_json,
        reversible,
        remote,
    )
}

pub fn list_activity(db: &Path, limit: usize) -> Result<Vec<ActivityEvent>, String> {
    let conn = open(db)?;

    let mut stmt = conn
        .prepare(
            r#"
            SELECT
              id,action,entity_type,entity_id,label,
              before_json,after_json,reversible,remote,undone,created_at
            FROM audit_events
            ORDER BY seq DESC
            LIMIT ?1
            "#,
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![limit as i64], |r| {
            Ok(ActivityEvent {
                id: r.get(0)?,
                action: r.get(1)?,
                entity_type: r.get(2)?,
                entity_id: r.get(3)?,
                label: r.get(4)?,
                before_json: r.get(5)?,
                after_json: r.get(6)?,
                reversible: r.get::<_, i64>(7)? != 0,
                remote: r.get::<_, i64>(8)? != 0,
                undone: r.get::<_, i64>(9)? != 0,
                created_at: r.get(10)?,
            })
        })
        .map_err(|e| e.to_string())?;

    let result = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    Ok(result)
}

pub fn update_schedule(
    db: &Path,
    target_id: &str,
    scheduled_at: Option<&str>,
) -> Result<bool, String> {
    let conn = open(db)?;

    let row: Option<(String, Option<String>, String)> = conn
        .query_row(
            "SELECT content_id,scheduled_at,status
             FROM publication_targets
             WHERE id=?1",
            params![target_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let Some((content_id, before, current_status)) = row else {
        return Err("Destino no encontrado.".into());
    };

    if current_status == "SCHEDULED_REMOTE" || current_status == "PUBLISHED" {
        return Err(
            "Esta publicación ya está programada/publicada externamente. Debes cancelarla mediante su provider antes de moverla."
                .into(),
        );
    }

    let status = if scheduled_at.is_some() {
        "PRECALENDARIZED"
    } else {
        "READY"
    };

    let n = conn
        .execute(
            r#"
            UPDATE publication_targets
            SET scheduled_at=?1,status=?2,schedule_source='MANUAL'
            WHERE id=?3
            "#,
            params![scheduled_at, status, target_id],
        )
        .map_err(|e| e.to_string())?;

    if n > 0 {
        let before_json = serde_json::json!({
            "scheduledAt": before
        })
        .to_string();

        let after_json = serde_json::json!({
            "scheduledAt": scheduled_at
        })
        .to_string();

        log_event_conn(
            &conn,
            "SCHEDULE",
            "publication_target",
            target_id,
            &format!("Programación modificada · {content_id}"),
            Some(&before_json),
            Some(&after_json),
            true,
            false,
        )?;
    }

    Ok(n > 0)
}

pub fn update_schedules(db: &Path, changes: &[ScheduleChange]) -> Result<usize, String> {
    let mut changed = 0;

    for c in changes {
        if update_schedule(db, &c.target_id, c.scheduled_at.as_deref())? {
            changed += 1;
        }
    }

    Ok(changed)
}

pub fn update_workflow_status(db: &Path, content_id: &str, status: &str) -> Result<bool, String> {
    let allowed = [
        "EN_CONFIRMACION",
        "CON_CORRECCION",
        "LISTO_POR_PROGRAMAR",
        "PROGRAMADO",
    ];

    if !allowed.contains(&status) {
        return Err("Estado editorial inválido.".into());
    }

    let conn = open(db)?;

    let before: Option<String> = conn
        .query_row(
            "SELECT workflow_status FROM contents WHERE id=?1",
            params![content_id],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let n = conn
        .execute(
            "UPDATE contents SET workflow_status=?1 WHERE id=?2",
            params![status, content_id],
        )
        .map_err(|e| e.to_string())?;

    if n > 0 && before.as_deref() != Some(status) {
        let before_json = serde_json::json!({
            "status": before
        })
        .to_string();

        let after_json = serde_json::json!({
            "status": status
        })
        .to_string();

        log_event_conn(
            &conn,
            "STATUS",
            "content",
            content_id,
            "Estado editorial cambiado",
            Some(&before_json),
            Some(&after_json),
            true,
            false,
        )?;
    }

    drop(conn);

    if n > 0 {
        let conn = open(db)?;

        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM correction_notes WHERE content_id=?1",
                params![content_id],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;

        drop(conn);

        if count > 0 {
            let (path, text) = correction_text(db, content_id)?;
            write_correction_file_atomic(&path, &text)?;
        }
    }

    Ok(n > 0)
}

pub fn add_note(
    db: &Path,
    content_id: &str,
    body: &str,
    status: &str,
) -> Result<CorrectionNote, String> {
    if body.trim().is_empty() {
        return Err("La nota no puede estar vacía.".into());
    }

    update_workflow_status(db, content_id, status)?;

    let conn = open(db)?;
    let now = Utc::now().to_rfc3339();

    let id = format!("note-{}", hash_id(&format!("{content_id}:{now}:{body}")));

    conn.execute(
        r#"
        INSERT INTO correction_notes(id,content_id,body,created_at)
        VALUES(?1,?2,?3,?4)
        "#,
        params![id, content_id, body.trim(), now],
    )
    .map_err(|e| e.to_string())?;

    log_event_conn(
        &conn,
        "NOTE",
        "content",
        content_id,
        "Corrección añadida",
        None,
        Some(
            &serde_json::json!({
                "body": body.trim()
            })
            .to_string(),
        ),
        false,
        false,
    )?;

    Ok(CorrectionNote {
        id,
        body: body.trim().to_string(),
        created_at: now,
    })
}

pub fn correction_text(db: &Path, content_id: &str) -> Result<(PathBuf, String), String> {
    let conn = open(db)?;

    let (folder, title, status): (String, String, String) = conn
        .query_row(
            "SELECT folder_path,title,workflow_status
             FROM contents
             WHERE id=?1",
            params![content_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .map_err(|e| e.to_string())?;

    let mut stmt = conn
        .prepare(
            "SELECT body,created_at
             FROM correction_notes
             WHERE content_id=?1
             ORDER BY created_at ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![content_id], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })
        .map_err(|e| e.to_string())?;

    let mut text = format!(
        "ABRAXAS_CORRECCION_V1\n\
         CONTENT_ID: {content_id}\n\
         CONTENT: {title}\n\
         STATUS: {status}\n\
         UPDATED_AT: {}\n\n\
         NOTAS:\n",
        Utc::now().to_rfc3339()
    );

    for row in rows {
        let (body, at) = row.map_err(|e| e.to_string())?;

        text.push_str(&format!("\n--- {at} ---\n{body}\n"));
    }

    Ok((PathBuf::from(folder).join("CORRECCION.txt"), text))
}

pub fn write_correction_file_atomic(path: &Path, text: &str) -> Result<(), String> {
    let parent = path.parent().ok_or_else(|| "Ruta inválida.".to_string())?;

    if !parent.is_dir() {
        return Err("La carpeta del contenido ya no existe.".into());
    }

    let tmp = parent.join(format!(".CORRECCION.txt.{}.tmp", std::process::id()));

    fs::write(&tmp, text).map_err(|e| e.to_string())?;

    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        e.to_string()
    })?;

    Ok(())
}

pub fn undo(db: &Path) -> Result<Option<ActivityEvent>, String> {
    let conn = open(db)?;

    let event: Option<ActivityEvent> = conn
        .query_row(
            r#"
            SELECT
              id,action,entity_type,entity_id,label,
              before_json,after_json,reversible,remote,undone,created_at
            FROM audit_events
            WHERE reversible=1 AND remote=0 AND undone=0
            ORDER BY seq DESC
            LIMIT 1
            "#,
            [],
            |r| {
                Ok(ActivityEvent {
                    id: r.get(0)?,
                    action: r.get(1)?,
                    entity_type: r.get(2)?,
                    entity_id: r.get(3)?,
                    label: r.get(4)?,
                    before_json: r.get(5)?,
                    after_json: r.get(6)?,
                    reversible: r.get::<_, i64>(7)? != 0,
                    remote: r.get::<_, i64>(8)? != 0,
                    undone: r.get::<_, i64>(9)? != 0,
                    created_at: r.get(10)?,
                })
            },
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let Some(event) = event else {
        return Ok(None);
    };

    let value: serde_json::Value =
        serde_json::from_str(event.before_json.as_deref().unwrap_or("{}"))
            .map_err(|e| e.to_string())?;

    match event.action.as_str() {
        "STATUS" => {
            if let Some(status) = value.get("status").and_then(|x| x.as_str()) {
                conn.execute(
                    "UPDATE contents SET workflow_status=?1 WHERE id=?2",
                    params![status, event.entity_id],
                )
                .map_err(|e| e.to_string())?;
            }
        }

        "SCHEDULE" => {
            let schedule = value.get("scheduledAt").and_then(|x| x.as_str());

            let status = if schedule.is_some() {
                "PRECALENDARIZED"
            } else {
                "READY"
            };

            conn.execute(
                "UPDATE publication_targets
                 SET scheduled_at=?1,status=?2,schedule_source='MANUAL'
                 WHERE id=?3",
                params![schedule, status, event.entity_id],
            )
            .map_err(|e| e.to_string())?;
        }

        _ => {}
    }

    conn.execute(
        "UPDATE audit_events
         SET undone=1,undone_at=?1
         WHERE id=?2",
        params![Utc::now().to_rfc3339(), event.id],
    )
    .map_err(|e| e.to_string())?;

    Ok(Some(event))
}

pub fn redo(db: &Path) -> Result<Option<ActivityEvent>, String> {
    let conn = open(db)?;

    let event: Option<ActivityEvent> = conn
        .query_row(
            r#"
            SELECT
              id,action,entity_type,entity_id,label,
              before_json,after_json,reversible,remote,undone,created_at
            FROM audit_events
            WHERE reversible=1 AND remote=0 AND undone=1
            ORDER BY undone_at DESC
            LIMIT 1
            "#,
            [],
            |r| {
                Ok(ActivityEvent {
                    id: r.get(0)?,
                    action: r.get(1)?,
                    entity_type: r.get(2)?,
                    entity_id: r.get(3)?,
                    label: r.get(4)?,
                    before_json: r.get(5)?,
                    after_json: r.get(6)?,
                    reversible: r.get::<_, i64>(7)? != 0,
                    remote: r.get::<_, i64>(8)? != 0,
                    undone: r.get::<_, i64>(9)? != 0,
                    created_at: r.get(10)?,
                })
            },
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let Some(event) = event else {
        return Ok(None);
    };

    let value: serde_json::Value =
        serde_json::from_str(event.after_json.as_deref().unwrap_or("{}"))
            .map_err(|e| e.to_string())?;

    match event.action.as_str() {
        "STATUS" => {
            if let Some(status) = value.get("status").and_then(|x| x.as_str()) {
                conn.execute(
                    "UPDATE contents SET workflow_status=?1 WHERE id=?2",
                    params![status, event.entity_id],
                )
                .map_err(|e| e.to_string())?;
            }
        }

        "SCHEDULE" => {
            let schedule = value.get("scheduledAt").and_then(|x| x.as_str());

            let status = if schedule.is_some() {
                "PRECALENDARIZED"
            } else {
                "READY"
            };

            conn.execute(
                "UPDATE publication_targets
                 SET scheduled_at=?1,status=?2,schedule_source='MANUAL'
                 WHERE id=?3",
                params![schedule, status, event.entity_id],
            )
            .map_err(|e| e.to_string())?;
        }

        _ => {}
    }

    conn.execute(
        "UPDATE audit_events
         SET undone=0,undone_at=NULL
         WHERE id=?1",
        params![event.id],
    )
    .map_err(|e| e.to_string())?;

    Ok(Some(event))
}

pub fn clear(db: &Path) -> Result<bool, String> {
    let conn = open(db)?;

    conn.execute("DELETE FROM contents", [])
        .map_err(|e| e.to_string())?;

    Ok(true)
}
