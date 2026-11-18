# Desplegar WinOpo

> Procedimiento real para el servidor de v0. Si algo de aquí no funciona, el documento está mal:
> se corrige, no se improvisa en el servidor.
> Arquitectura de referencia: [`ARCHITECTURE.md`](ARCHITECTURE.md).

## 0. Resumen

| Entorno | Dominio | Compose | Base |
|---|---|---|---|
| Local | `localhost:3000` / `:8080` | `infra/docker-compose.yml` | datos sintéticos |
| Staging | `staging.winopo.es` | `infra/docker-compose.staging.yml` | datos sintéticos |
| Producción | `winopo.es` (landing, Worker de Cloudflare) + `app.winopo.es` (plataforma) | `infra/docker-compose.prod.yml` | datos reales |

Hay **dos caminos de publicación**, y conviene no mezclarlos:

| Qué | Dónde vive | Cómo se publica |
|---|---|---|
| Landing (`landing/`) → `winopo.es`, `www.winopo.es` | Cloudflare Workers con assets (`wrangler.jsonc`) | `tools/deploy-landing.sh`, o el workflow **landing** en cada push que toque `landing/**` |
| Plataforma (`core`, `worker`, `web`, `db`) → `app.winopo.es` | la caja, detrás de Cloudflare Tunnel | workflow **Desplegar** (*Run workflow*) o `infra/scripts/deploy.sh` por SSH |

El despliegue del servidor es **manual por SSH** con un script. El workflow **Desplegar** (`.github/workflows/deploy.yml`)
lo lanza desde GitHub, pero solo cuando se le da a *Run workflow*: no despliega en cada push.
Seis contenedores: `db`, `core`, `worker`, `web`, `caddy` y `cloudflared`. La misma imagen de `core` sirve
los dos perfiles. El landing **no** es un contenedor: es un Worker de Cloudflare.

Producción vive **en la caja compartida con Komanda** y el tráfico entra por Cloudflare Tunnel: este stack
no publica ningún puerto. El porqué y el aislamiento están en
[`docs/runbooks/alta-servidor-winopo.md`](docs/runbooks/alta-servidor-winopo.md) §0.

**Estado a 18-nov-2026: la plataforma está publicada.** `app.winopo.es` entra por el túnel
`winopo-cax11` (`b2690a74-b65b-4909-9f4b-82ad29b7693c`) a `/opt/winopo` en la caja, con los seis
contenedores arriba; verificado desde fuera con `200` en `/`, `/login` y `/healthz`. Los despliegues, por
ahora, se hacen por SSH a mano: los secretos de SSH del workflow **Desplegar** aún no están cargados.

## 1. Antes del primer despliegue

### Servidor

- La caja ya existe: CAX11 ARM64 de 4 GB, compartida con Komanda (medido: 2 753 MiB disponibles, 27 G
  libres). Criterios de corte y cuándo se separa, en `docs/runbooks/alta-servidor-winopo.md` §0 y §8.
  Los datos concretos del servidor **no están en el repositorio**.
- Docker Engine + plugin `docker compose` (v2) ya están instalados: los usa Komanda.
- Reloj en hora (`timedatectl`): un desfase rompe las fechas de sesión.

### Red

**No se abre nada nuevo.** El 80/443 son del Caddy de Komanda y `ufw`/`fail2ban` ya están configurados por
él; reconfigurarlos es la forma más rápida de dejar Komanda sin acceso. Lo único que hay que comprobar:

```bash
sudo ufw status verbose          # 22, 80, 443 — sin cambios
docker compose --env-file .env -f infra/docker-compose.prod.yml ps   # ningún puerto en 0.0.0.0
```

`docker-compose.prod.yml` no publica puertos de base, API ni web: es a propósito. `cloudflared` sale a
Internet por su cuenta (conexión saliente al edge), así que no hace falta agujero de entrada.
Si alguna vez hace falta mirar la base desde fuera, se usa un túnel SSH, no se abre el puerto.

