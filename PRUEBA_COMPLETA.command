#!/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.cargo/bin:$PATH"

if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

mkdir -p "$ROOT/logs" "$ROOT/qa"

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$ROOT/logs/qa_$STAMP.log"
REPORT="$ROOT/qa/QA_$STAMP.md"

exec > >(tee -a "$LOG") 2>&1

PASS=0
FAIL=0
WARN=0

pass() {
  echo "PASS  $*"
  echo "- ✅ PASS — $*" >> "$REPORT"
  PASS=$((PASS+1))
}

fail() {
  echo "FAIL  $*"
  echo "- ❌ FAIL — $*" >> "$REPORT"
  FAIL=$((FAIL+1))
}

warn() {
  echo "WARN  $*"
  echo "- ⚠️ WARN — $*" >> "$REPORT"
  WARN=$((WARN+1))
}

section() {
  echo
  echo "=============================================================="
  echo "$*"
  echo "=============================================================="
  echo >> "$REPORT"
  echo "## $*" >> "$REPORT"
}

run_test() {
  local name="$1"
  shift

  echo
  echo "→ $name"

  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

cat > "$REPORT" <<EOF
# ABRAXAS Publisher · QA

Fecha:
$(date)

Proyecto:
$ROOT

EOF

###############################################################################
# 1. ENTORNO
###############################################################################

section "1. ENTORNO"

[ "$(uname -s)" = "Darwin" ] \
  && pass "macOS" \
  || fail "macOS"

ARCH="$(uname -m)"

[ "$ARCH" = "arm64" ] \
  && pass "Apple Silicon arm64" \
  || warn "Arquitectura $ARCH"

for cmd in node npm rustc cargo ffmpeg ffprobe; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd encontrado: $(command -v "$cmd")"
  else
    fail "$cmd no encontrado"
  fi
done

echo "Node    : $(node --version 2>/dev/null || true)"
echo "npm     : $(npm --version 2>/dev/null || true)"
echo "rustc   : $(rustc --version 2>/dev/null || true)"
echo "cargo   : $(cargo --version 2>/dev/null || true)"
echo "ffmpeg  : $(ffmpeg -hide_banner -version 2>/dev/null | head -n1 || true)"

###############################################################################
# 2. ESTRUCTURA
###############################################################################

section "2. ESTRUCTURA DEL PROYECTO"

for file in \
  package.json \
  src-tauri/Cargo.toml \
  src-tauri/tauri.conf.json
do
  [ -f "$file" ] \
    && pass "$file existe" \
    || fail "$file falta"
done

[ -f package-lock.json ] \
  && pass "package-lock.json existe" \
  || warn "package-lock.json no existe"

###############################################################################
# 3. FIX TAURI protocol-asset
###############################################################################

section "3. CONFIGURACIÓN TAURI"

python3 <<'PY'
from pathlib import Path
import json
import re
import sys

conf = Path("src-tauri/tauri.conf.json")
cargo = Path("src-tauri/Cargo.toml")

if not conf.exists() or not cargo.exists():
    sys.exit(1)

cfg = json.loads(conf.read_text(encoding="utf-8"))
text = cargo.read_text(encoding="utf-8")

conf_text = conf.read_text(encoding="utf-8")

uses_asset = (
    "assetProtocol" in conf_text
    or '"assetProtocol"' in conf_text
)

if not uses_asset:
    print("Tauri config no requiere protocol-asset.")
    sys.exit(0)

if '"protocol-asset"' in text:
    print("protocol-asset ya habilitado.")
    sys.exit(0)

lines = text.splitlines()
out = []
changed = False

for line in lines:
    if not changed and re.match(r'^\s*tauri\s*=', line):
        if "features" in line:
            line = re.sub(
                r'features\s*=\s*\[([^\]]*)\]',
                lambda m:
                    'features = [' +
                    (
                        m.group(1).strip() + ', '
                        if m.group(1).strip()
                        else ''
                    ) +
                    '"protocol-asset"]',
                line,
                count=1
            )
            changed = True

        elif "{" in line and "}" in line:
            p = line.rfind("}")
            before = line[:p].rstrip()

            if before.endswith(","):
                line = before + ' features = ["protocol-asset"] }'
            else:
                line = before + ', features = ["protocol-asset"] }'

            changed = True

        else:
            m = re.match(r'^(\s*tauri\s*=\s*)"([^"]+)"\s*$', line)

            if m:
                line = (
                    f'{m.group(1)}{{ version = "{m.group(2)}", '
                    f'features = ["protocol-asset"] }}'
                )
                changed = True

    out.append(line)

if not changed:
    print("No pude modificar automáticamente Cargo.toml.")
    sys.exit(2)

cargo.write_text("\n".join(out) + "\n", encoding="utf-8")
print("protocol-asset añadido correctamente.")
PY

if grep -q 'protocol-asset' src-tauri/Cargo.toml; then
  pass "Tauri protocol-asset"
else
  warn "protocol-asset no está configurado"
fi

###############################################################################
# 4. NPM
###############################################################################

section "4. DEPENDENCIAS JAVASCRIPT"

if [ ! -d node_modules ]; then

  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi

fi

[ -d node_modules ] \
  && pass "node_modules disponible" \
  || fail "node_modules"

###############################################################################
# 5. TYPESCRIPT
###############################################################################

section "5. TYPESCRIPT"

if npm run check; then
  pass "npm run check"
else
  fail "npm run check"
fi

###############################################################################
# 6. FRONTEND
###############################################################################

section "6. FRONTEND BUILD"

if npm run build; then
  pass "Vite production build"
else
  fail "Vite production build"
fi

[ -f dist/index.html ] \
  && pass "dist/index.html generado" \
  || fail "dist/index.html"

###############################################################################
# 7. RUST
###############################################################################

section "7. RUST"

if cargo check --manifest-path src-tauri/Cargo.toml; then
  pass "cargo check"
else
  fail "cargo check"
fi

if cargo test --manifest-path src-tauri/Cargo.toml; then
  pass "cargo test"
else
  fail "cargo test"
fi

###############################################################################
# 8. DOCTOR
###############################################################################

section "8. DOCTOR"

if [ -x scripts/doctor.sh ]; then

  set +e
  scripts/doctor.sh
  DOCTOR=$?
  set -e

  case "$DOCTOR" in
    0)
      pass "Doctor"
      ;;
    1)
      warn "Doctor terminó con warnings"
      ;;
    *)
      fail "Doctor encontró errores"
      ;;
  esac

