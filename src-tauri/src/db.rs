use crate::models::*;
use chrono::Utc;
use rusqlite::{params, Connection};
use sha2::Digest;
use std::{fs, path::{Path, PathBuf}};

fn has_column(conn:&Connection, table:&str, column:&str)->Result<bool,String>{
    let mut stmt=conn.prepare(&format!("PRAGMA table_info({})", table)).map_err(|e|e.to_string())?;
    let rows=stmt.query_map([],|r|r.get::<_,String>(1)).map_err(|e|e.to_string())?;
    for row in rows { if row.map_err(|e|e.to_string())? == column { return Ok(true) } }
    Ok(false)
}

fn add_column_if_missing(conn:&Connection, table:&str, column:&str, ddl:&str)->Result<(),String>{
    if !has_column(conn,table,column)? { conn.execute_batch(ddl).map_err(|e|e.to_string())?; }
    Ok(())
}

pub fn init(path:&Path)->Result<(),String>{
    let conn=Connection::open(path).map_err(|e|e.to_string())?;
    conn.execute_batch(r#"
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
    "#).map_err(|e|e.to_string())?;
    add_column_if_missing(&conn,"contents","workflow_status","ALTER TABLE contents ADD COLUMN workflow_status TEXT NOT NULL DEFAULT 'EN_CONFIRMACION';")?;
    add_column_if_missing(&conn,"contents","source_fingerprint","ALTER TABLE contents ADD COLUMN source_fingerprint TEXT;")?;
    add_column_if_missing(&conn,"contents","version","ALTER TABLE contents ADD COLUMN version INTEGER NOT NULL DEFAULT 1;")?;
    add_column_if_missing(&conn,"contents","refreshed_at","ALTER TABLE contents ADD COLUMN refreshed_at TEXT;")?;
    add_column_if_missing(&conn,"publication_targets","schedule_source","ALTER TABLE publication_targets ADD COLUMN schedule_source TEXT;")?;
    add_column_if_missing(&conn,"media_assets","sha256","ALTER TABLE media_assets ADD COLUMN sha256 TEXT;")?;
    add_column_if_missing(&conn,"media_assets","modified_at","ALTER TABLE media_assets ADD COLUMN modified_at TEXT;")?;
    Ok(())
}

pub fn get_version_and_fingerprint(db:&Path, id:&str)->Result<Option<(i64,Option<String>)>,String>{
    let conn=Connection::open(db).map_err(|e|e.to_string())?;
    let mut stmt=conn.prepare("SELECT version,source_fingerprint FROM contents WHERE id=?1").map_err(|e|e.to_string())?;
    let mut rows=stmt.query(params![id]).map_err(|e|e.to_string())?;
    if let Some(r)=rows.next().map_err(|e|e.to_string())? { Ok(Some((r.get(0).map_err(|e|e.to_string())?,r.get(1).map_err(|e|e.to_string())?))) } else { Ok(None) }
}

pub fn upsert_scan(db:&Path, items:&[ContentItem])->Result<(),String>{
    let mut conn=Connection::open(db).map_err(|e|e.to_string())?;
    let tx=conn.transaction().map_err(|e|e.to_string())?;
    for item in items {
        let existing:Option<(String,Option<String>,i64)>= {
            let mut stmt=tx.prepare("SELECT workflow_status,source_fingerprint,version FROM contents WHERE id=?1").map_err(|e|e.to_string())?;
            let mut rows=stmt.query(params![item.id]).map_err(|e|e.to_string())?;
            if let Some(r)=rows.next().map_err(|e|e.to_string())? { Some((r.get(0).map_err(|e|e.to_string())?,r.get(1).map_err(|e|e.to_string())?,r.get(2).map_err(|e|e.to_string())?)) } else { None }
        };
        let workflow=existing.as_ref().map(|x|x.0.clone()).unwrap_or_else(||item.status.clone());
        let version=match &existing {
            Some((_,old_fp,v)) if old_fp != &item.source_fingerprint => v+1,
            Some((_,_,v)) => *v,
            None => 1,
        };
        tx.execute("INSERT INTO contents(id,folder_path,title,client,content_type,status,workflow_status,source_fingerprint,version,refreshed_at,imported_at) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,datetime('now')) ON CONFLICT(id) DO UPDATE SET folder_path=excluded.folder_path,title=excluded.title,client=excluded.client,content_type=excluded.content_type,status=excluded.status,workflow_status=?7,source_fingerprint=excluded.source_fingerprint,version=?9,refreshed_at=excluded.refreshed_at,imported_at=excluded.imported_at",
            params![item.id,item.folder_path,item.title,item.client,item.content_type,item.validation_status,workflow,item.source_fingerprint,version,item.refreshed_at]).map_err(|e|e.to_string())?;

        let mut old_schedules=std::collections::HashMap::new();
        { let mut stmt=tx.prepare("SELECT id,scheduled_at,status,schedule_source FROM publication_targets WHERE content_id=?1").map_err(|e|e.to_string())?;
          let rows=stmt.query_map(params![item.id],|r|Ok((r.get::<_,String>(0)?,r.get::<_,Option<String>>(1)?,r.get::<_,String>(2)?,r.get::<_,Option<String>>(3)?))).map_err(|e|e.to_string())?;
          for row in rows { let (k,v,s,source)=row.map_err(|e|e.to_string())?; old_schedules.insert(k,(v,s,source)); } }

        tx.execute("DELETE FROM media_assets WHERE content_id=?1",params![item.id]).map_err(|e|e.to_string())?;
        tx.execute("DELETE FROM validation_issues WHERE content_id=?1",params![item.id]).map_err(|e|e.to_string())?;
        tx.execute("DELETE FROM publication_targets WHERE content_id=?1",params![item.id]).map_err(|e|e.to_string())?;
        for m in &item.media {
            tx.execute("INSERT INTO media_assets(id,content_id,path,kind,size_bytes,duration_seconds,sha256,modified_at) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)",params![m.id,item.id,m.path,m.kind,m.size_bytes as i64,m.duration_seconds,m.sha256,m.modified_at]).map_err(|e|e.to_string())?;
        }
        for t in &item.targets {
            let existing_target=old_schedules.get(&t.id);
            let manual=existing_target.and_then(|x|x.2.as_deref())==Some("MANUAL");
            let schedule=if manual { existing_target.and_then(|x|x.0.clone()) } else { t.scheduled_at.clone() };
            let schedule_source=if manual { Some("MANUAL".to_string()) } else { t.schedule_source.clone() };
            let target_status=if schedule.is_some(){"PRECALENDARIZED"}else{"READY"};
            tx.execute("INSERT INTO publication_targets(id,content_id,platform,account,status,scheduled_at,source_txt,copy,schedule_source) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)",params![t.id,item.id,t.platform,t.account,target_status,schedule,t.source_txt,t.copy,schedule_source]).map_err(|e|e.to_string())?;
        }
        for i in &item.issues {
            tx.execute("INSERT INTO validation_issues(id,content_id,severity,message) VALUES(?1,?2,?3,?4)",params![i.id,item.id,i.severity,i.message]).map_err(|e|e.to_string())?;
        }
    }
    tx.commit().map_err(|e|e.to_string())?;
    Ok(())
}

fn latest_note(conn:&Connection,content_id:&str)->Result<Option<CorrectionNote>,String>{
    let mut stmt=conn.prepare("SELECT id,body,created_at FROM correction_notes WHERE content_id=?1 ORDER BY created_at DESC LIMIT 1").map_err(|e|e.to_string())?;
    let mut rows=stmt.query(params![content_id]).map_err(|e|e.to_string())?;
    if let Some(r)=rows.next().map_err(|e|e.to_string())? { Ok(Some(CorrectionNote{id:r.get(0).map_err(|e|e.to_string())?,body:r.get(1).map_err(|e|e.to_string())?,created_at:r.get(2).map_err(|e|e.to_string())?})) } else { Ok(None) }
}

pub fn list(db:&Path)->Result<Vec<ContentItem>,String>{
    let conn=Connection::open(db).map_err(|e|e.to_string())?;
    let mut stmt=conn.prepare("SELECT id,folder_path,title,client,content_type,status,workflow_status,source_fingerprint,version,refreshed_at FROM contents ORDER BY imported_at DESC,title ASC").map_err(|e|e.to_string())?;
    let base=stmt.query_map([],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?,r.get::<_,Option<String>>(3)?,r.get::<_,String>(4)?,r.get::<_,String>(5)?,r.get::<_,String>(6)?,r.get::<_,Option<String>>(7)?,r.get::<_,i64>(8)?,r.get::<_,Option<String>>(9)?))).map_err(|e|e.to_string())?;
    let mut out=Vec::new();
    for row in base {
        let (id,folder,title,client,ctype,validation_status,workflow_status,source_fingerprint,version,refreshed_at)=row.map_err(|e|e.to_string())?;
        let mut ms=conn.prepare("SELECT id,path,kind,size_bytes,duration_seconds,sha256,modified_at FROM media_assets WHERE content_id=?1 ORDER BY path").map_err(|e|e.to_string())?;
        let media=ms.query_map(params![id.clone()],|r|Ok(MediaAsset{id:r.get(0)?,path:r.get(1)?,kind:r.get(2)?,size_bytes:r.get::<_,i64>(3)? as u64,duration_seconds:r.get(4)?,sha256:r.get(5)?,modified_at:r.get(6)?})).map_err(|e|e.to_string())?.collect::<Result<Vec<_>,_>>().map_err(|e|e.to_string())?;
        let mut ts=conn.prepare("SELECT id,platform,account,status,scheduled_at,source_txt,copy,schedule_source FROM publication_targets WHERE content_id=?1 ORDER BY platform").map_err(|e|e.to_string())?;
        let targets=ts.query_map(params![id.clone()],|r|Ok(PublicationTarget{id:r.get(0)?,platform:r.get(1)?,account:r.get(2)?,status:r.get(3)?,scheduled_at:r.get(4)?,source_txt:r.get(5)?,copy:r.get(6)?,schedule_source:r.get(7)?})).map_err(|e|e.to_string())?.collect::<Result<Vec<_>,_>>().map_err(|e|e.to_string())?;
        let mut is=conn.prepare("SELECT id,severity,message FROM validation_issues WHERE content_id=?1").map_err(|e|e.to_string())?;
        let issues=is.query_map(params![id.clone()],|r|Ok(ValidationIssue{id:r.get(0)?,severity:r.get(1)?,message:r.get(2)?})).map_err(|e|e.to_string())?.collect::<Result<Vec<_>,_>>().map_err(|e|e.to_string())?;
        out.push(ContentItem{id:id.clone(),folder_path:folder,title,client,content_type:ctype,status:workflow_status,validation_status,version,source_fingerprint,refreshed_at,latest_note:latest_note(&conn,&id)?,media,targets,issues});
    }
    Ok(out)
}