En una **caja dedicada** (ver §10 y el override `docker-compose.caja-propia.yml`) sí se abren 22, 80 y 443,
porque Caddy saca el certificado por HTTP-01.

### DNS

Hay dos mitades y **no se gestionan igual**:

**`winopo.es` y `www.winopo.es` son del Worker `winopo`.** Los crea Cloudflare al atar el
`custom_domain` de [`wrangler.jsonc`](wrangler.jsonc) (un `AAAA 100::` proxied) y se publican con
`tools/deploy-landing.sh` o el workflow **landing**. No se tocan a mano ni con el script de DNS: si
alguien los reapunta al túnel, la web comercial deja de servirse.

**`app.winopo.es` sí vive fuera de Cloudflare**, en la caja, y lo gestiona un script idempotente. En la
caja compartida el modo es **túnel**:

```bash
tools/dns-cloudflare.sh --tunnel            # simulación: enseña el cambio
tools/dns-cloudflare.sh --tunnel --apply    # aplica
```

| Nombre | Tipo | Valor | Quién lo posee |
|---|---|---|---|
| `winopo.es` | AAAA proxied | `100::` | Worker `winopo` (`custom_domain`) |
| `www.winopo.es` | AAAA proxied | `100::` | Worker `winopo` (`custom_domain`) |
| `app.winopo.es` | CNAME proxied | `b2690a74-b65b-4909-9f4b-82ad29b7693c.cfargotunnel.com` | la caja, vía túnel |

El script borra los restos muertos que quedan en la zona (`*.winopo.es` y cualquier CNAME a
`winopo.pages.dev`, un proyecto que ya no existe y devolvía `error code: 1014`) y no toca el `TXT` del
SPF ni los `MX`. Un registro `AAAA 100::` no se considera resto de Pages: es la firma del custom
domain del Worker y se deja como está.

Si el túnel no existe en la cuenta, el script sale con **2** sin escribir: un CNAME a `cfargotunnel` sin
túnel detrás solo convierte el 1014 en un NXDOMAIN. Y con el túnel creado, el DNS no basta: hace falta el
hostname dentro del túnel apuntando a `HTTP caddy:80`, o `cloudflared` responde 404.

Hostname público ya declarado en Zero Trust → Tunnels → `winopo-cax11`: `app.winopo.es` → `HTTP caddy:80`.
El túnel es *remotely managed* (`config_src: cloudflare`): el ingress se cambia en el panel o por API, no en
un fichero dentro de `cloudflared`. Crearlo por API necesita `Account → Cloudflare Tunnel → Edit`, que el
token actual no tiene (`10000 Authentication error`); se creó con la sesión OAuth de `wrangler` (§3 del
runbook).

Con **IP propia** el modo es el otro, y deja el registro en gris (Cloudflare no proxifica: Caddy gestiona
el certificado por HTTP-01; en naranja solo tendría sentido con modo SSL "Full strict" y Origin CA):

| Nombre | Tipo | Valor |
|---|---|---|
| `app.winopo.es` | **A** | IP del servidor |
| `staging.winopo.es` | A | IP del servidor (o de otro, si se separa) |

El apex y `www` siguen siendo del Worker en los dos modos: no hay registro `A` de apex, así que no hace
falta *CNAME flattening* para ellos.

Pasos completos, con el orden correcto (host → túnel → DNS → secretos → despliegue):
[`docs/runbooks/alta-servidor-winopo.md`](docs/runbooks/alta-servidor-winopo.md).
Comprobar antes de desplegar:

```bash
dig +short winopo.es        # IPs de Cloudflare: el Worker ya sirve el landing
dig +short app.winopo.es
```

En modo túnel, hasta que `cloudflared` esté conectado el dominio responde `error 1033`: es lo esperado, no
un fallo del DNS.

## 2. Secretos

