#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

echo "=============================================================="
echo " ABRAXAS Publisher V1.2 · Reparación TSX"
echo "=============================================================="

###############################################################################
# 1. BACKUP
###############################################################################

STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p ".v12-fix-backup/$STAMP"

for f in \
  src/components/ContentDetail.tsx \
  src/views/CalendarView.tsx \
  src/views/ImportView.tsx \
  src/lib/backend.ts
do
  [ -f "$f" ] && cp "$f" ".v12-fix-backup/$STAMP/$(basename "$f")"
done

echo "✓ Backup: .v12-fix-backup/$STAMP"

###############################################################################
# 2. ELIMINAR CASTS FRÁGILES EN JSX
###############################################################################

python3 <<'PY'
from pathlib import Path
import re

# ------------------------------------------------------------------
# backend.ts
# Aceptar string para status. Rust seguirá validando los valores.
# ------------------------------------------------------------------

p = Path("src/lib/backend.ts")
s = p.read_text(encoding="utf-8")

s = re.sub(
    r"status:\s*WorkflowStatus",
    "status: string",
    s,
)

p.write_text(s, encoding="utf-8")

# ------------------------------------------------------------------
# ImportView.tsx
# Evitar "e.target.value as Policy" partido por el formatter/paste.
# ------------------------------------------------------------------

p = Path("src/views/ImportView.tsx")
s = p.read_text(encoding="utf-8")

s = re.sub(
    r"setPolicy\(\s*e\.target\.value\s*as\s*Policy,?\s*\)",
    """setPolicy(
                      e.target.value === 'keep'
                        ? 'keep'
                        : e.target.value === 'skip'
                          ? 'skip'
                          : 'replace'
                    )""",
    s,
    flags=re.S,
)

p.write_text(s, encoding="utf-8")

# ------------------------------------------------------------------
# ContentDetail.tsx
# Eliminar casts TS que quedaron en posiciones conflictivas.
# ------------------------------------------------------------------

p = Path("src/components/ContentDetail.tsx")
s = p.read_text(encoding="utf-8")

# useState<WorkflowStatus>(item.status as WorkflowStatus)
s = re.sub(
    r"useState\s*<\s*WorkflowStatus\s*>\s*\(\s*item\.status\s*as\s*WorkflowStatus\s*,?\s*\)",
    "useState(item.status)",
    s,
    flags=re.S,
)

# e.target.value as WorkflowStatus
s = re.sub(
    r"e\.target\.value\s*as\s*WorkflowStatus",
    "e.target.value",
    s,
    flags=re.S,
)

# const next: WorkflowStatus =
s = s.replace(
    "const next:\n          WorkflowStatus =",
    "const next =",
)
s = s.replace(
    "const next: WorkflowStatus =",
    "const next =",
)

p.write_text(s, encoding="utf-8")

print("✓ Casts TSX normalizados")
PY

###############################################################################
# 3. REPARAR MODAL DEL CALENDARIO
###############################################################################

python3 <<'PY'
from pathlib import Path

p = Path("src/views/CalendarView.tsx")
s = p.read_text(encoding="utf-8")

# El bloque original utilizaba:
#
# { pending && (() => { ... })() }
#
# que quedó vulnerable al corte/paste.
#
# Lo sustituimos por un componente inline más simple.

start_marker = """        {
          pending
          && (() => {"""

end_marker = """          })()
        }
      </div>
    </DndContext>"""

if start_marker in s and end_marker in s:
    start = s.index(start_marker)
    end = s.index(end_marker, start)

    replacement = r"""        {
          pending
          && (
            <MovePublicationModal
              pending={pending}
              contents={visibleContents}
              moveScope={moveScope}
              setMoveScope={setMoveScope}
              selectedPlatforms={selectedPlatforms}
              setSelectedPlatforms={setSelectedPlatforms}
              onCancel={() => setPending(null)}
              onApply={applyMove}
            />
          )
        }
"""

    s = (
        s[:start]
        + replacement
        + s[end + len("""          })()
        }
"""):]
    )

# Añadir el componente antes de CalendarView si no existe.
marker = "export function CalendarView() {"

