mod db;
mod models;
mod scanner;

use chrono::Utc;
use models::*;
use std::{collections::BTreeMap,path::PathBuf,process::Command};
use tauri::{Manager, State};

pub struct AppState { db_path: PathBuf }

fn command_exists(cmd:&str)->bool{Command::new(cmd).arg("-version").output().map(|o|o.status.success()).unwrap_or(false)}

#[tauri::command]
fn health(state:State<AppState>)->Result<HealthReport,String>{
    Ok(HealthReport{database:state.db_path.exists(),ffmpeg:command_exists("ffmpeg"),ffprobe:command_exists("ffprobe"),app_data_dir:state.db_path.parent().unwrap_or(&state.db_path).to_string_lossy().to_string()})
}

#[tauri::command]
fn import_folder(path:String,state:State<AppState>)->Result<ScanResult,String>{
    let result=scanner::scan(PathBuf::from(&path).as_path())?;
    db::upsert_scan(&state.db_path,&result.contents)?;
    Ok(ScanResult{contents:db::list(&state.db_path)?,..result})
}

#[tauri::command]
fn list_contents(state:State<AppState>)->Result<Vec<ContentItem>,String>{db::list(&state.db_path)}

#[tauri::command]
fn update_schedule(target_id:String,scheduled_at:Option<String>,state:State<AppState>)->Result<bool,String>{
    db::update_schedule(&state.db_path,&target_id,scheduled_at.as_deref())
}

#[tauri::command]
fn update_workflow_status(content_id:String,status:String,state:State<AppState>)->Result<bool,String>{
    db::update_workflow_status(&state.db_path,&content_id,&status)
}

#[tauri::command]
fn save_correction_note(content_id:String,note:String,status:String,state:State<AppState>)->Result<CorrectionNote,String>{
    let saved=db::add_note(&state.db_path,&content_id,&note,&status)?;
    let (path,text)=db::correction_text(&state.db_path,&content_id)?;
    db::write_correction_file_atomic(&path,&text)?;
    Ok(saved)
}

#[tauri::command]
fn refresh_content(content_id:String,state:State<AppState>)->Result<RefreshResult,String>{
    let before=db::list(&state.db_path)?.into_iter().find(|c|c.id==content_id).ok_or_else(||"Contenido no encontrado.".to_string())?;
    let previous_version=before.version;
    let scanned=scanner::scan_content(PathBuf::from(&before.folder_path).as_path())?;
    db::upsert_scan(&state.db_path,&[scanned])?;
    let content=db::list(&state.db_path)?.into_iter().find(|c|c.id==content_id).ok_or_else(||"No se pudo releer el contenido.".to_string())?;
    let changed=content.version>previous_version;
    Ok(RefreshResult{current_version:content.version,previous_version,changed,message:if changed{"Se detectaron archivos nuevos o reemplazados. Preview y metadatos actualizados.".into()}else{"No se detectaron cambios en los archivos.".into()},content})
}

#[tauri::command]
fn clear_workspace(state:State<AppState>)->Result<bool,String>{db::clear(&state.db_path)}

#[tauri::command]
fn simulate_batch(state:State<AppState>)->Result<SimulationReport,String>{
    let contents=db::list(&state.db_path)?;
    let mut by:BTreeMap<String,(usize,usize,usize,usize)>=BTreeMap::new();
    let mut ready=0;let mut warnings=0;let mut errors=0;
    for c in &contents{for t in &c.targets{
        let has_error=c.issues.iter().any(|i|i.severity=="error");
        let editorial_ready=c.status=="LISTO_POR_PROGRAMAR"||c.status=="PROGRAMADO";
        let has_warn=c.issues.iter().any(|i|i.severity=="warning")||t.scheduled_at.is_none()||!editorial_ready;
        let e=by.entry(t.platform.clone()).or_insert((0,0,0,0));e.0+=1;
        if has_error{errors+=1;e.3+=1}else if has_warn{warnings+=1;e.2+=1}else{ready+=1;e.1+=1}
    }}
    let platforms=by.into_iter().map(|(platform,(total,ok,w,e))|SimulationPlatform{platform,total,ready:ok,warnings:w,errors:e}).collect::<Vec<_>>();
    let total_targets=ready+warnings+errors;
    Ok(SimulationReport{total_targets,ready,warnings,errors,generated_at:Utc::now().to_rfc3339(),platforms,note:"SIMULACIÓN LOCAL: no se llamó ninguna API social y no se publicó nada.".into()})
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run(){
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app|{
            let dir=app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            let db_path=dir.join("abraxas-publisher.sqlite3");
            db::init(&db_path).map_err(std::io::Error::other)?;
            app.manage(AppState{db_path});Ok(())
        })
        .invoke_handler(tauri::generate_handler![health,import_folder,list_contents,update_schedule,update_workflow_status,save_correction_note,refresh_content,simulate_batch,clear_workspace])
        .run(tauri::generate_context!()).expect("error while running ABRAXAS Publisher")
}
