# ABRAXAS Publisher v1.1 — Planning & Review

Aplicación de macOS para importar contenido en lote, revisarlo editorialmente, registrar correcciones, precalendarizarlo y simular la cola antes de conectar redes sociales.

## Qué está funcionando en v1.1

- Tauri 2 + React + TypeScript + Vite.
- Rust/Tauri + SQLite WAL.
- Importación de carpetas locales y carpetas de Google Drive sincronizadas en Finder.
- Parser de TXT por plataforma.
- Detección de Reel/video, imagen y carrusel.
- Fechas `DATE` + `TIME` del TXT entran como **PRECALENDARIZED**.
- Calendario semanal con drag & drop entre días.
- Bandeja **Sin calendarizar**; se puede arrastrar hacia/desde el calendario.
- Preview local de video/imágenes dentro de la ficha.
- Estados editoriales:
  - `EN_CONFIRMACION`
  - `CON_CORRECCION`
  - `LISTO_POR_PROGRAMAR`
  - `PROGRAMADO`
- Kanban informativo por estados; no permite cambiar estado arrastrando.
- Las fichas son el único lugar para cambiar estado/programación.
- Notas de corrección persistentes.
- `CORRECCION.txt` se crea/actualiza en la carpeta del contenido con escritura atómica.
- `Actualizar contenido` compara SHA-256 + mtime, relee assets/TXT/ffprobe y aumenta la versión si cambió la fuente.
- Conserva notas, estado editorial y programación al refrescar.
- Home/Welcome funcional.
- Help Center incorporado por escenarios.
- Cola + Dry Run / simulación de lote.
- Doctor + instalador/actualizador + reparación con logs.
- Publicación social real DESACTIVADA.

## Instalar o actualizar en el Mac

Descomprime el ZIP y ejecuta:

```bash
cd "$HOME/Downloads/abraxas-publisher-v1.1"
chmod +x *.command scripts/*.sh
./ACTUALIZAR_ABRAXAS_PUBLISHER.command
```

El bundle final queda en:

```text
~/Applications/ABRAXAS Publisher.app
```

El identifier continúa siendo `com.abraxas.publisher`, por lo que la actualización utiliza la misma base local de la versión anterior.

## Flujo recomendado

```text
Importar
→ revisar preview
→ En confirmación
→ (si hace falta) Con corrección + CORRECCION.txt
→ reemplazar archivo
→ Actualizar contenido
→ Listo / por programar
→ calendario / Sin calendarizar
→ Simular lote
→ Paso 2: conectar redes
```

## Nota importante sobre PROGRAMADO

En v1.1 `PROGRAMADO` es un **estado editorial del workflow**, no una confirmación remota de Instagram/LinkedIn/etc. Los `PublicationTarget` continúan marcados como locales/precalendarizados. Cuando el Paso 2 conecte APIs reales se añadirá la confirmación remota y sólo entonces se renombrarán TXT de plataforma como `PROGRAMADO_...`/`PUBLICADO_...` según el contrato final.

## Google Drive

En esta versión de desktop puedes seleccionar cualquier carpeta de Google Drive que esté sincronizada y visible en Finder. El contrato para Drive API directo/PWA se documenta en `docs/GOOGLE_DRIVE.md`, basado en el patrón ya usado por `LordJeferies/Abrxs-Review`. La conexión OAuth directa no se duplica prematuramente dentro de Tauri: se integrará en la capa cloud/web antes de activar publicación remota.

## Repo como handoff

Lee primero:

- `START_HERE.md`
- `HANDOFF_AI.md`
- `docs/ARCHITECTURE.md`
- `docs/STATE_MACHINE.md`
- `docs/TXT_PROTOCOL.md`
- `docs/GOOGLE_DRIVE.md`
- `docs/MAC_INSTALL.md`
- `docs/TROUBLESHOOTING.md`

## Paso 2

La base ya está lista para introducir `PublisherAdapter` reales y OAuth de Instagram/Facebook/LinkedIn/YouTube. La prueba de publicación masiva debe seguir siendo la última prueba, después de validar conexiones individuales y Dry Run.