pub fn update_schedule(db:&Path,target_id:&str,scheduled_at:Option<&str>)->Result<bool,String>{
    let conn=Connection::open(db).map_err(|e|e.to_string())?;
    let status=if scheduled_at.is_some(){"PRECALENDARIZED"}else{"READY"};
    let n=conn.execute("UPDATE publication_targets SET scheduled_at=?1,status=?2,schedule_source='MANUAL' WHERE id=?3",params![scheduled_at,status,target_id]).map_err(|e|e.to_string())?;
    Ok(n>0)
}

pub fn update_workflow_status(db:&Path,content_id:&str,status:&str)->Result<bool,String>{
    let allowed=["EN_CONFIRMACION","CON_CORRECCION","LISTO_POR_PROGRAMAR","PROGRAMADO"];
    if !allowed.contains(&status){return Err("Estado editorial inválido.".into())}
    let conn=Connection::open(db).map_err(|e|e.to_string())?;
    let n=conn.execute("UPDATE contents SET workflow_status=?1 WHERE id=?2",params![status,content_id]).map_err(|e|e.to_string())?;
    let note_count:i64=conn.query_row("SELECT COUNT(*) FROM correction_notes WHERE content_id=?1",params![content_id],|r|r.get(0)).map_err(|e|e.to_string())?;
    drop(conn);
    if n>0 && note_count>0 {
        let (path,text)=correction_text(db,content_id)?;
        write_correction_file_atomic(&path,&text)?;
    }
    Ok(n>0)
}

