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