else
  warn "scripts/doctor.sh no existe o no es ejecutable"
fi

###############################################################################
# 9. APP
###############################################################################

section "9. APP INSTALADA"

APP="$HOME/Applications/ABRAXAS Publisher.app"

if [ -d "$APP" ]; then
  pass "ABRAXAS Publisher.app existe"
else
  fail "ABRAXAS Publisher.app no está instalada"
fi

if [ -d "$APP" ]; then

  if xattr "$APP" 2>/dev/null | grep -q '^com.apple.quarantine$'; then
    warn "La app todavía tiene quarantine"
  else
    pass "App sin quarantine"
  fi

  if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    pass "codesign verify"
  else
    warn "codesign verify no pasa; puede ser normal en build local"
  fi

fi

###############################################################################
# 10. PRUEBAS MANUALES GUIADAS
###############################################################################

section "10. ACCEPTANCE TESTS"

if [ -d "$APP" ]; then
  open "$APP"
fi

echo
echo "La app se ha abierto."
echo
echo "Ahora el script te irá diciendo qué probar."
echo
echo "Responde:"
echo
echo "  y = funciona"
echo "  n = falla"
echo "  s = saltar"
echo

ask() {

  local id="$1"
  local title="$2"
  local instructions="$3"

  echo
  echo "--------------------------------------------------------------"
  echo "$id · $title"
  echo "--------------------------------------------------------------"
  echo "$instructions"
  echo

  while true; do

    read -r -p "Resultado [y/n/s]: " answer

    case "$answer" in

      y|Y)
        pass "$id · $title"
        break
        ;;

      n|N)
        fail "$id · $title"
        break
        ;;

      s|S)
        warn "$id · $title · SALTADO"
        break
        ;;

      *)
        echo "Usa y, n o s."
        ;;

    esac

  done
}

ask \
"A01" \
"Pantalla inicial" \
"Confirma que aparece Inicio/Welcome y que los botones principales responden."

ask \
"A02" \
"Selector de marca" \
"Comprueba que puedes elegir JOC/MOKA/u otra marca y que el contenido se filtra. Si esta función todavía no existe, marca n."

ask \
"A03" \
"Crear marca" \
"Crea una marca de prueba y confirma que queda disponible en el selector."

ask \
"A04" \
"Importar lote" \
"Importa una carpeta con Reel, imagen/carrusel y TXT. Confirma que detecta correctamente sus contenidos."

ask \
"A05" \
"Precalendarización" \
"Comprueba que un TXT con DATE/TIME coloca automáticamente su destino en el calendario."

ask \
"A06" \
"Sin calendarizar" \
"Comprueba que un contenido sin fecha aparece en la bandeja Sin calendarizar."

ask \
"A07" \
"Buscar Sin calendarizar" \
"Usa el buscador de la bandeja y confirma que filtra sin bloquear la interfaz."

