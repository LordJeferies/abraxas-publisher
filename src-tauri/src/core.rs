use crate::{db, models::*, scanner};
use chrono::Utc;
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

fn retarget(item: &mut ContentItem) {
    for target in &mut item.targets {
        target.id = hash_id(&format!("{}:{}", item.id, target.platform));
    }
}

fn apply_brand(items: &mut [ContentItem], brand: &str) {
    for item in items {
        item.client = Some(brand.to_string());
    }
}

fn copy_dir_recursive(from: &Path, to: &Path) -> Result<(), String> {
    fs::create_dir_all(to).map_err(|e| e.to_string())?;

    for entry in fs::read_dir(from).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let src = entry.path();
        let dst = to.join(entry.file_name());

        if src.is_dir() {
            copy_dir_recursive(&src, &dst)?;
        } else {
            fs::copy(&src, &dst).map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}

pub fn preview_local(db_path: &Path, root: &Path, brand: &str) -> Result<ImportPreview, String> {
    let mut scan = scanner::scan(root)?;
    apply_brand(&mut scan.contents, brand);

    let mut duplicates = Vec::new();

    for incoming in &scan.contents {
        if let Some(existing) = db::find_duplicate(db_path, incoming)? {
            duplicates.push(DuplicateConflict {
                incoming_id: incoming.id.clone(),
                incoming_title: incoming.title.clone(),
                existing_id: existing.id.clone(),
                existing_title: existing.title.clone(),
                identical_fingerprint: incoming.source_fingerprint == existing.source_fingerprint,
            });
        }
    }

    Ok(ImportPreview {
        root_path: scan.root_path,
        contents: scan.contents,
        duplicates,
        warnings: scan.warnings,
        errors: scan.errors,
    })
}

pub fn commit_local(
    db_path: &Path,
    root: &Path,
    brand: &str,
    duplicate_policy: &str,
    keep_cache: &Path,
) -> Result<ScanResult, String> {
    let mut scan = scanner::scan(root)?;
    apply_brand(&mut scan.contents, brand);

    let mut final_items = Vec::new();

    for (index, mut incoming) in scan.contents.into_iter().enumerate() {
        let duplicate = db::find_duplicate(db_path, &incoming)?;

        match (duplicate, duplicate_policy) {
            (None, _) => {
                final_items.push(incoming);
            }

            (Some(existing), "skip") => {
                db::log_event(
                    db_path,
                    "DUPLICATE_SKIP",
                    "content",
                    &existing.id,
                    "Duplicado omitido",
                    None,
                    None,
                    false,
                    false,
                )?;
            }

            (Some(_existing), "keep") => {
                let src = PathBuf::from(&incoming.folder_path);

                let dst = keep_cache.join(format!(
                    "{}-{}-{}",
                    Utc::now().timestamp_millis(),
                    index,
                    src.file_name()
                        .and_then(|x| x.to_str())
                        .unwrap_or("content")
                ));

                copy_dir_recursive(&src, &dst)?;

                let mut copy = scanner::scan_content(&dst)?;
                copy.client = Some(brand.to_string());
                copy.source_kind = "local-copy".into();
                copy.source_ref = Some(incoming.folder_path.clone());

                final_items.push(copy);

                db::log_event(
                    db_path,
                    "DUPLICATE_KEEP",
                    "content",
                    &incoming.id,
                    "Duplicado conservado como contenido adicional",
                    None,
                    None,
                    false,
                    false,
                )?;
            }

            (Some(existing), _) => {
                incoming.id = existing.id.clone();
                retarget(&mut incoming);

                final_items.push(incoming);

                db::log_event(
                    db_path,
                    "DUPLICATE_REPLACE",
                    "content",
                    &existing.id,
                    "Contenido existente reemplazado por versión importada",
                    None,
                    None,
                    false,
                    false,
                )?;
            }
        }
    }

    db::upsert_scan(db_path, &final_items)?;

    db::log_event(
        db_path,
        "IMPORT",
        "workspace",
        &root.to_string_lossy(),
        &format!(
            "Importación completada · {} contenidos · marca {}",
            final_items.len(),
            brand
        ),
        None,
        None,
        false,
        false,
    )?;

    let warnings = final_items
        .iter()
        .flat_map(|c| &c.issues)
        .filter(|x| x.severity == "warning")
        .count();

    let errors = final_items
        .iter()
        .flat_map(|c| &c.issues)
        .filter(|x| x.severity == "error")
        .count();

    Ok(ScanResult {
        root_path: root.to_string_lossy().to_string(),
        imported_count: final_items.len(),
        contents: db::list(db_path)?,
        warnings,
        errors,
    })
}
