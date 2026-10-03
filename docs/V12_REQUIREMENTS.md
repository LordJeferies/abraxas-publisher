# ABRAXAS Publisher V1.2 · Workspace

Esta versión termina el Paso 1 antes de conectar las APIs sociales.

## 1. Welcome / marcas

La pantalla de bienvenida debe permitir:

- seleccionar una marca;
- ver Todas las marcas;
- crear nueva marca;
- continuar workspace;
- importar desde Este Mac;
- importar desde Google Drive;
- abrir Cómo usar Publisher.

Brand debe ser entidad persistente en SQLite.

Debe funcionar con ejemplos como:

- JOC
- MOKA
- ABRAXAS

El selector de marca debe filtrar:

- Contenido
- Calendario
- Sin calendarizar
- Kanban
- Actividad cuando corresponda.

## 2. Google Drive directo

Debe existir un botón real:

Google Drive

No depender de Google Drive Desktop ni de Finder.

Inspiración/reutilización:

.references/Abrxs-Review/drive.js

pero adaptar correctamente a aplicación Desktop.

### Desktop OAuth

Usar:

- Google OAuth Client tipo Desktop;
- navegador del sistema;
- redirect loopback 127.0.0.1;
- Drive API;
- scope mínimo necesario para lectura.

No incrustar login de Google en WebView.

En Ajustes debe existir configuración del OAuth Client ID.

No incluir credenciales reales en el repo.

Si no está configurado:

Google Drive
→ explica configuración
→ permite guardar Client ID
→ botón Conectar.

### Drive Browser

Después de conectar:

- Mi Drive;
- carpetas;
- Atrás;
- Actualizar;
- Buscar;
- seleccionar carpeta;
- navegar subcarpetas;
- soportar Shared Drives donde sea razonable;
- importar carpeta seleccionada.

La metadata puede cargarse sin descargar todos los videos.

Para importar/preview cuando sea necesario:
Drive file ID
→ descarga/stream autenticado
→ caché local administrada por Publisher.

Conservar IDs de Drive/source metadata.

## 3. Importación local

Debe detectar recursivamente paquetes como:

SEMANA/
  CONTENIDO_01/
  CONTENIDO_02/
  CONTENIDO_03/

Cada subcarpeta de contenido puede tener:

- video;
- una imagen;
- varias imágenes;
- instagram.txt;
- facebook.txt;
- linkedin.txt;
- youtube.txt.

CORRECCION.txt no es un target social.

Antes de escribir a DB debe existir preview/resumen de importación.

## 4. Duplicados

No volver a importar silenciosamente algo existente.

Detectar identidad mediante:

- CONTENT_ID si existe;
- source identity;
- brand;
- fingerprint;
- relación con carpeta/origen.

Cuando existe conflicto:

Contenido existente encontrado.

Opciones:

- Reemplazar;
- Mantener ambos;
- Omitir.

Para lotes:

- aplicar sólo a éste;
- reemplazar todos;
- mantener todos;
- omitir todos;
- sí a todo/no a todo;
- resolver individualmente.

### Reemplazar

Debe conservar:

- identidad editorial;
- notas;
- historial;
- status;
- programación manual;
- receipts futuros.

Debe actualizar:

- assets;
- TXT;
- metadata;
- hashes;
- preview.

Debe incrementar versión.

### Mantener ambos

Crear identidad nueva explícita y conservar relationship al original.

## 5. Inspector

Actualmente no debe estar permanentemente ocupando ancho.

Reglas:

ninguna selección
→ inspector oculto.

una selección
→ inspector visible.

varias selecciones
→ resumen/bulk inspector.

Modos:

- Docked;
- Floating;
- Hidden.

Si es razonable con Tauri añadir Pop Out/WebviewWindow real, hacerlo sin romper
la app. Si no, Floating debe ser un panel libre correctamente funcional.

Debe recordar preferencia.

## 6. Ficha de contenido

Centro de control del contenido:

- preview;
- tipo;
- brand;
- source;
- assets;
- validation;
- workflow status;
- destinations;
- copy;
- schedule;
- notas;
- versión;
- Actualizar contenido.

Estados editoriales:

EN_CONFIRMACION
CON_CORRECCION
LISTO_POR_PROGRAMAR
PROGRAMADO

Cambiar estado desde ficha.

## 7. Correcciones

Guardar nota debe crear/actualizar atómicamente:

CORRECCION.txt

en la carpeta local del contenido.

Debe contener historial de notas.

Si source=Drive, diseñar/implementar el mecanismo para subir/crear
CORRECCION.txt en la carpeta Drive cuando haya autorización de escritura;
lectura normal no debe requerir escritura.

## 8. Refresh / versión

Actualizar contenido debe detectar reemplazo incluso si mantiene nombre mediante:

- SHA-256;
- size;
- mtime.

Actualizar:

- preview;
- metadata;
- ffprobe;
- assets;
- TXT.

Incrementar:

v1 → v2 → v3.

Conservar:

- notas;
- status;
- manual schedule.

Una decisión MANUAL de horario no debe ser pisada por el TXT al refrescar.

## 9. Schedule por PublicationTarget

No guardar una fecha única por Content.

Cada red tiene su PublicationTarget.

Ejemplo:

Instagram:
8 oct 17:00

LinkedIn:
8 oct 09:00

YouTube:
9 oct 12:00