ask \
"A08" \
"Filtro por marca" \
"Filtra la bandeja Sin calendarizar por marca."

ask \
"A09" \
"Drag Sin calendarizar → calendario" \
"Arrastra un contenido desde la bandeja hasta un día. Confirma que realmente se mueve."

ask \
"A10" \
"Drag entre días" \
"Mueve un contenido de un día a otro y confirma que cambia su fecha."

ask \
"A11" \
"Vista mes" \
"Cambia a Mes y confirma que puedes ver y seleccionar publicaciones."

ask \
"A12" \
"Drag en vista mes" \
"Mueve una publicación de un día a otro dentro de Mes."

ask \
"A13" \
"Selección por redes" \
"Mueve/cambia fecha de un contenido y confirma que puedes escoger Todas, una red o varias redes."

ask \
"A14" \
"Horarios distintos" \
"Pon Instagram y LinkedIn el mismo día pero con horas distintas."

ask \
"A15" \
"Fechas distintas" \
"Pon Instagram y YouTube del mismo contenido en días diferentes."

ask \
"A16" \
"Inspector condicionado" \
"Sin contenido seleccionado, el inspector derecho debe estar oculto."

ask \
"A17" \
"Inspector al seleccionar" \
"Selecciona un contenido y confirma que aparece su inspector."

ask \
"A18" \
"Inspector desacoplable" \
"Pon el inspector en modo flotante y luego vuelve a acoplarlo."

ask \
"A19" \
"Preview" \
"Comprueba preview de Reel, imagen y carrusel."

ask \
"A20" \
"Corrección" \
"Cambia un contenido a Con corrección, escribe una nota y guarda."

ask \
"A21" \
"CORRECCION.txt" \
"Abre la carpeta original y confirma que CORRECCION.txt contiene la nota."

ask \
"A22" \
"Historial de correcciones" \
"Agrega una segunda nota y confirma que la primera no desaparece."

ask \
"A23" \
"Kanban" \
"Comprueba En confirmación / Con corrección / Listo por programar / Programado."

ask \
"A24" \
"Kanban sólo lectura" \
"Intenta arrastrar una tarjeta entre estados. No debe poder hacerse."

ask \
"A25" \
"Cambio desde ficha" \
"Abre la ficha y cambia ahí el estado. Comprueba que Kanban se actualiza."

ask \
"A26" \
"Refresh de archivo" \
"Reemplaza un asset manteniendo el mismo nombre y pulsa Actualizar contenido."

ask \
"A27" \
"Versionado" \
"Confirma que el contenido pasó de v1 a v2 tras detectar el cambio."

ask \
"A28" \
"Persistencia después del refresh" \
"Confirma que nota, estado y programación manual sobrevivieron al refresh."

ask \
"A29" \
"Actividad" \
"Comprueba que mover, editar, corregir y actualizar generan entradas en Actividad."

ask \
"A30" \
"Undo local" \
"Mueve una precalendarización local y usa Undo. Debe volver a la fecha anterior."

ask \
"A31" \
"Redo local" \
"Ejecuta Redo y confirma que reaparece el cambio."

ask \
"A32" \
"Persistencia después de reiniciar" \
"Cierra completamente Publisher, vuelve a abrir y confirma que contenido, marcas, estados y calendario siguen iguales."

ask \
"A33" \
"Dry Run" \
"Ejecuta Simular lote y confirma que no realiza ninguna publicación real."

###############################################################################
# RESUMEN
###############################################################################

section "11. RESULTADO"

TOTAL=$((PASS+FAIL+WARN))

echo
echo "PASS : $PASS"
echo "FAIL : $FAIL"
echo "WARN : $WARN"
echo "TOTAL: $TOTAL"
echo

{
  echo
  echo "## RESULTADO"
  echo
  echo "- PASS: $PASS"
  echo "- FAIL: $FAIL"
  echo "- WARN: $WARN"
  echo "- TOTAL: $TOTAL"
  echo
  echo "Log:"
  echo "\`$LOG\`"
} >> "$REPORT"

if [ "$FAIL" -eq 0 ]; then

  echo "=============================================================="
  echo " QA APROBADO"
  echo "=============================================================="
  echo
  echo "La aplicación cumple este conjunto de pruebas."
  echo
  echo "Reporte:"
  echo "$REPORT"

  exit 0

else

  echo "=============================================================="
  echo " QA NO APROBADO"
  echo "=============================================================="
  echo
  echo "Todavía hay $FAIL fallo(s)."
  echo
  echo "Reporte:"
  echo "$REPORT"
  echo
  echo "No conviene empezar el Paso 2 todavía."

  exit 2

fi
