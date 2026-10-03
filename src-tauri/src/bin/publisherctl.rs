use abraxas_publisher_lib::{
    core, db, default_cache_dir, default_db_path, scanner, simulate_for_db,
};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

fn usage() {
    println!(
        r#"publisherctl

doctor

brands list
brands add NAME

content list
content show ID
content refresh ID

import local PATH --brand NAME --duplicates replace|keep|skip

status set ID STATUS

note add ID TEXTO...

schedule show ID
schedule set ID --platform instagram --at 2026-10-08T17:00:00
schedule clear ID --platform linkedin

activity
undo
redo
dry-run
qa
"#
    );
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|x| x == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn db_path() -> PathBuf {
    default_db_path()
}

fn init() -> Result<PathBuf, String> {
    let dbp = db_path();
    db::init(&dbp)?;
    Ok(dbp)
}

fn content_by_id(
    dbp: &Path,
    id: &str,
) -> Result<abraxas_publisher_lib::models::ContentItem, String> {
    db::list(dbp)?
        .into_iter()
        .find(|x| x.id == id)
        .ok_or_else(|| format!("Contenido no encontrado: {id}"))
}

fn doctor() -> Result<(), String> {
    let dbp = init()?;

    println!("ABRAXAS Publisher · Doctor CLI");
    println!("DB: {}", dbp.display());

    for cmd in ["ffmpeg", "ffprobe"] {
        let ok = Command::new(cmd)
            .arg("-version")
            .output()
            .map(|x| x.status.success())
            .unwrap_or(false);

        println!("{} {}", if ok { "OK" } else { "ERROR" }, cmd);

        if !ok {
            return Err(format!("Falta {cmd}"));
        }
    }

    println!("OK SQLite");

    Ok(())
}

fn qa() -> Result<(), String> {
    let root = std::env::temp_dir().join(format!(
        "abraxas-publisher-qa-{}",
        chrono::Utc::now().timestamp_millis()
    ));

    let dbp = root.join("qa.sqlite3");
    let content_root = root.join("week");
    let c = content_root.join("01_QA_CONTENT");
    let cache = root.join("cache");

    fs::create_dir_all(&c).map_err(|e| e.to_string())?;

    fs::write(c.join("post.jpg"), b"QA IMAGE PLACEHOLDER").map_err(|e| e.to_string())?;

    fs::write(
        c.join("instagram.txt"),
        b"PLATFORM: instagram\nACCOUNT: qa\nTYPE: image\nDATE: 2026-10-10\nTIME: 10:00\nCOPY:\nQA test",
    )
    .map_err(|e| e.to_string())?;

    db::init(&dbp)?;

    db::create_brand(&dbp, "QA")?;

    let preview = core::preview_local(&dbp, &content_root, "QA")?;

    if preview.contents.len() != 1 {
        return Err(format!(
            "QA import preview esperaba 1 contenido y obtuvo {}",
            preview.contents.len()
        ));
    }

    core::commit_local(&dbp, &content_root, "QA", "replace", &cache)?;

    let items = db::list(&dbp)?;

    if items.len() != 1 {
        return Err("QA import falló.".into());
    }

    let item = items[0].clone();

    db::update_workflow_status(&dbp, &item.id, "CON_CORRECCION")?;

    db::add_note(&dbp, &item.id, "QA correction", "CON_CORRECCION")?;

    let (correction_path, text) = db::correction_text(&dbp, &item.id)?;

    db::write_correction_file_atomic(&correction_path, &text)?;

    if !correction_path.exists() {
        return Err("QA CORRECCION.txt no se creó.".into());
    }

    let target = db::list(&dbp)?[0]
        .targets
        .first()
        .cloned()
        .ok_or("QA target ausente")?;

    db::update_schedule(&dbp, &target.id, Some("2026-10-12T15:00:00"))?;

    if db::list_activity(&dbp, 100)?.is_empty() {
        return Err("QA activity vacío.".into());
    }

    db::undo(&dbp)?;
    db::redo(&dbp)?;

    let sim = simulate_for_db(&dbp)?;

    if sim.total_targets == 0 {
        return Err("QA dry-run sin targets.".into());
    }

    // segundo import = conflicto
    let p2 = core::preview_local(&dbp, &content_root, "QA")?;

    if p2.duplicates.is_empty() {
        return Err("QA no detectó duplicado en segundo import.".into());
    }

    let _ = fs::remove_dir_all(&root);

    println!("PASS brand");
    println!("PASS import");
    println!("PASS duplicate detection");
    println!("PASS status");
    println!("PASS CORRECCION.txt");
    println!("PASS schedule");
    println!("PASS activity");
    println!("PASS undo/redo");
    println!("PASS dry-run");
    println!("QA APPROVED");

    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let result: Result<(), String> = (|| {
        if args.len() < 2 {
            usage();
            return Ok(());
        }

        match args[1].as_str() {
            "doctor" => doctor(),

            "qa" => qa(),

            "brands" if args.get(2).map(String::as_str) == Some("list") => {
                let dbp = init()?;
                println!(
                    "{}",
                    serde_json::to_string_pretty(&db::list_brands(&dbp)?)
                        .map_err(|e| e.to_string())?
                );
                Ok(())
            }

            "brands" if args.get(2).map(String::as_str) == Some("add") => {
                let dbp = init()?;
                let name = args[3..].join(" ");

                let brand = db::create_brand(&dbp, &name)?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&brand).map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "content" if args.get(2).map(String::as_str) == Some("list") => {
                let dbp = init()?;
                println!(
                    "{}",
                    serde_json::to_string_pretty(&db::list(&dbp)?).map_err(|e| e.to_string())?
                );
                Ok(())
            }

            "content" if args.get(2).map(String::as_str) == Some("show") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&content_by_id(&dbp, id)?)
                        .map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "content" if args.get(2).map(String::as_str) == Some("refresh") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let before = content_by_id(&dbp, id)?;

                let mut scanned = scanner::scan_content(Path::new(&before.folder_path))?;

                scanned.id = before.id;
                scanned.client = before.client;
                scanned.source_kind = before.source_kind;
                scanned.source_ref = before.source_ref;

                db::upsert_scan(&dbp, &[scanned])?;

                println!("OK refresh");
                Ok(())
            }

            "import" if args.get(2).map(String::as_str) == Some("local") => {
                let dbp = init()?;
                let path = args.get(3).ok_or("Falta PATH")?;

                let brand = flag(&args, "--brand").unwrap_or_else(|| "JOC".into());

                let policy = flag(&args, "--duplicates").unwrap_or_else(|| "replace".into());

                db::create_brand(&dbp, &brand)?;

                let r = core::commit_local(
                    &dbp,
                    Path::new(path),
                    &brand,
                    &policy,
                    &default_cache_dir().join("keep"),
                )?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&r).map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "status" if args.get(2).map(String::as_str) == Some("set") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let status = args.get(4).ok_or("Falta STATUS")?;

                db::update_workflow_status(&dbp, id, status)?;

                println!("OK");
                Ok(())
            }

            "note" if args.get(2).map(String::as_str) == Some("add") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let text = args[4..].join(" ");

                db::add_note(&dbp, id, &text, "CON_CORRECCION")?;

                let (path, body) = db::correction_text(&dbp, id)?;

                db::write_correction_file_atomic(&path, &body)?;

                println!("OK {}", path.display());
                Ok(())
            }

            "schedule" if args.get(2).map(String::as_str) == Some("show") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let content = content_by_id(&dbp, id)?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&content.targets).map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "schedule" if args.get(2).map(String::as_str) == Some("set") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let platform = flag(&args, "--platform").ok_or("Falta --platform")?;

                let at = flag(&args, "--at").ok_or("Falta --at")?;

                let content = content_by_id(&dbp, id)?;

                let target = content
                    .targets
                    .iter()
                    .find(|x| x.platform == platform)
                    .ok_or("Red no encontrada")?;

                db::update_schedule(&dbp, &target.id, Some(&at))?;

                println!("OK");
                Ok(())
            }

            "schedule" if args.get(2).map(String::as_str) == Some("clear") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let platform = flag(&args, "--platform").ok_or("Falta --platform")?;

                let content = content_by_id(&dbp, id)?;

                let target = content
                    .targets
                    .iter()
                    .find(|x| x.platform == platform)
                    .ok_or("Red no encontrada")?;

                db::update_schedule(&dbp, &target.id, None)?;

                println!("OK");
                Ok(())
            }

            "activity" => {
                let dbp = init()?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&db::list_activity(&dbp, 500)?)
                        .map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "undo" => {
                let dbp = init()?;
                println!("{:?}", db::undo(&dbp)?);
                Ok(())
            }

            "redo" => {
                let dbp = init()?;
                println!("{:?}", db::redo(&dbp)?);
                Ok(())
            }

            "dry-run" => {
                let dbp = init()?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&simulate_for_db(&dbp)?)
                        .map_err(|e| e.to_string())?
                );

                Ok(())
            }

            _ => {
                usage();
                Ok(())
            }
        }
    })();

    if let Err(e) = result {
        eprintln!("ERROR: {e}");
        std::process::exit(2);
    }
}