if "function MovePublicationModal(" not in s:
    component = r'''
function MovePublicationModal({
  pending,
  contents,
  moveScope,
  setMoveScope,
  selectedPlatforms,
  setSelectedPlatforms,
  onCancel,
  onApply,
}: {
  pending: PendingMove
  contents: ContentItem[]
  moveScope: 'all' | 'one' | 'selected'
  setMoveScope: (
    value: 'all' | 'one' | 'selected'
  ) => void
  selectedPlatforms: string[]
  setSelectedPlatforms: React.Dispatch<
    React.SetStateAction<string[]>
  >
  onCancel: () => void
  onApply: () => void
}) {
  const content = contents.find(
    (item) => item.id === pending.contentId,
  )

  const dragged = content?.targets.find(
    (target) => target.id === pending.targetId,
  )

  if (!content || !dragged) {
    return null
  }

  return (
    <div className="modal-backdrop">
      <section className="move-modal">
        <span className="eyebrow">
          MOVER PUBLICACIÓN
        </span>

        <h3>{content.title}</h3>

        <p>
          {pending.date
            ? `Nueva fecha: ${pending.date}`
            : 'Quitar fecha y devolver a Sin calendarizar'}
        </p>

        <label className="radio-row">
          <input
            type="radio"
            checked={moveScope === 'all'}
            onChange={() => setMoveScope('all')}
          />
          Todas las redes
        </label>

        <label className="radio-row">
          <input
            type="radio"
            checked={moveScope === 'one'}
            onChange={() => setMoveScope('one')}
          />
          Sólo {dragged.platform}
        </label>

        <label className="radio-row">
          <input
            type="radio"
            checked={moveScope === 'selected'}
            onChange={() => setMoveScope('selected')}
          />
          Elegir redes
        </label>

        {moveScope === 'selected' && (
          <div className="platform-checks">
            {content.targets.map((target) => (
              <label key={target.id}>
                <input
                  type="checkbox"
                  checked={selectedPlatforms.includes(
                    target.platform,
                  )}
                  onChange={(event) => {
                    setSelectedPlatforms((previous) => {
                      if (event.target.checked) {
                        return Array.from(
                          new Set([
                            ...previous,
                            target.platform,
                          ]),
                        )
                      }

                      return previous.filter(
                        (platform) =>
                          platform !== target.platform,
                      )
                    })
                  }}
                />

                {target.platform}
                {locked(target) ? ' 🔒' : ''}
              </label>
            ))}
          </div>
        )}

        <div className="modal-actions">
          <button
            className="secondary-btn"
            onClick={onCancel}
          >
            Cancelar
          </button>

          <button
            className="primary-btn"
            onClick={onApply}
          >
            Confirmar cambio
          </button>
        </div>
      </section>
    </div>
  )
}

'''
    if marker not in s:
        raise SystemExit(
            "ERROR: no encontré export function CalendarView()."
        )

    s = s.replace(
        marker,
        component + marker,
        1,
    )

p.write_text(s, encoding="utf-8")

print("✓ Modal de calendario reparado")
PY

###############################################################################
# 4. ASEGURAR React namespace PARA Dispatch/SetStateAction
###############################################################################

python3 <<'PY'
from pathlib import Path

p = Path("src/views/CalendarView.tsx")
s = p.read_text(encoding="utf-8")

# En vez de depender del namespace global React, importar los tipos.
s = s.replace(
    """import {
  useMemo,
  useState,
} from 'react'""",
    """import {
  useMemo,
  useState,
} from 'react'

import type {
  Dispatch,
  SetStateAction,
} from 'react'""",
)

s = s.replace(
    """setSelectedPlatforms: React.Dispatch<
    React.SetStateAction<string[]>
  >""",
    """setSelectedPlatforms: Dispatch<
    SetStateAction<string[]>
  >""",
)

p.write_text(s, encoding="utf-8")
PY

###############################################################################
# 5. PRIMER TYPECHECK
###############################################################################

echo
echo "=============================================================="
echo " TypeScript check"
echo "=============================================================="

set +e
npm run check 2>&1 | tee /tmp/abraxas_v12_tsc.log
TSC="${PIPESTATUS[0]}"
set -e

if [ "$TSC" -ne 0 ]; then
  echo
  echo "=============================================================="
  echo " QUEDAN ERRORES · CONTEXTO"
  echo "=============================================================="

  python3 <<'PY'
from pathlib import Path
import re

log = Path("/tmp/abraxas_v12_tsc.log").read_text(
    encoding="utf-8",
    errors="replace",
)

matches = re.findall(
    r"((?:src/[^(:]+\.tsx?))\((\d+),(\d+)\)",
    log,
)

seen = set()

