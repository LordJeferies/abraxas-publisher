# Mobile Publishing

## Regla

ABRAXAS puede publicar desde móvil cuando:

- el provider admite el flujo;
- OAuth está autorizado;
- el asset es accesible;
- no existe una dependencia local.

## Ejecuciones

### MOBILE → CLOUD

La PWA aprueba y publica mediante backend cloud.

### MOBILE → DESKTOP

La PWA aprueba.

Job:
WAITING_FOR_DESKTOP

Desktop recibe el job y ejecuta.

### MOBILE → MANUAL

La PWA mantiene:

MANUAL_REQUIRED

y recuerda al usuario publicar.

## Drive

Un archivo visible en Drive puede revisarse desde móvil.

Para publicar directamente desde Web:

- ABRAXAS Cloud debe poder leer/transferir el asset; o
- el provider debe aceptar una fuente remota compatible.

Si esto no está disponible:

PWA aprueba
→ Desktop ejecuta.

## Principle

No duplicar el mismo archivo innecesariamente.

Usar:

CONTENT_ID
ASSET_ID
Drive reference
fingerprint

en lugar de depender de paths absolutos.
