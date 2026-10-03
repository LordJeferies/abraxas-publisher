#!/bin/bash
set -Eeuo pipefail

###############################################################################
# ABRAXAS PUBLISHER V1.2
# Aplicación directa · SIN CODEX
###############################################################################

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$ROOT/logs"
LOG="$LOG_DIR/v12_direct_$STAMP.log"
BRANCH="v1.2-workspace"
REMOTE="https://github.com/LordJeferies/abraxas-publisher.git"

mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS Publisher V1.2 · FALLO"
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

###############################################################################
# 1. PREFLIGHT
###############################################################################

section "1/13 · PREFLIGHT"

[ "$(uname -s)" = "Darwin" ] || fail "Este instalador necesita macOS."

for cmd in git gh node npm rustc cargo python3 ffmpeg ffprobe; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Falta dependencia: $cmd"
  echo "✓ $cmd"
done

gh auth status >/dev/null 2>&1 || fail "GitHub CLI no está autenticado."

###############################################################################
# 2. REPO
###############################################################################

section "2/13 · REPOSITORIO"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
else
  git remote add origin "$REMOTE"
fi

git fetch origin --prune

if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "Backup local antes de V1.2 directa $STAMP" || true
fi

git branch "backup/pre-direct-v12-$STAMP" HEAD 2>/dev/null || true

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH"
else
  git switch -c "$BRANCH" origin/main
fi

echo "✓ Rama: $(git branch --show-current)"

###############################################################################
# 3. DEPENDENCIAS FRONTEND
###############################################################################

section "3/13 · DEPENDENCIAS"

npm install \
  @dnd-kit/core@^6.3.1 \
  @dnd-kit/utilities@^3.2.2 \
  --save

npm pkg set version=0.3.0

python3 <<'PY'
from pathlib import Path
import re

p = Path("src-tauri/Cargo.toml")
s = p.read_text()

s = re.sub(
    r'(?m)^version = "[^"]+"',
    'version = "0.3.0"',
    s,
    count=1
)

deps = """
base64 = "0.22"
rand = "0.8"
reqwest = { version = "0.12", features = ["blocking", "json", "rustls-tls"] }
url = "2"
"""

if 'base64 = "0.22"' not in s:
    s += "\n" + deps

p.write_text(s)
PY

echo "0.3.0 · V1.2 Workspace" > VERSION.txt

###############################################################################
# 4. RUST MODELS
###############################################################################

section "4/13 · BACKEND RUST"