for filename, line, col in matches:
    key = (filename, int(line))

    if key in seen:
        continue

    seen.add(key)

    path = Path(filename)

    if not path.exists():
        continue

    lines = path.read_text(
        encoding="utf-8",
        errors="replace",
    ).splitlines()

    n = int(line)

    print()
    print("=" * 72)
    print(f"{filename}:{line}:{col}")
    print("=" * 72)

    lo = max(1, n - 6)
    hi = min(len(lines), n + 6)

    for i in range(lo, hi + 1):
        marker = ">>" if i == n else "  "
        print(f"{marker} {i:4}: {lines[i-1]}")
PY

  echo
  echo "El TypeScript todavía tiene errores."
  echo "Pégame desde 'QUEDAN ERRORES · CONTEXTO' hasta el final."
  exit 2
fi

echo
echo "✓ TypeScript"

###############################################################################
# 6. FRONTEND BUILD
###############################################################################

npm run build

echo
echo "✓ Vite build"

###############################################################################
# 7. RUST
###############################################################################

cargo fmt \
  --manifest-path src-tauri/Cargo.toml \
  --all || true

cargo check \
  --manifest-path src-tauri/Cargo.toml

cargo test \
  --manifest-path src-tauri/Cargo.toml

echo
echo "✓ Rust"

###############################################################################
# 8. CLI / QA
###############################################################################

cargo build \
  --release \
  --manifest-path src-tauri/Cargo.toml \
  --bin publisherctl

./publisherctl qa
./publisher-mcp --self-test

echo
echo "✓ publisherctl"
echo "✓ publisher-mcp"

###############################################################################
# 9. TAURI
###############################################################################

npm run tauri:build

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

[ -d "$NEW_APP" ] || {
  echo "ERROR: no apareció ABRAXAS Publisher.app"
  exit 3
}

###############################################################################
# 10. INSTALACIÓN SEGURA
###############################################################################

APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP="$HOME/Applications/ABRAXAS Publisher.before-v12-$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.v12-$STAMP.app"

mkdir -p "$HOME/Applications"
rm -rf "$STAGE"

ditto "$NEW_APP" "$STAGE"

xattr -dr com.apple.quarantine "$STAGE" \
  >/dev/null 2>&1 || true

if [ -d "$APP" ]; then
  mv "$APP" "$BACKUP"
fi

if ! mv "$STAGE" "$APP"; then
  echo "ERROR instalando nueva app."

  if [ -d "$BACKUP" ]; then
    mv "$BACKUP" "$APP" || true
  fi

  exit 4
fi

###############################################################################
# 11. INSTALAR CLI/MCP
###############################################################################

mkdir -p "$HOME/.local/bin"

cp \
  "$ROOT/src-tauri/target/release/publisherctl" \
  "$HOME/.local/bin/publisherctl"

chmod +x \
  "$HOME/.local/bin/publisherctl"

MCP_DIR="$HOME/Library/Application Support/com.abraxas.publisher/tools"

mkdir -p "$MCP_DIR"

cp \
  "$ROOT/tools/publisher_mcp.py" \
  "$MCP_DIR/publisher_mcp.py"

chmod +x \
  "$MCP_DIR/publisher_mcp.py"

cat > "$HOME/.local/bin/publisher-mcp" <<EOF
#!/bin/bash
set -Eeuo pipefail
export PATH="\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec python3 "$MCP_DIR/publisher_mcp.py" "\$@"
EOF

chmod +x \
  "$HOME/.local/bin/publisher-mcp"

###############################################################################
# 12. POST QA
###############################################################################

export PATH="$HOME/.local/bin:$PATH"

publisherctl doctor
publisherctl qa
publisher-mcp --self-test

###############################################################################
# 13. COMMIT + PUSH
###############################################################################

git add -A

if ! git diff --cached --quiet; then
  git commit \
    -m "Fix and complete ABRAXAS Publisher V1.2"
fi

git push \
  -u origin \
  v1.2-workspace

###############################################################################
# FINAL
###############################################################################

echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.2 · REPARADA E INSTALADA"
echo "=============================================================="
echo
echo "App:"
echo "  $APP"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "CLI:"
echo "  $(command -v publisherctl)"
echo
echo "MCP:"
echo "  $(command -v publisher-mcp)"
echo
echo "Pruebas:"
echo "  publisherctl doctor"
echo "  publisherctl qa"
echo "  publisher-mcp --self-test"
echo
echo "Publicación social real:"
echo "  DESACTIVADA"
echo

open "$APP" || true
