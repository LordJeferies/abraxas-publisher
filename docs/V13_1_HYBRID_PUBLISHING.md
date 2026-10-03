# ABRAXAS Publisher V1.3.1

## Hybrid Publishing

Publisher no requiere tener todas las APIs conectadas.

Cada PublicationTarget determina independientemente su modo:

AUTO_API
MANUAL
EXTERNAL

## AUTO_API

Condiciones:

- cuenta del provider correcta;
- connection_status = CONNECTED;
- auth_state = AUTHORIZED;
- contenido válido;
- fecha válida.

Estado inicial:

QUEUED

## MANUAL

Se utiliza cuando:

- no hay cuenta;
- OAuth no está terminado;
- provider no está integrado;
- usuario fuerza publicación manual.

La ausencia de API no es un error.

Estado inicial:

MANUAL_REQUIRED

En UI puede representarse dinámicamente como:

MANUAL_REQUIRED
MANUAL_DUE
MANUAL_OVERDUE

## EXTERNAL

Cuando el usuario ya programó el contenido en:

- Edits;
- Meta Business Suite;
- YouTube Studio;
- LinkedIn;
- TikTok;
- Buffer;
- Later;
- otra herramienta.

Estado:

SCHEDULED_EXTERNAL

## Regla de preflight

Bloquean:

- contenido no aprobado;
- medio ausente;
- validation error;
- fecha ausente;
- destino remotamente bloqueado.

NO bloquea:

- ausencia de OAuth;
- ausencia de cuenta API;
- provider sin integración automática.

## Objetivo

Publisher debe seguir siendo completamente útil incluso con cero APIs:

- calendario;
- revisión;
- preview;
- cola;
- recordatorios;
- checklist;
- auditoría;
- programación externa.

Las APIs conectadas simplemente automatizan targets concretos.
