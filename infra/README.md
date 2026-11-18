# Infraestructura de WinOpo

Un servicio + un worker + una base + un bucket. Nada de Kubernetes en v0.

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | Local: postgres16 + mailpit (+ app con `--profile app`) |
| `docker-compose.staging.yml` | Staging con datos sintéticos |
| `docker-compose.prod.yml` | Producción en la caja compartida: sin puertos, entrada por Cloudflare Tunnel |
| `docker-compose.caja-propia.yml` | Override solo para caja dedicada: publica 80/443 y Caddy hace ACME |
| `postgres/init.sql` | Solo local: rol `winopo_app` sin `BYPASSRLS` |
| `seed/sintetica.sql` | 2 tenants y 3 roles falsos, para tests |
| `caddy/Caddyfile` | TLS automático: `winopo.es` → landing estático, `app.winopo.es` → web + `/v1` → core |
| `caddy/Caddyfile.staging` | Staging: un solo dominio, sin landing |
| `scripts/backup.sh` | `pg_dump` a destino **externo**, retención 30 días |
| `scripts/restore-test.sh` | Restauración probada; una copia sin probar no es una copia |
| `scripts/deploy.sh` | `deploy.sh staging\|prod`: build → rol de aplicación → migraciones → arranque |

## Dónde se despliega

Ver [`docs/infra-servidor.md`](../docs/infra-servidor.md). Resumen: WinOpo vive en la **caja compartida con
Komanda** (CAX11 ARM64 de 4 GB), aislado por proyecto Compose, base y volumen propios, y **sin publicar
ningún puerto**: el tráfico entra por un Cloudflare Tunnel hasta `caddy:80`. El 80/443 es del Caddy de
Komanda y no se toca.

Medido el 18-nov-2026 antes de entrar: 2 753 MiB disponibles, 27 G libres y Komanda usando ≈ 380 MiB. Si
`available` baja de 800 MiB de forma recurrente, WinOpo se muda a una caja propia con
`WINOPO_EDGE=propia` y `docker-compose.caja-propia.yml`.

El alta paso a paso (host, túnel, DNS, secretos, primer despliegue, despliegue desde GitHub) está en
[`docs/runbooks/alta-servidor-winopo.md`](../docs/runbooks/alta-servidor-winopo.md). El DNS se aplica con
`tools/dns-cloudflare.sh`, que **simula por defecto** y solo escribe con `--apply`.

## Aviso ARM64

Las imágenes deben ser multi-arch. Si se añade una dependencia con librería nativa (por ejemplo Argon2), comprobar
 que existe artefacto `linux/arm64` **antes** de meterla en el `build.gradle.kts`.
