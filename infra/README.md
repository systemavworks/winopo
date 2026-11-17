# Infraestructura de WinOpo

Un servicio + un worker + una base + un bucket. Nada de Kubernetes en v0.

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | Local: postgres16 + mailpit (+ app con `--profile app`) |
| `docker-compose.staging.yml` | Staging con datos sintéticos |
| `docker-compose.prod.yml` | Producción, misma imagen que staging |
| `postgres/init.sql` | Solo local: rol `winopo_app` sin `BYPASSRLS` |
| `seed/sintetica.sql` | 2 tenants y 3 roles falsos, para tests |
| `caddy/Caddyfile` | TLS automático: `winopo.es` → landing estático, `app.winopo.es` → web + `/v1` → core |
| `caddy/Caddyfile.staging` | Staging: un solo dominio, sin landing |
| `scripts/backup.sh` | `pg_dump` a destino **externo**, retención 30 días |
| `scripts/restore-test.sh` | Restauración probada; una copia sin probar no es una copia |
| `scripts/deploy.sh` | `deploy.sh staging\|prod`: build → rol de aplicación → migraciones → arranque |

## Dónde se despliega

Ver [`docs/infra-servidor.md`](../docs/infra-servidor.md). Resumen: la caja actual es **CAX11 ARM64 de 4 GB** y ya
 aloja Komanda y Billka. WinOpo va a **caja propia** (CAX21 recomendada) para no compartir memoria, red interna ni
 base de datos con los otros dos productos.

## Aviso ARM64

Las imágenes deben ser multi-arch. Si se añade una dependencia con librería nativa (por ejemplo Argon2), comprobar
 que existe artefacto `linux/arm64` **antes** de meterla en el `build.gradle.kts`.
