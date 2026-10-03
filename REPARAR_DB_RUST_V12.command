#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p ".v12-db-backup/$STAMP"

cp src-tauri/src/db.rs ".v12-db-backup/$STAMP/db.rs"
cp src-tauri/src/core.rs ".v12-db-backup/$STAMP/core.rs"

echo "=============================================================="
echo " ABRAXAS Publisher V1.2 · Reparación DB Rust"
echo "=============================================================="
echo
echo "Backup:"
echo "  .v12-db-backup/$STAMP"

python3 <<'PY'
from pathlib import Path

path = Path("src-tauri/src/db.rs")
source = path.read_text(encoding="utf-8")


def replace_rust_function(text: str, name: str, replacement: str) -> str:
    """
    Encuentra `pub fn NAME(` y sustituye toda la función contando llaves.
    No depende de espacios, saltos de línea ni cargo fmt.
    """
    needle = f"pub fn {name}("
    start = text.find(needle)

    if start == -1:
        raise SystemExit(f"ERROR: no encontré función {name}().")

    brace = text.find("{", start)

    if brace == -1:
        raise SystemExit(f"ERROR: no encontré apertura de {name}().")

    depth = 0
    in_string = False
    escape = False
    i = brace

    # Para estas funciones los SQL raw strings no contienen llaves,
    # por lo que el contador es seguro.
    while i < len(text):
        ch = text[i]

        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False

            i += 1
            continue

        if ch == '"':
            in_string = True
            i += 1
            continue

        if ch == "{":
            depth += 1

        elif ch == "}":
            depth -= 1

            if depth == 0:
                end = i + 1
                return (
                    text[:start]
                    + replacement.rstrip()
                    + "\n"
                    + text[end:]
                )

        i += 1

    raise SystemExit(
        f"ERROR: no pude determinar final de {name}()."
    )


LIST_BRANDS = r'''
pub fn list_brands(db: &Path) -> Result<Vec<Brand>, String> {
    let conn = open(db)?;

    let mut stmt = conn
        .prepare(
            "SELECT id,name,created_at
             FROM brands
             ORDER BY name COLLATE NOCASE",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |r| {
            Ok(Brand {
                id: r.get(0)?,
                name: r.get(1)?,
                created_at: r.get(2)?,
            })
        })
        .map_err(|e| e.to_string())?;

    let result = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    Ok(result)
}
'''


LIST_CONTENTS = r'''
pub fn list(db: &Path) -> Result<Vec<ContentItem>, String> {
    let conn = open(db)?;

    /*
     * Materializamos primero las filas base.
     *
     * Esto es deliberado: no mantenemos vivo un MappedRows/Statement
     * mientras hacemos nuevas consultas sobre la misma conexión.
     */
    let base = {
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

        let rows = stmt
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

        let result = rows
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;

        result
    };

    let mut out = Vec::with_capacity(base.len());

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
        ) = row;

        let media = {
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT
                      id,path,kind,size_bytes,
                      duration_seconds,sha256,modified_at
                    FROM media_assets
                    WHERE content_id=?1
                    ORDER BY path
                    "#,
                )
                .map_err(|e| e.to_string())?;

            let rows = stmt
                .query_map(params![id.clone()], |r| {
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
                .map_err(|e| e.to_string())?;

            let result = rows
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())?;

            result
        };

        let targets = {
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT
                      id,platform,account,status,
                      scheduled_at,source_txt,copy,schedule_source
                    FROM publication_targets
                    WHERE content_id=?1
                    ORDER BY platform
                    "#,
                )
                .map_err(|e| e.to_string())?;

            let rows = stmt
                .query_map(params![id.clone()], |r| {
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
                .map_err(|e| e.to_string())?;

            let result = rows
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())?;

            result
        };

        let issues = {
            let mut stmt = conn
                .prepare(
                    r#"
                    SELECT id,severity,message
                    FROM validation_issues
                    WHERE content_id=?1
                    "#,
                )
                .map_err(|e| e.to_string())?;

            let rows = stmt
                .query_map(params![id.clone()], |r| {
                    Ok(ValidationIssue {
                        id: r.get(0)?,
                        severity: r.get(1)?,
                        message: r.get(2)?,
                    })
                })
                .map_err(|e| e.to_string())?;

            let result = rows
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())?;

            result
        };

        let (source_kind, source_ref) =
            source_for(&conn, &id, &folder)?;

        let latest_note =
            latest_note(&conn, &id)?;

        out.push(ContentItem {
            id,
            folder_path: folder,
            title,
            client,
            content_type: ctype,
            status: workflow_status,
            validation_status,
            version,
            source_fingerprint,
            refreshed_at,
            latest_note,
            source_kind,
            source_ref,
            media,
            targets,
            issues,
        });
    }

    Ok(out)
}
'''


LIST_ACTIVITY = r'''
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

    let rows = stmt
        .query_map(params![limit as i64], |r| {
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
        .map_err(|e| e.to_string())?;

    let result = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    Ok(result)
}
'''


source = replace_rust_function(
    source,
    "list_brands",
    LIST_BRANDS,
)

# Es importante buscar exactamente `pub fn list(`;
# no toca list_brands/list_activity.
source = replace_rust_function(
    source,
    "list",
    LIST_CONTENTS,
)

source = replace_rust_function(
    source,
    "list_activity",
    LIST_ACTIVITY,
)

path.write_text(
    source,
    encoding="utf-8",
)

print("✓ list_brands() sustituida")
print("✓ list() sustituida")
print("✓ list_activity() sustituida")
PY

###############################################################################
# WARNING DE core.rs
###############################################################################

python3 <<'PY'
from pathlib import Path

p = Path("src-tauri/src/core.rs")
s = p.read_text(encoding="utf-8")

s = s.replace(
    '(Some(existing), "keep") => {',
    '(Some(_existing), "keep") => {',
)

p.write_text(
    s,
    encoding="utf-8",
)

print("✓ warning _existing corregido")
PY

###############################################################################
# FORMAT
###############################################################################

echo
echo "=============================================================="
echo " CARGO FMT"
echo "=============================================================="

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all

###############################################################################
# CARGO CHECK
###############################################################################

echo
echo "=============================================================="
echo " CARGO CHECK"
echo "=============================================================="

cargo check \
  --manifest-path src-tauri/Cargo.toml

###############################################################################
# CARGO TEST
###############################################################################

echo
echo "=============================================================="
echo " CARGO TEST"
echo "=============================================================="

cargo test \
  --manifest-path src-tauri/Cargo.toml

###############################################################################
# TYPESCRIPT / VITE
###############################################################################

echo
echo "=============================================================="
echo " TYPESCRIPT"
echo "=============================================================="

npm run check

echo
echo "=============================================================="
echo " VITE"
echo "=============================================================="

npm run build

###############################################################################
# CLI RELEASE
###############################################################################

echo
echo "=============================================================="
echo " PUBLISHERCTL"
echo "=============================================================="

cargo build \
  --release \
  --manifest-path src-tauri/Cargo.toml \
  --bin publisherctl

chmod +x \
  publisherctl \
  publisher-mcp \
  tools/publisher_mcp.py

./publisherctl qa

echo
echo "=============================================================="
echo " MCP"
echo "=============================================================="

./publisher-mcp --self-test

###############################################################################
# Si todo lo anterior funcionó, usar el finalizador existente para
# build Tauri + instalación + GitHub.
###############################################################################

echo
echo "=============================================================="
echo " CORE V1.2 APROBADO"
echo "=============================================================="
echo
echo "Continuando con build e instalación completa..."
echo

./FINALIZAR_V12.command
