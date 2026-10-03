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