---

# Desktop + Web/PWA

ABRAXAS Publisher dispone de dos superficies:

- **Desktop/Tauri**: ejecución nativa, filesystem, ffmpeg, SQLite y workers.
- **Web/PWA**: revisión, planificación, aprobación, previews y coordinación remota.

Ambas comparten el mismo modelo de producto y repositorio.

La PWA se despliega mediante GitHub Pages.

## Execution hosts

- `CLOUD`
- `DESKTOP`
- `MANUAL`

La ausencia de una API nunca invalida el workspace.

## Sync

GitHub Pages sirve la aplicación, pero no es la base de datos.

Para sincronización cross-device se configura:

```bash
VITE_ABRAXAS_SYNC_API=https://...Más información:
- docs/DESKTOP_WEB_PWA_SYNC.md
- docs/MOBILE_PUBLISHING.md
- docs/V13_1_HYBRID_PUBLISHING.md
  MD
###############################################################################
12. CSS
###############################################################################
cat >> src/styles.css <<'CSS'
/* ==========================================================
   V1.3.2 · Desktop / Web / PWA / Sync
   ========================================================== */
.sync-grid{
  display:grid;
  grid-template-columns:repeat(2,minmax(0,1fr));
  gap:10px;
  margin-bottom:10px;
}
.sync-card{
  position:relative;
}
.sync-card-icon{
  width:38px;
  height:38px;
  border-radius:11px;
  display:grid;
  place-items:center;
  margin-bottom:10px;
  background:rgba(60,90,150,.09);
}
.sync-card h2{
  margin:4px 0;
}
.sync-card p,
.sync-card small{
  color:var(--muted);
}
.sync-explainer{
  margin-bottom:10px;
}
.sync-flow-row{
  display:grid;
  grid-template-columns:100px 1fr auto 1fr auto 1fr;
  gap:8px;
  align-items:center;
  border-top:1px solid var(--line);
  padding:10px 0;
  font-size:9px;
}
.cloud-foundation-warning{
  display:grid;
  grid-template-columns:auto 1fr;
  gap:10px;
  align-items:flex-start;
  margin-bottom:10px;
  background:rgba(220,145,20,.07);
  border-color:rgba(220,145,20,.3);
}
.cloud-foundation-warning p{
  color:var(--muted);
  margin-bottom:0;
}
.capability-table{
  display:grid;
}
.capability-table>div{
  display:flex;
  justify-content:space-between;
  gap:15px;
  padding:8px 0;
  border-top:1px solid var(--line);
}
.capability-table b{
  display:flex;
  gap:5px;
  align-items:center;
  text-align:right;
}
.help-architecture{
  margin-bottom:10px;
}
.architecture-diagram{
  display:grid;
  grid-template-columns:1fr auto 1fr auto 1fr;
  gap:10px;
  align-items:center;
  margin-top:14px;
}
.architecture-diagram>div{
  border:1px solid var(--line);
  border-radius:12px;
  padding:12px;
}
.architecture-diagram strong,
.architecture-diagram span{
  display:block;
}
.architecture-diagram span{
  color:var(--muted);
  margin-top:4px;
  font-size:9px;
}
.help-comparison{
  display:grid;
}
.help-comparison>div{
  display:grid;
  grid-template-columns:minmax(180px,1fr) 120px 120px;
  gap:10px;
  padding:7px 0;
  border-top:1px solid var(--line);
}
.help-comparison-head{
  border-top:0 !important;
}
.execution-doc-grid{
  display:grid;
  grid-template-columns:repeat(3,1fr);
  gap:8px;
  margin-top:10px;
}
.execution-doc-grid article{
  border:1px solid var(--line);
  border-radius:11px;
  padding:11px;
}
.execution-doc-grid p{
  color:var(--muted);
  font-size:9px;
  line-height:1.5;
}
.help-steps{
  color:var(--muted);
  line-height:1.7;
}
@media(max-width:800px){
  .sync-grid{
    grid-template-columns:1fr;
  }
  .sync-flow-row{
    grid-template-columns:1fr;
  }
  .architecture-diagram{
    grid-template-columns:1fr;
  }
  .architecture-diagram>b{
    transform:rotate(90deg);
    justify-self:center;
  }
  .help-comparison{
    overflow-x:auto;
  }
  .help-comparison>div{
    min-width:520px;
  }
  .execution-doc-grid{
    grid-template-columns:1fr;
  }
}
CSS
###############################################################################
13. QA
###############################################################################
section "12/13 · QA"
npm install
npm run check 
  || fail "TypeScript falló."
npm run build 
  || fail "Desktop frontend build falló."
cargo fmt 
  --manifest-path src-tauri/Cargo.toml 
  --all
cargo check 
  --manifest-path src-tauri/Cargo.toml 
  || fail "cargo check falló."
cargo test 
  --manifest-path src-tauri/Cargo.toml 
  || fail "cargo test falló."
###############################################################################
WEB BUILD TEST
###############################################################################
echo
echo "Probando Web/PWA..."
GITHUB_ACTIONS=true 
npm run build:web 
  || fail "PWA build falló."
[ -f dist/manifest.webmanifest ] 
  || fail "manifest.webmanifest no llegó al build."
[ -f dist/sw.js ] 
  || fail "service worker no llegó al build."
echo "✓ Web/PWA"
###############################################################################
DESKTOP BUILD
###############################################################################
echo
echo "Construyendo Desktop..."
unset GITHUB_ACTIONS
npm run tauri:build 
  || fail "Tauri build falló."
NEW_APP="$ROOT/src-tauri/target/release/bundle/macos/ABRAXAS Publisher.app"
if [ ! -d "$NEW_APP" ]; then
  NEW_APP="$(
    find 
      "$ROOT/src-tauri/target/release/bundle" 
      -type d 
      -name "*.app" 
      -print 
      -quit
  )"
fi
[ -d "$NEW_APP" ] 
  || fail "No se encontró .app."
###############################################################################
INSTALL DESKTOP
###############################################################################
APP="$HOME/Applications/ABRAXAS Publisher.app"
BACKUP_APP="$HOME/Applications/ABRAXAS Publisher.V131.backup.$STAMP.app"
STAGE="$HOME/Applications/.ABRAXAS Publisher.V132.$STAMP.app"
mkdir -p 
  "$HOME/Applications"
rm -rf 
  "$STAGE"
ditto 
  "$NEW_APP" 
  "$STAGE"
xattr -dr 
  com.apple.quarantine 
  "$STAGE" \
/dev/null 2>&1 
  || true

if [ -d "$APP" ]; then
  mv 
    "$APP" 
    "$BACKUP_APP"
fi
if ! mv 
  "$STAGE" 
  "$APP"
then
  if [ -d "$BACKUP_APP" ]; then
    mv 
      "$BACKUP_APP" 
      "$APP" 
      || true
  fi
  fail "Instalación Desktop falló."
fi
###############################################################################
DESKTOP SHORTCUT
###############################################################################
rm -f 
  "$HOME/Desktop/ABRAXAS Publisher.app"
ln -s 
  "$APP" 
  "$HOME/Desktop/ABRAXAS Publisher.app"
echo "✓ Acceso de Escritorio"
###############################################################################
COMMIT / PUSH
###############################################################################
section "13/13 · RELEASE / GITHUB"
git add -A
git commit 
  -m "ABRAXAS Publisher V1.3.2 Desktop Web PWA Sync Foundation"
RELEASE_SHA="$(
  git rev-parse HEAD
)"
git tag 
  -f 
  publisher-v1.3.2
git push 
  -u origin 
  "$BRANCH"
git push 
  origin 
  publisher-v1.3.2 
  --force
###############################################################################
Intentar actualizar main de forma segura.
NO force.
###############################################################################
if git push 
  origin 
  "Branch: Main"
then
  echo "✓ main actualizado"
else
  echo
  echo "AVISO:"
  echo "main no pudo actualizarse por fast-forward."
  echo "La rama v1.3-publishing-center sí quedó actualizada."
fi
###############################################################################
Intentar activar GitHub Pages Actions
###############################################################################
echo
echo "Configurando GitHub Pages..."
if gh api 
  repos/LordJeferies/abraxas-publisher/pages \
/dev/null 2>&1
then
  gh api 
    --method PUT 
    repos/LordJeferies/abraxas-publisher/pages 
    -f build_type=workflow 
    >/dev/null 2>&1 
    || true
else
  gh api 
    --method POST 
    repos/LordJeferies/abraxas-publisher/pages 
    -f build_type=workflow 
    >/dev/null 2>&1 
    || true
fi

###############################################################################
SNAPSHOTS
###############################################################################
RELEASE_DIR="$HOME/Developer/abraxas-publisher/releases/v1.3.2"
mkdir -p 
  "$RELEASE_DIR"
FULL_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.2_FULL.zip"
git archive 
  --format=zip 
  --output="$FULL_ZIP" 
  HEAD
PATCH_TMP="$(
  mktemp -d
)"
mkdir -p 
  "$PATCH_TMP/files"
git diff 
  --name-only 
  "$BASE_SHA" 
  "$RELEASE_SHA" \
"$PATCH_TMP/FILES.txt"

while IFS= read -r FILE
do
  [ -n "$FILE" ] || continue
  [ -e "$FILE" ] || continue
  mkdir -p 
    "$PATCH_TMP/files/$(dirname "$FILE")"
  cp -R 
    "$FILE" 
    "$PATCH_TMP/files/$FILE"
done < "$PATCH_TMP/FILES.txt"
cat > "$PATCH_TMP/PATCH_MANIFEST.json" <<EOF
{
  "app": "ABRAXAS Publisher",
  "version": "1.3.2",
  "packageVersion": "0.4.2",
  "baseCommit": "$BASE_SHA",
  "releaseCommit": "$RELEASE_SHA",
  "surfaces": [
    "desktop",
    "web",
    "pwa"
  ],
  "executionHosts": [
    "CLOUD",
    "DESKTOP",
    "MANUAL"
  ],
  "sync": {
    "foundation": true,
    "cloudBackendRequiredForCrossDeviceSync": true
  }
}
EOF
PATCH_ZIP="$RELEASE_DIR/ABRAXAS_PUBLISHER_V1.3.2_PATCH.zip"
ditto 
  -c 
  -k 
  --sequesterRsrc 
  "$PATCH_TMP" 
  "$PATCH_ZIP"
rm -rf 
  "$PATCH_TMP"
###############################################################################
FINAL
###############################################################################
echo
echo "=============================================================="
echo " ABRAXAS PUBLISHER V1.3.2 · COMPLETADA"
echo "=============================================================="
echo
echo "Desktop:"
echo "  $APP"
echo
echo "Acceso Escritorio:"
echo "  $HOME/Desktop/ABRAXAS Publisher.app"
echo
echo "Backup V1.3.1:"
echo "  $BACKUP_APP"
echo
echo "Branch:"
echo "  $BRANCH"
echo
echo "Commit:"
echo "  $RELEASE_SHA"
echo
echo "PWA esperada:"
echo "  https://lordjeferies.github.io/abraxas-publisher/"
echo
echo "FULL:"
echo "  $FULL_ZIP"
echo
echo "PATCH:"
echo "  $PATCH_ZIP"
echo
echo "Log:"
echo "  $LOG"
echo
echo "Capacidades:"
echo "  ✓ Desktop/Tauri"
echo "  ✓ Web build"
echo "  ✓ PWA manifest"
echo "  ✓ Service Worker"
echo "  ✓ GitHub Pages workflow"
echo "  ✓ NativeBackend"
echo "  ✓ WebBackend"
echo "  ✓ Sync Center"
echo "  ✓ documentación Desktop/Web/PWA"
echo "  ✓ execution host CLOUD/DESKTOP/MANUAL"
echo "  ✓ acceso en Escritorio"
echo
echo "Sync real entre dispositivos:"
echo "  requiere VITE_ABRAXAS_SYNC_API"
echo
echo "No se finge una sincronización inexistente."
echo
open "$APP" || true
