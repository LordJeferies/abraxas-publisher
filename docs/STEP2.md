# Paso 2 — Integraciones reales

v1.1 debe considerarse la base congelada de workflow/editorial.

## Orden de implementación

1. `PublisherAdapter` interface común.
2. Vault de credenciales (Keychain en Mac / server secrets en cloud).
3. OAuth y health por cuenta, una plataforma a la vez.
4. Validación real de capacidades/formatos por provider.
5. Upload individual de un contenido de prueba.
6. Verificación y receipt remoto.
7. Scheduling individual.
8. Retries/idempotencia.
9. Dry run del lote con providers conectados pero publicación bloqueada.
10. **Última prueba:** publicar un lote real pequeño y verificar cada receipt.

## Regla

No renombrar TXT como `PROGRAMADO_...` por el workflow editorial. Ese rename debe depender del receipt remoto del provider.
