# Changelog

## 0.2.0 — Planning & Review

- Welcome/Home funcional.
- Help Center por escenarios.
- Ficha de contenido con preview real local.
- Workflow editorial separado de validación técnica.
- Estados: En confirmación / Con corrección / Listo por programar / Programado.
- Kanban informativo sin drag entre estados.
- Correcciones persistentes + `CORRECCION.txt` atómico.
- Refresh por SHA-256 + mtime y versionado de contenido.
- Calendar DnD con bandeja Sin calendarizar.
- Precalendarización desde DATE/TIME de TXT.
- Instalador de actualización con stage/backup/rollback.
- Doctor y handoff de repo.
- Publicación social sigue desactivada.

## 0.3.0 · V1.2 Workspace

- marcas;
- importación recursiva;
- duplicados;
- Drive OAuth directo;
- calendar Day/Week/Month;
- multi-network scheduling;
- inspector dock/float/hide;
- activity;
- undo/redo;
- publisherctl;
- publisher-mcp;
- QA automatizado;
- publicación social real sigue desactivada.

## 0.4.0 · Publisher V1.3

### Publishing Center

- Accounts Center.
- Provider capability registry.
- Publishing wizard.
- Selection basket.
- Destination/account selection.
- Preflight.
- Platform mockups.
- Persistent publication jobs.
- Idempotency keys.
- Queue V1.3.
- SCHEDULED_EXTERNAL.
- External scheduler provenance.
- Publishing-specific navigation.
- Contextual network themes.

### Preserved

- V1.2 SQLite data.
- brands.
- content.
- calendar.
- notes.
- Drive.
- activity.
- publisherctl.
- MCP.
- existing scheduling.

### Safety

No provider is considered connected without verified auth.
No remote publishing is claimed without remote verification.

## 0.4.1 · V1.3.1 Hybrid Publishing

- AUTO_API / MANUAL / EXTERNAL por PublicationTarget.
- Sin API ya no bloquea preflight.
- MANUAL_REQUIRED.
- MANUAL_DUE.
- MANUAL_OVERDUE.
- Mixed batch confirmation.
- Dashboard Hoy con manual attention.
- Queue separa automatic/manual/external.
- Connected accounts pueden coexistir con redes manuales.
