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