El `.env` vive **solo en el servidor** (`/opt/winopo/.env`), con permisos `600`, y nunca entra en git
(está en `.gitignore`; `.env.example` es la plantilla sin valores).

```bash
cd /opt/winopo
cp .env.example .env
chmod 600 .env

# Generar valores reales (no inventarlos a mano)
echo "SESSION_SECRET=$(openssl rand -base64 48)"
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
echo "POSTGRES_APP_PASSWORD=$(openssl rand -hex 24)"
```

Se usa **hex** para las contraseñas de base de datos y no base64: el `DATABASE_URL` lleva las
credenciales en la cadena de consulta y los caracteres `+ / =` obligan a escaparlos. Un `hex` no
tiene ese problema.

Qué significa cada una:

| Variable | Para qué | Si se filtra |
|---|---|---|
| `POSTGRES_PASSWORD` | superusuario del contenedor; administra y migra | hay que rotarla y revisar accesos |
| `POSTGRES_APP_PASSWORD` | usuario de la aplicación (sin `BYPASSRLS`) | rotarla: `deploy.sh` la reescribe en la base |
| `SESSION_SECRET` | firma de sesiones | rotarla invalida todas las sesiones (efecto: todos a login) |

**Nunca** se usa el superusuario para la aplicación: un superusuario se salta la RLS y con él el
aislamiento entre preparadores deja de existir. `deploy.sh` crea el rol `winopo_app` en cada despliegue
con la contraseña del `.env`.

## 3. Migraciones

- Se aplican **en orden** (`migrations/*.sql`), con `ON_ERROR_STOP=1`: la primera que falla detiene
  el despliegue y no se levanta la aplicación.
- **Una migración aplicada no se edita nunca.** Se corrige con la siguiente.
- La RLS de una tabla va en la misma migración que crea la tabla.
- **Antes de migrar en producción, copia** (§9). No hay migraciones destructivas previstas, pero
  "no previstas" no es "imposible".

`deploy.sh` ya hace build → rol → migraciones → arranque, en ese orden.

## 4. Primer despliegue, paso a paso

```bash
# 1. Código en el servidor (git, no scp de carpetas sueltas)
sudo mkdir -p /opt/winopo && sudo chown "$USER" /opt/winopo
git clone https://github.com/systemavworks/winopo.git /opt/winopo
cd /opt/winopo

# 2. Secretos
cp .env.example .env
chmod 600 .env
# editar .env: POSTGRES_PASSWORD, POSTGRES_APP_PASSWORD, SESSION_SECRET
#                APP_ENV=prod, WINOPO_DOMINIO=winopo.es, WINOPO_APP_DOMINIO=app.winopo.es

# 3. Desplegar (build + rol + migraciones + arranque)
infra/scripts/deploy.sh prod

# 4. Comprobar
curl -fsS https://winopo.es/ | head -5
curl -fsS https://app.winopo.es/healthz
```

La primera vez, Caddy tarda unos segundos en obtener el certificado. Si a los dos minutos no hay TLS:

```bash
docker compose -f infra/docker-compose.prod.yml logs caddy | tail -30
```

Causas habituales, en orden de frecuencia: DNS aún sin propagar, puerto 80 cerrado (Let's Encrypt lo
usa para validar), o un `A` apuntando a otra máquina.

### Sembrar el primer preparador

No hay registro público: el primer usuario se crea a mano, y esa es una decisión, no un olvido
(el alta de preparadores en v0 es manual para controlar quién entra).

```bash
docker compose -f infra/docker-compose.prod.yml exec -T db \
  psql -U winopo -d winopo -v ON_ERROR_STOP=1
```

Dentro de `psql`, insertar `tenant`, `app_user` (con hash PBKDF2 generado por la herramienta del
proyecto, nunca una contraseña en claro) y `membership` con rol `preparador`. El procedimiento exacto
está en `docs/runbooks/alta-preparador.md` cuando exista; hasta entonces, este paso se hace con
supervisión y se anota en el registro de cambios.

