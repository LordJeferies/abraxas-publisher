use crate::models::*;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::Utc;
use rand::{distributions::Alphanumeric, Rng};
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

const FOLDER_MIME: &str = "application/vnd.google-apps.folder";

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

fn token(session: &Mutex<DriveSession>) -> Result<String, String> {
    let s = session.lock().map_err(|e| e.to_string())?;

    if s.access_token.is_none() || Utc::now().timestamp() >= s.expires_at {
        return Err("Google Drive no está conectado o la sesión caducó.".into());
    }

    Ok(s.access_token.clone().unwrap())
}

pub fn connected(session: &Mutex<DriveSession>) -> bool {
    token(session).is_ok()
}

pub fn connect(client_id: &str, session: &Mutex<DriveSession>) -> Result<DriveAuthResult, String> {
    let client_id = client_id.trim();

    if !client_id.ends_with(".apps.googleusercontent.com") {
        return Err(
            "Introduce un OAuth Client ID de tipo Desktop terminado en .apps.googleusercontent.com."
                .into(),
        );
    }

    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;

    listener.set_nonblocking(true).map_err(|e| e.to_string())?;

    let port = listener.local_addr().map_err(|e| e.to_string())?.port();

    let redirect = format!("http://127.0.0.1:{port}");

    let verifier: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(72)
        .map(char::from)
        .collect();

    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));

    let mut auth =
        Url::parse("https://accounts.google.com/o/oauth2/v2/auth").map_err(|e| e.to_string())?;

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
        .map_err(|e| format!("No se pudo abrir el navegador: {e}"))?;

    let started = Instant::now();
    let code = loop {
        if started.elapsed() > Duration::from_secs(180) {
            return Err("Tiempo agotado esperando autorización de Google.".into());
        }

        match listener.accept() {
            Ok((mut stream, _)) => {
                let mut buf = [0u8; 8192];
                let n = stream.read(&mut buf).unwrap_or(0);

                let request = String::from_utf8_lossy(&buf[..n]);

                let first = request.lines().next().unwrap_or("");

                let path = first.split_whitespace().nth(1).unwrap_or("/");

                let parsed =
                    Url::parse(&format!("http://127.0.0.1{path}")).map_err(|e| e.to_string())?;

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
                    return Err(format!("Google rechazó la autorización: {error}"));
                }

                if let Some(code) = code {
                    break code;
                }
            }

            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
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

        return Err(format!("Google token exchange falló ({status}): {body}"));
    }

    let data: TokenResponse = token_response.json().map_err(|e| e.to_string())?;

    {
        let mut s = session.lock().map_err(|e| e.to_string())?;

        s.access_token = Some(data.access_token);
        s.expires_at = Utc::now().timestamp() + data.expires_in - 60;
    }

    Ok(DriveAuthResult {
        connected: true,
        message: "Google Drive conectado.".into(),
    })
}

pub fn list(session: &Mutex<DriveSession>, folder_id: &str) -> Result<Vec<DriveItem>, String> {
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

        let response = req.send().map_err(|e| e.to_string())?;

        if !response.status().is_success() {
            return Err(format!("Drive API {}", response.status()));
        }

        let data: DriveFilesResponse = response.json().map_err(|e| e.to_string())?;

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

fn folder_meta(session: &Mutex<DriveSession>, id: &str) -> Result<DriveApiFile, String> {
    let access = token(session)?;

    let response = Client::new()
        .get(format!("https://www.googleapis.com/drive/v3/files/{id}"))
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
        return Err(format!("No se pudo descargar {id}: {}", response.status()));
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
        return Err("La carpeta excede la profundidad máxima de 8 niveles.".into());
    }

    fs::create_dir_all(destination).map_err(|e| e.to_string())?;

    fs::write(destination.join(".abraxas_drive_id"), folder_id).map_err(|e| e.to_string())?;

    for item in list(session, folder_id)? {
        let dst = destination.join(safe_name(&item.name));

        if item.is_folder {
            download_folder_recursive(session, &item.id, &dst, depth + 1)?;
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

    let destination = cache_root.join(folder_id).join(safe_name(&meta.name));

    fs::create_dir_all(&destination).map_err(|e| e.to_string())?;

    download_folder_recursive(session, folder_id, &destination, 0)?;

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

    let boundary = format!("abraxas-{}", Utc::now().timestamp_millis());

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