cat > src-tauri/src/models.rs <<'RS'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaAsset {
    pub id: String,
    pub path: String,
    pub kind: String,
    pub size_bytes: u64,
    pub duration_seconds: Option<f64>,
    pub sha256: Option<String>,
    pub modified_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublicationTarget {
    pub id: String,
    pub platform: String,
    pub account: Option<String>,
    pub status: String,
    pub scheduled_at: Option<String>,
    pub source_txt: Option<String>,
    pub copy: Option<String>,
    pub schedule_source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ValidationIssue {
    pub id: String,
    pub severity: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CorrectionNote {
    pub id: String,
    pub body: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentItem {
    pub id: String,
    pub folder_path: String,
    pub title: String,

    // client funciona como Brand en V1.2 para mantener compatibilidad
    // con la base SQLite anterior sin destruir datos.
    pub client: Option<String>,

    pub content_type: String,
    pub status: String,
    pub validation_status: String,
    pub version: i64,
    pub source_fingerprint: Option<String>,
    pub refreshed_at: Option<String>,
    pub latest_note: Option<CorrectionNote>,

    pub source_kind: String,
    pub source_ref: Option<String>,

    pub media: Vec<MediaAsset>,
    pub targets: Vec<PublicationTarget>,
    pub issues: Vec<ValidationIssue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanResult {
    pub root_path: String,
    pub imported_count: usize,
    pub contents: Vec<ContentItem>,
    pub warnings: usize,
    pub errors: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshResult {
    pub content: ContentItem,
    pub changed: bool,
    pub previous_version: i64,
    pub current_version: i64,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Brand {
    pub id: String,
    pub name: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DuplicateConflict {
    pub incoming_id: String,
    pub incoming_title: String,
    pub existing_id: String,
    pub existing_title: String,
    pub identical_fingerprint: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportPreview {
    pub root_path: String,
    pub contents: Vec<ContentItem>,
    pub duplicates: Vec<DuplicateConflict>,
    pub warnings: usize,
    pub errors: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleChange {
    pub target_id: String,
    pub scheduled_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityEvent {
    pub id: String,
    pub action: String,
    pub entity_type: String,
    pub entity_id: String,
    pub label: String,
    pub before_json: Option<String>,
    pub after_json: Option<String>,
    pub reversible: bool,
    pub remote: bool,
    pub undone: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DriveItem {
    pub id: String,
    pub name: String,
    pub mime_type: String,
    pub is_folder: bool,
    pub size: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DriveAuthResult {
    pub connected: bool,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SimulationPlatform {
    pub platform: String,
    pub total: usize,
    pub ready: usize,
    pub warnings: usize,
    pub errors: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SimulationReport {
    pub total_targets: usize,
    pub ready: usize,
    pub warnings: usize,
    pub errors: usize,
    pub generated_at: String,
    pub platforms: Vec<SimulationPlatform>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthReport {
    pub database: bool,
    pub ffmpeg: bool,
    pub ffprobe: bool,
    pub app_data_dir: String,
}
RS

###############################################################################
# 5. SCANNER
###############################################################################

cat > src-tauri/src/scanner.rs <<'RS'
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
        let pair = line
            .split_once(':')
            .or_else(|| line.split_once('='));

        if let Some((k, v)) = pair {
            let key = k.trim().to_ascii_uppercase();

            if key
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_')
                && key.len() < 50
            {
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

        let name = p
            .file_name()
            .and_then(|x| x.to_str())
            .unwrap_or("");

        let ext = p
            .extension()
            .and_then(|x| x.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();

        if supported_media(&ext).is_some() {
            return true;
        }

        if ext == "txt"
            && name != "CORRECCION.txt"
            && platform_from_name(name).is_some()
        {
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

            let name = p
                .file_name()
                .and_then(|x| x.to_str())
                .unwrap_or("");

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

        explicit_content_id = explicit_content_id
            .or_else(|| map.get("CONTENT_ID").cloned());

        title = title
            .or_else(|| map.get("NAME").cloned())
            .or_else(|| map.get("TITLE").cloned())
            .or_else(|| map.get("CONTENT_NAME").cloned());

        client = client
            .or_else(|| map.get("BRAND").cloned())
            .or_else(|| map.get("CLIENT").cloned());

        explicit_type = explicit_type
            .or_else(|| map.get("TYPE").map(|s| s.to_ascii_lowercase()));

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
                platform_from_name(
                    txt.file_name()
                        .and_then(|x| x.to_str())
                        .unwrap_or(""),
                )
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
        client = root
            .file_name()
            .and_then(|x| x.to_str())
            .map(humanize);
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
        if dirs.iter().any(|parent| {
            candidate != *parent && candidate.starts_with(parent)
        }) {
            continue;
        }

        dirs.push(candidate);
    }

    if dirs.is_empty() && looks_like_content_dir(path) {
        dirs.push(path.to_path_buf());
    }

    let contents: Vec<_> = dirs
        .iter()
        .map(|d| scan_one(d, path))
        .collect();

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
RS

###############################################################################
# 6. DATABASE
###############################################################################

cat > src-tauri/src/db.rs <<'RS'
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

fn has_column(
    conn: &Connection,
    table: &str,
    column: &str,
) -> Result<bool, String> {
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

pub fn create_brand(
    db: &Path,
    name: &str,
) -> Result<Brand, String> {
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
        .prepare("SELECT id,name,created_at FROM brands ORDER BY name COLLATE NOCASE")
        .map_err(|e| e.to_string())?;

    stmt.query_map([], |r| {
        Ok(Brand {
            id: r.get(0)?,
            name: r.get(1)?,
            created_at: r.get(2)?,
        })
    })
    .map_err(|e| e.to_string())?
    .collect::<Result<Vec<_>, _>>()
    .map_err(|e| e.to_string())
}

pub fn set_setting(
    db: &Path,
    key: &str,
    value: &str,
) -> Result<bool, String> {
    let conn = open(db)?;

    conn.execute(
        "INSERT INTO settings(key,value) VALUES(?1,?2)
         ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        params![key, value],
    )
    .map_err(|e| e.to_string())?;

    Ok(true)
}

pub fn get_setting(
    db: &Path,
    key: &str,
) -> Result<Option<String>, String> {
    let conn = open(db)?;

    conn.query_row(
        "SELECT value FROM settings WHERE key=?1",
        params![key],
        |r| r.get(0),
    )
    .optional()
    .map_err(|e| e.to_string())
}

fn latest_note(
    conn: &Connection,
    content_id: &str,
) -> Result<Option<CorrectionNote>, String> {
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

pub fn get_content_source(
    db: &Path,
    content_id: &str,
) -> Result<(String, Option<String>), String> {
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

pub fn upsert_scan(
    db: &Path,
    items: &[ContentItem],
) -> Result<(), String> {
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
                let (platform, schedule, status, source) =
                    row.map_err(|e| e.to_string())?;

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

            let manual = old
                .and_then(|x| x.2.as_deref())
                == Some("MANUAL");

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

    let base = stmt
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

    let mut out = Vec::new();

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
        ) = row.map_err(|e| e.to_string())?;

        let media = {
            let mut s = conn
                .prepare(
                    r#"
                    SELECT id,path,kind,size_bytes,duration_seconds,sha256,modified_at
                    FROM media_assets
                    WHERE content_id=?1
                    ORDER BY path
                    "#,
                )
                .map_err(|e| e.to_string())?;

            s.query_map(params![id.clone()], |r| {
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
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?
        };

        let targets = {
            let mut s = conn
                .prepare(
                    r#"
                    SELECT id,platform,account,status,scheduled_at,source_txt,copy,schedule_source
                    FROM publication_targets
                    WHERE content_id=?1
                    ORDER BY platform
                    "#,
                )
                .map_err(|e| e.to_string())?;

            s.query_map(params![id.clone()], |r| {
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
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?
        };

        let issues = {
            let mut s = conn
                .prepare(
                    "SELECT id,severity,message
                     FROM validation_issues
                     WHERE content_id=?1",
                )
                .map_err(|e| e.to_string())?;

            s.query_map(params![id.clone()], |r| {
                Ok(ValidationIssue {
                    id: r.get(0)?,
                    severity: r.get(1)?,
                    message: r.get(2)?,
                })
            })
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?
        };

        let (source_kind, source_ref) =
            source_for(&conn, &id, &folder)?;

        out.push(ContentItem {
            id: id.clone(),
            folder_path: folder,
            title,
            client,
            content_type: ctype,
            status: workflow_status,
            validation_status,
            version,
            source_fingerprint,
            refreshed_at,
            latest_note: latest_note(&conn, &id)?,
            source_kind,
            source_ref,
            media,
            targets,
            issues,
        });
    }

    Ok(out)
}

pub fn find_duplicate(
    db: &Path,
    incoming: &ContentItem,
) -> Result<Option<ContentItem>, String> {
    let contents = list(db)?;

    Ok(contents.into_iter().find(|existing| {
        existing.id == incoming.id
            || (
                incoming.source_fingerprint.is_some()
                && incoming.source_fingerprint == existing.source_fingerprint
            )
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
        hash_id(&format!(
            "{action}:{entity_type}:{entity_id}:{label}:{now}"
        ))
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

pub fn list_activity(
    db: &Path,
    limit: usize,
) -> Result<Vec<ActivityEvent>, String> {
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

    stmt.query_map(params![limit as i64], |r| {
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
    .map_err(|e| e.to_string())?
    .collect::<Result<Vec<_>, _>>()
    .map_err(|e| e.to_string())
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

    if current_status == "SCHEDULED_REMOTE"
        || current_status == "PUBLISHED"
    {
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

pub fn update_schedules(
    db: &Path,
    changes: &[ScheduleChange],
) -> Result<usize, String> {
    let mut changed = 0;

    for c in changes {
        if update_schedule(
            db,
            &c.target_id,
            c.scheduled_at.as_deref(),
        )? {
            changed += 1;
        }
    }

    Ok(changed)
}

pub fn update_workflow_status(
    db: &Path,
    content_id: &str,
    status: &str,
) -> Result<bool, String> {
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

    let id = format!(
        "note-{}",
        hash_id(&format!("{content_id}:{now}:{body}"))
    );

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

pub fn correction_text(
    db: &Path,
    content_id: &str,
) -> Result<(PathBuf, String), String> {
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
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
            ))
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

        text.push_str(&format!(
            "\n--- {at} ---\n{body}\n"
        ));
    }

    Ok((PathBuf::from(folder).join("CORRECCION.txt"), text))
}

pub fn write_correction_file_atomic(
    path: &Path,
    text: &str,
) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "Ruta inválida.".to_string())?;

    if !parent.is_dir() {
        return Err("La carpeta del contenido ya no existe.".into());
    }

    let tmp = parent.join(format!(
        ".CORRECCION.txt.{}.tmp",
        std::process::id()
    ));

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

    let value: serde_json::Value = serde_json::from_str(
        event.before_json.as_deref().unwrap_or("{}"),
    )
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
            let schedule = value
                .get("scheduledAt")
                .and_then(|x| x.as_str());

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

    let value: serde_json::Value = serde_json::from_str(
        event.after_json.as_deref().unwrap_or("{}"),
    )
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
            let schedule = value
                .get("scheduledAt")
                .and_then(|x| x.as_str());

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
RS

###############################################################################
# 7. IMPORT CORE
###############################################################################

cat > src-tauri/src/core.rs <<'RS'
use crate::{
    db,
    models::*,
    scanner,
};
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
        target.id = hash_id(
            &format!("{}:{}", item.id, target.platform)
        );
    }
}

fn apply_brand(
    items: &mut [ContentItem],
    brand: &str,
) {
    for item in items {
        item.client = Some(brand.to_string());
    }
}

fn copy_dir_recursive(
    from: &Path,
    to: &Path,
) -> Result<(), String> {
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

pub fn preview_local(
    db_path: &Path,
    root: &Path,
    brand: &str,
) -> Result<ImportPreview, String> {
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
                identical_fingerprint:
                    incoming.source_fingerprint
                        == existing.source_fingerprint,
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

            (Some(existing), "keep") => {
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
RS

###############################################################################
# 8. GOOGLE DRIVE
###############################################################################

cat > src-tauri/src/drive.rs <<'RS'
use crate::models::*;
use base64::{
    engine::general_purpose::URL_SAFE_NO_PAD,
    Engine,
};
use chrono::Utc;
use rand::{
    distributions::Alphanumeric,
    Rng,
};
use reqwest::blocking::Client;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    net::TcpListener,
    path::{Path, PathBuf},
    process::Command,
    sync::Mutex,
    thread,
    time::{Duration, Instant},
};
use url::Url;

const FOLDER_MIME: &str =
    "application/vnd.google-apps.folder";

#[derive(Default)]
pub struct DriveSession {
    pub access_token: Option<String>,
    pub expires_at: i64,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveFilesResponse {
    files: Vec<DriveApiFile>,
    next_page_token: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveApiFile {
    id: String,
    name: String,
    mime_type: String,
    size: Option<String>,
}

fn token(
    session: &Mutex<DriveSession>,
) -> Result<String, String> {
    let s = session.lock().map_err(|e| e.to_string())?;

    if s.access_token.is_none()
        || Utc::now().timestamp() >= s.expires_at
    {
        return Err(
            "Google Drive no está conectado o la sesión caducó.".into(),
        );
    }

    Ok(s.access_token.clone().unwrap())
}

pub fn connected(
    session: &Mutex<DriveSession>,
) -> bool {
    token(session).is_ok()
}

pub fn connect(
    client_id: &str,
    session: &Mutex<DriveSession>,
) -> Result<DriveAuthResult, String> {
    let client_id = client_id.trim();

    if !client_id.ends_with(".apps.googleusercontent.com") {
        return Err(
            "Introduce un OAuth Client ID de tipo Desktop terminado en .apps.googleusercontent.com."
                .into(),
        );
    }

    let listener = TcpListener::bind("127.0.0.1:0")
        .map_err(|e| e.to_string())?;

    listener
        .set_nonblocking(true)
        .map_err(|e| e.to_string())?;

    let port = listener
        .local_addr()
        .map_err(|e| e.to_string())?
        .port();

    let redirect = format!("http://127.0.0.1:{port}");

    let verifier: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(72)
        .map(char::from)
        .collect();

    let challenge =
        URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));

    let mut auth = Url::parse(
        "https://accounts.google.com/o/oauth2/v2/auth",
    )
    .map_err(|e| e.to_string())?;

    auth.query_pairs_mut()
        .append_pair("client_id", client_id)
        .append_pair("redirect_uri", &redirect)
        .append_pair("response_type", "code")
        .append_pair(
            "scope",
            "https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/drive.file",
        )
        .append_pair("code_challenge", &challenge)
        .append_pair("code_challenge_method", "S256")
        .append_pair("access_type", "offline")
        .append_pair("prompt", "consent");

    Command::new("open")
        .arg(auth.as_str())
        .spawn()
        .map_err(|e| {
            format!("No se pudo abrir el navegador: {e}")
        })?;

    let started = Instant::now();
    let code = loop {
        if started.elapsed() > Duration::from_secs(180) {
            return Err(
                "Tiempo agotado esperando autorización de Google.".into(),
            );
        }

        match listener.accept() {
            Ok((mut stream, _)) => {
                let mut buf = [0u8; 8192];
                let n = stream.read(&mut buf).unwrap_or(0);

                let request =
                    String::from_utf8_lossy(&buf[..n]);

                let first = request
                    .lines()
                    .next()
                    .unwrap_or("");

                let path = first
                    .split_whitespace()
                    .nth(1)
                    .unwrap_or("/");

                let parsed = Url::parse(
                    &format!("http://127.0.0.1{path}"),
                )
                .map_err(|e| e.to_string())?;

                let code = parsed
                    .query_pairs()
                    .find(|(k, _)| k == "code")
                    .map(|(_, v)| v.to_string());

                let error = parsed
                    .query_pairs()
                    .find(|(k, _)| k == "error")
                    .map(|(_, v)| v.to_string());

                let html = if code.is_some() {
                    "<html><body style='font-family:-apple-system;padding:40px'><h2>ABRAXAS Publisher</h2><p>Google Drive quedó autorizado. Puedes cerrar esta ventana y volver a Publisher.</p></body></html>"
                } else {
                    "<html><body style='font-family:-apple-system;padding:40px'><h2>ABRAXAS Publisher</h2><p>No se completó la autorización. Puedes volver a Publisher.</p></body></html>"
                };

                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    html.len(),
                    html
                );

                let _ = stream.write_all(response.as_bytes());

                if let Some(error) = error {
                    return Err(format!(
                        "Google rechazó la autorización: {error}"
                    ));
                }

                if let Some(code) = code {
                    break code;
                }
            }

            Err(e)
                if e.kind()
                    == std::io::ErrorKind::WouldBlock =>
            {
                thread::sleep(Duration::from_millis(150));
            }

            Err(e) => return Err(e.to_string()),
        }
    };

    let token_response = Client::new()
        .post("https://oauth2.googleapis.com/token")
        .form(&[
            ("client_id", client_id),
            ("code", &code),
            ("code_verifier", &verifier),
            ("redirect_uri", &redirect),
            ("grant_type", "authorization_code"),
        ])
        .send()
        .map_err(|e| e.to_string())?;

    if !token_response.status().is_success() {
        let status = token_response.status();
        let body = token_response.text().unwrap_or_default();

        return Err(format!(
            "Google token exchange falló ({status}): {body}"
        ));
    }

    let data: TokenResponse = token_response
        .json()
        .map_err(|e| e.to_string())?;

    {
        let mut s = session.lock().map_err(|e| e.to_string())?;

        s.access_token = Some(data.access_token);
        s.expires_at =
            Utc::now().timestamp() + data.expires_in - 60;
    }

    Ok(DriveAuthResult {
        connected: true,
        message: "Google Drive conectado.".into(),
    })
}

pub fn list(
    session: &Mutex<DriveSession>,
    folder_id: &str,
) -> Result<Vec<DriveItem>, String> {
    let access = token(session)?;
    let folder_id = if folder_id.trim().is_empty() {
        "root"
    } else {
        folder_id
    };

    let client = Client::new();
    let mut all = Vec::new();
    let mut page_token: Option<String> = None;

    loop {
        let q = format!(
            "'{}' in parents and trashed = false",
            folder_id.replace('\'', "\\'")
        );

        let mut req = client
            .get("https://www.googleapis.com/drive/v3/files")
            .bearer_auth(&access)
            .query(&[
                ("q", q.as_str()),
                ("fields", "nextPageToken,files(id,name,mimeType,size)"),
                ("pageSize", "1000"),
                ("orderBy", "folder,name"),
                ("supportsAllDrives", "true"),
                ("includeItemsFromAllDrives", "true"),
            ]);

        if let Some(token) = &page_token {
            req = req.query(&[("pageToken", token.as_str())]);
        }

        let response = req
            .send()
            .map_err(|e| e.to_string())?;

        if !response.status().is_success() {
            return Err(format!(
                "Drive API {}",
                response.status()
            ));
        }

        let data: DriveFilesResponse =
            response.json().map_err(|e| e.to_string())?;

        for f in data.files {
            all.push(DriveItem {
                id: f.id,
                name: f.name,
                is_folder: f.mime_type == FOLDER_MIME,
                mime_type: f.mime_type,
                size: f.size.and_then(|x| x.parse().ok()),
            });
        }

        page_token = data.next_page_token;

        if page_token.is_none() {
            break;
        }
    }

    Ok(all)
}

fn folder_meta(
    session: &Mutex<DriveSession>,
    id: &str,
) -> Result<DriveApiFile, String> {
    let access = token(session)?;

    let response = Client::new()
        .get(format!(
            "https://www.googleapis.com/drive/v3/files/{id}"
        ))
        .bearer_auth(access)
        .query(&[
            ("fields", "id,name,mimeType,size"),
            ("supportsAllDrives", "true"),
        ])
        .send()
        .map_err(|e| e.to_string())?;

    if !response.status().is_success() {
        return Err(format!(
            "No se pudo leer carpeta Drive: {}",
            response.status()
        ));
    }

    response.json().map_err(|e| e.to_string())
}

fn safe_name(name: &str) -> String {
    let clean: String = name
        .chars()
        .map(|c| {
            if c == '/' || c == '\\' || c == ':' {
                '_'
            } else {
                c
            }
        })
        .collect();

    if clean.trim().is_empty() {
        "drive-item".into()
    } else {
        clean
    }
}

fn downloadable(mime: &str) -> bool {
    mime.starts_with("video/")
        || mime.starts_with("image/")
        || mime == "text/plain"
        || mime == "application/json"
}

fn download_file(
    session: &Mutex<DriveSession>,
    id: &str,
    destination: &Path,
) -> Result<(), String> {
    let access = token(session)?;

    let response = Client::new()
        .get(format!(
            "https://www.googleapis.com/drive/v3/files/{id}?alt=media&supportsAllDrives=true"
        ))
        .bearer_auth(access)
        .send()
        .map_err(|e| e.to_string())?;

    if !response.status().is_success() {
        return Err(format!(
            "No se pudo descargar {id}: {}",
            response.status()
        ));
    }

    let bytes = response.bytes().map_err(|e| e.to_string())?;

    fs::write(destination, &bytes).map_err(|e| e.to_string())
}

fn download_folder_recursive(
    session: &Mutex<DriveSession>,
    folder_id: &str,
    destination: &Path,
    depth: usize,
) -> Result<(), String> {
    if depth > 8 {
        return Err(
            "La carpeta excede la profundidad máxima de 8 niveles.".into(),
        );
    }

    fs::create_dir_all(destination)
        .map_err(|e| e.to_string())?;

    fs::write(
        destination.join(".abraxas_drive_id"),
        folder_id,
    )
    .map_err(|e| e.to_string())?;

    for item in list(session, folder_id)? {
        let dst = destination.join(safe_name(&item.name));

        if item.is_folder {
            download_folder_recursive(
                session,
                &item.id,
                &dst,
                depth + 1,
            )?;
        } else if downloadable(&item.mime_type) {
            download_file(session, &item.id, &dst)?;
        }
    }

    Ok(())
}

pub fn download_tree(
    session: &Mutex<DriveSession>,
    folder_id: &str,
    cache_root: &Path,
) -> Result<PathBuf, String> {
    let meta = folder_meta(session, folder_id)?;

    let destination = cache_root
        .join(folder_id)
        .join(safe_name(&meta.name));

    fs::create_dir_all(&destination)
        .map_err(|e| e.to_string())?;

    download_folder_recursive(
        session,
        folder_id,
        &destination,
        0,
    )?;

    Ok(destination)
}

pub fn upload_correction_text(
    session: &Mutex<DriveSession>,
    folder_id: &str,
    text: &str,
) -> Result<(), String> {
    let access = token(session)?;
    let client = Client::new();

    let q = format!(
        "'{}' in parents and trashed=false and name='CORRECCION.txt'",
        folder_id.replace('\'', "\\'")
    );

    let existing: DriveFilesResponse = client
        .get("https://www.googleapis.com/drive/v3/files")
        .bearer_auth(&access)
        .query(&[
            ("q", q.as_str()),
            ("fields", "files(id,name,mimeType,size)"),
            ("pageSize", "10"),
            ("supportsAllDrives", "true"),
            ("includeItemsFromAllDrives", "true"),
        ])
        .send()
        .map_err(|e| e.to_string())?
        .json()
        .map_err(|e| e.to_string())?;

    if let Some(file) = existing.files.first() {
        let r = client
            .patch(format!(
                "https://www.googleapis.com/upload/drive/v3/files/{}?uploadType=media&supportsAllDrives=true",
                file.id
            ))
            .bearer_auth(&access)
            .header("Content-Type", "text/plain; charset=utf-8")
            .body(text.to_string())
            .send()
            .map_err(|e| e.to_string())?;

        if !r.status().is_success() {
            return Err(format!(
                "No se pudo actualizar CORRECCION.txt en Drive: {}",
                r.status()
            ));
        }

        return Ok(());
    }

    let boundary = format!(
        "abraxas-{}",
        Utc::now().timestamp_millis()
    );

    let metadata = serde_json::json!({
        "name": "CORRECCION.txt",
        "mimeType": "text/plain",
        "parents": [folder_id]
    });

    let body = format!(
        "--{boundary}\r\n\
         Content-Type: application/json; charset=UTF-8\r\n\r\n\
         {}\r\n\
         --{boundary}\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         {text}\r\n\
         --{boundary}--",
        metadata
    );

    let r = client
        .post(
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true",
        )
        .bearer_auth(&access)
        .header(
            "Content-Type",
            format!("multipart/related; boundary={boundary}"),
        )
        .body(body)
        .send()
        .map_err(|e| e.to_string())?;

    if !r.status().is_success() {
        return Err(format!(
            "No se pudo crear CORRECCION.txt en Drive: {}",
            r.status()
        ));
    }

    Ok(())
}
RS

###############################################################################
# 9. LIB / TAURI COMMANDS
###############################################################################

cat > src-tauri/src/lib.rs <<'RS'
pub mod core;
pub mod db;
pub mod drive;
pub mod models;
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

    let home = std::env::var("HOME")
        .unwrap_or_else(|_| ".".into());

    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("com.abraxas.publisher")
        .join("abraxas-publisher.sqlite3")
}

pub fn default_cache_dir() -> PathBuf {
    let db = default_db_path();

    db.parent()
        .unwrap_or(Path::new("."))
        .join("cache")
}

fn command_exists(cmd: &str) -> bool {
    Command::new(cmd)
        .arg("-version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

pub fn simulate_for_db(
    db_path: &Path,
) -> Result<SimulationReport, String> {
    let contents = db::list(db_path)?;

    let mut by: BTreeMap<String, (usize, usize, usize, usize)> =
        BTreeMap::new();

    let mut ready = 0;
    let mut warnings = 0;
    let mut errors = 0;

    for c in &contents {
        for t in &c.targets {
            let has_error =
                c.issues.iter().any(|i| i.severity == "error");

            let editorial_ready =
                c.status == "LISTO_POR_PROGRAMAR"
                    || c.status == "PROGRAMADO";

            let has_warn =
                c.issues.iter().any(|i| i.severity == "warning")
                    || t.scheduled_at.is_none()
                    || !editorial_ready;

            let e = by
                .entry(t.platform.clone())
                .or_insert((0, 0, 0, 0));

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
        .map(
            |(platform, (total, ok, w, e))| SimulationPlatform {
                platform,
                total,
                ready: ok,
                warnings: w,
                errors: e,
            },
        )
        .collect::<Vec<_>>();

    Ok(SimulationReport {
        total_targets: ready + warnings + errors,
        ready,
        warnings,
        errors,
        generated_at: Utc::now().to_rfc3339(),
        platforms,
        note:
            "SIMULACIÓN LOCAL: no se llamó ninguna API social y no se publicó nada."
                .into(),
    })
}

#[tauri::command]
fn health(
    state: State<'_, AppState>,
) -> Result<HealthReport, String> {
    Ok(HealthReport {
        database: state.db_path.exists(),
        ffmpeg: command_exists("ffmpeg"),
        ffprobe: command_exists("ffprobe"),
        app_data_dir: state
            .app_data_dir
            .to_string_lossy()
            .to_string(),
    })
}

#[tauri::command]
fn list_brands(
    state: State<'_, AppState>,
) -> Result<Vec<Brand>, String> {
    db::list_brands(&state.db_path)
}

#[tauri::command]
fn create_brand(
    name: String,
    state: State<'_, AppState>,
) -> Result<Brand, String> {
    db::create_brand(&state.db_path, &name)
}

#[tauri::command]
fn preview_import_local(
    path: String,
    brand: String,
    state: State<'_, AppState>,
) -> Result<ImportPreview, String> {
    core::preview_local(
        &state.db_path,
        Path::new(&path),
        &brand,
    )
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
fn import_folder(
    path: String,
    state: State<'_, AppState>,
) -> Result<ScanResult, String> {
    core::commit_local(
        &state.db_path,
        Path::new(&path),
        "JOC",
        "replace",
        &state.app_data_dir.join("duplicate-imports"),
    )
}

#[tauri::command]
fn list_contents(
    state: State<'_, AppState>,
) -> Result<Vec<ContentItem>, String> {
    db::list(&state.db_path)
}

#[tauri::command]
fn update_schedule(
    target_id: String,
    scheduled_at: Option<String>,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    db::update_schedule(
        &state.db_path,
        &target_id,
        scheduled_at.as_deref(),
    )
}

#[tauri::command]
fn update_schedules(
    changes: Vec<ScheduleChange>,
    state: State<'_, AppState>,
) -> Result<usize, String> {
    db::update_schedules(
        &state.db_path,
        &changes,
    )
}

#[tauri::command]
fn update_workflow_status(
    content_id: String,
    status: String,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    db::update_workflow_status(
        &state.db_path,
        &content_id,
        &status,
    )
}

#[tauri::command]
fn save_correction_note(
    content_id: String,
    note: String,
    status: String,
    state: State<'_, AppState>,
) -> Result<CorrectionNote, String> {
    let saved = db::add_note(
        &state.db_path,
        &content_id,
        &note,
        &status,
    )?;

    let (path, text) =
        db::correction_text(&state.db_path, &content_id)?;

    db::write_correction_file_atomic(&path, &text)?;

    if let Ok((kind, Some(folder_id))) =
        db::get_content_source(&state.db_path, &content_id)
    {
        if kind == "drive" && drive::connected(&state.drive) {
            let _ = drive::upload_correction_text(
                &state.drive,
                &folder_id,
                &text,
            );
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

    let mut scanned = scanner::scan_content(
        PathBuf::from(&before.folder_path).as_path(),
    )?;

    scanned.id = before.id.clone();
    scanned.client = before.client.clone();
    scanned.source_kind = before.source_kind.clone();
    scanned.source_ref = before.source_ref.clone();

    for target in &mut scanned.targets {
        target.id = scanner::stable_id(
            &format!("{}:{}", scanned.id, target.platform),
        );
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
                previous_version,
                content.version
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
fn list_activity(
    state: State<'_, AppState>,
) -> Result<Vec<ActivityEvent>, String> {
    db::list_activity(&state.db_path, 500)
}

#[tauri::command]
fn undo_last(
    state: State<'_, AppState>,
) -> Result<Option<ActivityEvent>, String> {
    db::undo(&state.db_path)
}

#[tauri::command]
fn redo_last(
    state: State<'_, AppState>,
) -> Result<Option<ActivityEvent>, String> {
    db::redo(&state.db_path)
}

#[tauri::command]
fn get_drive_client_id(
    state: State<'_, AppState>,
) -> Result<Option<String>, String> {
    db::get_setting(
        &state.db_path,
        "google_drive_client_id",
    )
}

#[tauri::command]
fn set_drive_client_id(
    client_id: String,
    state: State<'_, AppState>,
) -> Result<bool, String> {
    db::set_setting(
        &state.db_path,
        "google_drive_client_id",
        client_id.trim(),
    )
}

#[tauri::command]
fn drive_status(
    state: State<'_, AppState>,
) -> bool {
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
        db::set_setting(
            &db_path,
            "google_drive_client_id",
            client_id.trim(),
        )?;

        drive::connect(
            &client_id,
            &session,
        )
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
        let root = drive::download_tree(
            &session,
            &folder_id,
            &cache,
        )?;

        core::preview_local(
            &db,
            &root,
            &brand,
        )
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
        let root = drive::download_tree(
            &session,
            &folder_id,
            &app_data.join("drive-cache"),
        )?;

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
fn simulate_batch(
    state: State<'_, AppState>,
) -> Result<SimulationReport, String> {
    simulate_for_db(&state.db_path)
}

#[tauri::command]
fn clear_workspace(
    state: State<'_, AppState>,
) -> Result<bool, String> {
    db::clear(&state.db_path)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let dir = app.path().app_data_dir()?;

            std::fs::create_dir_all(&dir)?;

            let db_path =
                dir.join("abraxas-publisher.sqlite3");

            db::init(&db_path)
                .map_err(std::io::Error::other)?;

            app.manage(AppState {
                db_path,
                app_data_dir: dir,
                drive: Arc::new(Mutex::new(
                    drive::DriveSession::default(),
                )),
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            health,
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
RS

###############################################################################
# 10. CLI publisherctl
###############################################################################

mkdir -p src-tauri/src/bin

cat > src-tauri/src/bin/publisherctl.rs <<'RS'
use abraxas_publisher_lib::{
    core,
    db,
    default_cache_dir,
    default_db_path,
    scanner,
    simulate_for_db,
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

fn flag(
    args: &[String],
    name: &str,
) -> Option<String> {
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

        println!(
            "{} {}",
            if ok { "OK" } else { "ERROR" },
            cmd
        );

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

    fs::write(
        c.join("post.jpg"),
        b"QA IMAGE PLACEHOLDER",
    )
    .map_err(|e| e.to_string())?;

    fs::write(
        c.join("instagram.txt"),
        b"PLATFORM: instagram\nACCOUNT: qa\nTYPE: image\nDATE: 2026-10-10\nTIME: 10:00\nCOPY:\nQA test",
    )
    .map_err(|e| e.to_string())?;

    db::init(&dbp)?;

    db::create_brand(&dbp, "QA")?;

    let preview =
        core::preview_local(&dbp, &content_root, "QA")?;

    if preview.contents.len() != 1 {
        return Err(format!(
            "QA import preview esperaba 1 contenido y obtuvo {}",
            preview.contents.len()
        ));
    }

    core::commit_local(
        &dbp,
        &content_root,
        "QA",
        "replace",
        &cache,
    )?;

    let items = db::list(&dbp)?;

    if items.len() != 1 {
        return Err("QA import falló.".into());
    }

    let item = items[0].clone();

    db::update_workflow_status(
        &dbp,
        &item.id,
        "CON_CORRECCION",
    )?;

    db::add_note(
        &dbp,
        &item.id,
        "QA correction",
        "CON_CORRECCION",
    )?;

    let (correction_path, text) =
        db::correction_text(&dbp, &item.id)?;

    db::write_correction_file_atomic(
        &correction_path,
        &text,
    )?;

    if !correction_path.exists() {
        return Err("QA CORRECCION.txt no se creó.".into());
    }

    let target = db::list(&dbp)?[0]
        .targets
        .first()
        .cloned()
        .ok_or("QA target ausente")?;

    db::update_schedule(
        &dbp,
        &target.id,
        Some("2026-10-12T15:00:00"),
    )?;

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
    let p2 =
        core::preview_local(&dbp, &content_root, "QA")?;

    if p2.duplicates.is_empty() {
        return Err(
            "QA no detectó duplicado en segundo import.".into(),
        );
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
                    serde_json::to_string_pretty(
                        &db::list_brands(&dbp)?
                    )
                    .map_err(|e| e.to_string())?
                );
                Ok(())
            }

            "brands" if args.get(2).map(String::as_str) == Some("add") => {
                let dbp = init()?;
                let name = args[3..].join(" ");

                let brand =
                    db::create_brand(&dbp, &name)?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&brand)
                        .map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "content" if args.get(2).map(String::as_str) == Some("list") => {
                let dbp = init()?;
                println!(
                    "{}",
                    serde_json::to_string_pretty(&db::list(&dbp)?)
                        .map_err(|e| e.to_string())?
                );
                Ok(())
            }

            "content" if args.get(2).map(String::as_str) == Some("show") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(
                        &content_by_id(&dbp, id)?
                    )
                    .map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "content" if args.get(2).map(String::as_str) == Some("refresh") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let before = content_by_id(&dbp, id)?;

                let mut scanned =
                    scanner::scan_content(
                        Path::new(&before.folder_path)
                    )?;

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

                let brand =
                    flag(&args, "--brand")
                        .unwrap_or_else(|| "JOC".into());

                let policy =
                    flag(&args, "--duplicates")
                        .unwrap_or_else(|| "replace".into());

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
                    serde_json::to_string_pretty(&r)
                        .map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "status" if args.get(2).map(String::as_str) == Some("set") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let status = args.get(4).ok_or("Falta STATUS")?;

                db::update_workflow_status(
                    &dbp,
                    id,
                    status,
                )?;

                println!("OK");
                Ok(())
            }

            "note" if args.get(2).map(String::as_str) == Some("add") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let text = args[4..].join(" ");

                db::add_note(
                    &dbp,
                    id,
                    &text,
                    "CON_CORRECCION",
                )?;

                let (path, body) =
                    db::correction_text(&dbp, id)?;

                db::write_correction_file_atomic(
                    &path,
                    &body,
                )?;

                println!("OK {}", path.display());
                Ok(())
            }

            "schedule" if args.get(2).map(String::as_str) == Some("show") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let content = content_by_id(&dbp, id)?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(&content.targets)
                        .map_err(|e| e.to_string())?
                );

                Ok(())
            }

            "schedule" if args.get(2).map(String::as_str) == Some("set") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let platform =
                    flag(&args, "--platform")
                        .ok_or("Falta --platform")?;

                let at =
                    flag(&args, "--at")
                        .ok_or("Falta --at")?;

                let content = content_by_id(&dbp, id)?;

                let target = content
                    .targets
                    .iter()
                    .find(|x| x.platform == platform)
                    .ok_or("Red no encontrada")?;

                db::update_schedule(
                    &dbp,
                    &target.id,
                    Some(&at),
                )?;

                println!("OK");
                Ok(())
            }

            "schedule" if args.get(2).map(String::as_str) == Some("clear") => {
                let dbp = init()?;
                let id = args.get(3).ok_or("Falta ID")?;
                let platform =
                    flag(&args, "--platform")
                        .ok_or("Falta --platform")?;

                let content = content_by_id(&dbp, id)?;

                let target = content
                    .targets
                    .iter()
                    .find(|x| x.platform == platform)
                    .ok_or("Red no encontrada")?;

                db::update_schedule(
                    &dbp,
                    &target.id,
                    None,
                )?;

                println!("OK");
                Ok(())
            }

            "activity" => {
                let dbp = init()?;

                println!(
                    "{}",
                    serde_json::to_string_pretty(
                        &db::list_activity(&dbp, 500)?
                    )
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
                    serde_json::to_string_pretty(
                        &simulate_for_db(&dbp)?
                    )
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
RS

###############################################################################
# 11. FRONTEND TYPES / BACKEND / STORE
###############################################################################

cat > src/types.ts <<'TS'
export type Platform =
  | 'instagram'
  | 'facebook'
  | 'linkedin'
  | 'youtube'
  | string

export type ContentType =
  | 'reel'
  | 'video'
  | 'carousel'
  | 'image'
  | 'unknown'
  | string

export type WorkflowStatus =
  | 'EN_CONFIRMACION'
  | 'CON_CORRECCION'
  | 'LISTO_POR_PROGRAMAR'
  | 'PROGRAMADO'

export type ValidationStatus =
  | 'VALID'
  | 'WARNING'
  | 'INVALID'
  | string

export type InspectorMode =
  | 'hidden'
  | 'docked'
  | 'floating'

export interface MediaAsset {
  id: string
  path: string
  kind: 'video' | 'image' | string
  sizeBytes: number
  durationSeconds?: number | null
  sha256?: string | null
  modifiedAt?: string | null
}

export interface PublicationTarget {
  id: string
  platform: Platform
  account?: string | null
  status: string
  scheduledAt?: string | null
  sourceTxt?: string | null
  copy?: string | null
  scheduleSource?: string | null
}

export interface ValidationIssue {
  id: string
  severity: 'warning' | 'error' | string
  message: string
}

export interface CorrectionNote {
  id: string
  body: string
  createdAt: string
}

export interface ContentItem {
  id: string
  folderPath: string
  title: string
  client?: string | null
  contentType: ContentType
  status: WorkflowStatus | string
  validationStatus: ValidationStatus
  version: number
  sourceFingerprint?: string | null
  refreshedAt?: string | null
  latestNote?: CorrectionNote | null
  sourceKind: string
  sourceRef?: string | null
  media: MediaAsset[]
  targets: PublicationTarget[]
  issues: ValidationIssue[]
}

export interface Brand {
  id: string
  name: string
  createdAt: string
}

export interface DuplicateConflict {
  incomingId: string
  incomingTitle: string
  existingId: string
  existingTitle: string
  identicalFingerprint: boolean
}

export interface ImportPreview {
  rootPath: string
  contents: ContentItem[]
  duplicates: DuplicateConflict[]
  warnings: number
  errors: number
}

export interface ScanResult {
  rootPath: string
  importedCount: number
  contents: ContentItem[]
  warnings: number
  errors: number
}

export interface RefreshResult {
  content: ContentItem
  changed: boolean
  previousVersion: number
  currentVersion: number
  message: string
}

export interface ScheduleChange {
  targetId: string
  scheduledAt: string | null
}

export interface ActivityEvent {
  id: string
  action: string
  entityType: string
  entityId: string
  label: string
  beforeJson?: string | null
  afterJson?: string | null
  reversible: boolean
  remote: boolean
  undone: boolean
  createdAt: string
}

export interface DriveItem {
  id: string
  name: string
  mimeType: string
  isFolder: boolean
  size?: number | null
}

export interface DriveAuthResult {
  connected: boolean
  message: string
}

export interface SimulationPlatform {
  platform: string
  total: number
  ready: number
  warnings: number
  errors: number
}

export interface SimulationReport {
  totalTargets: number
  ready: number
  warnings: number
  errors: number
  generatedAt: string
  platforms: SimulationPlatform[]
  note: string
}

export interface HealthReport {
  database: boolean
  ffmpeg: boolean
  ffprobe: boolean
  appDataDir: string
}
TS

cat > src/lib/backend.ts <<'TS'
import { invoke } from '@tauri-apps/api/core'

import type {
  ActivityEvent,
  Brand,
  ContentItem,
  CorrectionNote,
  DriveAuthResult,
  DriveItem,
  HealthReport,
  ImportPreview,
  RefreshResult,
  ScanResult,
  ScheduleChange,
  SimulationReport,
  WorkflowStatus,
} from '../types'

export const backend = {
  health: () =>
    invoke<HealthReport>('health'),

  listBrands: () =>
    invoke<Brand[]>('list_brands'),

  createBrand: (name: string) =>
    invoke<Brand>('create_brand', { name }),

  previewImportLocal: (
    path: string,
    brand: string,
  ) =>
    invoke<ImportPreview>(
      'preview_import_local',
      { path, brand },
    ),

  commitImportLocal: (
    path: string,
    brand: string,
    duplicatePolicy: 'replace' | 'keep' | 'skip',
  ) =>
    invoke<ScanResult>(
      'commit_import_local',
      { path, brand, duplicatePolicy },
    ),

  importFolder: (path: string) =>
    invoke<ScanResult>(
      'import_folder',
      { path },
    ),

  listContents: () =>
    invoke<ContentItem[]>('list_contents'),

  updateSchedule: (
    targetId: string,
    scheduledAt: string | null,
  ) =>
    invoke<boolean>(
      'update_schedule',
      { targetId, scheduledAt },
    ),

  updateSchedules: (
    changes: ScheduleChange[],
  ) =>
    invoke<number>(
      'update_schedules',
      { changes },
    ),

  updateWorkflowStatus: (
    contentId: string,
    status: WorkflowStatus,
  ) =>
    invoke<boolean>(
      'update_workflow_status',
      { contentId, status },
    ),

  saveCorrectionNote: (
    contentId: string,
    note: string,
    status: WorkflowStatus,
  ) =>
    invoke<CorrectionNote>(
      'save_correction_note',
      { contentId, note, status },
    ),

  refreshContent: (contentId: string) =>
    invoke<RefreshResult>(
      'refresh_content',
      { contentId },
    ),

  listActivity: () =>
    invoke<ActivityEvent[]>(
      'list_activity',
    ),

  undo: () =>
    invoke<ActivityEvent | null>(
      'undo_last',
    ),

  redo: () =>
    invoke<ActivityEvent | null>(
      'redo_last',
    ),

  getDriveClientId: () =>
    invoke<string | null>(
      'get_drive_client_id',
    ),

  setDriveClientId: (clientId: string) =>
    invoke<boolean>(
      'set_drive_client_id',
      { clientId },
    ),

  driveStatus: () =>
    invoke<boolean>(
      'drive_status',
    ),

  driveConnect: (clientId: string) =>
    invoke<DriveAuthResult>(
      'drive_connect',
      { clientId },
    ),

  driveList: (folderId = 'root') =>
    invoke<DriveItem[]>(
      'drive_list',
      { folderId },
    ),

  drivePreviewFolder: (
    folderId: string,
    brand: string,
  ) =>
    invoke<ImportPreview>(
      'drive_preview_folder',
      { folderId, brand },
    ),

  driveImportFolder: (
    folderId: string,
    brand: string,
    duplicatePolicy: 'replace' | 'keep' | 'skip',
  ) =>
    invoke<ScanResult>(
      'drive_import_folder',
      {
        folderId,
        brand,
        duplicatePolicy,
      },
    ),

  simulateBatch: () =>
    invoke<SimulationReport>(
      'simulate_batch',
    ),

  clearWorkspace: () =>
    invoke<boolean>(
      'clear_workspace',
    ),
}
TS

cat > src/lib/store.ts <<'TS'
import { create } from 'zustand'

import type {
  Brand,
  ContentItem,
  InspectorMode,
  SimulationReport,
} from '../types'

export type View =
  | 'home'
  | 'today'
  | 'content'
  | 'kanban'
  | 'calendar'
  | 'queue'
  | 'import'
  | 'activity'
  | 'help'
  | 'settings'

interface AppStore {
  view: View
  contents: ContentItem[]
  brands: Brand[]

  selectedId: string | null
  selectedIds: string[]

  selectedBrand: string
  inspectorMode: InspectorMode

  detailOpen: boolean
  simulation: SimulationReport | null
  loading: boolean

  setView: (view: View) => void
  setContents: (contents: ContentItem[]) => void
  setBrands: (brands: Brand[]) => void

  setSelectedBrand: (brand: string) => void

  setSelectedId: (id: string | null) => void
  selectContent: (id: string, multi?: boolean) => void
  clearSelection: () => void

  openDetail: (id: string) => void
  closeDetail: () => void

  setInspectorMode: (mode: InspectorMode) => void

  setSimulation: (
    r: SimulationReport | null,
  ) => void

  setLoading: (v: boolean) => void
}

const savedInspector =
  (localStorage.getItem(
    'abraxas.inspectorMode',
  ) as InspectorMode | null)
  ?? 'docked'

const savedBrand =
  localStorage.getItem(
    'abraxas.selectedBrand',
  )
  ?? 'ALL'

export const useAppStore =
  create<AppStore>((set) => ({
    view: 'home',

    contents: [],
    brands: [],

    selectedId: null,
    selectedIds: [],

    selectedBrand: savedBrand,
    inspectorMode: savedInspector,

    detailOpen: false,
    simulation: null,
    loading: false,

    setView: (view) =>
      set({ view }),

    setContents: (contents) =>
      set({ contents }),

    setBrands: (brands) =>
      set({ brands }),

    setSelectedBrand: (selectedBrand) => {
      localStorage.setItem(
        'abraxas.selectedBrand',
        selectedBrand,
      )

      set({
        selectedBrand,
        selectedId: null,
        selectedIds: [],
      })
    },

    setSelectedId: (selectedId) =>
      set((state) => ({
        selectedId,
        selectedIds:
          selectedId
            ? [selectedId]
            : [],
        inspectorMode:
          selectedId
            ? (
                state.inspectorMode === 'hidden'
                  ? 'docked'
                  : state.inspectorMode
              )
            : state.inspectorMode,
      })),

    selectContent: (id, multi = false) =>
      set((state) => {
        let selectedIds: string[]

        if (!multi) {
          selectedIds = [id]
        } else if (
          state.selectedIds.includes(id)
        ) {
          selectedIds =
            state.selectedIds.filter(
              (x) => x !== id,
            )
        } else {
          selectedIds =
            [...state.selectedIds, id]
        }

        return {
          selectedIds,
          selectedId:
            selectedIds.length
              ? id
              : null,
          inspectorMode:
            selectedIds.length
              && state.inspectorMode === 'hidden'
              ? 'docked'
              : state.inspectorMode,
        }
      }),

    clearSelection: () =>
      set({
        selectedId: null,
        selectedIds: [],
      }),

    openDetail: (selectedId) =>
      set((state) => ({
        selectedId,
        selectedIds:
          state.selectedIds.includes(selectedId)
            ? state.selectedIds
            : [selectedId],
        detailOpen: true,
      })),

    closeDetail: () =>
      set({
        detailOpen: false,
      }),

    setInspectorMode: (inspectorMode) => {
      localStorage.setItem(
        'abraxas.inspectorMode',
        inspectorMode,
      )

      set({ inspectorMode })
    },

    setSimulation: (simulation) =>
      set({ simulation }),

    setLoading: (loading) =>
      set({ loading }),
  }))
TS

###############################################################################
# 12. APP / SIDEBAR / INSPECTOR
###############################################################################

cat > src/App.tsx <<'TS'
import { useEffect } from 'react'

import { Sidebar } from './components/Sidebar'
import { TopBar } from './components/TopBar'
import { Inspector } from './components/Inspector'
import { ContentDetail } from './components/ContentDetail'

import { HomeView } from './views/HomeView'
import { TodayView } from './views/TodayView'
import { ContentView } from './views/ContentView'
import { KanbanView } from './views/KanbanView'
import { ImportView } from './views/ImportView'
import { CalendarView } from './views/CalendarView'
import { QueueView } from './views/QueueView'
import { ActivityView } from './views/ActivityView'
import { HelpView } from './views/HelpView'
import { SettingsView } from './views/SettingsView'

import { useAppStore } from './lib/store'
import { backend } from './lib/backend'

function MainView() {
  const v = useAppStore(
    (s) => s.view,
  )

  if (v === 'home') return <HomeView/>
  if (v === 'content') return <ContentView/>
  if (v === 'kanban') return <KanbanView/>
  if (v === 'import') return <ImportView/>
  if (v === 'calendar') return <CalendarView/>
  if (v === 'queue') return <QueueView/>
  if (v === 'activity') return <ActivityView/>
  if (v === 'help') return <HelpView/>
  if (v === 'settings') return <SettingsView/>

  return <TodayView/>
}

export default function App() {
  const {
    contents,
    setContents,
    brands,
    setBrands,
    selectedId,
    selectedIds,
    inspectorMode,
    detailOpen,
  } = useAppStore()

  useEffect(() => {
    Promise.all([
      backend.listContents(),
      backend.listBrands(),
    ])
      .then(([content, brandList]) => {
        setContents(content)
        setBrands(brandList)
      })
      .catch(console.error)
  }, [setContents, setBrands])

  useEffect(() => {
    const handler = async (
      event: KeyboardEvent,
    ) => {
      if (!event.metaKey) return

      if (
        event.key.toLowerCase() === 'z'
        && !event.shiftKey
      ) {
        event.preventDefault()

        await backend.undo()
        setContents(
          await backend.listContents(),
        )
      }

      if (
        event.key.toLowerCase() === 'z'
        && event.shiftKey
      ) {
        event.preventDefault()

        await backend.redo()
        setContents(
          await backend.listContents(),
        )
      }
    }

    window.addEventListener(
      'keydown',
      handler,
    )

    return () =>
      window.removeEventListener(
        'keydown',
        handler,
      )
  }, [setContents])

  const selected = contents.filter(
    (c) => selectedIds.includes(c.id),
  )

  const primary = contents.find(
    (c) => c.id === selectedId,
  )

  const docked =
    selected.length > 0
    && inspectorMode === 'docked'

  return (
    <>
      <div
        className={
          docked
            ? 'app-shell with-inspector'
            : 'app-shell no-inspector'
        }
      >
        <Sidebar/>

        <div className="center-shell">
          <TopBar/>
          <main className="main-area">
            <MainView/>
          </main>
        </div>

        {
          selected.length > 0
          && inspectorMode !== 'hidden'
          && (
            <Inspector
              items={selected}
              mode={inspectorMode}
            />
          )
        }
      </div>

      {
        detailOpen
        && primary
        && (
          <ContentDetail
            item={primary}
            brands={brands}
          />
        )
      }
    </>
  )
}
TS

cat > src/components/Sidebar.tsx <<'TS'
import {
  Activity,
  CalendarDays,
  FileStack,
  Inbox,
  LayoutDashboard,
  Settings,
  Upload,
  ListChecks,
  Columns3,
  CircleHelp,
  House,
} from 'lucide-react'

import { useAppStore } from '../lib/store'

const items = [
  ['home', House, 'Inicio'],
  ['today', LayoutDashboard, 'Hoy'],
  ['content', FileStack, 'Contenido'],
  ['kanban', Columns3, 'Estados'],
  ['calendar', CalendarDays, 'Calendario'],
  ['queue', ListChecks, 'Cola'],
  ['import', Upload, 'Importar'],
  ['activity', Activity, 'Actividad'],
] as const

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
            Publisher · v1.2
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
            brands.map((b) => (
              <option
                key={b.id}
                value={b.name}
              >
                {b.name}
              </option>
            ))
          }
        </select>
      </div>

      <nav>
        {
          items.map(
            ([id, Icon, label]) => (
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
                  {label}
                </span>
              </button>
            ),
          )
        }
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
          <span>Cómo usar</span>
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
          <span>Ajustes</span>
        </button>
      </nav>

      <div className="sidebar-foot">
        <Inbox size={15}/>
        <span>
          Local · Sin publicar
        </span>
      </div>
    </aside>
  )
}
TS

cat > src/components/Inspector.tsx <<'TS'
import type {
  ContentItem,
  InspectorMode,
} from '../types'

import {
  Dock,
  ExternalLink,
  FileText,
  PanelRightClose,
  PictureInPicture2,
} from 'lucide-react'

import { useAppStore } from '../lib/store'
import { StatusBadge } from './StatusBadge'

export function Inspector({
  items,
  mode,
}: {
  items: ContentItem[]
  mode: InspectorMode
}) {
  const {
    openDetail,
    setInspectorMode,
    clearSelection,
  } = useAppStore()

  if (!items.length) {
    return null
  }

  if (items.length > 1) {
    return (
      <aside
        className={
          mode === 'floating'
            ? 'inspector floating'
            : 'inspector'
        }
      >
        <div className="inspector-tools">
          <strong>
            {items.length} seleccionados
          </strong>

          <div>
            <button
              onClick={() =>
                setInspectorMode('docked')
              }
              title="Acoplar"
            >
              <Dock size={14}/>
            </button>

            <button
              onClick={() =>
                setInspectorMode('floating')
              }
              title="Flotante"
            >
              <PictureInPicture2 size={14}/>
            </button>

            <button
              onClick={() =>
                setInspectorMode('hidden')
              }
              title="Ocultar"
            >
              <PanelRightClose size={14}/>
            </button>
          </div>
        </div>

        <section>
          <h4>
            Selección múltiple
          </h4>

          {
            items.map((item) => (
              <button
                className="multi-inspector-row"
                key={item.id}
                onClick={() =>
                  openDetail(item.id)
                }
              >
                <span>
                  {item.title}
                </span>

                <small>
                  {item.client || 'Sin marca'}
                </small>
              </button>
            ))
          }
        </section>

        <button
          className="secondary-btn wide"
          onClick={clearSelection}
        >
          Limpiar selección
        </button>
      </aside>
    )
  }

  const item = items[0]

  return (
    <aside
      className={
        mode === 'floating'
          ? 'inspector floating'
          : 'inspector'
      }
    >
      <div className="inspector-tools">
        <span>
          Detalles
        </span>

        <div>
          <button
            className={
              mode === 'docked'
                ? 'active'
                : ''
            }
            onClick={() =>
              setInspectorMode('docked')
            }
            title="Acoplar"
          >
            <Dock size={14}/>
          </button>

          <button
            className={
              mode === 'floating'
                ? 'active'
                : ''
            }
            onClick={() =>
              setInspectorMode('floating')
            }
            title="Flotante"
          >
            <PictureInPicture2 size={14}/>
          </button>

          <button
            onClick={() =>
              setInspectorMode('hidden')
            }
            title="Ocultar"
          >
            <PanelRightClose size={14}/>
          </button>
        </div>
      </div>

      <div className="inspector-hero">
        <div>
          <span>
            {item.contentType}
            {' · '}
            v{item.version}
          </span>

          <strong>
            {item.title}
          </strong>

          <small>
            {item.client || 'Sin marca'}
          </small>
        </div>
      </div>

      <section>
        <h4>
          Estado editorial
        </h4>

        <StatusBadge
          status={item.status}
        />

        <div className="validation-line">
          Validación:{' '}
          <StatusBadge
            status={item.validationStatus}
          />
        </div>
      </section>

      {
        item.latestNote
        && (
          <section>
            <h4>
              Última corrección
            </h4>

            <p className="note-preview">
              {item.latestNote.body}
            </p>
          </section>
        )
      }

      <section>
        <h4>
          Origen
        </h4>

        <div className="source-chip">
          {item.sourceKind}
        </div>
      </section>

      <section>
        <h4>
          Destinos
        </h4>

        {
          item.targets.map((t) => (
            <div
              className="target-row"
              key={t.id}
            >
              <span>
                {t.platform}
              </span>

              <small>
                {
                  t.scheduledAt
                    ? new Date(
                        t.scheduledAt,
                      ).toLocaleString()
                    : 'Sin hora'
                }
              </small>
            </div>
          ))
        }
      </section>

      <section>
        <h4>
          Archivos
        </h4>

        {
          item.media.map((m) => (
            <div
              className="file-row"
              key={m.id}
            >
              <FileText size={14}/>

              <span>
                {
                  m.path
                    .split('/')
                    .pop()
                }
              </span>
            </div>
          ))
        }
      </section>

      <button
        className="primary-btn wide"
        onClick={() =>
          openDetail(item.id)
        }
      >
        <ExternalLink size={15}/>
        Abrir ficha
      </button>
    </aside>
  )
}
TS

###############################################################################
# 13. CONTENT CARD / CONTENT / HOME / KANBAN
###############################################################################

cat > src/components/ContentCard.tsx <<'TS'
import type {
  MouseEvent,
} from 'react'

import {
  Film,
  Images,
  Image as ImageIcon,
  CalendarClock,
  MessageSquareText,
} from 'lucide-react'

import type {
  ContentItem,
} from '../types'

import {
  StatusBadge,
} from './StatusBadge'

function Icon({
  type,
}: {
  type: string
}) {
  if (type === 'carousel') {
    return <Images size={30}/>
  }

  if (type === 'image') {
    return <ImageIcon size={30}/>
  }

  return <Film size={30}/>
}

export function ContentCard({
  item,
  selected,
  onSelect,
}: {
  item: ContentItem
  selected: boolean
  onSelect: (
    event: MouseEvent<HTMLButtonElement>,
  ) => void
}) {
  return (
    <button
      className={
        selected
          ? 'content-card selected'
          : 'content-card'
      }
      onClick={onSelect}
    >
      <div
        className={
          `thumb thumb-${item.contentType}`
        }
      >
        <Icon
          type={item.contentType}
        />

        <span>
          {item.contentType}
          {' · '}
          v{item.version}
        </span>
      </div>

      <div className="content-card-body">
        <small className="card-brand">
          {item.client || 'Sin marca'}
        </small>

        <div className="card-title">
          {item.title}
        </div>

        <div className="platform-row">
          {
            item.targets.map((t) => (
              <span key={t.id}>
                {
                  t.platform
                    .slice(0, 2)
                    .toUpperCase()
                }
              </span>
            ))
          }
        </div>

        <div className="card-foot">
          <StatusBadge
            status={item.status}
          />

          <span className="card-icons">
            {
              item.latestNote
              && (
                <MessageSquareText
                  size={14}
                />
              )
            }

            {
              item.targets.some(
                (t) => t.scheduledAt,
              )
              && (
                <CalendarClock
                  size={14}
                />
              )
            }
          </span>
        </div>
      </div>
    </button>
  )
}
TS

cat > src/views/ContentView.tsx <<'TS'
import {
  useMemo,
  useState,
} from 'react'

import {
  useAppStore,
} from '../lib/store'

import {
  ContentCard,
} from '../components/ContentCard'

export function ContentView() {
  const {
    contents,
    selectedIds,
    selectContent,
    openDetail,
    selectedBrand,
  } = useAppStore()

  const [query, setQuery] =
    useState('')

  const [status, setStatus] =
    useState('ALL')

  const filtered = useMemo(
    () =>
      contents.filter((c) => {
        if (
          selectedBrand !== 'ALL'
          && c.client !== selectedBrand
        ) {
          return false
        }

        if (
          status !== 'ALL'
          && c.status !== status
        ) {
          return false
        }

        return [
          c.title,
          c.client,
          c.contentType,
        ]
          .join(' ')
          .toLowerCase()
          .includes(
            query.toLowerCase(),
          )
      }),
    [
      contents,
      query,
      status,
      selectedBrand,
    ],
  )

  return (
    <div className="page scrollable">
      <header className="page-header compact">
        <div>
          <span className="eyebrow">
            BIBLIOTECA
          </span>

          <h1>
            Contenido
          </h1>

          <p>
            Click selecciona. ⌘/Shift + click permite seleccionar varias fichas.
          </p>
        </div>

        <div className="filter-row">
          <select
            className="field"
            value={status}
            onChange={(e) =>
              setStatus(
                e.target.value,
              )
            }
          >
            <option value="ALL">
              Todos los estados
            </option>

            <option value="EN_CONFIRMACION">
              En confirmación
            </option>

            <option value="CON_CORRECCION">
              Con corrección
            </option>

            <option value="LISTO_POR_PROGRAMAR">
              Listo / por programar
            </option>

            <option value="PROGRAMADO">
              Programado
            </option>
          </select>

          <input
            className="field compact-field"
            value={query}
            onChange={(e) =>
              setQuery(
                e.target.value,
              )
            }
            placeholder="Buscar…"
          />
        </div>
      </header>

      {
        filtered.length
        ? (
          <div className="content-grid">
            {
              filtered.map(
                (item) => (
                  <div
                    key={item.id}
                    onDoubleClick={() =>
                      openDetail(item.id)
                    }
                  >
                    <ContentCard
                      item={item}
                      selected={
                        selectedIds.includes(
                          item.id,
                        )
                      }
                      onSelect={(e) =>
                        selectContent(
                          item.id,
                          e.metaKey
                            || e.shiftKey,
                        )
                      }
                    />
                  </div>
                ),
              )
            }
          </div>
        )
        : (
          <div className="hero-empty">
            <h2>
              No hay contenido
            </h2>

            <p>
              Importa una carpeta local o abre Google Drive.
            </p>
          </div>
        )
      }
    </div>
  )
}
TS

cat > src/views/HomeView.tsx <<'TS'
import {
  useState,
} from 'react'

import {
  CalendarDays,
  CircleHelp,
  Cloud,
  FileCheck2,
  FolderOpen,
  Plus,
} from 'lucide-react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

export function HomeView() {
  const {
    contents,
    brands,
    setBrands,
    selectedBrand,
    setSelectedBrand,
    setView,
    openDetail,
  } = useAppStore()

  const [creating, setCreating] =
    useState(false)

  const [brandName, setBrandName] =
    useState('')

  const recent = contents
    .filter(
      (c) =>
        selectedBrand === 'ALL'
        || c.client === selectedBrand,
    )
    .slice(0, 4)

  const addBrand = async () => {
    if (!brandName.trim()) {
      return
    }

    const brand =
      await backend.createBrand(
        brandName.trim(),
      )

    const next =
      await backend.listBrands()

    setBrands(next)
    setSelectedBrand(brand.name)

    setBrandName('')
    setCreating(false)
  }

  return (
    <div className="page scrollable welcome-page">
      <section className="welcome-hero">
        <span className="eyebrow">
          ABRAXAS PUBLISHER · V1.2
        </span>

        <h1>
          Planifica. Revisa. Programa.
        </h1>

        <p>
          Elige la marca y entra al workspace o importa contenido desde tu Mac o Google Drive.
        </p>

        <div className="welcome-brand-picker">
          <label>
            Marca
          </label>

          <select
            className="field"
            value={selectedBrand}
            onChange={(e) =>
              setSelectedBrand(
                e.target.value,
              )
            }
          >
            <option value="ALL">
              Todas las marcas
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

          <button
            className="secondary-btn"
            onClick={() =>
              setCreating(
                !creating,
              )
            }
          >
            <Plus size={15}/>
            Nueva marca
          </button>
        </div>

        {
          creating
          && (
            <div className="inline-create-brand">
              <input
                className="field"
                placeholder="Ej. MOKA"
                value={brandName}
                onChange={(e) =>
                  setBrandName(
                    e.target.value,
                  )
                }
                onKeyDown={(e) => {
                  if (
                    e.key === 'Enter'
                  ) {
                    addBrand()
                  }
                }}
              />

              <button
                className="primary-btn"
                onClick={addBrand}
              >
                Crear
              </button>
            </div>
          )
        }

        <div className="welcome-actions">
          <button
            className="primary-btn welcome-primary"
            onClick={() =>
              setView('import')
            }
          >
            <FolderOpen size={17}/>
            Importar contenido
          </button>

          <button
            className="secondary-btn"
            onClick={() =>
              setView('help')
            }
          >
            <CircleHelp size={17}/>
            Cómo usar
          </button>
        </div>
      </section>

      <div className="welcome-grid">
        <button
          className="welcome-card"
          onClick={() =>
            setView('content')
          }
        >
          <FileCheck2/>

          <div>
            <strong>
              Revisar contenido
            </strong>

            <span>
              Preview, correcciones, estados y versiones.
            </span>
          </div>
        </button>

        <button
          className="welcome-card"
          onClick={() =>
            setView('calendar')
          }
        >
          <CalendarDays/>

          <div>
            <strong>
              Precalendarizar
            </strong>

            <span>
              Día, semana, mes y bandeja sin calendarizar.
            </span>
          </div>
        </button>

        <button
          className="welcome-card"
          onClick={() =>
            setView('import')
          }
        >
          <Cloud/>

          <div>
            <strong>
              Google Drive directo
            </strong>

            <span>
              Navega Drive desde Publisher sin depender de Finder.
            </span>
          </div>
        </button>
      </div>

      <section className="panel recent-panel">
        <div className="panel-title-row">
          <h3>
            Recientes
          </h3>

          <span>
            {recent.length}
          </span>
        </div>

        {
          recent.length
          ? recent.map(
              (c) => (
                <button
                  className="recent-content"
                  key={c.id}
                  onClick={() =>
                    openDetail(c.id)
                  }
                >
                  <div>
                    <strong>
                      {c.title}
                    </strong>

                    <span>
                      {c.client || 'Sin marca'}
                      {' · '}
                      {c.contentType}
                      {' · '}
                      v{c.version}
                    </span>
                  </div>

                  <span>
                    {c.status.replaceAll('_', ' ')}
                  </span>
                </button>
              ),
            )
          : (
            <div className="empty-state">
              Todavía no hay contenido para esta marca.
            </div>
          )
        }
      </section>
    </div>
  )
}
TS

cat > src/views/KanbanView.tsx <<'TS'
import {
  useMemo,
} from 'react'

import {
  useAppStore,
} from '../lib/store'

import type {
  WorkflowStatus,
} from '../types'

const columns: {
  status: WorkflowStatus
  title: string
}[] = [
  {
    status: 'EN_CONFIRMACION',
    title: 'En confirmación',
  },
  {
    status: 'CON_CORRECCION',
    title: 'Con corrección',
  },
  {
    status: 'LISTO_POR_PROGRAMAR',
    title: 'Listo / por programar',
  },
  {
    status: 'PROGRAMADO',
    title: 'Programado',
  },
]

export function KanbanView() {
  const {
    contents,
    openDetail,
    selectedBrand,
  } = useAppStore()

  const visible = useMemo(
    () =>
      contents.filter(
        (c) =>
          selectedBrand === 'ALL'
          || c.client === selectedBrand,
      ),
    [
      contents,
      selectedBrand,
    ],
  )

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            ESTADOS
          </span>

          <h1>
            Kanban editorial
          </h1>

          <p>
            Es una vista de control. El estado se cambia exclusivamente desde la ficha.
          </p>
        </div>
      </header>

      <div className="kanban-grid">
        {
          columns.map((column) => {
            const items =
              visible.filter(
                (c) =>
                  c.status
                  === column.status,
              )

            return (
              <section
                className="kanban-column"
                key={column.status}
              >
                <header>
                  <strong>
                    {column.title}
                  </strong>

                  <span>
                    {items.length}
                  </span>
                </header>

                <div>
                  {
                    items.map(
                      (item) => (
                        <button
                          className="kanban-card"
                          key={item.id}
                          onClick={() =>
                            openDetail(item.id)
                          }
                        >
                          <small>
                            {item.client || 'Sin marca'}
                          </small>

                          <strong>
                            {item.title}
                          </strong>

                          <span>
                            {
                              item.targets
                                .map(
                                  (x) =>
                                    x.platform,
                                )
                                .join(' · ')
                            }
                          </span>
                        </button>
                      ),
                    )
                  }
                </div>
              </section>
            )
          })
        }
      </div>
    </div>
  )
}
TS

###############################################################################
# 14. IMPORT VIEW · LOCAL + DRIVE
###############################################################################

cat > src/views/ImportView.tsx <<'TS'
import {
  open,
} from '@tauri-apps/plugin-dialog'

import {
  Cloud,
  FolderOpen,
  RefreshCcw,
  ShieldCheck,
  TriangleAlert,
  ChevronLeft,
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
  DriveItem,
  ImportPreview,
  ScanResult,
} from '../types'

type Mode =
  | 'local'
  | 'drive'

type Policy =
  | 'replace'
  | 'keep'
  | 'skip'

export function ImportView() {
  const {
    brands,
    selectedBrand,
    setSelectedBrand,
    setContents,
    loading,
    setLoading,
    setView,
  } = useAppStore()

  const fallbackBrand =
    selectedBrand !== 'ALL'
      ? selectedBrand
      : (
          brands[0]?.name
          || 'JOC'
        )

  const [brand, setBrand] =
    useState(fallbackBrand)

  const [mode, setMode] =
    useState<Mode>('local')

  const [path, setPath] =
    useState('')

  const [preview, setPreview] =
    useState<ImportPreview | null>(null)

  const [result, setResult] =
    useState<ScanResult | null>(null)

  const [error, setError] =
    useState<string | null>(null)

  const [policy, setPolicy] =
    useState<Policy>('replace')

  const [clientId, setClientId] =
    useState('')

  const [driveConnected, setDriveConnected] =
    useState(false)

  const [driveItems, setDriveItems] =
    useState<DriveItem[]>([])

  const [folderId, setFolderId] =
    useState('root')

  const [folderName, setFolderName] =
    useState('Mi Drive')

  const [stack, setStack] =
    useState<
      { id: string; name: string }[]
    >([])

  const [driveSearch, setDriveSearch] =
    useState('')

  useEffect(() => {
    backend.getDriveClientId()
      .then((x) => {
        if (x) setClientId(x)
      })
      .catch(() => {})

    backend.driveStatus()
      .then(setDriveConnected)
      .catch(() => {})
  }, [])

  useEffect(() => {
    if (
      selectedBrand !== 'ALL'
      && selectedBrand !== brand
    ) {
      setBrand(selectedBrand)
    }
  }, [selectedBrand])

  const filteredDriveItems =
    useMemo(
      () => {
        const q =
          driveSearch
            .trim()
            .toLowerCase()

        if (!q) {
          return driveItems
        }

        return driveItems.filter(
          (item) =>
            item.name
              .toLowerCase()
              .includes(q),
        )
      },
      [
        driveItems,
        driveSearch,
      ],
    )

  const refreshWorkspace =
    async () => {
      setContents(
        await backend.listContents(),
      )
    }

  const pickLocal =
    async () => {
      const selected = await open({
        directory: true,
        multiple: false,
        title:
          'Selecciona una carpeta o semana de contenido',
      })

      if (
        !selected
        || Array.isArray(selected)
      ) {
        return
      }

      setPath(selected)
      setPreview(null)
      setResult(null)
      setError(null)

      setLoading(true)

      try {
        const p =
          await backend.previewImportLocal(
            selected,
            brand,
          )

        setPreview(p)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const previewLocalAgain =
    async () => {
      if (!path) {
        return
      }

      setLoading(true)
      setError(null)

      try {
        setPreview(
          await backend.previewImportLocal(
            path,
            brand,
          ),
        )
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const commitLocal =
    async () => {
      if (!path || !preview) {
        return
      }

      setLoading(true)
      setError(null)

      try {
        /*
         * Resolver contenido por contenido permite
         * mantener decisiones distintas cuando
         * aparezcan duplicados.
         *
         * El selector general `policy` funciona
         * como "Aplicar a todos".
         */
        let last: ScanResult | null = null

        for (const item of preview.contents) {
          last =
            await backend.commitImportLocal(
              item.folderPath,
              brand,
              policy,
            )
        }

        if (last) {
          setResult(last)
        }

        await refreshWorkspace()

        setSelectedBrand(brand)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const connectDrive =
    async () => {
      if (!clientId.trim()) {
        setError(
          'Primero introduce el OAuth Client ID de Google tipo Desktop.',
        )
        return
      }

      setLoading(true)
      setError(null)

      try {
        await backend.setDriveClientId(
          clientId.trim(),
        )

        const auth =
          await backend.driveConnect(
            clientId.trim(),
          )

        setDriveConnected(
          auth.connected,
        )

        if (auth.connected) {
          const items =
            await backend.driveList(
              'root',
            )

          setDriveItems(items)
          setFolderId('root')
          setFolderName('Mi Drive')
          setStack([])
        }
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const loadDrive =
    async (
      id: string,
    ) => {
      setLoading(true)
      setError(null)

      try {
        setDriveItems(
          await backend.driveList(id),
        )

        setFolderId(id)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const enterFolder =
    async (
      item: DriveItem,
    ) => {
      if (!item.isFolder) {
        return
      }

      setStack(
        (prev) => [
          ...prev,
          {
            id: folderId,
            name: folderName,
          },
        ],
      )

      setFolderName(item.name)

      await loadDrive(item.id)
    }

  const backDrive =
    async () => {
      const previous =
        stack[
          stack.length - 1
        ]

      if (!previous) {
        return
      }

      setStack(
        (prev) =>
          prev.slice(
            0,
            -1,
          ),
      )

      setFolderName(
        previous.name,
      )

      await loadDrive(
        previous.id,
      )
    }

  const previewDrive =
    async () => {
      if (!driveConnected) {
        return
      }

      setLoading(true)
      setError(null)
      setPreview(null)
      setResult(null)

      try {
        const p =
          await backend.drivePreviewFolder(
            folderId,
            brand,
          )

        setPreview(p)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const commitDrive =
    async () => {
      if (!preview) {
        return
      }

      setLoading(true)
      setError(null)

      try {
        /*
         * Si el preview devuelve carpetas
         * individuales de Drive con sourceRef,
         * se importan de manera independiente.
         * Así un conflicto no obliga a modificar
         * toda la semana.
         */
        let last: ScanResult | null = null

        for (
          const item
          of preview.contents
        ) {
          const driveFolderId =
            item.sourceRef
            || folderId

          last =
            await backend.driveImportFolder(
              driveFolderId,
              brand,
              policy,
            )
        }

        if (!preview.contents.length) {
          last =
            await backend.driveImportFolder(
              folderId,
              brand,
              policy,
            )
        }

        if (last) {
          setResult(last)
        }

        await refreshWorkspace()

        setSelectedBrand(brand)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            INGESTA
          </span>

          <h1>
            Importar contenido
          </h1>

          <p>
            Desde este Mac o directamente desde Google Drive.
          </p>
        </div>

        <select
          className="field"
          value={brand}
          onChange={(e) =>
            setBrand(
              e.target.value,
            )
          }
        >
          {
            brands.map(
              (b) => (
                <option
                  key={b.id}
                  value={b.name}
                >
                  {b.name}
                </option>
              ),
            )
          }
        </select>
      </header>

      <div className="source-tabs">
        <button
          className={
            mode === 'local'
              ? 'source-tab active'
              : 'source-tab'
          }
          onClick={() => {
            setMode('local')
            setPreview(null)
            setResult(null)
          }}
        >
          <FolderOpen size={17}/>
          Este Mac
        </button>

        <button
          className={
            mode === 'drive'
              ? 'source-tab active'
              : 'source-tab'
          }
          onClick={() => {
            setMode('drive')
            setPreview(null)
            setResult(null)
          }}
        >
          <Cloud size={17}/>
          Google Drive
        </button>
      </div>

      {
        mode === 'local'
        && (
          <section className="source-panel">
            <button
              className="drop-zone"
              onClick={pickLocal}
              disabled={loading}
            >
              <FolderOpen size={34}/>

              <strong>
                {
                  loading
                    ? 'Analizando…'
                    : 'Seleccionar carpeta'
                }
              </strong>

              <span>
                Puedes seleccionar una carpeta individual o una carpeta que contenga toda una semana.
              </span>
            </button>

            {
              path
              && (
                <div className="selected-source">
                  <span>
                    Carpeta
                  </span>

                  <strong>
                    {path}
                  </strong>

                  <button
                    className="secondary-btn small"
                    onClick={
                      previewLocalAgain
                    }
                  >
                    <RefreshCcw size={14}/>
                    Volver a analizar
                  </button>
                </div>
              )
            }
          </section>
        )
      }

      {
        mode === 'drive'
        && (
          <section className="source-panel">
            {
              !driveConnected
              ? (
                <div className="drive-connect-card">
                  <Cloud size={34}/>

                  <h3>
                    Conectar Google Drive
                  </h3>

                  <p>
                    Usa un OAuth Client ID de tipo Desktop. El login se abre en tu navegador, no dentro del WebView.
                  </p>

                  <input
                    className="field full-field"
                    value={clientId}
                    onChange={(e) =>
                      setClientId(
                        e.target.value,
                      )
                    }
                    placeholder="xxxxxxxx.apps.googleusercontent.com"
                  />

                  <button
                    className="primary-btn"
                    disabled={
                      loading
                      || !clientId.trim()
                    }
                    onClick={
                      connectDrive
                    }
                  >
                    <Cloud size={15}/>
                    Conectar Drive
                  </button>

                  <small className="helper">
                    El Client ID se guarda en los ajustes locales de Publisher. No se guarda ningún token social.
                  </small>
                </div>
              )
              : (
                <div className="drive-browser">
                  <div className="drive-browser-head">
                    <button
                      className="secondary-btn small"
                      disabled={
                        !stack.length
                      }
                      onClick={
                        backDrive
                      }
                    >
                      <ChevronLeft size={14}/>
                      Atrás
                    </button>

                    <div>
                      <span className="eyebrow">
                        GOOGLE DRIVE
                      </span>

                      <strong>
                        {folderName}
                      </strong>
                    </div>

                    <button
                      className="secondary-btn small"
                      onClick={() =>
                        loadDrive(
                          folderId,
                        )
                      }
                    >
                      <RefreshCcw size={14}/>
                      Actualizar
                    </button>
                  </div>

                  <input
                    className="field full-field"
                    placeholder="Buscar dentro de esta carpeta…"
                    value={driveSearch}
                    onChange={(e) =>
                      setDriveSearch(
                        e.target.value,
                      )
                    }
                  />

                  <div className="drive-list">
                    {
                      filteredDriveItems.map(
                        (item) => (
                          <button
                            className={
                              item.isFolder
                                ? 'drive-row folder'
                                : 'drive-row'
                            }
                            key={item.id}
                            onDoubleClick={() =>
                              enterFolder(
                                item,
                              )
                            }
                            onClick={() => {
                              if (
                                item.isFolder
                              ) {
                                enterFolder(
                                  item,
                                )
                              }
                            }}
                          >
                            {
                              item.isFolder
                                ? '📁'
                                : '📄'
                            }

                            <span>
                              <strong>
                                {item.name}
                              </strong>

                              <small>
                                {
                                  item.isFolder
                                    ? 'Carpeta'
                                    : item.mimeType
                                }
                              </small>
                            </span>
                          </button>
                        ),
                      )
                    }

                    {
                      !filteredDriveItems.length
                      && (
                        <div className="empty-state">
                          Esta carpeta está vacía o el filtro no encontró resultados.
                        </div>
                      )
                    }
                  </div>

                  <button
                    className="primary-btn wide"
                    disabled={loading}
                    onClick={
                      previewDrive
                    }
                  >
                    <ShieldCheck size={15}/>
                    Usar esta carpeta
                  </button>
                </div>
              )
            }
          </section>
        )
      }

      {
        error
        && (
          <div className="banner error">
            <TriangleAlert size={17}/>
            {error}
          </div>
        )
      }

      {
        preview
        && (
          <section className="import-preview panel">
            <div className="panel-title-row">
              <div>
                <span className="eyebrow">
                  PREVIEW DE IMPORTACIÓN
                </span>

                <h3>
                  {
                    preview.contents.length
                  } contenidos detectados
                </h3>
              </div>

              <div className="import-counts">
                <span>
                  {
                    preview.duplicates.length
                  } duplicados
                </span>

                <span>
                  {
                    preview.warnings
                  } warnings
                </span>

                <span>
                  {
                    preview.errors
                  } errores
                </span>
              </div>
            </div>

            {
              preview.duplicates.length
              > 0
              && (
                <div className="duplicate-panel">
                  <TriangleAlert size={18}/>

                  <div>
                    <strong>
                      Contenido ya existente
                    </strong>

                    <p>
                      Publisher detectó {
                        preview.duplicates.length
                      } conflicto(s). Elige qué hacer.
                    </p>
                  </div>

                  <select
                    className="field"
                    value={policy}
                    onChange={(e) =>
                      setPolicy(
                        e.target.value
                        as Policy,
                      )
                    }
                  >
                    <option value="replace">
                      Reemplazar todos
                    </option>

                    <option value="keep">
                      Mantener ambos
                    </option>

                    <option value="skip">
                      Omitir todos
                    </option>
                  </select>
                </div>
              )
            }

            <div className="import-content-list">
              {
                preview.contents.map(
                  (item) => {
                    const duplicate =
                      preview.duplicates
                        .find(
                          (x) =>
                            x.incomingId
                            === item.id,
                        )

                    return (
                      <div
                        className="import-content-row"
                        key={
                          `${item.id}-${item.folderPath}`
                        }
                      >
                        <div>
                          <small>
                            {
                              item.client
                              || brand
                            }
                          </small>

                          <strong>
                            {item.title}
                          </strong>

                          <span>
                            {item.contentType}
                            {' · '}
                            {
                              item.targets
                                .map(
                                  (x) =>
                                    x.platform,
                                )
                                .join(' · ')
                            }
                          </span>
                        </div>

                        {
                          duplicate
                          ? (
                            <span className="duplicate-badge">
                              Ya existe
                            </span>
                          )
                          : (
                            <span className="new-badge">
                              Nuevo
                            </span>
                          )
                        }
                      </div>
                    )
                  },
                )
              }
            </div>

            <button
              className="primary-btn wide"
              disabled={loading}
              onClick={
                mode === 'local'
                  ? commitLocal
                  : commitDrive
              }
            >
              {
                loading
                  ? 'Importando…'
                  : 'Confirmar importación'
              }
            </button>
          </section>
        )
      }

      {
        result
        && (
          <div className="import-summary">
            <div className="summary-top">
              <ShieldCheck size={21}/>

              <div>
                <strong>
                  Importación completada
                </strong>

                <span>
                  {
                    result.importedCount
                  } elementos procesados
                </span>
              </div>
            </div>

            <button
              className="primary-btn wide"
              onClick={() =>
                setView('content')
              }
            >
              Ver contenido
            </button>
          </div>
        )
      }
    </div>
  )
}
TS

###############################################################################
# 15. CALENDARIO · DÍA / SEMANA / MES · DND
###############################################################################

cat > src/views/CalendarView.tsx <<'TS'
import {
  useMemo,
  useState,
} from 'react'

import {
  DndContext,
  DragEndEvent,
  useDraggable,
  useDroppable,
} from '@dnd-kit/core'

import {
  CSS,
} from '@dnd-kit/utilities'

import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Inbox,
  Search,
  X,
} from 'lucide-react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  ContentItem,
  PublicationTarget,
} from '../types'

type CalendarMode =
  | 'day'
  | 'week'
  | 'month'

type PendingMove = {
  contentId: string
  targetId: string
  date: string | null
}

function ymd(
  date: Date,
) {
  const y =
    date.getFullYear()

  const m =
    String(
      date.getMonth() + 1,
    ).padStart(
      2,
      '0',
    )

  const d =
    String(
      date.getDate(),
    ).padStart(
      2,
      '0',
    )

  return `${y}-${m}-${d}`
}

function mondayOf(
  date: Date,
) {
  const d =
    new Date(date)

  const delta =
    (d.getDay() + 6)
    % 7

  d.setHours(
    12,
    0,
    0,
    0,
  )

  d.setDate(
    d.getDate()
    - delta,
  )

  return d
}

function addDays(
  date: Date,
  days: number,
) {
  const d =
    new Date(date)

  d.setDate(
    d.getDate() + days,
  )

  return d
}

function weekDays(
  anchor: Date,
) {
  const start =
    mondayOf(anchor)

  return Array.from(
    {
      length: 7,
    },
    (_, i) =>
      addDays(
        start,
        i,
      ),
  )
}

function monthDays(
  anchor: Date,
) {
  const first =
    new Date(
      anchor.getFullYear(),
      anchor.getMonth(),
      1,
      12,
    )

  const start =
    mondayOf(first)

  return Array.from(
    {
      length: 42,
    },
    (_, i) =>
      addDays(
        start,
        i,
      ),
  )
}

function locked(
  target: PublicationTarget,
) {
  return (
    target.status
    === 'SCHEDULED_REMOTE'
    || target.status
    === 'PUBLISHED'
  )
}

function scheduleForDate(
  target: PublicationTarget,
  date: string | null,
) {
  if (!date) {
    return null
  }

  const previousTime =
    target.scheduledAt
      ?.slice(
        11,
        19,
      )
    || '10:00:00'

  return (
    `${date}T${previousTime}`
  )
}

function DraggableTarget({
  item,
  target,
  openDetail,
}: {
  item: ContentItem
  target: PublicationTarget
  openDetail: (id: string) => void
}) {
  const isLocked =
    locked(target)

  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    isDragging,
  } = useDraggable({
    id: target.id,
    disabled: isLocked,
    data: {
      contentId: item.id,
    },
  })

  const style = {
    transform:
      CSS.Transform.toString(
        transform,
      ),
    opacity:
      isDragging
        ? .4
        : 1,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={
        isLocked
          ? 'calendar-item locked'
          : 'calendar-item'
      }
      {...attributes}
      {...listeners}
      onDoubleClick={() =>
        openDetail(item.id)
      }
    >
      <span className="calendar-time">
        {
          isLocked
          && '🔒 '
        }

        <Clock3 size={11}/>

        {
          target.scheduledAt
            ?.slice(
              11,
              16,
            )
          || 'Sin hora'
        }
      </span>

      <strong>
        {item.title}
      </strong>

      <small>
        {target.platform}
        {' · '}
        {
          item.client
          || 'Sin marca'
        }
      </small>
    </div>
  )
}

function DropZone({
  id,
  className,
  children,
}: {
  id: string
  className: string
  children: React.ReactNode
}) {
  const {
    setNodeRef,
    isOver,
  } = useDroppable({
    id,
  })

  return (
    <div
      ref={setNodeRef}
      className={
        `${className}${
          isOver
            ? ' drop-over'
            : ''
        }`
      }
    >
      {children}
    </div>
  )
}

export function CalendarView() {
  const {
    contents,
    setContents,
    openDetail,
    selectedBrand,
  } = useAppStore()

  const [
    anchor,
    setAnchor,
  ] =
    useState(
      () => new Date(),
    )

  const [
    mode,
    setMode,
  ] =
    useState<CalendarMode>(
      'week',
    )

  const [
    pending,
    setPending,
  ] =
    useState<PendingMove | null>(
      null,
    )

  const [
    moveScope,
    setMoveScope,
  ] =
    useState<
      'all'
      | 'one'
      | 'selected'
    >(
      'all',
    )

  const [
    selectedPlatforms,
    setSelectedPlatforms,
  ] =
    useState<string[]>([])

  const [
    query,
    setQuery,
  ] =
    useState('')

  const [
    platformFilter,
    setPlatformFilter,
  ] =
    useState('ALL')

  const [
    typeFilter,
    setTypeFilter,
  ] =
    useState('ALL')

  const [
    statusFilter,
    setStatusFilter,
  ] =
    useState('ALL')

  const [
    message,
    setMessage,
  ] =
    useState('')

  const visibleContents =
    useMemo(
      () =>
        contents.filter(
          (content) =>
            selectedBrand
            === 'ALL'
            || content.client
            === selectedBrand,
        ),
      [
        contents,
        selectedBrand,
      ],
    )

  const all =
    useMemo(
      () =>
        visibleContents
          .flatMap(
            (content) =>
              content.targets
                .map(
                  (target) => ({
                    content,
                    target,
                  }),
                ),
          ),
      [
        visibleContents,
      ],
    )

  const unscheduled =
    useMemo(
      () =>
        all.filter(
          ({
            content,
            target,
          }) => {
            if (
              target.scheduledAt
            ) {
              return false
            }

            if (
              platformFilter
              !== 'ALL'
              && target.platform
              !== platformFilter
            ) {
              return false
            }

            if (
              typeFilter
              !== 'ALL'
              && content.contentType
              !== typeFilter
            ) {
              return false
            }

            if (
              statusFilter
              !== 'ALL'
              && content.status
              !== statusFilter
            ) {
              return false
            }

            const haystack =
              [
                content.title,
                content.client,
                content.contentType,
                target.platform,
              ]
                .join(' ')
                .toLowerCase()

            return haystack.includes(
              query
                .trim()
                .toLowerCase(),
            )
          },
        ),
      [
        all,
        query,
        platformFilter,
        typeFilter,
        statusFilter,
      ],
    )

  const refresh =
    async () => {
      setContents(
        await backend.listContents(),
      )
    }

  const requestMove =
    (
      targetId: string,
      date: string | null,
    ) => {
      const entry =
        all.find(
          (x) =>
            x.target.id
            === targetId,
        )

      if (!entry) {
        return
      }

      if (
        locked(
          entry.target,
        )
      ) {
        setMessage(
          'Esta publicación ya está programada o publicada externamente. Primero debes cancelarla mediante su provider.',
        )

        return
      }

      setMoveScope(
        'all',
      )

      setSelectedPlatforms(
        entry.content.targets.map(
          (t) =>
            t.platform,
        ),
      )

      setPending({
        contentId:
          entry.content.id,
        targetId,
        date,
      })
    }

  const onDragEnd =
    (
      event: DragEndEvent,
    ) => {
      const targetId =
        String(
          event.active.id,
        )

      const overId =
        event.over
          ? String(
              event.over.id,
            )
          : ''

      if (!overId) {
        return
      }

      if (
        overId
        === 'unscheduled'
      ) {
        requestMove(
          targetId,
          null,
        )

        return
      }

      if (
        overId.startsWith(
          'date:',
        )
      ) {
        requestMove(
          targetId,
          overId.slice(5),
        )
      }
    }

  const applyMove =
    async () => {
      if (!pending) {
        return
      }

      const content =
        visibleContents.find(
          (c) =>
            c.id
            === pending.contentId,
        )

      if (!content) {
        return
      }

      const dragged =
        content.targets.find(
          (t) =>
            t.id
            === pending.targetId,
        )

      if (!dragged) {
        return
      }

      let targets:
        PublicationTarget[]

      if (
        moveScope === 'one'
      ) {
        targets = [dragged]
      } else if (
        moveScope
        === 'selected'
      ) {
        targets =
          content.targets
            .filter(
              (target) =>
                selectedPlatforms
                  .includes(
                    target.platform,
                  ),
            )
      } else {
        targets =
          content.targets
      }

      const blocked =
        targets.filter(
          locked,
        )

      if (
        blocked.length
      ) {
        setMessage(
          `No se movió nada. ${
            blocked.map(
              (x) =>
                x.platform,
            ).join(', ')
          } ya está bloqueado por programación remota.`,
        )

        setPending(null)
        return
      }

      await backend.updateSchedules(
        targets.map(
          (target) => ({
            targetId:
              target.id,
            scheduledAt:
              scheduleForDate(
                target,
                pending.date,
              ),
          }),
        ),
      )

      await refresh()

      setPending(null)

      setMessage(
        pending.date
          ? 'Fecha de precalendarización actualizada.'
          : 'Destino devuelto a Sin calendarizar.',
      )
    }

  const shift =
    (
      direction: number,
    ) => {
      const d =
        new Date(anchor)

      if (
        mode === 'day'
      ) {
        d.setDate(
          d.getDate()
          + direction,
        )
      } else if (
        mode === 'week'
      ) {
        d.setDate(
          d.getDate()
          + direction * 7,
        )
      } else {
        d.setMonth(
          d.getMonth()
          + direction,
        )
      }

      setAnchor(d)
    }

  const renderItemsForDate =
    (
      date: Date,
    ) => {
      const key =
        ymd(date)

      return all
        .filter(
          (x) =>
            x.target
              .scheduledAt
              ?.slice(
                0,
                10,
              )
            === key,
        )
        .sort(
          (a, b) =>
            String(
              a.target
                .scheduledAt,
            )
              .localeCompare(
                String(
                  b.target
                    .scheduledAt,
                ),
              ),
        )
        .map(
          ({
            content,
            target,
          }) => (
            <DraggableTarget
              key={target.id}
              item={content}
              target={target}
              openDetail={
                openDetail
              }
            />
          ),
        )
    }

  const week =
    weekDays(anchor)

  const month =
    monthDays(anchor)

  const currentMonth =
    anchor.getMonth()

  const platforms =
    Array.from(
      new Set(
        all.map(
          (x) =>
            x.target.platform,
        ),
      ),
    ).sort()

  const types =
    Array.from(
      new Set(
        visibleContents.map(
          (x) =>
            x.contentType,
        ),
      ),
    ).sort()

  return (
    <DndContext
      onDragEnd={
        onDragEnd
      }
    >
      <div className="page calendar-page">
        <header className="page-header compact">
          <div>
            <span className="eyebrow">
              PRECALENDARIZACIÓN
            </span>

            <h1>
              Calendario
            </h1>

            <p>
              Cada red tiene su propia fecha. Mueve todas, una o una selección.
            </p>
          </div>

          <div className="calendar-toolbar">
            <div className="segmented-control">
              {
                (
                  [
                    'day',
                    'week',
                    'month',
                  ]
                  as CalendarMode[]
                ).map(
                  (value) => (
                    <button
                      key={value}
                      className={
                        mode
                        === value
                          ? 'active'
                          : ''
                      }
                      onClick={() =>
                        setMode(
                          value,
                        )
                      }
                    >
                      {
                        value === 'day'
                          ? 'Día'
                          : value
                            === 'week'
                            ? 'Semana'
                            : 'Mes'
                      }
                    </button>
                  ),
                )
              }
            </div>

            <button
              className="secondary-btn small"
              onClick={() =>
                shift(-1)
              }
            >
              <ChevronLeft size={15}/>
            </button>

            <button
              className="secondary-btn small"
              onClick={() =>
                setAnchor(
                  new Date(),
                )
              }
            >
              Hoy
            </button>

            <button
              className="secondary-btn small"
              onClick={() =>
                shift(1)
              }
            >
              <ChevronRight size={15}/>
            </button>
          </div>
        </header>

        {
          message
          && (
            <div className="calendar-message">
              <span>
                {message}
              </span>

              <button
                onClick={() =>
                  setMessage('')
                }
              >
                <X size={14}/>
              </button>
            </div>
          )
        }

        {
          mode === 'day'
          && (
            <div className="day-view">
              <DropZone
                id={
                  `date:${ymd(anchor)}`
                }
                className="day-view-drop"
              >
                <header>
                  <CalendarDays size={18}/>

                  <div>
                    <strong>
                      {
                        anchor.toLocaleDateString(
                          undefined,
                          {
                            weekday:
                              'long',
                            day:
                              'numeric',
                            month:
                              'long',
                            year:
                              'numeric',
                          },
                        )
                      }
                    </strong>
                  </div>
                </header>

                <div className="day-view-items">
                  {
                    renderItemsForDate(
                      anchor,
                    )
                  }
                </div>
              </DropZone>
            </div>
          )
        }

        {
          mode === 'week'
          && (
            <div className="week-grid">
              {
                week.map(
                  (date) => {
                    const key =
                      ymd(date)

                    return (
                      <DropZone
                        key={key}
                        id={
                          `date:${key}`
                        }
                        className="day-col"
                      >
                        <div className="day-head">
                          <span>
                            {
                              date.toLocaleDateString(
                                undefined,
                                {
                                  weekday:
                                    'short',
                                },
                              )
                            }
                          </span>

                          <strong>
                            {
                              date.getDate()
                            }
                          </strong>
                        </div>

                        <div className="day-stack">
                          {
                            renderItemsForDate(
                              date,
                            )
                          }
                        </div>
                      </DropZone>
                    )
                  },
                )
              }
            </div>
          )
        }

        {
          mode === 'month'
          && (
            <div className="month-grid">
              {
                month.map(
                  (date) => {
                    const key =
                      ymd(date)

                    return (
                      <DropZone
                        key={key}
                        id={
                          `date:${key}`
                        }
                        className={
                          date.getMonth()
                          === currentMonth
                            ? 'month-cell'
                            : 'month-cell outside'
                        }
                      >
                        <header>
                          <strong>
                            {
                              date.getDate()
                            }
                          </strong>
                        </header>

                        <div className="month-items">
                          {
                            renderItemsForDate(
                              date,
                            )
                          }
                        </div>
                      </DropZone>
                    )
                  },
                )
              }
            </div>
          )
        }

        <DropZone
          id="unscheduled"
          className="unscheduled-rail"
        >
          <div className="rail-title">
            <Inbox size={17}/>

            <div>
              <strong>
                Sin calendarizar
              </strong>

              <span>
                {
                  unscheduled.length
                } destinos visibles
              </span>
            </div>
          </div>

          <div className="rail-controls">
            <label className="rail-search">
              <Search size={14}/>

              <input
                value={query}
                onChange={(e) =>
                  setQuery(
                    e.target.value,
                  )
                }
                placeholder="Buscar contenido…"
              />
            </label>

            <select
              className="field"
              value={platformFilter}
              onChange={(e) =>
                setPlatformFilter(
                  e.target.value,
                )
              }
            >
              <option value="ALL">
                Todas las redes
              </option>

              {
                platforms.map(
                  (p) => (
                    <option
                      key={p}
                      value={p}
                    >
                      {p}
                    </option>
                  ),
                )
              }
            </select>

            <select
              className="field"
              value={typeFilter}
              onChange={(e) =>
                setTypeFilter(
                  e.target.value,
                )
              }
            >
              <option value="ALL">
                Todos los tipos
              </option>

              {
                types.map(
                  (type) => (
                    <option
                      key={type}
                      value={type}
                    >
                      {type}
                    </option>
                  ),
                )
              }
            </select>

            <select
              className="field"
              value={statusFilter}
              onChange={(e) =>
                setStatusFilter(
                  e.target.value,
                )
              }
            >
              <option value="ALL">
                Todos los estados
              </option>

              <option value="EN_CONFIRMACION">
                En confirmación
              </option>

              <option value="CON_CORRECCION">
                Con corrección
              </option>

              <option value="LISTO_POR_PROGRAMAR">
                Listo / por programar
              </option>

              <option value="PROGRAMADO">
                Programado
              </option>
            </select>
          </div>

          <div className="unscheduled-list">
            {
              unscheduled.map(
                ({
                  content,
                  target,
                }) => (
                  <DraggableTarget
                    key={target.id}
                    item={content}
                    target={target}
                    openDetail={
                      openDetail
                    }
                  />
                ),
              )
            }

            {
              !unscheduled.length
              && (
                <div className="rail-empty">
                  No hay destinos que coincidan con estos filtros.
                </div>
              )
            }
          </div>
        </DropZone>

        {
          pending
          && (() => {
            const content =
              visibleContents.find(
                (c) =>
                  c.id
                  === pending.contentId,
              )

            const dragged =
              content?.targets.find(
                (t) =>
                  t.id
                  === pending.targetId,
              )

            if (
              !content
              || !dragged
            ) {
              return null
            }

            return (
              <div className="modal-backdrop">
                <section className="move-modal">
                  <span className="eyebrow">
                    MOVER PUBLICACIÓN
                  </span>

                  <h3>
                    {content.title}
                  </h3>

                  <p>
                    {
                      pending.date
                        ? `Nueva fecha: ${pending.date}`
                        : 'Quitar fecha y devolver a Sin calendarizar'
                    }
                  </p>

                  <label className="radio-row">
                    <input
                      type="radio"
                      checked={
                        moveScope
                        === 'all'
                      }
                      onChange={() =>
                        setMoveScope(
                          'all',
                        )
                      }
                    />

                    Todas las redes
                  </label>

                  <label className="radio-row">
                    <input
                      type="radio"
                      checked={
                        moveScope
                        === 'one'
                      }
                      onChange={() =>
                        setMoveScope(
                          'one',
                        )
                      }
                    />

                    Sólo {
                      dragged.platform
                    }
                  </label>

                  <label className="radio-row">
                    <input
                      type="radio"
                      checked={
                        moveScope
                        === 'selected'
                      }
                      onChange={() =>
                        setMoveScope(
                          'selected',
                        )
                      }
                    />

                    Elegir redes
                  </label>

                  {
                    moveScope
                    === 'selected'
                    && (
                      <div className="platform-checks">
                        {
                          content.targets
                            .map(
                              (target) => (
                                <label
                                  key={
                                    target.id
                                  }
                                >
                                  <input
                                    type="checkbox"
                                    checked={
                                      selectedPlatforms
                                        .includes(
                                          target.platform,
                                        )
                                    }
                                    onChange={(e) =>
                                      setSelectedPlatforms(
                                        (prev) =>
                                          e.target.checked
                                            ? Array.from(
                                                new Set(
                                                  [
                                                    ...prev,
                                                    target.platform,
                                                  ],
                                                ),
                                              )
                                            : prev.filter(
                                                (x) =>
                                                  x
                                                  !== target.platform,
                                              ),
                                      )
                                    }
                                  />

                                  {
                                    target.platform
                                  }

                                  {
                                    locked(target)
                                    && ' 🔒'
                                  }
                                </label>
                              ),
                            )
                        }
                      </div>
                    )
                  }

                  <div className="modal-actions">
                    <button
                      className="secondary-btn"
                      onClick={() =>
                        setPending(
                          null,
                        )
                      }
                    >
                      Cancelar
                    </button>

                    <button
                      className="primary-btn"
                      onClick={
                        applyMove
                      }
                    >
                      Confirmar cambio
                    </button>
                  </div>
                </section>
              </div>
            )
          })()
        }
      </div>
    </DndContext>
  )
}
TS

###############################################################################
# 16. FICHA · PROGRAMACIÓN MULTIRED
###############################################################################

cat > src/components/ContentDetail.tsx <<'TS'
import {
  convertFileSrc,
} from '@tauri-apps/api/core'

import {
  AlertTriangle,
  CalendarClock,
  CheckCircle2,
  FileText,
  RefreshCcw,
  Save,
  X,
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
  ContentItem,
  WorkflowStatus,
} from '../types'

import {
  StatusBadge,
} from './StatusBadge'

const statuses: {
  value: WorkflowStatus
  label: string
}[] = [
  {
    value:
      'EN_CONFIRMACION',
    label:
      'En confirmación',
  },
  {
    value:
      'CON_CORRECCION',
    label:
      'Con corrección',
  },
  {
    value:
      'LISTO_POR_PROGRAMAR',
    label:
      'Listo / por programar',
  },
  {
    value:
      'PROGRAMADO',
    label:
      'Programado',
  },
]

function Preview({
  item,
}: {
  item: ContentItem
}) {
  const [
    index,
    setIndex,
  ] =
    useState(0)

  useEffect(
    () =>
      setIndex(0),
    [
      item.id,
      item.version,
    ],
  )

  if (
    !item.media.length
  ) {
    return (
      <div className="preview-empty">
        No hay medio para previsualizar.
      </div>
    )
  }

  const media =
    item.media[
      Math.min(
        index,
        item.media.length - 1,
      )
    ]

  const src =
    convertFileSrc(
      media.path,
    )

  return (
    <div className="detail-preview">
      {
        media.kind
        === 'video'
        ? (
          <video
            key={
              `${media.id}-${item.version}`
            }
            controls
            playsInline
            preload="metadata"
            src={src}
          />
        )
        : (
          <img
            key={
              `${media.id}-${item.version}`
            }
            src={src}
            alt={item.title}
          />
        )
      }

      {
        item.media.length
        > 1
        && (
          <div className="preview-strip">
            {
              item.media.map(
                (
                  asset,
                  i,
                ) => (
                  <button
                    key={asset.id}
                    className={
                      i === index
                        ? 'preview-dot active'
                        : 'preview-dot'
                    }
                    onClick={() =>
                      setIndex(i)
                    }
                  >
                    {i + 1}
                  </button>
                ),
              )
            }
          </div>
        )
      }
    </div>
  )
}

export function ContentDetail({
  item,
}: {
  item: ContentItem
}) {
  const {
    closeDetail,
    setContents,
  } = useAppStore()

  const [
    status,
    setStatus,
  ] =
    useState<WorkflowStatus>(
      item.status
      as WorkflowStatus,
    )

  const [
    note,
    setNote,
  ] =
    useState('')

  const [
    message,
    setMessage,
  ] =
    useState('')

  const [
    busy,
    setBusy,
  ] =
    useState(false)

  const [
    times,
    setTimes,
  ] =
    useState<
      Record<
        string,
        string
      >
    >(
      () =>
        Object.fromEntries(
          item.targets.map(
            (t) => [
              t.id,
              t.scheduledAt
                ?.slice(
                  0,
                  16,
                )
              || '',
            ],
          ),
        ),
    )

  const [
    chosen,
    setChosen,
  ] =
    useState<string[]>(
      item.targets.map(
        (t) =>
          t.id,
      ),
    )

  useEffect(
    () => {
      setStatus(
        item.status
        as WorkflowStatus,
      )

      setTimes(
        Object.fromEntries(
          item.targets.map(
            (t) => [
              t.id,
              t.scheduledAt
                ?.slice(
                  0,
                  16,
                )
              || '',
            ],
          ),
        ),
      )

      setChosen(
        item.targets.map(
          (t) =>
            t.id,
        ),
      )

      setMessage('')
    },
    [
      item.id,
      item.version,
      item.status,
      item.targets,
    ],
  )

  const allScheduled =
    useMemo(
      () =>
        item.targets.length
        > 0
        && item.targets.every(
          (t) =>
            times[t.id],
        ),
      [
        item.targets,
        times,
      ],
    )

  const refreshAll =
    async () => {
      setContents(
        await backend.listContents(),
      )
    }

  const changeStatus =
    async (
      value: WorkflowStatus,
    ) => {
      setBusy(true)
      setMessage('')

      try {
        await backend.updateWorkflowStatus(
          item.id,
          value,
        )

        setStatus(value)

        await refreshAll()

        setMessage(
          'Estado actualizado.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const saveNote =
    async () => {
      if (!note.trim()) {
        return
      }

      setBusy(true)
      setMessage('')

      try {
        const next:
          WorkflowStatus =
            status
            === 'PROGRAMADO'
              ? status
              : 'CON_CORRECCION'

        await backend.saveCorrectionNote(
          item.id,
          note,
          next,
        )

        setStatus(next)
        setNote('')

        await refreshAll()

        setMessage(
          item.sourceKind
          === 'drive'
            ? 'Corrección guardada. Si Drive está conectado, CORRECCION.txt también se sincronizó en la carpeta de Drive.'
            : 'Corrección guardada y CORRECCION.txt actualizado.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const refresh =
    async () => {
      setBusy(true)
      setMessage('')

      try {
        const result =
          await backend.refreshContent(
            item.id,
          )

        await refreshAll()

        setMessage(
          `${result.message} Versión ${result.currentVersion}.`,
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const saveOne =
    async (
      targetId: string,
    ) => {
      const target =
        item.targets.find(
          (x) =>
            x.id
            === targetId,
        )

      if (
        !target
      ) {
        return
      }

      if (
        target.status
        === 'SCHEDULED_REMOTE'
        || target.status
        === 'PUBLISHED'
      ) {
        setMessage(
          'Ese destino ya está bloqueado externamente y no puede modificarse sin cancelación remota.',
        )

        return
      }

      setBusy(true)

      try {
        const value =
          times[targetId]
          || null

        await backend.updateSchedule(
          targetId,
          value
            ? `${value}:00`
            : null,
        )

        await refreshAll()

        setMessage(
          value
            ? 'Precalendarización actualizada.'
            : 'Destino devuelto a Sin calendarizar.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const applyChosen =
    async () => {
      const changes =
        item.targets
          .filter(
            (t) =>
              chosen.includes(
                t.id,
              ),
          )
          .map(
            (target) => ({
              targetId:
                target.id,
              scheduledAt:
                times[
                  target.id
                ]
                  ? `${times[target.id]}:00`
                  : null,
            }),
          )

      if (
        !changes.length
      ) {
        return
      }

      setBusy(true)

      try {
        await backend.updateSchedules(
          changes,
        )

        await refreshAll()

        setMessage(
          'Cambios aplicados a las redes seleccionadas.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  return (
    <div
      className="detail-backdrop"
      onMouseDown={(e) => {
        if (
          e.target
          === e.currentTarget
        ) {
          closeDetail()
        }
      }}
    >
      <section
        className="detail-sheet"
        role="dialog"
        aria-modal="true"
      >
        <header className="detail-head">
          <div>
            <span className="eyebrow">
              FICHA DE CONTENIDO · v{
                item.version
              }
            </span>

            <h2>
              {item.title}
            </h2>

            <div className="detail-badges">
              <StatusBadge
                status={
                  item.status
                }
              />

              <StatusBadge
                status={
                  item.validationStatus
                }
              />
            </div>
          </div>

          <button
            className="icon-close"
            onClick={
              closeDetail
            }
          >
            <X size={20}/>
          </button>
        </header>

        <div className="detail-grid">
          <div className="detail-left">
            <Preview item={item}/>

            <div className="detail-filemeta">
              <div>
                <span>
                  {
                    item.sourceKind
                  }
                </span>

                <small>
                  {
                    item.folderPath
                  }
                </small>
              </div>

              <button
                className="secondary-btn small"
                onClick={
                  refresh
                }
                disabled={busy}
              >
                <RefreshCcw size={14}/>
                Actualizar contenido
              </button>
            </div>

            {
              item.issues.length
              > 0
              && (
                <div className="detail-issues">
                  <h4>
                    <AlertTriangle size={15}/>
                    Validación
                  </h4>

                  {
                    item.issues.map(
                      (issue) => (
                        <div
                          className={
                            `issue ${issue.severity}`
                          }
                          key={issue.id}
                        >
                          {issue.message}
                        </div>
                      ),
                    )
                  }
                </div>
              )
            }
          </div>

          <div className="detail-right">
            <section className="detail-panel">
              <h3>
                Estado editorial
              </h3>

              <p>
                El Kanban sólo refleja este valor. El estado se cambia aquí.
              </p>

              <select
                className="field full-field"
                value={status}
                disabled={busy}
                onChange={(e) =>
                  changeStatus(
                    e.target.value
                    as WorkflowStatus,
                  )
                }
              >
                {
                  statuses.map(
                    (s) => (
                      <option
                        key={
                          s.value
                        }
                        value={
                          s.value
                        }
                        disabled={
                          s.value
                          === 'PROGRAMADO'
                          && !allScheduled
                        }
                      >
                        {s.label}
                        {
                          s.value
                          === 'PROGRAMADO'
                          && !allScheduled
                            ? ' · requiere fechas'
                            : ''
                        }
                      </option>
                    ),
                  )
                }
              </select>
            </section>

            <section className="detail-panel">
              <h3>
                Corrección / nota
              </h3>

              {
                item.latestNote
                && (
                  <div className="latest-note">
                    <small>
                      {
                        new Date(
                          item.latestNote.createdAt,
                        ).toLocaleString()
                      }
                    </small>

                    <p>
                      {
                        item.latestNote.body
                      }
                    </p>
                  </div>
                )
              }

              <textarea
                className="field note-box"
                value={note}
                onChange={(e) =>
                  setNote(
                    e.target.value,
                  )
                }
                placeholder="Ej.: cambiar portada, corregir subtítulo en 00:23, reemplazar lámina 3…"
              />

              <button
                className="primary-btn wide"
                disabled={
                  busy
                  || !note.trim()
                }
                onClick={
                  saveNote
                }
              >
                <Save size={15}/>
                Guardar corrección
              </button>
            </section>

            <section className="detail-panel">
              <div className="panel-title-row">
                <div>
                  <h3>
                    Precalendarización por red
                  </h3>

                  <p>
                    Puedes cambiar una red o varias a la vez.
                  </p>
                </div>

                <button
                  className="secondary-btn small"
                  onClick={() =>
                    setChosen(
                      item.targets.map(
                        (x) =>
                          x.id,
                      ),
                    )
                  }
                >
                  Seleccionar todas
                </button>
              </div>

              {
                item.targets.map(
                  (target) => {
                    const isLocked =
                      target.status
                      === 'SCHEDULED_REMOTE'
                      || target.status
                      === 'PUBLISHED'

                    return (
                      <div
                        className={
                          isLocked
                            ? 'schedule-edit locked'
                            : 'schedule-edit'
                        }
                        key={
                          target.id
                        }
                      >
                        <label className="schedule-check">
                          <input
                            type="checkbox"
                            checked={
                              chosen.includes(
                                target.id,
                              )
                            }
                            disabled={
                              isLocked
                            }
                            onChange={(e) =>
                              setChosen(
                                (prev) =>
                                  e.target.checked
                                    ? [
                                        ...prev,
                                        target.id,
                                      ]
                                    : prev.filter(
                                        (x) =>
                                          x
                                          !== target.id,
                                      ),
                              )
                            }
                          />

                          <span>
                            <strong>
                              {
                                target.platform
                              }
                            </strong>

                            <small>
                              {
                                target.account
                                || 'Sin cuenta'
                              }
                              {
                                isLocked
                                  ? ' · 🔒 remoto'
                                  : ''
                              }
                            </small>
                          </span>
                        </label>

                        <input
                          className="field"
                          type="datetime-local"
                          disabled={
                            isLocked
                          }
                          value={
                            times[
                              target.id
                            ]
                            || ''
                          }
                          onChange={(e) =>
                            setTimes(
                              (prev) => ({
                                ...prev,
                                [
                                  target.id
                                ]:
                                  e.target.value,
                              }),
                            )
                          }
                        />

                        <button
                          className="secondary-btn small"
                          disabled={
                            busy
                            || isLocked
                          }
                          onClick={() =>
                            saveOne(
                              target.id,
                            )
                          }
                        >
                          <CalendarClock size={14}/>
                          Guardar
                        </button>
                      </div>
                    )
                  },
                )
              }

              <button
                className="primary-btn wide"
                disabled={
                  busy
                  || !chosen.length
                }
                onClick={
                  applyChosen
                }
              >
                Aplicar a redes seleccionadas
              </button>
            </section>

            <section className="detail-panel">
              <h3>
                Archivos detectados
              </h3>

              {
                item.media.map(
                  (media) => (
                    <div
                      className="asset-row"
                      key={media.id}
                    >
                      <FileText size={14}/>

                      <div>
                        <strong>
                          {
                            media.path
                              .split('/')
                              .pop()
                          }
                        </strong>

                        <small>
                          {
                            Math.round(
                              media.sizeBytes
                              / 1024
                              / 1024
                              * 10,
                            )
                            / 10
                          } MB
                          {' · '}
                          {
                            media.sha256
                              ?.slice(
                                0,
                                10,
                              )
                            || 'sin hash'
                          }…
                        </small>
                      </div>
                    </div>
                  ),
                )
              }
            </section>

            {
              message
              && (
                <div className="detail-message">
                  <CheckCircle2 size={15}/>
                  {message}
                </div>
              )
            }
          </div>
        </div>
      </section>
    </div>
  )
}
TS

###############################################################################
# 17. ACTIVIDAD · UNDO / REDO
###############################################################################

cat > src/views/ActivityView.tsx <<'TS'
import {
  RotateCcw,
  RotateCw,
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
  ActivityEvent,
} from '../types'

export function ActivityView() {
  const [
    events,
    setEvents,
  ] =
    useState<
      ActivityEvent[]
    >([])

  const [
    message,
    setMessage,
  ] =
    useState('')

  const setContents =
    useAppStore(
      (s) =>
        s.setContents,
    )

  const load =
    async () => {
      setEvents(
        await backend.listActivity(),
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

  const undo =
    async () => {
      const result =
        await backend.undo()

      setMessage(
        result
          ? `Deshecho: ${result.label}`
          : 'No hay ninguna acción local reversible.',
      )

      setContents(
        await backend.listContents(),
      )

      await load()
    }

  const redo =
    async () => {
      const result =
        await backend.redo()

      setMessage(
        result
          ? `Rehecho: ${result.label}`
          : 'No hay ninguna acción para rehacer.',
      )

      setContents(
        await backend.listContents(),
      )

      await load()
    }

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            AUDITORÍA
          </span>

          <h1>
            Actividad
          </h1>

          <p>
            Historial del workspace. Undo/Redo sólo afecta acciones locales reversibles.
          </p>
        </div>

        <div className="activity-actions">
          <button
            className="secondary-btn"
            onClick={undo}
          >
            <RotateCcw size={15}/>
            Undo
            <kbd>⌘Z</kbd>
          </button>

          <button
            className="secondary-btn"
            onClick={redo}
          >
            <RotateCw size={15}/>
            Redo
            <kbd>⇧⌘Z</kbd>
          </button>
        </div>
      </header>

      {
        message
        && (
          <div className="calendar-message">
            {message}
          </div>
        )
      }

      <section className="activity-list panel">
        {
          events.length
          ? events.map(
            (event) => (
              <article
                className={
                  event.undone
                    ? 'activity-row undone'
                    : 'activity-row'
                }
                key={event.id}
              >
                <div className="activity-time">
                  {
                    new Date(
                      event.createdAt,
                    ).toLocaleString()
                  }
                </div>

                <div className="activity-main">
                  <strong>
                    {
                      event.label
                    }
                  </strong>

                  <span>
                    {
                      event.action
                    }
                    {' · '}
                    {
                      event.entityType
                    }
                    {
                      event.remote
                        ? ' · REMOTO'
                        : ' · LOCAL'
                    }
                    {
                      event.undone
                        ? ' · DESHECHO'
                        : ''
                    }
                  </span>
                </div>

                <div className="activity-flags">
                  {
                    event.reversible
                    && !event.remote
                    && (
                      <span>
                        reversible
                      </span>
                    )
                  }

                  {
                    event.remote
                    && (
                      <span className="danger">
                        definitivo
                      </span>
                    )
                  }
                </div>
              </article>
            ),
          )
          : (
            <div className="empty-state">
              Todavía no hay actividad.
            </div>
          )
        }
      </section>
    </div>
  )
}
TS

###############################################################################
# 18. AJUSTES · DRIVE
###############################################################################

cat > src/views/SettingsView.tsx <<'TS'
import {
  Cloud,
  Save,
} from 'lucide-react'

import {
  useEffect,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import type {
  HealthReport,
} from '../types'

export function SettingsView() {
  const [
    health,
    setHealth,
  ] =
    useState<
      HealthReport | null
    >(null)

  const [
    clientId,
    setClientId,
  ] =
    useState('')

  const [
    connected,
    setConnected,
  ] =
    useState(false)

  const [
    message,
    setMessage,
  ] =
    useState('')

  useEffect(
    () => {
      backend.health()
        .then(setHealth)
        .catch(() => {})

      backend.getDriveClientId()
        .then(
          (id) =>
            setClientId(
              id || '',
            ),
        )
        .catch(() => {})

      backend.driveStatus()
        .then(setConnected)
        .catch(() => {})
    },
    [],
  )

  const save =
    async () => {
      await backend.setDriveClientId(
        clientId.trim(),
      )

      setMessage(
        'Configuración guardada.',
      )
    }

  const connect =
    async () => {
      try {
        await backend.setDriveClientId(
          clientId.trim(),
        )

        const result =
          await backend.driveConnect(
            clientId.trim(),
          )

        setConnected(
          result.connected,
        )

        setMessage(
          result.message,
        )
      } catch (e) {
        setMessage(
          String(e),
        )
      }
    }

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            SISTEMA
          </span>

          <h1>
            Ajustes
          </h1>

          <p>
            Diagnóstico local, Google Drive y configuración del workspace.
          </p>
        </div>
      </header>

      <section className="panel settings-panel">
        <h3>
          Doctor
        </h3>

        <div className="health-row">
          <span>
            SQLite
          </span>

          <b>
            {
              health?.database
                ? 'OK'
                : '—'
            }
          </b>
        </div>

        <div className="health-row">
          <span>
            FFmpeg
          </span>

          <b>
            {
              health?.ffmpeg
                ? 'OK'
                : 'No detectado'
            }
          </b>
        </div>

        <div className="health-row">
          <span>
            FFprobe
          </span>

          <b>
            {
              health?.ffprobe
                ? 'OK'
                : 'No detectado'
            }
          </b>
        </div>

        <div className="health-row">
          <span>
            Datos
          </span>

          <small>
            {
              health?.appDataDir
              || '...'
            }
          </small>
        </div>
      </section>

      <section className="panel settings-panel">
        <div className="panel-title-row">
          <div>
            <h3>
              Google Drive directo
            </h3>

            <p>
              {
                connected
                  ? 'Conectado durante esta sesión.'
                  : 'No conectado.'
              }
            </p>
          </div>

          <Cloud
            size={24}
          />
        </div>

        <label className="field-label">
          OAuth Client ID · Desktop
        </label>

        <input
          className="field full-field"
          value={clientId}
          onChange={(e) =>
            setClientId(
              e.target.value,
            )
          }
          placeholder="xxxxxxxx.apps.googleusercontent.com"
        />

        <div className="button-row">
          <button
            className="secondary-btn"
            onClick={save}
          >
            <Save size={14}/>
            Guardar
          </button>

          <button
            className="primary-btn"
            onClick={connect}
            disabled={
              !clientId.trim()
            }
          >
            <Cloud size={14}/>
            Conectar Drive
          </button>
        </div>

        <small className="helper">
          El OAuth se abre en el navegador del sistema mediante loopback local 127.0.0.1.
        </small>
      </section>

      <section className="panel settings-panel">
        <h3>
          Redes sociales
        </h3>

        <div className="disabled-connect">
          Instagram · Facebook · LinkedIn · YouTube

          <span>
            Publicación real continúa desactivada. Esto pertenece al Paso 2.
          </span>
        </div>
      </section>

      {
        message
        && (
          <div className="calendar-message">
            {message}
          </div>
        )
      }
    </div>
  )
}
TS

###############################################################################
# 19. MCP LOCAL
###############################################################################

mkdir -p tools

cat > tools/publisher_mcp.py <<'PY'
#!/usr/bin/env python3

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def ctl_command():
    installed = shutil.which("publisherctl")

    if installed:
        return [installed]

    release = (
        ROOT
        / "src-tauri"
        / "target"
        / "release"
        / "publisherctl"
    )

    if release.exists():
        return [str(release)]

    debug = (
        ROOT
        / "src-tauri"
        / "target"
        / "debug"
        / "publisherctl"
    )

    if debug.exists():
        return [str(debug)]

    return [
        "cargo",
        "run",
        "--quiet",
        "--manifest-path",
        str(
            ROOT
            / "src-tauri"
            / "Cargo.toml"
        ),
        "--bin",
        "publisherctl",
        "--",
    ]


def run_ctl(args):
    proc = subprocess.run(
        ctl_command() + args,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            proc.stderr.strip()
            or proc.stdout.strip()
            or f"publisherctl exit {proc.returncode}"
        )

    return proc.stdout.strip()


TOOLS = [
    {
        "name": "publisher_list_brands",
        "description": "Lista marcas de ABRAXAS Publisher.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_create_brand",
        "description": "Crea una marca.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                }
            },
            "required": ["name"],
        },
    },
    {
        "name": "publisher_list_content",
        "description": "Lista contenido del workspace.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_get_content",
        "description": "Obtiene una ficha de contenido por ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                }
            },
            "required": ["id"],
        },
    },
    {
        "name": "publisher_import_local_folder",
        "description": "Importa una carpeta local sin publicar nada.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                },
                "brand": {
                    "type": "string",
                },
                "duplicates": {
                    "type": "string",
                    "enum": [
                        "replace",
                        "keep",
                        "skip",
                    ],
                },
            },
            "required": [
                "path",
                "brand",
            ],
        },
    },
    {
        "name": "publisher_refresh_content",
        "description": "Refresca un contenido y detecta archivos reemplazados.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                }
            },
            "required": ["id"],
        },
    },
    {
        "name": "publisher_add_note",
        "description": "Añade una nota de corrección.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                },
                "note": {
                    "type": "string",
                },
            },
            "required": [
                "id",
                "note",
            ],
        },
    },
    {
        "name": "publisher_set_editorial_status",
        "description": "Cambia el estado editorial de un contenido.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                },
                "status": {
                    "type": "string",
                    "enum": [
                        "EN_CONFIRMACION",
                        "CON_CORRECCION",
                        "LISTO_POR_PROGRAMAR",
                        "PROGRAMADO",
                    ],
                },
            },
            "required": [
                "id",
                "status",
            ],
        },
    },
    {
        "name": "publisher_get_activity",
        "description": "Devuelve historial de actividad.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_undo",
        "description": "Deshace la última acción local reversible.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_redo",
        "description": "Rehace la última acción deshecha.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_dry_run",
        "description": "Ejecuta simulación sin publicar.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_doctor",
        "description": "Ejecuta diagnóstico local.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
]


def call_tool(name, args):
    if name == "publisher_list_brands":
        return run_ctl(
            ["brands", "list"]
        )

    if name == "publisher_create_brand":
        return run_ctl(
            [
                "brands",
                "add",
                args["name"],
            ]
        )

    if name == "publisher_list_content":
        return run_ctl(
            ["content", "list"]
        )

    if name == "publisher_get_content":
        return run_ctl(
            [
                "content",
                "show",
                args["id"],
            ]
        )

    if name == "publisher_import_local_folder":
        cmd = [
            "import",
            "local",
            args["path"],
            "--brand",
            args["brand"],
            "--duplicates",
            args.get(
                "duplicates",
                "replace",
            ),
        ]

        return run_ctl(cmd)

    if name == "publisher_refresh_content":
        return run_ctl(
            [
                "content",
                "refresh",
                args["id"],
            ]
        )

    if name == "publisher_add_note":
        return run_ctl(
            [
                "note",
                "add",
                args["id"],
                args["note"],
            ]
        )

    if name == "publisher_set_editorial_status":
        return run_ctl(
            [
                "status",
                "set",
                args["id"],
                args["status"],
            ]
        )

    if name == "publisher_get_activity":
        return run_ctl(
            ["activity"]
        )

    if name == "publisher_undo":
        return run_ctl(
            ["undo"]
        )

    if name == "publisher_redo":
        return run_ctl(
            ["redo"]
        )

    if name == "publisher_dry_run":
        return run_ctl(
            ["dry-run"]
        )

    if name == "publisher_doctor":
        return run_ctl(
            ["doctor"]
        )

    raise RuntimeError(
        f"Unknown tool: {name}"
    )


def response(req_id, result=None, error=None):
    obj = {
        "jsonrpc": "2.0",
        "id": req_id,
    }

    if error is not None:
        obj["error"] = {
            "code": -32000,
            "message": str(error),
        }
    else:
        obj["result"] = result

    sys.stdout.write(
        json.dumps(obj)
        + "\n"
    )
    sys.stdout.flush()


def self_test():
    output = run_ctl(
        ["qa"]
    )

    if "QA APPROVED" not in output:
        raise RuntimeError(
            "publisherctl qa no terminó correctamente."
        )

    print(
        "PASS publisher-mcp self-test"
    )


def main():
    if "--self-test" in sys.argv:
        self_test()
        return

    for line in sys.stdin:
        line = line.strip()

        if not line:
            continue

        try:
            message = json.loads(line)
        except Exception:
            continue

        method = message.get("method")
        req_id = message.get("id")

        if method == "notifications/initialized":
            continue

        if method == "initialize":
            response(
                req_id,
                {
                    "protocolVersion":
                        "2024-11-05",
                    "capabilities": {
                        "tools": {}
                    },
                    "serverInfo": {
                        "name":
                            "abraxas-publisher",
                        "version":
                            "0.3.0",
                    },
                },
            )
            continue

        if method == "tools/list":
            response(
                req_id,
                {
                    "tools": TOOLS
                },
            )
            continue

        if method == "tools/call":
            params = (
                message
                .get(
                    "params",
                    {},
                )
            )

            name = params.get("name")
            args = params.get(
                "arguments",
                {},
            )

            try:
                value = call_tool(
                    name,
                    args,
                )

                response(
                    req_id,
                    {
                        "content": [
                            {
                                "type":
                                    "text",
                                "text":
                                    value,
                            }
                        ],
                        "isError":
                            False,
                    },
                )
            except Exception as exc:
                response(
                    req_id,
                    {
                        "content": [
                            {
                                "type":
                                    "text",
                                "text":
                                    str(exc),
                            }
                        ],
                        "isError":
                            True,
                    },
                )

            continue

        if req_id is not None:
            response(
                req_id,
                error=
                    f"Unsupported method: {method}",
            )


if __name__ == "__main__":
    main()
PY

chmod +x tools/publisher_mcp.py

cat > publisher-mcp <<'SH'
#!/bin/bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$ROOT/tools/publisher_mcp.py" "$@"
SH

chmod +x publisher-mcp

cat > publisherctl <<'SH'
#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

BIN="$ROOT/src-tauri/target/release/publisherctl"

if [ -x "$BIN" ]; then
  exec "$BIN" "$@"
fi

exec cargo run \
  --quiet \
  --manifest-path "$ROOT/src-tauri/Cargo.toml" \
  --bin publisherctl \
  -- "$@"
SH

chmod +x publisherctl

###############################################################################
# 20. HELP
###############################################################################

cat > src/views/HelpView.tsx <<'TS'
const scenarios = [
  [
    'Tengo una semana completa',
    'Importar → Este Mac o Google Drive → selecciona la carpeta raíz → revisa el preview → resuelve duplicados → confirma.',
  ],
  [
    'Mis TXT ya tienen fecha',
    'Al importar, DATE y TIME crean una precalendarización local. No significa que la red social ya esté programada.',
  ],
  [
    'El contenido necesita cambios',
    'Abre la ficha → cambia a Con corrección → escribe la nota. Publisher crea CORRECCION.txt.',
  ],
  [
    'Reemplacé un archivo',
    'Abre la ficha → Actualizar contenido. Se compara SHA-256, tamaño y modificación; si cambió, aumenta la versión.',
  ],
  [
    'Quiero cambiar la fecha',
    'Calendario → Día/Semana/Mes → arrastra la publicación. Puedes mover todas las redes, una sola o redes seleccionadas.',
  ],
  [
    'Quiero usar varias marcas',
    'Inicio → Marca → Nueva marca. El selector filtra Contenido, Calendario y Kanban.',
  ],
  [
    'Mi contenido está en Drive',
    'Importar → Google Drive → conecta OAuth Desktop → navega hasta la carpeta → Usar esta carpeta.',
  ],
  [
    'Quiero automatizar sin usar la interfaz',
    'Usa publisherctl o publisher-mcp. Ambos trabajan contra el mismo workspace local.',
  ],
]

export function HelpView() {
  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            GUÍA
          </span>

          <h1>
            Cómo usar Publisher
          </h1>

          <p>
            Elige el escenario que se parece a lo que necesitas hacer.
          </p>
        </div>
      </header>

      <div className="help-grid">
        {
          scenarios.map(
            (
              [
                title,
                text,
              ],
            ) => (
              <section
                className="panel help-card"
                key={title}
              >
                <h3>
                  {title}
                </h3>

                <p>
                  {text}
                </p>
              </section>
            ),
          )
        }
      </div>
    </div>
  )
}
TS

###############################################################################
# 21. CSS V1.2
###############################################################################

cat >> src/styles.css <<'CSS'

/* ============================================================
   ABRAXAS Publisher V1.2 · Workspace
   ============================================================ */

.app-shell.no-inspector{
  grid-template-columns:224px minmax(0,1fr);
}

.inspector.floating{
  position:fixed;
  z-index:80;
  right:22px;
  top:92px;
  bottom:22px;
  width:min(360px,calc(100vw - 44px));
  border:1px solid var(--line);
  border-radius:18px;
  box-shadow:0 24px 70px rgba(0,0,0,.2);
  padding:14px;
  background:rgba(245,245,247,.88);
}

.inspector-tools{
  display:flex;
  justify-content:space-between;
  align-items:center;
  gap:8px;
  padding:4px 2px 10px;
  font-size:11px;
  color:var(--muted);
}

.inspector-tools>div{
  display:flex;
  gap:4px;
}

.inspector-tools button{
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:8px;
  cursor:pointer;
  background:transparent;
}

.inspector-tools button:hover,
.inspector-tools button.active{
  background:rgba(0,0,0,.07);
}

.inspector-bulk-list{
  display:grid;
  gap:6px;
  margin:8px 0 14px;
}

.inspector-bulk-item{
  text-align:left;
  border:1px solid var(--line);
  background:rgba(255,255,255,.6);
  padding:9px;
  border-radius:9px;
  cursor:pointer;
}

.inspector-bulk-item strong,
.inspector-bulk-item small{
  display:block;
}

.inspector-bulk-item small{
  margin-top:2px;
  color:var(--muted);
}

.source-tabs{
  display:flex;
  gap:5px;
  margin-bottom:14px;
}

.source-tab{
  border:1px solid var(--line);
  background:rgba(255,255,255,.5);
  padding:9px 13px;
  border-radius:10px;
  display:flex;
  align-items:center;
  gap:7px;
  cursor:pointer;
}

.source-tab.active{
  background:#17191f;
  color:#fff;
}

.source-panel{
  margin-bottom:14px;
}

.selected-source{
  margin-top:9px;
  border:1px solid var(--line);
  border-radius:12px;
  background:var(--panel);
  padding:10px;
  display:grid;
  gap:4px;
}

.selected-source span{
  color:var(--muted);
  font-size:10px;
}

.selected-source strong{
  font-size:11px;
  word-break:break-all;
}

.drive-connect-card{
  min-height:260px;
  border:1px solid var(--line);
  border-radius:18px;
  background:var(--panel);
  padding:28px;
  display:flex;
  align-items:center;
  justify-content:center;
  flex-direction:column;
  text-align:center;
  gap:10px;
}

.drive-connect-card h3,
.drive-connect-card p{
  margin:0;
}

.drive-connect-card p{
  max-width:520px;
  font-size:12px;
  color:var(--muted);
}

.drive-browser{
  border:1px solid var(--line);
  border-radius:16px;
  padding:12px;
  background:var(--panel);
}

.drive-browser-head{
  display:grid;
  grid-template-columns:auto 1fr auto;
  align-items:center;
  gap:10px;
  margin-bottom:10px;
}

.drive-browser-head strong,
.drive-browser-head span{
  display:block;
}

.drive-list{
  max-height:340px;
  overflow:auto;
  margin:10px 0;
  border:1px solid var(--line);
  border-radius:11px;
}

.drive-row{
  width:100%;
  text-align:left;
  background:transparent;
  border-bottom:1px solid var(--line);
  padding:9px 11px;
  display:grid;
  grid-template-columns:24px 1fr;
  gap:8px;
  cursor:pointer;
}

.drive-row:last-child{
  border-bottom:0;
}

.drive-row:hover{
  background:rgba(255,255,255,.56);
}

.drive-row strong,
.drive-row small{
  display:block;
}

.drive-row strong{
  font-size:12px;
}

.drive-row small{
  color:var(--muted);
  font-size:9px;
  margin-top:2px;
}

.import-preview{
  margin-top:14px;
}

.import-counts{
  display:flex;
  gap:6px;
  flex-wrap:wrap;
}

.import-counts span{
  background:rgba(0,0,0,.04);
  border-radius:999px;
  padding:5px 8px;
  font-size:9px;
}

.duplicate-panel{
  display:grid;
  grid-template-columns:auto 1fr auto;
  gap:10px;
  align-items:center;
  margin:12px 0;
  border-radius:12px;
  padding:11px;
  background:#fff0d3;
  color:#6d4c00;
}

.duplicate-panel strong,
.duplicate-panel p{
  display:block;
  margin:0;
}

.duplicate-panel p{
  margin-top:3px;
  font-size:10px;
}

.import-content-list{
  display:grid;
  max-height:320px;
  overflow:auto;
  margin:10px 0 14px;
}

.import-content-row{
  display:flex;
  justify-content:space-between;
  align-items:center;
  gap:12px;
  border-top:1px solid var(--line);
  padding:9px 2px;
}

.import-content-row:first-child{
  border-top:0;
}

.import-content-row strong,
.import-content-row span,
.import-content-row small{
  display:block;
}

.import-content-row strong{
  font-size:12px;
}

.import-content-row span,
.import-content-row small{
  font-size:9px;
  color:var(--muted);
}

.duplicate-badge,
.new-badge{
  border-radius:999px;
  padding:5px 7px;
  font-size:9px!important;
  white-space:nowrap;
}

.duplicate-badge{
  background:#fff0d3;
  color:#805700!important;
}

.new-badge{
  background:#e7f3e9;
  color:#236932!important;
}

.card-brand{
  color:var(--muted);
  font-size:9px;
  display:block;
  margin-bottom:3px;
}

.welcome-brand-picker{
  display:flex;
  gap:8px;
  align-items:center;
  justify-content:center;
  margin:18px 0 4px;
  flex-wrap:wrap;
}

.welcome-brand-picker label{
  font-size:11px;
  color:var(--muted);
}

.inline-create-brand{
  display:flex;
  justify-content:center;
  gap:7px;
  max-width:420px;
  margin:9px auto;
}

.calendar-page{
  overflow:hidden;
}

.calendar-toolbar{
  display:flex;
  align-items:center;
  gap:5px;
}

.segmented-control{
  border:1px solid var(--line);
  border-radius:9px;
  display:flex;
  overflow:hidden;
  background:rgba(255,255,255,.45);
}

.segmented-control button{
  background:transparent;
  padding:6px 9px;
  cursor:pointer;
  font-size:10px;
}

.segmented-control button.active{
  background:#17191f;
  color:#fff;
}

.calendar-message{
  display:flex;
  justify-content:space-between;
  align-items:center;
  gap:10px;
  border:1px solid var(--line);
  background:rgba(255,255,255,.68);
  border-radius:11px;
  padding:8px 10px;
  font-size:11px;
  margin-bottom:9px;
}

.calendar-message button{
  background:transparent;
  cursor:pointer;
}

.drop-over{
  outline:2px solid rgba(55,100,190,.6);
  outline-offset:-2px;
}

.calendar-item{
  text-align:left;
  touch-action:none;
}

.calendar-item.locked{
  opacity:.58;
  cursor:not-allowed;
  background:rgba(230,230,232,.9);
}

.calendar-time{
  display:flex!important;
  align-items:center;
  gap:3px;
}

.day-view{
  flex:1;
  min-height:0;
  overflow:auto;
}

.day-view-drop{
  min-height:420px;
  border:1px solid var(--line);
  border-radius:16px;
  background:rgba(255,255,255,.45);
  padding:12px;
}

.day-view-drop>header{
  display:flex;
  gap:8px;
  align-items:center;
  margin-bottom:12px;
}

.day-view-items{
  display:grid;
  gap:7px;
  max-width:600px;
}

.month-grid{
  flex:1;
  min-height:0;
  display:grid;
  grid-template-columns:repeat(7,minmax(115px,1fr));
  grid-template-rows:repeat(6,minmax(110px,1fr));
  border:1px solid var(--line);
  border-radius:16px;
  overflow:auto;
  background:rgba(255,255,255,.45);
}

.month-cell{
  border-right:1px solid var(--line);
  border-bottom:1px solid var(--line);
  padding:6px;
  min-width:115px;
  min-height:110px;
}

.month-cell.outside{
  opacity:.42;
}

.month-cell>header{
  display:flex;
  justify-content:flex-end;
  font-size:10px;
  color:var(--muted);
  margin-bottom:5px;
}

.month-items{
  display:grid;
  gap:4px;
}

.month-cell .calendar-item{
  padding:5px;
}

.month-cell .calendar-item strong{
  font-size:9px;
}

.unscheduled-rail{
  margin-top:10px;
  max-height:205px;
  overflow:hidden;
}

.rail-controls{
  display:grid;
  grid-template-columns:minmax(190px,1fr) repeat(3,150px);
  gap:6px;
  padding:8px 0;
}

.rail-search{
  display:flex;
  align-items:center;
  gap:6px;
  border:1px solid var(--line);
  border-radius:9px;
  padding:0 8px;
  background:rgba(255,255,255,.65);
}

.rail-search input{
  border:0;
  outline:0;
  background:transparent;
  min-width:0;
  width:100%;
}

.unscheduled-list{
  overflow:auto;
  max-height:105px;
}

.unscheduled-list .calendar-item{
  min-width:170px;
}

.modal-backdrop{
  position:fixed;
  z-index:200;
  inset:0;
  background:rgba(10,12,16,.35);
  backdrop-filter:blur(5px);
  display:grid;
  place-items:center;
  padding:20px;
}

.move-modal{
  width:min(460px,100%);
  border:1px solid rgba(255,255,255,.75);
  border-radius:18px;
  background:rgba(248,248,250,.96);
  padding:20px;
  box-shadow:0 30px 90px rgba(0,0,0,.25);
}

.move-modal h3{
  margin:6px 0;
}

.move-modal p{
  font-size:11px;
  color:var(--muted);
}

.radio-row{
  display:flex;
  gap:8px;
  align-items:center;
  padding:8px 0;
  font-size:12px;
}

.platform-checks{
  margin:3px 0 10px 25px;
  display:grid;
  gap:5px;
}

.platform-checks label{
  font-size:11px;
  display:flex;
  align-items:center;
  gap:6px;
}

.modal-actions{
  display:flex;
  justify-content:flex-end;
  gap:7px;
  margin-top:15px;
}

.schedule-check{
  display:flex;
  align-items:center;
  gap:7px;
}

.schedule-check span,
.schedule-check strong,
.schedule-check small{
  display:block;
}

.schedule-check small{
  color:var(--muted);
  font-size:9px;
}

.schedule-edit.locked{
  opacity:.58;
}

.detail-filemeta>div span,
.detail-filemeta>div small{
  display:block;
}

.detail-filemeta>div span{
  text-transform:uppercase;
  font-size:9px;
  color:var(--muted);
}

.detail-filemeta>div small{
  max-width:450px;
  overflow:hidden;
  text-overflow:ellipsis;
  white-space:nowrap;
}

.activity-actions{
  display:flex;
  gap:6px;
}

.activity-actions kbd{
  font-size:9px;
  opacity:.65;
}

.activity-list{
  padding:0 14px;
}

.activity-row{
  display:grid;
  grid-template-columns:160px minmax(0,1fr) auto;
  gap:12px;
  align-items:center;
  border-top:1px solid var(--line);
  padding:11px 0;
}

.activity-row:first-child{
  border-top:0;
}

.activity-row.undone{
  opacity:.42;
}

.activity-time{
  color:var(--muted);
  font-size:9px;
}

.activity-main strong,
.activity-main span{
  display:block;
}

.activity-main strong{
  font-size:11px;
}

.activity-main span{
  color:var(--muted);
  font-size:9px;
  margin-top:2px;
}

.activity-flags{
  display:flex;
  gap:4px;
}

.activity-flags span{
  border-radius:999px;
  background:rgba(0,0,0,.05);
  padding:4px 6px;
  font-size:8px;
}

.activity-flags span.danger{
  color:#a2312f;
  background:#fbe3e2;
}

.field-label{
  display:block;
  margin:9px 0 5px;
  color:var(--muted);
  font-size:10px;
}

.full-field{
  width:100%;
}

.button-row{
  display:flex;
  gap:6px;
  margin-top:9px;
}

.help-grid{
  display:grid;
  grid-template-columns:repeat(auto-fill,minmax(240px,1fr));
  gap:10px;
}

.help-card p{
  color:var(--muted);
  font-size:11px;
  line-height:1.5;
}

@media(max-width:1100px){
  .rail-controls{
    grid-template-columns:1fr 1fr;
  }

  .month-grid{
    grid-template-columns:repeat(7,130px);
  }
}

@media(max-width:900px){
  .rail-controls{
    grid-template-columns:1fr;
  }

  .calendar-toolbar{
    flex-wrap:wrap;
  }

  .activity-row{
    grid-template-columns:1fr;
  }

  .inspector.floating{
    display:block;
  }
}

@media(prefers-color-scheme:dark){
  .source-tab{
    background:rgba(255,255,255,.05);
  }

  .source-tab.active{
    background:#f0f1f3;
    color:#17181b;
  }

  .drive-connect-card,
  .drive-browser,
  .calendar-message{
    background:rgba(35,36,41,.82);
  }

  .drive-row:hover{
    background:rgba(255,255,255,.05);
  }

  .move-modal{
    background:rgba(34,35,39,.97);
  }

  .inspector.floating{
    background:rgba(28,29,33,.94);
  }

  .duplicate-panel{
    background:rgba(130,90,0,.25);
    color:#ffd47a;
  }
}
CSS

###############################################################################
# 22. AJUSTES DE APP / VERSIÓN
###############################################################################

python3 <<'PY'
from pathlib import Path
import json

p = Path("src-tauri/tauri.conf.json")
cfg = json.loads(p.read_text())

cfg["productName"] = "ABRAXAS Publisher"
cfg["version"] = "0.3.0"
cfg["identifier"] = "com.abraxas.publisher"

p.write_text(
    json.dumps(
        cfg,
        ensure_ascii=False,
        indent=2,
    )
    + "\n"
)

sidebar = Path(
    "src/components/Sidebar.tsx"
)

if sidebar.exists():
    text = sidebar.read_text()

    text = (
        text
        .replace(
            "Publisher · v1.1",
            "Publisher · v1.2",
        )
    )

    sidebar.write_text(text)

app = Path("src/App.tsx")

if app.exists():
    text = app.read_text()

    old = (
        '<div className="app-shell">'
    )

    if old in text:
        text = text.replace(
            old,
            """<div className={`app-shell ${
              !selectedIds.length || inspectorMode === 'hidden'
                ? 'no-inspector'
                : ''
            }`}>""",
            1,
        )

    app.write_text(text)
PY

###############################################################################
# 23. DOCUMENTACIÓN
###############################################################################

cat > docs/V12_IMPLEMENTED.md <<'MD'
# ABRAXAS Publisher V1.2

## Implementado

- marcas persistentes;
- selector Todas / JOC / MOKA / otras;
- creación de marcas;
- import local recursivo;
- preview antes de importar;
- detección de duplicados;
- replace / keep / skip;
- Google Drive directo mediante OAuth Desktop;
- navegador de carpetas Drive;
- caché local de contenido Drive;
- CORRECCION.txt local;
- CORRECCION.txt Drive cuando la sesión tiene permiso;
- inspector condicionado por selección;
- inspector docked / floating / hidden;
- multi-select;
- preview de media;
- estados editoriales;
- refresh por SHA-256 / tamaño / mtime;
- versionado;
- schedule por PublicationTarget;
- calendario Día / Semana / Mes;
- drag & drop;
- movimientos multired;
- bloqueo SCHEDULED_REMOTE / PUBLISHED;
- Sin calendarizar con búsqueda y filtros;
- Kanban informativo;
- actividad;
- Undo / Redo local;
- publisherctl;
- publisher-mcp;
- Dry Run;
- QA en DB temporal.

## No implementado todavía

Publicación real en:

- Instagram
- Facebook
- LinkedIn
- YouTube

Esto corresponde al Paso 2.

## Google Drive

Se necesita un OAuth Client ID de Google de tipo Desktop:

xxxxxxxx.apps.googleusercontent.com

No se incluye ningún Client ID privado en el repositorio.

La sesión actual de Drive se mantiene en memoria.
Si caduca, Publisher solicita reconexión.

## Estados remotos

La arquitectura reconoce:

READY
PRECALENDARIZED
SCHEDULED_REMOTE
PUBLISHED

Un destino SCHEDULED_REMOTE o PUBLISHED no puede moverse con drag & drop.
En Paso 2 su modificación debe pasar por cancelación/verificación del provider.
MD

cat >> CHANGELOG.md <<'MD'

## 0.3.0 · V1.2 Workspace

- marcas;
- importación recursiva;
- duplicados;
- Drive OAuth directo;
- calendar Day/Week/Month;
- multi-network scheduling;
- inspector dock/float/hide;
- activity;
- undo/redo;
- publisherctl;
- publisher-mcp;
- QA automatizado;
- publicación social real sigue desactivada.
MD

###############################################################################
# 24. FORMATO + FRONTEND QA
###############################################################################

section "10/13 · FRONTEND QA"

if [ -f package-lock.json ]; then
  npm install
else
  npm install
fi

npm run check \
  || fail "TypeScript no pasó."

npm run build \
  || fail "Vite build no pasó."

echo "✓ Frontend"

###############################################################################
# 25. RUST QA
###############################################################################

section "11/13 · RUST QA"

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all || true

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check falló."

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

cargo build \
  --release \
  --manifest-path src-tauri/Cargo.toml \
  --bin publisherctl \
  || fail "publisherctl release build falló."

echo "✓ Rust"

###############################################################################
# 26. PUBLISHERCTL QA
###############################################################################

section "12/13 · CLI / MCP / DOCTOR"

./publisherctl qa \
  || fail "publisherctl qa falló."

./publisher-mcp --self-test \
  || fail "publisher-mcp self-test falló."

if [ -x scripts/doctor.sh ]; then
  scripts/doctor.sh \
    || fail "Doctor falló."
fi

echo "✓ CLI / MCP / Doctor"

###############################################################################
# 27. TAURI BUILD
###############################################################################

section "13/13 · BUILD / INSTALACIÓN / GITHUB"

npm run tauri:build \
  || fail "Tauri build falló."

NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"

if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(
    find \
      "$ROOT/src-tauri/target/release/bundle" \
      -maxdepth 4 \
      -type d \
      -name "ABRAXAS Publisher.app" \
      -print \
      -quit
  )"
fi

[ -n "${NEW_APP:-}" ] \
  || fail "No se encontró ABRAXAS Publisher.app."

[ -d "$NEW_APP" ] \
  || fail "Bundle .app inexistente."

INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/ABRAXAS Publisher.app"
STAGE="$INSTALL_DIR/.ABRAXAS Publisher.v12.$STAMP.app"
BACKUP="$INSTALL_DIR/ABRAXAS Publisher.backup.$STAMP.app"

mkdir -p "$INSTALL_DIR"

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
    "$BACKUP"
fi

if ! mv \
  "$STAGE" \
  "$APP"
then
  if [ -d "$BACKUP" ]; then
    mv \
      "$BACKUP" \
      "$APP" \
      || true
  fi

  fail "No se pudo instalar la app nueva."
fi

echo "✓ App instalada:"
echo "  $APP"

if codesign \
  --verify \
  --deep \
  --strict \
  "$APP" \
  >/dev/null 2>&1
then
  echo "✓ codesign verify"
else
  echo "WARN codesign verify: build local sin firma completa."
fi

###############################################################################
# 28. INSTALAR CLI + MCP EN ~/.local/bin
###############################################################################

mkdir -p "$HOME/.local/bin"

PUBLISHERCTL_BIN="$ROOT/src-tauri/target/release/publisherctl"

[ -x "$PUBLISHERCTL_BIN" ] \
  || fail "No existe publisherctl release."

cp \
  "$PUBLISHERCTL_BIN" \
  "$HOME/.local/bin/publisherctl"

chmod +x \
  "$HOME/.local/bin/publisherctl"

TOOLS_DIR="$HOME/Library/Application Support/com.abraxas.publisher/tools"

mkdir -p "$TOOLS_DIR"

cp \
  "$ROOT/tools/publisher_mcp.py" \
  "$TOOLS_DIR/publisher_mcp.py"

chmod +x \
  "$TOOLS_DIR/publisher_mcp.py"

cat > "$HOME/.local/bin/publisher-mcp" <<SH
#!/bin/bash
set -Eeuo pipefail
export PATH="\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec python3 "$TOOLS_DIR/publisher_mcp.py" "\$@"
SH

chmod +x \
  "$HOME/.local/bin/publisher-mcp"

echo "✓ publisherctl instalado"
echo "✓ publisher-mcp instalado"

###############################################################################
# 29. POST-INSTALL QA
###############################################################################

publisherctl doctor \
  || fail "publisherctl doctor post-install falló."

publisher-mcp --self-test \
  || fail "MCP post-install falló."

###############################################################################
# 30. GIT COMMIT / PUSH
###############################################################################

git add -A

if ! git diff \
  --cached \
  --quiet
then
  git commit \
    -m "ABRAXAS Publisher V1.2 Workspace"
fi

git push \
  -u origin \
  "$BRANCH"

PR_URL="$(
  gh pr list \
    --repo LordJeferies/abraxas-publisher \
    --base main \
    --head "$BRANCH" \
    --json url \
    --jq '.[0].url' \
    2>/dev/null \
    || true
)"

if [ -z "$PR_URL" ]; then
  PR_URL="$(
    gh pr create \
      --repo LordJeferies/abraxas-publisher \
      --base main \
      --head "$BRANCH" \
      --title "ABRAXAS Publisher V1.2 · Workspace" \
      --body "V1.2 del Paso 1: marcas, Google Drive directo, importación recursiva y duplicados, calendario día/semana/mes, programación por destino/red, inspector dock/float/hide, actividad, undo/redo, publisherctl, MCP y QA. No incluye publicación social real."
  )"
fi

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.2 · TERMINADA"
echo "=============================================================="
echo
echo "Aplicación:"
echo "  $APP"
echo
echo "CLI:"
echo "  $HOME/.local/bin/publisherctl"
echo
echo "MCP:"
echo "  $HOME/.local/bin/publisher-mcp"
echo
echo "Repo:"
echo "  https://github.com/LordJeferies/abraxas-publisher"
echo
echo "Rama:"
echo "  $BRANCH"
echo
echo "Pull Request:"
echo "  ${PR_URL:-No disponible}"
echo
echo "Log:"
echo "  $LOG"
echo
echo "Pruebas rápidas:"
echo
echo "  publisherctl doctor"
echo "  publisherctl brands list"
echo "  publisherctl content list"
echo "  publisherctl activity"
echo "  publisherctl dry-run"
echo "  publisherctl qa"
echo "  publisher-mcp --self-test"
echo
echo "IMPORTANTE:"
echo "  La publicación social real continúa desactivada."
echo "  No se ha mezclado automáticamente la rama con main."
echo

open "$APP" || true

