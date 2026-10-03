# Google Drive

## v1.1 Desktop

Funciona con carpetas de Google Drive sincronizadas y visibles en Finder: se seleccionan desde el mismo importador local.

## Drive API directo / PWA

La referencia existente es `LordJeferies/Abrxs-Review`, especialmente `drive.js`:
- Google Identity Services;
- scope `drive.readonly`;
- `drive.file` adicional sólo para escritura explícita;
- navegación de carpetas;
- Shared Drives;
- lectura TXT/JSON;
- streaming privado y descarga opcional;
- token sólo en memoria.

Publisher debe reutilizar el contrato/patrones, no compartir un access token entre aplicaciones.

Arquitectura objetivo:

```text
LocalFolderSource | DriveFolderSource
             -> Content normalized model
             -> Review / Calendar
             -> MediaResolver
             -> PublisherAdapter (Paso 2)
```

La nota `CORRECCION.txt` en Drive deberá crearse en la misma carpeta mediante una acción explícita y confirmada, equivalente al `uploadText` de Abrxs Review.
