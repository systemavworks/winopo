# Infraestructura · estado real

**Fecha**: 17-nov-2026. Este documento describe **lo que hay**, no lo que nos gustaría tener.

## 1. Servidor actual (Hetzner)

| Dato | Valor |
|---|---|
| Tipo | **CAX11** (Ampere, **ARM64**) |
| vCPU | 2 |
| RAM | 4 GB |
| Disco | 40 GB local |
| Región | UE (Falkenstein) |
| Aloja además | Komanda (publicado, en `/opt/komanda`). La API de Billka está prevista en esta caja pero **aún no desplegada**: su dashboard vive en Cloudflare Workers |

Los datos identificables de la máquina (ID, hostname, IPv4 e IPv6) **no se publican**: están en
 `privado/infra-real.md`, fuera de git. Un repositorio público con la IP del servidor es un objetivo regalado.

## 2. Dos consecuencias inmediatas

### 2.1 Es ARM64

Toda imagen de WinOpo tiene que ser **multi-arch** o construirse en la propia máquina. Las que usa el
 esqueleto (`postgres:16-alpine`, `caddy:2-alpine`, `eclipse-temurin:21-jre-alpine`) lo son. Lo que no lo es:

- Librerías nativas: `argon2-jvm` con `.so` de x86. Por eso `Passwords.kt` usa **PBKDF2 del JDK** y no Argon2id.
  En una caja ARM64 sin artefacto nativo, Argon2 conlleva compilar o cambiar de librería: no es gratis.
- Imágenes de proveedores de TTS o de render de vídeo, si se empaquetan en local: hay que revisarlas una a una.

### 2.2 Cuánta RAM hace falta

Presupuesto estimado de WinOpo:

| Contenedor | RAM en reposo | RAM con carga |
|---|---|---|
| `core` (API, JVM) | 250–400 MB | 500–700 MB |
| `worker` (JVM) | 250–400 MB | 600–900 MB (IA y vídeo) |
| `db` (PostgreSQL 16) | 150–250 MB | 400–600 MB |
| `web` (Next.js standalone) | 120–200 MB | 250–350 MB |
| `caddy` (edge interno) | 20–30 MB | 50 MB |
| `cloudflared` (túnel) | 20–30 MB | 50 MB |
| **Total** | **~0,8 GB** | **~2,2 GB** |

Medido el 18-nov-2026, la caja **no** estaba ocupada: Komanda (caddy + core + web + postgres) suma ≈ 380 MiB
y quedan 2 753 MiB disponibles con 27 G de disco libres. Los techos de arriba (2,2 GB) solo se alcanzarían con
todo a plena carga a la vez, escenario que en v0 no existe; aun así son válvulas anti-fuga, no reservas.

## 3. Decisión: compartir la caja, aislado

Igual que Billka con Komanda (ADR `B0009`): **misma máquina, runtime y datos separados**. WinOpo es el tercer
producto, así que las reglas son más estrictas, no menos:

| Recurso | WinOpo |
|---|---|
| Proyecto Compose | `winopo` → red `winopo_default`, sin servicios de Komanda |
| Base de datos | contenedor propio + volumen `winopo_prod-db`; ningún usuario ni base compartidos |
| Puertos | **ninguno publicado**: entra `cloudflared` a `caddy:80` por la red interna |
| Secretos | `.env` propio, 600, sin credenciales cruzadas |

| Opción | Cuándo tiene sentido |
|---|---|
| **Compartir el CAX11** (elegida) | hoy: 2 753 MiB disponibles y Komanda en 380 MiB. Coste incremental ~0 € |
| **CAX21** (4 vCPU · 8 GB · 80 GB, ARM) | cuando se cumpla un disparador del §8 del runbook: `available` < 800 MiB recurrente, disco > 70 %, primer cliente de pago, o necesidad de ventanas de mantenimiento propias |

El 80/443 de la caja es del Caddy de Komanda: un segundo edge publicando esos puertos deja **los dos**
productos caídos. Por eso la entrada es un Cloudflare Tunnel (`cloudflared` → `caddy:80`, TLS en el edge) y
no hay certificado que gestionar. El camino de vuelta a caja propia es
`WINOPO_EDGE=propia` + `docker-compose.caja-propia.yml` + registros `A` en gris.

Comprobar precio y disponibilidad en el panel antes de decidir: las tarifas cambian.


## 4. Antes de decidir, medir (en la caja actual)

```bash
free -h
docker stats --no-stream
df -h /
du -sh /var/lib/docker
```

Si `free -h` muestra menos de 800 MB disponibles y ya hay swap en uso, el debate está cerrado: caja nueva.

## 5. Red y seguridad mínimas

- **Firewall**: en la caja compartida no se añade nada (22/80/443 ya los usa Komanda) y `ufw`/`fail2ban` no se
  reconfiguran. En una caja dedicada: 22, 80, 443 y nada más. PostgreSQL y el core **no** se publican nunca.
- En el compose, `db` sin `ports:`; solo accesible por la red interna de Docker.
- SSH con clave, sin contraseña, y `fail2ban` si no está.
- Copias **fuera** de la caja (`infra/scripts/backup.sh` con `BACKUP_DESTINO` remoto): un disco que se pierde se
  lleva la base y las copias si están en el mismo sitio.
- El vídeo vive en R2, no en el disco de la caja: 40 GB se llenan con dos temporadas de PDF.

## 6. Dominios

| Dominio | Sirve | Cómo llega |
|---|---|---|
| `winopo.es` + `www` | landing estático (`landing/`) | **Cloudflare Worker** con assets (`wrangler.jsonc`), publicado desde GitHub |
| `app.winopo.es` | plataforma (Next.js) y API `/v1` | Cloudflare Tunnel → `caddy:80` |
| `staging.winopo.es` | entorno de pruebas (un solo dominio) | **No** en esta caja: publica 80/443 |

El landing **no depende de esta caja**: `tools/deploy-landing.sh` (o el workflow «landing» en cada push)
sube `landing/` al Worker y Cloudflare crea el registro del apex y de `www` (`AAAA 100::` proxied) al atar
el `custom_domain`. Caddy enruta por nombre de host dentro de la red (`infra/caddy/Caddyfile`), y el túnel
solo necesita declarar `app.winopo.es` → `HTTP caddy:80`.

En caja dedicada, `app.winopo.es` pasa a registro `A` en gris y certificado de Caddy por HTTP-01, con
`tools/dns-cloudflare.sh --ip <IP>`. El apex sigue siendo del Worker en los dos casos.

El apex se sirve como archivos estáticos desde el edge: si `core` o `web` se caen, la web comercial sigue en
pie, y el despliegue del landing no toca el servidor.
Detalle del despliegue en [`../DEPLOY.md`](../DEPLOY.md).
