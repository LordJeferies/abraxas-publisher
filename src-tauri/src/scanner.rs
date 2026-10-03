use crate::models::*;
use chrono::{DateTime, Utc};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::Command,
};
use walkdir::WalkDir;

pub fn stable_id(s: &str) -> String {
    let mut h = Sha256::new();
    h.update(s.as_bytes());
    hex::encode(h.finalize())[..20].to_string()
}

fn humanize(s: &str) -> String {
    s.replace('_', " ")
        .replace('-', " ")
        .split_whitespace()
        .map(|w| {
            let mut c = w.chars();
            match c.next() {
                None => String::new(),
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn platform_from_name(name: &str) -> Option<&'static str> {
    let n = name.to_ascii_lowercase();

    ["instagram", "facebook", "linkedin", "youtube"]
        .into_iter()
        .find(|p| n.contains(p))
}

fn parse_txt(path: &Path) -> HashMap<String, String> {
    let Ok(raw) = fs::read_to_string(path) else {
        return HashMap::new();
    };

    let raw = raw.trim_start_matches('\u{feff}').replace("\r\n", "\n");

    let mut out = HashMap::new();
    let mut current: Option<String> = None;

    for line in raw.lines() {
        let pair = line.split_once(':').or_else(|| line.split_once('='));

        if let Some((k, v)) = pair {
            let key = k.trim().to_ascii_uppercase();

            if key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && key.len() < 50 {
                out.insert(key.clone(), v.trim().to_string());
                current = Some(key);
                continue;
            }
        }

        if let Some(k) = &current {
            if !line.trim().is_empty() {
                out.entry(k.clone()).and_modify(|v| {
                    if !v.is_empty() {
                        v.push('\n');
                    }

                    v.push_str(line.trim());
                });
            }
        }
    }

    out
}

fn ffprobe_duration(path: &Path) -> Option<f64> {
    let out = Command::new("ffprobe")
        .args([
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
        ])
        .arg(path)
        .output()
        .ok()?;

    if !out.status.success() {
        return None;
    }

    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

fn sha256_file(path: &Path) -> Option<String> {
    let mut file = fs::File::open(path).ok()?;
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 1024 * 1024];

    loop {
        let n = file.read(&mut buffer).ok()?;

        if n == 0 {
            break;
        }

        hash.update(&buffer[..n]);
    }

    Some(hex::encode(hash.finalize()))
}

fn iso_mtime(path: &Path) -> Option<String> {
    let t = fs::metadata(path).ok()?.modified().ok()?;
    let dt: DateTime<Utc> = DateTime::<Utc>::from(t);

    Some(dt.to_rfc3339())
}

fn fingerprint_parts(parts: &[String]) -> String {
    let mut h = Sha256::new();

    for p in parts {
        h.update(p.as_bytes());
        h.update(b"\n");
    }

    hex::encode(h.finalize())
}

fn supported_media(ext: &str) -> Option<&'static str> {
    if ["mp4", "mov", "m4v", "webm"].contains(&ext) {
        Some("video")
    } else if ["jpg", "jpeg", "png", "webp", "heic"].contains(&ext) {
        Some("image")
    } else {
        None
    }
}

fn looks_like_content_dir(dir: &Path) -> bool {
    let Ok(rd) = fs::read_dir(dir) else {
        return false;
    };

    for e in rd.flatten() {
        let p = e.path();

        if !p.is_file() {
            continue;
        }

        let name = p.file_name().and_then(|x| x.to_str()).unwrap_or("");

        let ext = p
            .extension()
            .and_then(|x| x.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();

        if supported_media(&ext).is_some() {
            return true;
        }

        if ext == "txt" && name != "CORRECCION.txt" && platform_from_name(name).is_some() {
            return true;
        }
    }

    false
}

pub fn scan_one(dir: &Path, root: &Path) -> ContentItem {
    let folder = dir.to_string_lossy().to_string();

    let mut media = Vec::new();
    let mut txts = Vec::new();
    let mut fp = Vec::new();

    let drive_marker = dir.join(".abraxas_drive_id");

    let (source_kind, source_ref) = if drive_marker.is_file() {
        (
            "drive".to_string(),
            fs::read_to_string(&drive_marker)
                .ok()
                .map(|x| x.trim().to_string()),
        )
    } else {
        ("local".to_string(), Some(folder.clone()))
    };

    if let Ok(rd) = fs::read_dir(dir) {
        let mut entries: Vec<_> = rd.flatten().map(|e| e.path()).collect();
        entries.sort();

        for p in entries {
            if !p.is_file() {
                continue;
            }

            let ext = p
                .extension()
                .and_then(|x| x.to_str())
                .unwrap_or("")
                .to_ascii_lowercase();

            let name = p.file_name().and_then(|x| x.to_str()).unwrap_or("");

            if name == "CORRECCION.txt"
                || name.starts_with(".CORRECCION.txt")
                || name == ".abraxas_drive_id"
            {
                continue;
            }

            if ext == "txt" {
                let raw_hash = sha256_file(&p).unwrap_or_default();

                fp.push(format!(
                    "txt|{}|{}|{}",
                    name,
                    iso_mtime(&p).unwrap_or_default(),
                    raw_hash
                ));

                txts.push(p.clone());
                continue;
            }

            if let Some(kind) = supported_media(&ext) {
                let size = fs::metadata(&p).map(|m| m.len()).unwrap_or(0);
                let sha = sha256_file(&p);
                let modified_at = iso_mtime(&p);

                fp.push(format!(
                    "media|{}|{}|{}|{}",
                    name,
                    size,
                    modified_at.clone().unwrap_or_default(),
                    sha.clone().unwrap_or_default()
                ));

                media.push(MediaAsset {
                    id: stable_id(&p.to_string_lossy()),
                    path: p.to_string_lossy().to_string(),
                    kind: kind.into(),
                    size_bytes: size,
                    duration_seconds: if kind == "video" {
                        ffprobe_duration(&p)
                    } else {
                        None
                    },
                    sha256: sha,
                    modified_at,
                });
            }
        }
    }

    let mut target_maps = Vec::new();
    let mut explicit_content_id: Option<String> = None;
    let mut title: Option<String> = None;
    let mut client: Option<String> = None;
    let mut explicit_type: Option<String> = None;

    for txt in &txts {
        let map = parse_txt(txt);

        explicit_content_id = explicit_content_id.or_else(|| map.get("CONTENT_ID").cloned());

        title = title
            .or_else(|| map.get("NAME").cloned())
            .or_else(|| map.get("TITLE").cloned())
            .or_else(|| map.get("CONTENT_NAME").cloned());

        client = client
            .or_else(|| map.get("BRAND").cloned())
            .or_else(|| map.get("CLIENT").cloned());

        explicit_type = explicit_type.or_else(|| map.get("TYPE").map(|s| s.to_ascii_lowercase()));

        target_maps.push((txt.clone(), map));
    }

    let id = explicit_content_id
        .map(|x| stable_id(&format!("content-id:{x}")))
        .unwrap_or_else(|| stable_id(&folder));

    let mut targets = Vec::new();

    for (txt, map) in target_maps {
        let platform = map
            .get("PLATFORM")
            .map(|s| s.to_ascii_lowercase())
            .or_else(|| {
                platform_from_name(txt.file_name().and_then(|x| x.to_str()).unwrap_or(""))
                    .map(str::to_string)
            });

        let Some(platform) = platform else {
            continue;
        };

        let account = map.get("ACCOUNT").cloned();
        let date = map.get("DATE").cloned();
        let time = map.get("TIME").cloned();

        let scheduled_at = match (date, time) {
            (Some(d), Some(t)) => {
                let sec = if t.matches(':').count() >= 2 {
                    t
                } else {
                    format!("{t}:00")
                };

                Some(format!("{d}T{sec}"))
            }
            _ => None,
        };

        let copy = map.get("COPY").cloned();

        targets.push(PublicationTarget {
            id: stable_id(&format!("{id}:{platform}")),
            platform,
            account,
            status: if scheduled_at.is_some() {
                "PRECALENDARIZED".into()
            } else {
                "READY".into()
            },
            scheduled_at: scheduled_at.clone(),
            source_txt: Some(txt.to_string_lossy().to_string()),
            copy,
            schedule_source: if scheduled_at.is_some() {
                Some("TXT".into())
            } else {
                None
            },
        });
    }

    let ctype = explicit_type.unwrap_or_else(|| {
        let videos = media.iter().filter(|m| m.kind == "video").count();
        let images = media.iter().filter(|m| m.kind == "image").count();

        if videos > 0 {
            "reel".into()
        } else if images > 1 {
            "carousel".into()
        } else if images == 1 {
            "image".into()
        } else {
            "unknown".into()
        }
    });

    let title = title.unwrap_or_else(|| {
        humanize(
            dir.file_name()
                .and_then(|x| x.to_str())
                .unwrap_or("Contenido"),
        )
    });

    if client.is_none() {
        client = root.file_name().and_then(|x| x.to_str()).map(humanize);
    }

    let mut issues = Vec::new();

    if media.is_empty() {
        issues.push(ValidationIssue {
            id: format!("{id}-media"),
            severity: "error".into(),
            message: "No se encontró medio publicable.".into(),
        });
    }

    if targets.is_empty() {
        issues.push(ValidationIssue {
            id: format!("{id}-targets"),
            severity: "error".into(),
            message: "No se encontró TXT de red social.".into(),
        });
    }

    for t in &targets {
        if t.account.as_deref().unwrap_or("").is_empty() {
            issues.push(ValidationIssue {
                id: format!("{id}-{}-account", t.platform),
                severity: "warning".into(),
                message: format!("{} no tiene ACCOUNT definido.", t.platform),
            });
        }
    }

    let validation_status = if issues.iter().any(|i| i.severity == "error") {
        "INVALID"
    } else if issues.iter().any(|i| i.severity == "warning") {
        "WARNING"
    } else {
        "VALID"
    }
    .to_string();

    ContentItem {
        id,
        folder_path: folder,
        title,
        client,
        content_type: ctype,
        status: "EN_CONFIRMACION".into(),
        validation_status,
        version: 1,
        source_fingerprint: Some(fingerprint_parts(&fp)),
        refreshed_at: Some(Utc::now().to_rfc3339()),
        latest_note: None,
        source_kind,
        source_ref,
        media,
        targets,
        issues,
    }
}

pub fn scan(path: &Path) -> Result<ScanResult, String> {
    if !path.exists() {
        return Err("La carpeta no existe.".into());
    }

    let mut candidates: Vec<PathBuf> = WalkDir::new(path)
        .max_depth(6)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|e| e.file_type().is_dir())
        .map(|e| e.path().to_path_buf())
        .filter(|p| {
            p.file_name()
                .and_then(|x| x.to_str())
                .map(|x| !x.starts_with('.'))
                .unwrap_or(true)
        })
        .filter(|p| looks_like_content_dir(p))
        .collect();

    candidates.sort_by_key(|p| p.components().count());

    let mut dirs: Vec<PathBuf> = Vec::new();

    for candidate in candidates {
        if dirs
            .iter()
            .any(|parent| candidate != *parent && candidate.starts_with(parent))
        {
            continue;
        }

        dirs.push(candidate);
    }

    if dirs.is_empty() && looks_like_content_dir(path) {
        dirs.push(path.to_path_buf());
    }

    let contents: Vec<_> = dirs.iter().map(|d| scan_one(d, path)).collect();

    let warnings = contents
        .iter()
        .flat_map(|c| &c.issues)
        .filter(|i| i.severity == "warning")
        .count();

    let errors = contents
        .iter()
        .flat_map(|c| &c.issues)
        .filter(|i| i.severity == "error")
        .count();

    Ok(ScanResult {
        root_path: path.to_string_lossy().to_string(),
        imported_count: contents.len(),
        contents,
        warnings,
        errors,
    })
}

pub fn scan_content(folder: &Path) -> Result<ContentItem, String> {
    if !folder.is_dir() {
        return Err("La carpeta del contenido no existe.".into());
    }

    let root = folder.parent().unwrap_or(folder);

    Ok(scan_one(folder, root))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_is_stable() {
        assert_eq!(stable_id("abc"), stable_id("abc"));
        assert_ne!(stable_id("abc"), stable_id("abcd"));
    }
}
