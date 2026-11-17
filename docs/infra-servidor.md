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
| Aloja además | otros dos productos del mismo titular |

Los datos identificables de la máquina (ID, hostname, IPv4 e IPv6) **no se publican**: están en
 `privado/infra-real.md`, fuera de git. Un repositorio público con la IP del servidor es un objetivo regalado.

## 2. Dos consecuencias inmediatas

### 2.1 Es ARM64

Toda imagen de WinOpo tiene que ser **multi-arch** o construirse en la propia máquina. Las que usa el
 esqueleto (`postgres:16-alpine`, `caddy:2-alpine`, `eclipse-temurin:21-jre-alpine`) lo son. Lo que no lo es:

- Librerías nativas: `argon2-jvm` con `.so` de x86. Por eso `Passwords.kt` usa **PBKDF2 del JDK** y no Argon2id.
  En una caja ARM64 sin artefacto nativo, Argon2 conlleva compilar o cambiar de librería: no es gratis.
- Imágenes de proveedores de TTS o de render de vídeo, si se empaquetan en local: hay que revisarlas una a una.

### 2.2 4 GB ya están ocupados

Con Komanda y Billka dentro, WinOpo **no cabe con holgura**. Presupuesto estimado de WinOpo:

| Contenedor | RAM en reposo | RAM con carga |
|---|---|---|
| `core` (API, JVM) | 250–400 MB | 500–700 MB |
| `worker` (JVM) | 250–400 MB | 600–900 MB (IA y vídeo) |
| `db` (PostgreSQL 16) | 150–250 MB | 400–600 MB |
| `web` (Next.js standalone) | 120–200 MB | 250–350 MB |
| `caddy` | 20–30 MB | 50 MB |
| **Total** | **~0,8 GB** | **~2,2 GB** |

Sumado a lo que ya corre, se entra en swap y en OOM killer. Y un OOM killer en producción no avisa: mata el
 proceso que elija.

## 3. Decisión recomendada

**Caja propia para WinOpo.** Es la misma regla que ya aplica Billka con Komanda (ADR `B0002`): runtime, base de
 datos y despliegue propios; si comparten máquina, no comparten red interna ni base de datos.

| Opción | Cuándo tiene sentido |
|---|---|
| **CAX21** (4 vCPU · 8 GB · 80 GB, ARM) | Recomendada. Margen para worker de IA y vídeo sin ahogar la web |
| CAX11 (2 vCPU · 4 GB · 40 GB) solo para WinOpo | Vale para F0–F2, sin worker pesado. Migrar antes de vender |
| Compartir la caja actual | **No**. Tres productos en 4 GB es pedir un incidente |

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

- **Firewall del panel**: 22, 80, 443. Nada más. PostgreSQL y el core **no** se publican a Internet.
- En el compose, `db` sin `ports:`; solo accesible por la red interna de Docker.
- SSH con clave, sin contraseña, y `fail2ban` si no está.
- Copias **fuera** de la caja (`infra/scripts/backup.sh` con `BACKUP_DESTINO` remoto): un disco que se pierde se
  lleva la base y las copias si están en el mismo sitio.
- El vídeo vive en R2, no en el disco de la caja: 40 GB se llenan con dos temporadas de PDF.

## 6. Dominios

| Dominio | Sirve | Certificado |
|---|---|---|
| `winopo.es` + `www` | landing estático (`landing/`) | Caddy / Let's Encrypt |
| `app.winopo.es` | plataforma (Next.js) y API `/v1` | Caddy / Let's Encrypt |
| `staging.winopo.es` | entorno de pruebas (un solo dominio) | Caddy / Let's Encrypt |

Los tres apuntan a la misma máquina con registros `A`; el apex no admite `CNAME`. Caddy enruta por
nombre de host (`infra/caddy/Caddyfile`), así que los certificados son independientes entre sí.

El apex se sirve como archivos estáticos: si `core` o `web` se caen, la web comercial sigue en pie.
Detalle del despliegue en [`../DEPLOY.md`](../DEPLOY.md).