pub fn add_note(db:&Path,content_id:&str,body:&str,status:&str)->Result<CorrectionNote,String>{
    if body.trim().is_empty(){return Err("La nota no puede estar vacía.".into())}
    update_workflow_status(db,content_id,status)?;
    let conn=Connection::open(db).map_err(|e|e.to_string())?;
    let now=Utc::now().to_rfc3339();
    let id=format!("note-{}",hex::encode(sha2::Sha256::digest(format!("{}:{}:{}",content_id,now,body).as_bytes()))[..20].to_string());
    conn.execute("INSERT INTO correction_notes(id,content_id,body,created_at) VALUES(?1,?2,?3,?4)",params![id,content_id,body.trim(),now]).map_err(|e|e.to_string())?;
    Ok(CorrectionNote{id,body:body.trim().to_string(),created_at:now})
}

pub fn correction_text(db:&Path,content_id:&str)->Result<(PathBuf,String),String>{
    let conn=Connection::open(db).map_err(|e|e.to_string())?;
    let (folder,title,status):(String,String,String)=conn.query_row("SELECT folder_path,title,workflow_status FROM contents WHERE id=?1",params![content_id],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).map_err(|e|e.to_string())?;
    let mut stmt=conn.prepare("SELECT body,created_at FROM correction_notes WHERE content_id=?1 ORDER BY created_at ASC").map_err(|e|e.to_string())?;
    let rows=stmt.query_map(params![content_id],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?))).map_err(|e|e.to_string())?;
    let mut text=format!("ABRAXAS_CORRECCION_V1\nCONTENT_ID: {}\nCONTENT: {}\nSTATUS: {}\nUPDATED_AT: {}\n\nNOTAS:\n",content_id,title,status,Utc::now().to_rfc3339());
    for row in rows { let (body,at)=row.map_err(|e|e.to_string())?; text.push_str(&format!("\n--- {} ---\n{}\n",at,body)); }
    Ok((PathBuf::from(folder).join("CORRECCION.txt"),text))
}

pub fn write_correction_file_atomic(path:&Path,text:&str)->Result<(),String>{
    let parent=path.parent().ok_or_else(||"Ruta de corrección inválida.".to_string())?;
    if !parent.is_dir(){return Err("La carpeta del contenido ya no existe.".into())}
    let tmp=parent.join(format!(".CORRECCION.txt.{}.tmp",std::process::id()));
    fs::write(&tmp,text).map_err(|e|e.to_string())?;
    fs::rename(&tmp,path).map_err(|e|{let _=fs::remove_file(&tmp);e.to_string()})?;
    Ok(())
}

pub fn clear(db:&Path)->Result<bool,String>{
    let conn=Connection::open(db).map_err(|e|e.to_string())?;
    conn.execute("DELETE FROM contents",[]).map_err(|e|e.to_string())?;
    Ok(true)
}