## 5. Desplegar cambios

```bash
cd /opt/winopo
git pull --ff-only
git log --oneline -1          # saber qué se está desplegando
infra/scripts/deploy.sh prod
```

`deploy.sh` hace, en orden: build de imágenes → crea/actualiza el rol de aplicación → migraciones →
`up -d --remove-orphans` → estado.

### Verificación después de cada despliegue

```bash
curl -fsS https://app.winopo.es/healthz        # {"estado":"ok","servicio":"winopo"}
curl -fsS -o /dev/null -w '%{http_code}\n' https://app.winopo.es/login   # 200
curl -fsS -o /dev/null -w '%{http_code}\n' https://winopo.es/            # 200
curl -fsS -o /dev/null -w '%{http_code}\n' https://app.winopo.es/v1/auth/sesion  # 401 (sin cookie)
```

Y un login real con un usuario de prueba. Un `/healthz` en verde solo dice que el proceso vive;
no dice que la base responda ni que la RLS esté haciendo su trabajo.

### Revertir (rollback)

No hay despliegue azul-verde. Revertir es volver al commit anterior y reconstruir:

```bash
cd /opt/winopo
git log --oneline -5
git checkout <commit-anterior>
infra/scripts/deploy.sh prod
```

Límite importante: **las migraciones no se revierten solas**. Si el commit anterior no conocía una
columna nueva, la base la conserva y no molesta; si el commit anterior esperaba un esquema que ya
cambió, hay que restaurar copia (§8). Por eso las migraciones se escriben compatibles hacia atrás
cuando se pueda (añadir columna con `default`, no renombrar en el mismo paso que se usa).

## 6. El landing de `winopo.es`

Es HTML estático en `landing/`, publicado como **Worker de Cloudflare con assets** ([`wrangler.jsonc`](wrangler.jsonc)),
igual que `komanda.es` y `app.billka.es`. **No pasa por el servidor**: no necesita build, ni `git pull` en
la caja, ni recargar Caddy, y si la plataforma se cae la web comercial sigue en pie.

```bash
tools/deploy-landing.sh           # publica y comprueba que lo servido es el repositorio
tools/deploy-landing.sh --check   # solo comprueba, sin publicar
make landing-deploy               # lo mismo, con make
make landing-check
```

En CI lo hace el workflow **landing** (`.github/workflows/landing.yml`) en cada push a `main` que toque
`landing/**` o `wrangler.jsonc`, con el secreto `CLOUDFLARE_API_TOKEN` (y opcionalmente la variable
`CLOUDFLARE_ACCOUNT_ID`). Sin secreto el job **no falla**: avisa y se salta el despliegue.

Ese secreto ya está configurado en el repositorio. Para crearlo o rotarlo (el token necesita
**Workers Scripts: Edit** y **Workers Routes: Edit** sobre la zona `winopo.es`; no hace falta `Zone.DNS: Edit`,
lo pone Cloudflare al crear el `custom_domain`):

```bash
printf '%s' "$API_TOKEN_CLOUDFLARE" | gh secret set CLOUDFLARE_API_TOKEN   # lee de stdin, no del historial
gh variable set CLOUDFLARE_ACCOUNT_ID --body '85acbbc7a2dbb26ec060129fab495c2f'
gh workflow run landing.yml && gh run watch                                # prueba de punta a punta
```

- `landing/_headers` lleva las cabeceras que antes ponía Caddy: HSTS, `nosniff`, `X-Frame-Options`,
  `Referrer-Policy` y CSP con `script-src 'none'`. El script de publicación comprueba que llegan.
- `landing/_redirects` manda `/login`, `/app` y `/v1` a `app.winopo.es`, como hacía el `redir` de Caddy.
- Está pensado para no necesitar nada más: sin JavaScript, sin fuentes externas, sin cookies, sin
  analítica. Por eso no hay banner de consentimiento (no hay nada que consentir) y la CSP bloquea
  scripts (`script-src 'none'`).
