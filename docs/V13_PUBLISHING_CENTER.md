# ABRAXAS Publisher V1.3 · Publishing Center

## Objetivo

V1.3 transforma Publisher de planner editorial a centro operacional de publicación.

## Flujo

IMPORT
→ EDITORIAL REVIEW
→ LISTO_POR_PROGRAMAR
→ PRECALENDARIZED
→ PUBLISHING WIZARD
→ PREFLIGHT
→ PLATFORM PREVIEW
→ QUEUED
→ PROVIDER ADAPTER
→ VERIFY
→ SCHEDULED_REMOTE / PUBLISHED

## Estados externos

Cuando una publicación se realiza fuera de Publisher:

SCHEDULED_EXTERNAL

Ejemplos:

- Edits
- Meta Business Suite
- YouTube Studio
- LinkedIn
- TikTok
- otro scheduler

Nunca usar SCHEDULED_REMOTE para una acción que Publisher no verificó.

## Accounts

Estados:

NEEDS_AUTH
CONNECTED
EXTERNAL_ONLY
ERROR

Auth:

PENDING
AUTHORIZED
EXPIRED
REVOKED
NOT_REQUIRED

No se considera una cuenta CONNECTED sólo por guardar su nombre.

## Provider Strategies

YouTube:
NATIVE_OR_LOCAL

LinkedIn:
LOCAL_DISPATCH

TikTok:
LOCAL_DISPATCH

Instagram:
LOCAL_DISPATCH

Facebook:
PROVIDER_OR_LOCAL

Las capabilities deben validarse contra la cuenta real antes de publicar.

## OAuth

V1.3 incluye el Accounts Center y contratos de provider.

OAuth real sólo se marca autorizado después de:

1. OAuth provider.
2. token válido.
3. scopes.
4. account identity.
5. capability verification.

Tokens y secretos nunca deben guardarse en frontend ni Git.

## Queue

Los publication_jobs tienen idempotency_key.

Esto evita duplicados causados por reintentos.

Estados futuros:

REVIEW_REQUIRED
QUEUED
WAITING
DISPATCHING
UPLOADING
PROCESSING_REMOTE
VERIFYING
SCHEDULED_REMOTE
SCHEDULED_EXTERNAL
PUBLISHED
FAILED
CANCELLED

## Platform Preview Engine

Mockups contextuales:

- Instagram
- Facebook
- LinkedIn
- YouTube
- TikTok

El preview es editorial y visual.
No afirma reproducir píxel por píxel versiones futuras de las apps externas.

## Seguridad

V1.3 no incorpora secretos en el repo.

V1.3 no marca como publicada una publicación sin remote verification.

V1.3 no usa Undo para revertir una acción remota.
