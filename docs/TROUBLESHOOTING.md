# Troubleshooting

## `patch-package: command not found`
LiquidGlass 1.0.3 llama `patch-package` en postinstall. Root debe mantener `patch-package` en `devDependencies`.

## npm quedó a medias
```bash
./REPARAR_INSTALACION.command
```

## Doctor
```bash
./scripts/doctor.sh
echo $?
```
0 OK, 1 warnings, 2 errors.

## El preview no cambia tras reemplazar un archivo
Abre la ficha y pulsa `Actualizar contenido`. Si SHA-256/mtime cambian, la versión debe subir.

## La nota no aparece en carpeta
Comprueba que la carpeta fuente siga siendo escribible y que no se haya movido. La app escribe `CORRECCION.txt` atómicamente.