- La marca va aparte: `landing/assets/` contiene el emblema, el favicon, el icono de iOS y la tarjeta
  para redes. Salen del logo original con `python3 tools/marca/generar_marca.py`, que recorta, quita el
  fondo crema y genera cada tamaño. **Si cambia el logo, se regeneran; no se editan a mano.** Suman
  unos 190 KB, servidos por el mismo Worker (sin CDN ni terceros).

El bloque del apex sigue en `infra/caddy/Caddyfile` como red de seguridad (sirve el mismo `landing/` desde
`/srv/landing` dentro de la caja), pero en producción **no se usa**: el apex lo sirve el Worker. Si algún
día se detacha el custom domain, ese bloque es lo que mantiene la web comercial sin tocar nada más.

Detalles que no hay que olvidar al publicarlo:

1. `landing/index.html` lleva `meta robots="noindex, nofollow"` mientras sea una versión de prueba.
   **Quitar esas dos líneas el día del lanzamiento**, o el dominio no aparecerá en Google.
2. El correo de contacto es `hola@winopo.es`: hay que crear el buzón o el alias antes de publicar.
3. Las llamadas a la acción apuntan a `https://app.winopo.es/login`. Si cambia el subdominio, se
   cambia en `landing/index.html` y en `landing/_redirects`.
4. La tarjeta para redes (`og:image`) apunta a `https://winopo.es/assets/og-winopo.jpg`: **la URL es
   absoluta a propósito** (los rastreadores de redes no resuelven rutas relativas), así que si el
   dominio cambia hay que regenerar y ajustar esa línea.
5. El aviso legal y la política de privacidad están marcados como "en preparación": es texto honesto,
   pero **no se puede lanzar comercialmente sin ellos** (LSSI + RGPD). Pendiente legal (§12).

Ver el landing en local, sin Docker:

```bash
make landing     # http://localhost:4000
```

## 7. Staging

```bash
cd /opt/winopo
infra/scripts/deploy.sh staging
```

- `staging.winopo.es`, un solo dominio (no sirve landing: `infra/caddy/Caddyfile.staging`).
- **Datos sintéticos. Nunca alumnos reales**: es el entorno donde se rompen las cosas.
- Base y volúmenes distintos (`winopo-staging`), mismo código.
- Un error se reproduce primero aquí. Si solo se reproduce en producción, se trabaja con copia de
  producción restaurada en local, nunca consultando datos reales desde el portátil.

## 8. Copias de seguridad

El procedimiento completo está en [`docs/runbooks/backup-restauracion.md`](docs/runbooks/backup-restauracion.md).
Resumen de lo que hay que tener claro:

```bash
# Copia manual
BACKUP_DESTINO=s3:... infra/scripts/backup.sh
# Prueba de restauración (mensual, no el día del incidente)
infra/scripts/restore-test.sh backups/winopo-YYYY-MM-DD.dump
```

- `pg_dump -Fc`, cifrado en destino, retención 30 días, **fuera del mismo disco**.
- Lo que se pierde en una restauración es todo lo posterior a la copia. De ahí que sea diaria.
- El vídeo y los PDFs viven en R2 y **no** entran en el `pg_dump`: sus metadatos sí. Si R2 y la base
  se desincronizan, hay un registro apuntando a un objeto que ya no existe.
- Una copia que nunca se ha restaurado no es una copia: es una esperanza. De ahí la prueba mensual.

**Estado real a día de hoy:** el script existe, la tarea programada **no está configurada** en el
servidor. Es lo primero que hay que hacer antes de que haya datos de un preparador real.

## 9. Logs y diagnóstico

```bash
cd /opt/winopo
docker compose -f infra/docker-compose.prod.yml ps
docker compose -f infra/docker-compose.prod.yml logs -f --tail=100 core
docker compose -f infra/docker-compose.prod.yml logs -f --tail=100 worker
docker compose -f infra/docker-compose.prod.yml logs -f --tail=100 caddy
```

