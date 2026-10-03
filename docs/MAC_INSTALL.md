# Instalación macOS

Destino: `~/Applications/ABRAXAS Publisher.app`.

```bash
chmod +x *.command scripts/*.sh
./ACTUALIZAR_ABRAXAS_PUBLISHER.command
```

El instalador:
1. valida macOS/Xcode CLT;
2. prepara Homebrew PATH;
3. comprueba Node >=20;
4. comprueba Rust/cargo;
5. comprueba FFmpeg/ffprobe;
6. instala dependencias npm;
7. ejecuta TypeScript/Vite/Cargo checks;
8. genera Tauri `.app`;
9. stagea, hace backup, reemplaza, limpia quarantine, doctor y abre.

El data store no se elimina durante una actualización.
