# ABRAXAS Publisher · Agent rules

Trabaja sobre la aplicación existente. No la sustituyas por un mockup.

Stack existente que debe conservarse salvo razón técnica demostrable:

- Tauri 2
- React
- TypeScript
- Vite
- Rust
- SQLite/rusqlite
- FFmpeg/FFprobe
- Zustand
- diseño macOS / Liquid Glass existente

## Reglas críticas

1. Mantener identifier:

   com.abraxas.publisher

2. Mantener compatibilidad/migración de la SQLite existente.

3. Nunca borrar datos de usuario para solucionar una migración.

4. Ninguna API social real se ejecuta en V1.2.

5. No renombrar un TXT a PROGRAMADO_ salvo confirmación futura de una API real.

6. No fingir funcionalidades. Si un botón existe, debe ejecutar la función.

7. No almacenar OAuth tokens, passwords o secretos en Git.

8. Google Drive debe usar OAuth de aplicación Desktop y navegador del sistema.
   No incrustar el login de Google dentro del WebView.

9. La app debe seguir funcionando aunque Google Drive no esté configurado.

10. La programación local es reversible.
    Una programación remota futura será irreversible mediante Undo y requerirá
    cancelación explícita mediante el adapter correspondiente.

11. CORRECCION.txt no se interpreta como TXT de red social.

12. El Kanban es visual. El estado cambia desde la ficha del contenido.

13. No romper el instalador que ya funciona en este Mac.

14. Antes de terminar:
    - npm check
    - frontend build
    - cargo check
    - cargo test
    - tests propios
    - doctor
    - build Tauri

15. Actualizar:
    README.md
    START_HERE.md
    HANDOFF_AI.md
    CHANGELOG.md
    documentación afectada.

16. No hagas git push ni merge.
    El script exterior se encarga de Git después de pasar QA.