Qué buscar:

| Síntoma | Dónde mirar | Causa típica |
|---|---|---|
| 502 en `app.winopo.es` | `logs caddy`, `ps` | `core` o `web` caídos; el otro extremo no escucha |
| 502 solo en `/v1` | `logs core` | la API murió al arrancar (falta `SESSION_SECRET` o `DATABASE_URL`) |
| Todo 500 | `logs core` | base de datos inaccesible o migración no aplicada |
| TLS inválido | `logs caddy` | DNS, puerto 80 cerrado o límite de Let's Encrypt |
| Login correcto pero sin acceso | `psql` sobre `membership` | `estado` distinto de `activo` |
| Contenedor reiniciándose en bucle | `logs <servicio>` | variable obligatoria ausente (`Settings` falla al arrancar, a propósito) |

Un arranque que falla por falta de configuración es una función, no un fallo: es preferible a arrancar
a medias y descubrir el problema con un opositor delante.

## 10. TLS y certificados

**En la caja compartida no hay certificados que gestionar.** Cloudflare termina el TLS en su edge y habla
con `cloudflared` por un canal cifrado; `cloudflared` reenvía a `caddy:80` en claro dentro de la red
`winopo_default`. Por eso el compose fija `WINOPO_SCHEME=http`, Caddy no publica puertos y no hay
`caddy-data`: ni ACME, ni Origin CA, ni modo "Full (strict)", ni puerto 80 abierto al mundo.

- HSTS lo pone Caddy y llega al navegador a través del edge: un año con `includeSubDomains`. No hay vuelta
  atrás cómoda a HTTP, así que antes de publicar un subdominio nuevo hay que comprobar que también tendrá TLS.
- El certificado del borde se renueva solo; si un día falla, se ve en el panel de Cloudflare, no en los logs
  del servidor.

**En una caja dedicada** (`WINOPO_EDGE=propia` + `docker-compose.caja-propia.yml`) el esquema es el clásico:
Caddy obtiene y renueva certificados de Let's Encrypt por HTTP-01 (puerto 80) y los guarda en el volumen
`caddy-data`. **Ese volumen no se borra** con un `down -v` accidental sin asumir el coste: Let's Encrypt
limita los certificados duplicados por semana.


## 11. Lo que **no** está automatizado

Enumerado para que nadie lo dé por hecho:

| Tema | Estado |
|---|---|
| CI/CD hacia el servidor | manual: workflow **Desplegar** por SSH + `deploy.sh`; no se dispara en cada push |
| Copias programadas | script listo, `cron`/temporizador **sin configurar** |
| Monitorización y alertas | nada: ni Uptime Kuma, ni alertas de disco, ni de memoria |
| Rotación de logs | la de Docker por defecto; sin límite configurado |
| Despliegue sin caída | no: `up -d` recrea contenedores, hay unos segundos de 502 |
| Rollback de migraciones | no: se restaura copia |
| Alta de preparadores | manual, por `psql` |
| Restauración probada | nunca se ha ejecutado en el servidor real |

Cada línea de esta tabla es una tarea concreta para antes de tener clientes de pago.

## 12. Pendientes que no son código

Bloquean el lanzamiento comercial, no el despliegue técnico:

1. **Aviso legal y política de privacidad** en el landing (LSSI + RGPD). Hoy dice "en preparación".
2. **Responsable del tratamiento** (D7): falta decidir si es la sociedad o el preparador, y reflejarlo
   en el contrato de encargado del tratamiento.
3. **Dominio `vinopo.es`** (variante con uve) y confirmación de la titularidad de `winopo.es`.
4. **Marca**: búsqueda en OEPM y EUIPO, clase 41. Antes de imprimir nada.
5. **Correo `hola@winopo.es`** operativo.
6. **Precio real por opositor** (D9), que condiciona la página de precios del landing.


