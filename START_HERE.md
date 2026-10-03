# START HERE — ABRAXAS Publisher

## Objetivo actual

v1.1 es la última versión local/editorial antes del Paso 2 de integraciones sociales.

## Instalar / actualizar

```bash
chmod +x *.command scripts/*.sh
./ACTUALIZAR_ABRAXAS_PUBLISHER.command
```

## Probar

1. Abre `ABRAXAS Publisher.app`.
2. Importa `examples/JOC_SEMANA_DEMO`.
3. Abre una ficha.
4. Deja una nota; comprueba `CORRECCION.txt` en esa carpeta.
5. Reemplaza un archivo o modifica un TXT y pulsa **Actualizar contenido**.
6. Comprueba que la versión cambia si la huella cambia.
7. Revisa `Estados` (Kanban no arrastrable).
8. Revisa `Calendario`; mueve un destino entre días y a `Sin calendarizar`.
9. En `Cola`, ejecuta **Simular lote**.
10. Confirma que ninguna API social ha sido llamada.

## No hacer todavía

- No añadir tokens sociales a TXT.
- No automatizar navegadores para publicar.
- No tratar `PRECALENDARIZED` como publicación remota.
- No renombrar `instagram.txt` a `PROGRAMADO_instagram.txt` hasta recibir confirmación real de la plataforma en Paso 2.