UI debe permitir:

- todas las redes;
- sólo esta;
- redes seleccionadas;
- todas excepto una.

## 10. Calendario

Vistas obligatorias:

- Día;
- Semana;
- Mes.

Drag & drop obligatorio en Semana y Mes.

Al cambiar de día, actualizar realmente scheduledAt.

Al mover contenido con múltiples redes:

Mover:

- todas las publicaciones;
- sólo una red;
- seleccionar redes.

La mayoría de las veces todas se mueven juntas, así que Todas debe ser cómodo.

## 11. Remote lock

Estados preparados:

READY
PRECALENDARIZED
SCHEDULED_REMOTE
PUBLISHED

PRECALENDARIZED:
se puede mover.

SCHEDULED_REMOTE:
no se arrastra.

Al intentar:

"Esta publicación ya está programada externamente."

En V1.2 no hay API social real.

Crear contrato para futura cancelación:

cancel remote
→ confirmation
→ provider
→ verify
→ unlock.

Nunca simular que se canceló una API si no existe.

## 12. Sin calendarizar

Content rail/bandeja fija y funcional.

Debe tener:

- buscador;
- brand filter;
- platform filter;
- type filter;
- workflow filter;
- contador;
- thumbnails lazy;
- buen rendimiento.

Debe poder arrastrarse de:

Sin calendarizar → calendario.

Y:

calendario → Sin calendarizar.

## 13. Kanban

Columnas:

- En confirmación;
- Con corrección;
- Listo / por programar;
- Programado.

No drag entre estados.

Click tarjeta:
→ abre ficha.

## 14. Actividad

Persistir audit events:

- fecha;
- actor;
- acción;
- entidad;
- before;
- after;
- reversible;
- remote.

Registrar como mínimo:

- import;
- replace;
- keep both;
- status;
- note;
- refresh;
- version;
- schedule move;
- schedule clear;
- brand changes;
- undo;
- redo.

## 15. Undo / Redo

Atajos:

Cmd+Z
Shift+Cmd+Z

Acciones locales reversibles.

Nunca usar Undo para revertir una acción remota confirmada.

Debe existir historial de undo/redo persistente o suficientemente robusto.

## 16. publisherctl

Crear CLI real que use el mismo Core/SQLite:

publisherctl doctor

publisherctl brands list
publisherctl brands add MOKA

publisherctl content list
publisherctl content show ID
publisherctl content refresh ID

publisherctl import local PATH
publisherctl import local PATH --brand JOC

publisherctl note add ID "texto"

publisherctl status set ID CON_CORRECCION

publisherctl schedule show ID

publisherctl schedule set ID \
  --platform instagram \
  --at 2026-10-08T17:00:00

publisherctl schedule clear ID --platform linkedin

publisherctl activity

publisherctl undo
publisherctl redo

publisherctl dry-run

publisherctl qa

No duplicar reglas de negocio innecesariamente entre UI y CLI.

## 17. MCP

Crear MCP stdio local:

publisher-mcp

Debe exponer, como mínimo:

- publisher_list_brands
- publisher_create_brand
- publisher_list_content
- publisher_get_content
- publisher_import_local_folder
- publisher_refresh_content
- publisher_add_note
- publisher_set_editorial_status
- publisher_get_calendar
- publisher_move_schedule
- publisher_get_activity
- publisher_undo
- publisher_redo
- publisher_dry_run
- publisher_doctor

Debe llamar al mismo Core que usa Publisher.

No inventar una segunda base de datos.

Añadir self-test que no modifica datos reales de usuario.

## 18. QA

Automatizar todo lo razonable.

Crear fixtures temporales para probar:

- brand CRUD;
- import;
- duplicate detection;
- replace;
- keep both;
- status;
- note;
- CORRECCION.txt;
- refresh;
- version;
- schedules;
- per-platform schedules;
- month calculations;
- activity;
- undo;
- redo;
- dry run;
- CLI;
- MCP self test.

Las pruebas no deben usar la SQLite real del usuario.

## 19. Diseño

Mantener el diseño actual que ya está aprobado.

Seguir macOS:

- sidebar;
- toolbar contextual;
- inspector;
- sheets;
- floating panels;
- light/dark;
- responsive.

LiquidGlass sólo donde corresponda.

No convertirlo en dashboard SaaS genérico.

## 20. Performance

- no ffprobe en UI thread;
- listas grandes virtualizadas si hace falta;
- debounce;
- lazy thumbnails;
- incremental scan;
- caché;
- no reescanear todo si cambia un solo asset.

## 21. PWA

Mantener frontend responsive y preparado para PWA.

Si se añade manifest/service worker no debe interferir con Tauri.

No afirmar que existe cloud sync hasta que realmente exista.

## 22. Publicación social

PROHIBIDO en V1.2:

- publicar en Instagram;
- publicar en Facebook;
- publicar en LinkedIn;
- publicar en YouTube;
- pedir tokens sociales reales.

Sólo Dry Run.

## Acceptance gate

Antes de declarar V1.2 terminada:

npm / TS
PASS

Vite
PASS

cargo check
PASS

cargo test
PASS

publisherctl qa
PASS

publisher-mcp self-test
PASS

Doctor
PASS

Tauri build
PASS

App instalada sin destruir versión anterior
PASS

Ninguna API social llamada
PASS
