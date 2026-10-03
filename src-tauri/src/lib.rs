pub mod core;
pub mod db;
pub mod drive;
pub mod models;
pub mod publishing;
pub mod scanner;

use chrono::Utc;
use models::*;
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    process::Command,
    sync::{Arc, Mutex},
};
use tauri::{Manager, State};

pub struct AppState {
    pub db_path: PathBuf,
    pub app_data_dir: PathBuf,
    pub drive: Arc<Mutex<drive::DriveSession>>,
}

pub fn default_db_path() -> PathBuf {
    if let Ok(path) = std::env::var("ABRAXAS_PUBLISHER_DB") {
        return PathBuf::from(path);
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());

    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("com.abraxas.publisher")
        .join("abraxas-publisher.sqlite3")
}

pub fn default_cache_dir() -> PathBuf {
    let db = default_db_path();

    db.parent().unwrap_or(Path::new(".")).join("cache")
}

fn command_exists(cmd: &str) -> bool {
    Command::new(cmd)
        .arg("-version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

pub fn simulate_for_db(db_path: &Path) -> Result<SimulationReport, String> {
    let contents = db::list(db_path)?;

    let mut by: BTreeMap<String, (usize, usize, usize, usize)> = BTreeMap::new();

    let mut ready = 0;
    let mut warnings = 0;
    let mut errors = 0;

    for c in &contents {
        for t in &c.targets {
            let has_error = c.issues.iter().any(|i| i.severity == "error");

            let editorial_ready = c.status == "LISTO_POR_PROGRAMAR" || c.status == "PROGRAMADO";

            let has_warn = c.issues.iter().any(|i| i.severity == "warning")
                || t.scheduled_at.is_none()
                || !editorial_ready;

            let e = by.entry(t.platform.clone()).or_insert((0, 0, 0, 0));

            e.0 += 1;

            if has_error {
                errors += 1;
                e.3 += 1;
            } else if has_warn {
                warnings += 1;
                e.2 += 1;
            } else {
                ready += 1;
                e.1 += 1;
            }
        }
    }

    let platforms = by
        .into_iter()
        .map(|(platform, (total, ok, w, e))| SimulationPlatform {
            platform,
            total,
            ready: ok,
            warnings: w,
            errors: e,
        })
        .collect::<Vec<_>>();

    Ok(SimulationReport {
        total_targets: ready + warnings + errors,
        ready,
        warnings,
        errors,
        generated_at: Utc::now().to_rfc3339(),
        platforms,
        note: "SIMULACIÓN LOCAL: no se llamó ninguna API social y no se publicó nada.".into(),
    })
}

#[tauri::command]
fn health(state: State<'_, AppState>) -> Result<HealthReport, String> {
    Ok(HealthReport {
        database: state.db_path.exists(),
        ffmpeg: command_exists("ffmpeg"),
        ffprobe: command_exists("ffprobe"),
        app_data_dir: state.app_data_dir.to_string_lossy().to_string(),
    })
}

#[tauri::command]
fn list_brands(state: State<'_, AppState>) -> Result<Vec<Brand>, String> {
    db::list_brands(&state.db_path)
}

#[tauri::command]
fn create_brand(name: String, state: State<'_, AppState>) -> Result<Brand, String> {
    db::create_brand(&state.db_path, &name)
}

#[tauri::command]
fn preview_import_local(
    path: String,
    brand: String,
    state: State<'_, AppState>,
) -> Result<ImportPreview, String> {
    core::preview_local(&state.db_path, Path::new(&path), &brand)
}

#[tauri::command]
fn commit_import_local(
    path: String,
    brand: String,
    duplicate_policy: String,
    state: State<'_, AppState>,
) -> Result<ScanResult, String> {
    core::commit_local(
        &state.db_path,
        Path::new(&path),
        &brand,
        &duplicate_policy,
        &state.app_data_dir.join("duplicate-imports"),
    )
}

// compatibilidad con V1.1
#[tauri::command]
fn import_folder(path: String, state: State<'_, AppState>) -> Result<ScanResult, String> {
    core::commit_local(
        &state.db_path,
        Path::new(&path),
        "JOC",
        "replace",
        &state.app_data_dir.join("duplicate-imports"),
    )
}

#[tauri::command]
fn list_contents(state: State<'_, AppState>) -> Result<Vec<ContentItem>, String> {
    db::list(&state.db_path)
}

#[tauri::command]
fn update_schedule(
    target_id: String,
    scheduled_at: Option<String>,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    db::update_schedule(&state.db_path, &target_id, scheduled_at.as_deref())
}

#[tauri::command]
fn update_schedules(
    changes: Vec<ScheduleChange>,
    state: State<'_, AppState>,
) -> Result<usize, String> {
    db::update_schedules(&state.db_path, &changes)
}

#[tauri::command]
fn update_workflow_status(
    content_id: String,
    status: String,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    db::update_workflow_status(&state.db_path, &content_id, &status)
}

#[tauri::command]
fn save_correction_note(
    content_id: String,
    note: String,
    status: String,
    state: State<'_, AppState>,
) -> Result<CorrectionNote, String> {
    let saved = db::add_note(&state.db_path, &content_id, &note, &status)?;

    let (path, text) = db::correction_text(&state.db_path, &content_id)?;

    db::write_correction_file_atomic(&path, &text)?;

    if let Ok((kind, Some(folder_id))) = db::get_content_source(&state.db_path, &content_id) {
        if kind == "drive" && drive::connected(&state.drive) {
            let _ = drive::upload_correction_text(&state.drive, &folder_id, &text);
        }
    }

    Ok(saved)
}

#[tauri::command]
fn refresh_content(
    content_id: String,
    state: State<'_, AppState>,
) -> Result<RefreshResult, String> {
    let before = db::list(&state.db_path)?
        .into_iter()
        .find(|c| c.id == content_id)
        .ok_or_else(|| "Contenido no encontrado.".to_string())?;

    let previous_version = before.version;

    let mut scanned = scanner::scan_content(PathBuf::from(&before.folder_path).as_path())?;

    scanned.id = before.id.clone();
    scanned.client = before.client.clone();
    scanned.source_kind = before.source_kind.clone();
    scanned.source_ref = before.source_ref.clone();

    for target in &mut scanned.targets {
        target.id = scanner::stable_id(&format!("{}:{}", scanned.id, target.platform));
    }

    db::upsert_scan(&state.db_path, &[scanned])?;

    let content = db::list(&state.db_path)?
        .into_iter()
        .find(|c| c.id == content_id)
        .ok_or_else(|| "No se pudo releer el contenido.".to_string())?;

    let changed = content.version > previous_version;

    if changed {
        db::log_event(
            &state.db_path,
            "REFRESH",
            "content",
            &content_id,
            &format!(
                "Contenido actualizado · v{} → v{}",
                previous_version, content.version
            ),
            None,
            None,
            false,
            false,
        )?;
    }

    Ok(RefreshResult {
        current_version: content.version,
        previous_version,
        changed,
        message: if changed {
            "Se detectaron archivos nuevos o reemplazados.".into()
        } else {
            "No se detectaron cambios.".into()
        },
        content,
    })
}

#[tauri::command]
fn list_activity(state: State<'_, AppState>) -> Result<Vec<ActivityEvent>, String> {
    db::list_activity(&state.db_path, 500)
}

#[tauri::command]
fn undo_last(state: State<'_, AppState>) -> Result<Option<ActivityEvent>, String> {
    db::undo(&state.db_path)
}

#[tauri::command]
fn redo_last(state: State<'_, AppState>) -> Result<Option<ActivityEvent>, String> {
    db::redo(&state.db_path)
}

#[tauri::command]
fn get_drive_client_id(state: State<'_, AppState>) -> Result<Option<String>, String> {
    db::get_setting(&state.db_path, "google_drive_client_id")
}

#[tauri::command]
fn set_drive_client_id(client_id: String, state: State<'_, AppState>) -> Result<bool, String> {
    db::set_setting(&state.db_path, "google_drive_client_id", client_id.trim())
}

#[tauri::command]
fn drive_status(state: State<'_, AppState>) -> bool {
    drive::connected(&state.drive)
}

#[tauri::command]
async fn drive_connect(
    client_id: String,
    state: State<'_, AppState>,
) -> Result<DriveAuthResult, String> {
    let db_path = state.db_path.clone();
    let session = state.drive.clone();

    tauri::async_runtime::spawn_blocking(move || {
        db::set_setting(&db_path, "google_drive_client_id", client_id.trim())?;

        drive::connect(&client_id, &session)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn drive_list(
    folder_id: String,
    state: State<'_, AppState>,
) -> Result<Vec<DriveItem>, String> {
    let session = state.drive.clone();

    tauri::async_runtime::spawn_blocking(move || {
        drive::list(
            &session,
            if folder_id.is_empty() {
                "root"
            } else {
                &folder_id
            },
        )
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn drive_preview_folder(
    folder_id: String,
    brand: String,
    state: State<'_, AppState>,
) -> Result<ImportPreview, String> {
    let session = state.drive.clone();
    let db = state.db_path.clone();
    let cache = state.app_data_dir.join("drive-cache");

    tauri::async_runtime::spawn_blocking(move || {
        let root = drive::download_tree(&session, &folder_id, &cache)?;

        core::preview_local(&db, &root, &brand)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn drive_import_folder(
    folder_id: String,
    brand: String,
    duplicate_policy: String,
    state: State<'_, AppState>,
) -> Result<ScanResult, String> {
    let session = state.drive.clone();
    let db = state.db_path.clone();
    let app_data = state.app_data_dir.clone();

    tauri::async_runtime::spawn_blocking(move || {
        let root = drive::download_tree(&session, &folder_id, &app_data.join("drive-cache"))?;

        core::commit_local(
            &db,
            &root,
            &brand,
            &duplicate_policy,
            &app_data.join("duplicate-imports"),
        )
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
fn simulate_batch(state: State<'_, AppState>) -> Result<SimulationReport, String> {
    simulate_for_db(&state.db_path)
}

#[tauri::command]
fn clear_workspace(state: State<'_, AppState>) -> Result<bool, String> {
    db::clear(&state.db_path)
}

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
    publishing::preflight(&state.db_path, &target_id, account_id.as_deref())
}

#[tauri::command]
fn enqueue_publications(
    inputs: Vec<publishing::EnqueueInput>,
    state: State<'_, AppState>,
) -> Result<Vec<publishing::PublishJob>, String> {
    publishing::enqueue(&state.db_path, &inputs)
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let dir = app.path().app_data_dir()?;

            std::fs::create_dir_all(&dir)?;

            let db_path = dir.join("abraxas-publisher.sqlite3");

            db::init(&db_path).map_err(std::io::Error::other)?;
            publishing::init(&db_path).map_err(std::io::Error::other)?;

            app.manage(AppState {
                db_path,
                app_data_dir: dir,
                drive: Arc::new(Mutex::new(drive::DriveSession::default())),
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            health,
            list_connected_accounts,
            save_connected_account,
            remove_connected_account,
            list_publication_jobs,
            publishing_preflight,
            enqueue_publications,
            mark_scheduled_external,
            list_brands,
            create_brand,
            preview_import_local,
            commit_import_local,
            import_folder,
            list_contents,
            update_schedule,
            update_schedules,
            update_workflow_status,
            save_correction_note,
            refresh_content,
            list_activity,
            undo_last,
            redo_last,
            get_drive_client_id,
            set_drive_client_id,
            drive_status,
            drive_connect,
            drive_list,
            drive_preview_folder,
            drive_import_folder,
            simulate_batch,
            clear_workspace
        ])
        .run(tauri::generate_context!())
        .expect("error while running ABRAXAS Publisher");
}
