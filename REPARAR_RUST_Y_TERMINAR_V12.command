#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$ROOT/logs/v12_rust_fix_$STAMP.log"

mkdir -p "$ROOT/logs"
exec > >(tee -a "$LOG") 2>&1

fail() {
  echo
  echo "=============================================================="
  echo " ABRAXAS PUBLISHER V1.2 · FALLO"
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
# 1. BACKUP
###############################################################################

section "1/10 · BACKUP"

BACKUP="$ROOT/.v12-rust-backup/$STAMP"
mkdir -p "$BACKUP"

cp src-tauri/src/db.rs "$BACKUP/db.rs"
cp src-tauri/src/core.rs "$BACKUP/core.rs"

echo "✓ Backup creado:"
echo "$BACKUP"

###############################################################################
# 2. PATCH db.rs
###############################################################################

section "2/10 · REPARAR LIFETIMES RUSQLITE"

python3 <<'PY'
from pathlib import Path
import re

path = Path("src-tauri/src/db.rs")
s = path.read_text(encoding="utf-8")

###############################################################################
# list_brands
###############################################################################

old = r'''pub fn list_brands(db: &Path) -> Result<Vec<Brand>, String> {
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
}'''

new = r'''pub fn list_brands(db: &Path) -> Result<Vec<Brand>, String> {
    let conn = open(db)?;

    let mut stmt = conn
        .prepare("SELECT id,name,created_at FROM brands ORDER BY name COLLATE NOCASE")
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
}'''

if old not in s:
    print("WARN: list_brands no coincidió exactamente; intentando regex.")

    pattern = re.compile(
        r'''pub fn list_brands\(db: &Path\) -> Result<Vec<Brand>, String> \{
.*?
\}
(?=
pub fn set_setting)''',
        re.S,
    )

    if not pattern.search(s):
        raise SystemExit("ERROR: no pude localizar list_brands.")

    s = pattern.sub(new, s, count=1)

else:
    s = s.replace(old, new, 1)

###############################################################################
# list() media block
###############################################################################

media_pattern = re.compile(
    r'''let media = \{
\s*let mut s = conn
\s*\.prepare\(
\s*r#"
\s*SELECT id,path,kind,size_bytes,duration_seconds,sha256,modified_at
\s*FROM media_assets
\s*WHERE content_id=\?1
\s*ORDER BY path
\s*"#,
\s*\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?;

\s*s\.query_map\(params!\[id\.clone\(\)\], \|r\| \{
\s*Ok\(MediaAsset \{
\s*id: r\.get\(0\)\?,
\s*path: r\.get\(1\)\?,
\s*kind: r\.get\(2\)\?,
\s*size_bytes: r\.get::<_, i64>\(3\)\? as u64,
\s*duration_seconds: r\.get\(4\)\?,
\s*sha256: r\.get\(5\)\?,
\s*modified_at: r\.get\(6\)\?,
\s*\}\)
\s*\}\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?
\s*\.collect::<Result<Vec<_>, _>>\(\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?
\s*\};''',
    re.S,
)

media_new = r'''let media = {
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

            let rows = s
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
        };'''

s, n = media_pattern.subn(media_new, s, count=1)
if n != 1:
    raise SystemExit(f"ERROR: media block reemplazado {n} veces.")

###############################################################################
# targets block
###############################################################################

targets_pattern = re.compile(
    r'''let targets = \{
\s*let mut s = conn
\s*\.prepare\(
\s*r#"
\s*SELECT id,platform,account,status,scheduled_at,source_txt,copy,schedule_source
\s*FROM publication_targets
\s*WHERE content_id=\?1
\s*ORDER BY platform
\s*"#,
\s*\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?;

\s*s\.query_map\(params!\[id\.clone\(\)\], \|r\| \{
\s*Ok\(PublicationTarget \{
\s*id: r\.get\(0\)\?,
\s*platform: r\.get\(1\)\?,
\s*account: r\.get\(2\)\?,
\s*status: r\.get\(3\)\?,
\s*scheduled_at: r\.get\(4\)\?,
\s*source_txt: r\.get\(5\)\?,
\s*copy: r\.get\(6\)\?,
\s*schedule_source: r\.get\(7\)\?,
\s*\}\)
\s*\}\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?
\s*\.collect::<Result<Vec<_>, _>>\(\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?
\s*\};''',
    re.S,
)

targets_new = r'''let targets = {
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

            let rows = s
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
        };'''

s, n = targets_pattern.subn(targets_new, s, count=1)
if n != 1:
    raise SystemExit(f"ERROR: targets block reemplazado {n} veces.")

###############################################################################
# issues block
###############################################################################

issues_pattern = re.compile(
    r'''let issues = \{
\s*let mut s = conn
\s*\.prepare\(
\s*"SELECT id,severity,message
\s*FROM validation_issues
\s*WHERE content_id=\?1",
\s*\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?;

\s*s\.query_map\(params!\[id\.clone\(\)\], \|r\| \{
\s*Ok\(ValidationIssue \{
\s*id: r\.get\(0\)\?,
\s*severity: r\.get\(1\)\?,
\s*message: r\.get\(2\)\?,
\s*\}\)
\s*\}\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?
\s*\.collect::<Result<Vec<_>, _>>\(\)
\s*\.map_err\(\|e\| e\.to_string\(\)\)\?
\s*\};''',
    re.S,
)

issues_new = r'''let issues = {
            let mut s = conn
                .prepare(
                    "SELECT id,severity,message
                     FROM validation_issues
                     WHERE content_id=?1",
                )
                .map_err(|e| e.to_string())?;

            let rows = s
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
        };'''

s, n = issues_pattern.subn(issues_new, s, count=1)
if n != 1:
    raise SystemExit(f"ERROR: issues block reemplazado {n} veces.")

###############################################################################
# list_activity
###############################################################################

activity_pattern = re.compile(
    r'''pub fn list_activity\(
\s*db: &Path,
\s*limit: usize,
\s*\) -> Result<Vec<ActivityEvent>, String> \{
.*?
\}
(?=
pub fn update_schedule)''',
    re.S,
)

activity_new = r'''pub fn list_activity(
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
}'''

if not activity_pattern.search(s):
    raise SystemExit("ERROR: no pude localizar list_activity.")

s = activity_pattern.sub(
    activity_new,
    s,
    count=1,
)

path.write_text(s, encoding="utf-8")

print("✓ list_brands")
print("✓ media")
print("✓ targets")
print("✓ issues")
print("✓ list_activity")
PY

###############################################################################
# 3. WARNING core.rs
###############################################################################

section "3/10 · LIMPIEZA WARNING"

python3 <<'PY'
from pathlib import Path

p = Path("src-tauri/src/core.rs")
s = p.read_text(encoding="utf-8")

s = s.replace(
    '(Some(existing), "keep") => {',
    '(Some(_existing), "keep") => {',
)

p.write_text(s, encoding="utf-8")

print("✓ warning existing → _existing")
PY

###############################################################################
# 4. RUST FORMAT + CHECK
###############################################################################

section "4/10 · CARGO CHECK"

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all

cargo check \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo check todavía falla."

echo "✓ cargo check"

###############################################################################
# 5. RUST TESTS
###############################################################################

section "5/10 · CARGO TEST"

cargo test \
  --manifest-path src-tauri/Cargo.toml \
  || fail "cargo test falló."

echo "✓ cargo test"

###############################################################################
# 6. FRONTEND RECHECK
###############################################################################

section "6/10 · FRONTEND RECHECK"

npm run check \
  || fail "TypeScript volvió a fallar."

npm run build \
  || fail "Vite build falló."

echo "✓ TypeScript"
echo "✓ Vite"

###############################################################################
# 7. CLI + MCP
###############################################################################

section "7/10 · CLI / MCP QA"

cargo build \
  --release \
  --manifest-path src-tauri/Cargo.toml \
  --bin publisherctl \
  || fail "publisherctl release no compiló."

chmod +x publisherctl publisher-mcp tools/publisher_mcp.py

./publisherctl qa \
  || fail "publisherctl qa falló."

./publisher-mcp --self-test \
  || fail "publisher-mcp self-test falló."

echo "✓ publisherctl"
echo "✓ publisher-mcp"

###############################################################################
# 8. TAURI BUILD
###############################################################################

section "8/10 · TAURI BUILD"

npm run tauri:build \
  || fail "Tauri build falló."

NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"

if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(
    find "$ROOT/src-tauri/target/release/bundle" \
      -type d \
      -name "ABRAXAS Publisher.app" \
      -print \
      -quit
  )"
fi

[ -n "${NEW_APP:-}" ] || fail "No encontré el bundle .app."
[ -d "$NEW_APP" ] || fail "El bundle .app no existe."

echo "✓ Bundle generado"

###############################################################################
# 9. INSTALACIÓN SEGURA
###############################################################################

section "9/10 · INSTALAR"

APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP_APP="$HOME/Applications/ABRAXAS Publisher.before-v12-$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.stage-$STAMP.app"

mkdir -p "$HOME/Applications"

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
  mv "$APP" "$BACKUP_APP"
fi

if ! mv "$STAGE" "$APP"; then
  echo "ERROR instalando V1.2."

  if [ -d "$BACKUP_APP" ]; then
    mv "$BACKUP_APP" "$APP" || true
  fi

  fail "Se restauró la app anterior."
fi

xattr -dr \
  com.apple.quarantine \
  "$APP" \
  >/dev/null 2>&1 \
  || true

echo "✓ App instalada"

###############################################################################
# CLI INSTALADO
###############################################################################

mkdir -p "$HOME/.local/bin"

cp \
  "$ROOT/src-tauri/target/release/publisherctl" \
  "$HOME/.local/bin/publisherctl"

chmod +x "$HOME/.local/bin/publisherctl"

MCP_DIR="$HOME/Library/Application Support/com.abraxas.publisher/tools"

mkdir -p "$MCP_DIR"

cp \
  "$ROOT/tools/publisher_mcp.py" \
  "$MCP_DIR/publisher_mcp.py"

chmod +x "$MCP_DIR/publisher_mcp.py"

cat > "$HOME/.local/bin/publisher-mcp" <<EOF
#!/bin/bash
set -Eeuo pipefail
export PATH="\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec python3 "$MCP_DIR/publisher_mcp.py" "\$@"
EOF

chmod +x "$HOME/.local/bin/publisher-mcp"

export PATH="$HOME/.local/bin:$PATH"

###############################################################################
# POST INSTALL
###############################################################################

publisherctl doctor \
  || fail "publisherctl doctor falló."

publisherctl qa \
  || fail "publisherctl qa post-install falló."

publisher-mcp --self-test \
  || fail "publisher-mcp post-install falló."

###############################################################################
# 10. GIT
###############################################################################

section "10/10 · GITHUB"

git switch v1.2-workspace 2>/dev/null \
  || git switch -c v1.2-workspace

git add -A

if ! git diff --cached --quiet; then
  git commit \
    -m "Fix rusqlite lifetimes and finish ABRAXAS Publisher V1.2"
fi

git push \
  -u origin \
  v1.2-workspace

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.2 · COMPLETADA"
echo "=============================================================="
echo
echo "App:"
echo "  $APP"
echo
echo "Backup anterior:"
echo "  $BACKUP_APP"
echo
echo "CLI:"
echo "  $(command -v publisherctl)"
echo
echo "MCP:"
echo "  $(command -v publisher-mcp)"
echo
echo "Log:"
echo "  $LOG"
echo
echo "QA:"
echo "  ✓ cargo check"
echo "  ✓ cargo test"
echo "  ✓ TypeScript"
echo "  ✓ Vite"
echo "  ✓ publisherctl qa"
echo "  ✓ publisher-mcp"
echo "  ✓ Tauri"
echo
echo "Publicación social real:"
echo "  DESACTIVADA"
echo

open "$APP" || true
