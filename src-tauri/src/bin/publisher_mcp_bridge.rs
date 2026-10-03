use abraxas_publisher_lib::{core, db, default_cache_dir, default_db_path, publishing, scanner, simulate_for_db};
use serde_json::{json, Value};
use std::{path::Path, process::Command};

fn arg(v: &Value, key: &str) -> Result<String, String> {
    v.get(key).and_then(Value::as_str).map(str::to_string).ok_or_else(|| format!("Falta {key}"))
}

fn opt(v: &Value, key: &str) -> Option<String> {
    v.get(key).and_then(Value::as_str).map(str::to_string)
}

fn init() -> Result<std::path::PathBuf, String> {
    let dbp = default_db_path();
    db::init(&dbp)?;
    publishing::init(&dbp)?;
    Ok(dbp)
}

fn content_by_id(dbp: &Path, id: &str) -> Result<abraxas_publisher_lib::models::ContentItem, String> {
    db::list(dbp)?.into_iter().find(|x| x.id == id).ok_or_else(|| format!("Contenido no encontrado: {id}"))
}

fn command_exists(cmd: &str) -> bool {
    Command::new(cmd).arg("-version").output().map(|o| o.status.success()).unwrap_or(false)
}

fn run(op: &str, input: Value) -> Result<Value, String> {
    let dbp = init()?;

    match op {
        "doctor" => Ok(json!({
            "database": dbp.exists(),
            "dbPath": dbp,
            "ffmpeg": command_exists("ffmpeg"),
            "ffprobe": command_exists("ffprobe")
        })),

        "brands.list" => Ok(serde_json::to_value(db::list_brands(&dbp)?).map_err(|e| e.to_string())?),
        "brands.create" => Ok(serde_json::to_value(db::create_brand(&dbp, &arg(&input, "name")?)?).map_err(|e| e.to_string())?),

        "content.list" => Ok(serde_json::to_value(db::list(&dbp)?).map_err(|e| e.to_string())?),
        "content.show" => Ok(serde_json::to_value(content_by_id(&dbp, &arg(&input, "contentId")?)?).map_err(|e| e.to_string())?),
        "content.refresh" => {
            let id = arg(&input, "contentId")?;
            let before = content_by_id(&dbp, &id)?;
            let previous_version = before.version;
            let mut scanned = scanner::scan_content(Path::new(&before.folder_path))?;
            scanned.id = before.id;
            scanned.client = before.client;
            scanned.source_kind = before.source_kind;
            scanned.source_ref = before.source_ref;
            db::upsert_scan(&dbp, &[scanned])?;
            let content = content_by_id(&dbp, &id)?;
            Ok(json!({
                "content": content,
                "changed": content.version > previous_version,
                "previousVersion": previous_version,
                "currentVersion": content.version
            }))
        }
        "content.importLocal" => {
            let path = arg(&input, "path")?;
            let brand = opt(&input, "brand").unwrap_or_else(|| "JOC".into());
            let duplicate_policy = opt(&input, "duplicatePolicy").unwrap_or_else(|| "replace".into());
            db::create_brand(&dbp, &brand)?;
            Ok(serde_json::to_value(core::commit_local(
                &dbp,
                Path::new(&path),
                &brand,
                &duplicate_policy,
                &default_cache_dir().join("keep"),
            )?).map_err(|e| e.to_string())?)
        }

        "status.set" => {
            let id = arg(&input, "contentId")?;
            let status = arg(&input, "status")?;
            let allowed = ["EN_CONFIRMACION", "CON_CORRECCION", "LISTO_POR_PROGRAMAR", "PROGRAMADO"];
            if !allowed.contains(&status.as_str()) { return Err("Estado editorial inválido".into()); }
            Ok(json!({"updated": db::update_workflow_status(&dbp, &id, &status)?}))
        }

        "note.add" => {
            let id = arg(&input, "contentId")?;
            let note = arg(&input, "note")?;
            let status = opt(&input, "status").unwrap_or_else(|| "CON_CORRECCION".into());
            let saved = db::add_note(&dbp, &id, &note, &status)?;
            let (path, body) = db::correction_text(&dbp, &id)?;
            db::write_correction_file_atomic(&path, &body)?;
            Ok(json!({"note": saved, "correctionFile": path}))
        }

        "schedule.show" => Ok(serde_json::to_value(content_by_id(&dbp, &arg(&input, "contentId")?)?.targets).map_err(|e| e.to_string())?),
        "schedule.set" => {
            let content = content_by_id(&dbp, &arg(&input, "contentId")?)?;
            let platform = arg(&input, "platform")?;
            let at = arg(&input, "scheduledAt")?;
            let target = content.targets.iter().find(|x| x.platform == platform).ok_or("Red no encontrada")?;
            Ok(json!({"updated": db::update_schedule(&dbp, &target.id, Some(&at))?}))
        }
        "schedule.clear" => {
            let content = content_by_id(&dbp, &arg(&input, "contentId")?)?;
            let platform = arg(&input, "platform")?;
            let target = content.targets.iter().find(|x| x.platform == platform).ok_or("Red no encontrada")?;
            Ok(json!({"updated": db::update_schedule(&dbp, &target.id, None)?}))
        }

        "activity.list" => Ok(serde_json::to_value(db::list_activity(&dbp, 500)?).map_err(|e| e.to_string())?),
        "undo" => Ok(serde_json::to_value(db::undo(&dbp)?).map_err(|e| e.to_string())?),
        "redo" => Ok(serde_json::to_value(db::redo(&dbp)?).map_err(|e| e.to_string())?),
        "dryRun" => Ok(serde_json::to_value(simulate_for_db(&dbp)?).map_err(|e| e.to_string())?),

        "accounts.list" => Ok(serde_json::to_value(publishing::list_accounts(&dbp)?).map_err(|e| e.to_string())?),
        "accounts.save" => {
            let value = input.get("account").cloned().ok_or("Falta account")?;
            let account: publishing::SaveAccountInput = serde_json::from_value(value).map_err(|e| e.to_string())?;
            Ok(serde_json::to_value(publishing::save_account(&dbp, account)?).map_err(|e| e.to_string())?)
        }
        "accounts.remove" => Ok(json!({"removed": publishing::remove_account(&dbp, &arg(&input, "accountId")?)?})),

        "jobs.list" => Ok(serde_json::to_value(publishing::list_jobs(&dbp)?).map_err(|e| e.to_string())?),
        "publishing.preflight" => {
            let target_id = arg(&input, "targetId")?;
            let account_id = opt(&input, "accountId");
            Ok(serde_json::to_value(publishing::preflight(&dbp, &target_id, account_id.as_deref())?).map_err(|e| e.to_string())?)
        }
        "publishing.enqueue" => {
            let values = input.get("inputs").cloned().ok_or("Falta inputs")?;
            let inputs: Vec<publishing::EnqueueInput> = serde_json::from_value(values).map_err(|e| e.to_string())?;
            Ok(serde_json::to_value(publishing::enqueue(&dbp, &inputs)?).map_err(|e| e.to_string())?)
        }
        "publishing.markExternal" => {
            let target_id = arg(&input, "targetId")?;
            let method = arg(&input, "method")?;
            let scheduled_at = opt(&input, "scheduledAt");
            let remote_url = opt(&input, "remoteUrl");
            let note = opt(&input, "note");
            Ok(serde_json::to_value(publishing::mark_external(
                &dbp,
                &target_id,
                &method,
                scheduled_at.as_deref(),
                remote_url.as_deref(),
                note.as_deref(),
            )?).map_err(|e| e.to_string())?)
        }

        "drive.getClientId" => Ok(json!({"clientId": db::get_setting(&dbp, "google_drive_client_id")?})),
        "drive.setClientId" => Ok(json!({"updated": db::set_setting(&dbp, "google_drive_client_id", &arg(&input, "clientId")?)?})),

        "workspace.clear" => Ok(json!({"cleared": db::clear(&dbp)?})),

        _ => Err(format!("Operación MCP desconocida: {op}")),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Uso: publisher_mcp_bridge OP [JSON]");
        std::process::exit(2);
    }

    let input = args.get(2)
        .map(|x| serde_json::from_str::<Value>(x).map_err(|e| e.to_string()))
        .transpose()
        .unwrap_or_else(|e| Err(e))
        .unwrap_or_else(|e| {
            eprintln!("ERROR: {e}");
            std::process::exit(2);
        })
        .unwrap_or_else(|| json!({}));

    match run(&args[1], input) {
        Ok(value) => println!("{}", serde_json::to_string(&value).unwrap_or_else(|_| "null".into())),
        Err(error) => {
            eprintln!("ERROR: {error}");
            std::process::exit(2);
        }
    }
}
