# State Machine

## Workflow editorial

```text
EN_CONFIRMACION
  -> CON_CORRECCION
  -> LISTO_POR_PROGRAMAR
  -> PROGRAMADO
```

El usuario cambia este estado exclusivamente desde la ficha de contenido. El Kanban sólo visualiza.

## Validación técnica

Separada del workflow:

```text
VALID
WARNING
INVALID
```

## Target / plataforma

En v1.1:

```text
READY
PRECALENDARIZED
```

En Paso 2 se añadirán `SCHEDULED`, `UPLOADING`, `PROCESSING`, `PUBLISHED`, `FAILED`, etc. basados en receipts reales del provider.
