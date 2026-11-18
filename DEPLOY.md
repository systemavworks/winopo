# Desplegar WinOpo

> Procedimiento real para el servidor de v0. Si algo de aquí no funciona, el documento está mal:
> se corrige, no se improvisa en el servidor.
> Arquitectura de referencia: [`ARCHITECTURE.md`](ARCHITECTURE.md).

## 0. Resumen

| Entorno | Dominio | Compose | Base |
|---|---|---|---|
| Local | `localhost:3000` / `:8080` | `infra/docker-compose.yml` | datos sintéticos |
| Staging | `staging.winopo.es` | `infra/docker-compose.staging.yml` | datos sintéticos |
| Producción | `winopo.es` (landing) + `app.winopo.es` (plataforma) | `infra/docker-compose.prod.yml` | datos reales |

El despliegue es **manual por SSH** con un script. El workflow **Desplegar** (`.github/workflows/deploy.yml`)
lo lanza desde GitHub, pero solo cuando se le da a *Run workflow*: no despliega en cada push.
Seis contenedores: `db`, `core`, `worker`, `web`, `caddy` y `cloudflared`. La misma imagen de `core` sirve
los dos perfiles.

Producción vive **en la caja compartida con Komanda** y el tráfico entra por Cloudflare Tunnel: este stack
no publica ningún puerto. El porqué y el aislamiento están en
[`docs/runbooks/alta-servidor-winopo.md`](docs/runbooks/alta-servidor-winopo.md) §0.

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

Los registros se aplican con un script idempotente, no a mano en el panel. En la caja compartida el modo es
**túnel**: los CNAME los crea el propio túnel al declarar los hostnames públicos, y el script solo limpia
los restos muertos de Pages.

```bash
tools/dns-cloudflare.sh --tunnel            # simulación: enseña qué borraría
tools/dns-cloudflare.sh --tunnel --apply    # borra `*.winopo.es` y `www` si apuntan a pages.dev
```

Hostnames públicos a declarar en Zero Trust → Tunnels → `winopo-cax11` (los tres al servicio
`HTTP caddy:80`): `winopo.es`, `www.winopo.es`, `app.winopo.es`.

El script borra además los restos de Cloudflare Pages: `*.winopo.es` y `www` apuntaban a
`winopo.pages.dev`, un proyecto que ya no existe, y Cloudflare respondía `error code: 1014` en todo
subdominio. No toca el `TXT` del SPF ni los `MX`.

Con **IP propia** el modo es el otro, y deja registros en gris (Cloudflare no proxifica: Caddy gestiona el
certificado por HTTP-01; en naranja solo tendría sentido con modo SSL "Full strict" y Origin CA):

| Nombre | Tipo | Valor |
|---|---|---|
| `winopo.es` | **A** | IP del servidor |
| `www.winopo.es` | CNAME | `winopo.es` |
| `app.winopo.es` | A | IP del servidor |
| `staging.winopo.es` | A | IP del servidor (o de otro, si se separa) |

El apex **no puede ser CNAME** sin *flattening*: por eso en modo IP es un registro `A` y en modo túnel lo
achata Cloudflare.

Pasos completos, con el orden correcto (host → túnel → DNS → secretos → despliegue):
[`docs/runbooks/alta-servidor-winopo.md`](docs/runbooks/alta-servidor-winopo.md).
Comprobar antes de desplegar:

```bash
dig +short winopo.es
dig +short app.winopo.es
```

En modo túnel, hasta que `cloudflared` esté conectado el dominio responde `error 1033`: es lo esperado, no
un fallo del DNS.

## 2. Secretos

El `.env` vive **solo en el servidor** (`/srv/winopo/.env`), con permisos `600`, y nunca entra en git
(está en `.gitignore`; `.env.example` es la plantilla sin valores).

```bash
cd /srv/winopo
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
sudo mkdir -p /srv/winopo && sudo chown "$USER" /srv/winopo
git clone https://github.com/systemavworks/winopo.git /srv/winopo
cd /srv/winopo

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
cd /srv/winopo
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
cd /srv/winopo
git log --oneline -5
git checkout <commit-anterior>
infra/scripts/deploy.sh prod
```

Límite importante: **las migraciones no se revierten solas**. Si el commit anterior no conocía una
columna nueva, la base la conserva y no molesta; si el commit anterior esperaba un esquema que ya
cambió, hay que restaurar copia (§8). Por eso las migraciones se escriben compatibles hacia atrás
cuando se pueda (añadir columna con `default`, no renombrar en el mismo paso que se usa).

## 6. El landing de `winopo.es`

Es HTML estático en `landing/index.html`. **No requiere build ni reinicio de la aplicación.**

- En el servidor, Caddy lo sirve desde `/srv/landing` (volumen de solo lectura del repositorio).
- Cambiar el landing = `git pull` y, como mucho, `docker compose ... exec caddy caddy reload --config /etc/caddy/Caddyfile`.
- Está pensado para no necesitar nada más: sin JavaScript, sin fuentes externas, sin cookies, sin
  analítica. Por eso no hay banner de consentimiento (no hay nada que consentir) y la CSP del apex
  bloquea scripts (`script-src 'none'`).
- La marca va aparte: `landing/assets/` contiene el emblema, el favicon, el icono de iOS y la tarjeta
  para redes. Salen del logo original con `python3 tools/marca/generar_marca.py`, que recorta, quita el
  fondo crema y genera cada tamaño. **Si cambia el logo, se regeneran; no se editan a mano.** Suman
  unos 190 KB, servidos desde el mismo dominio (sin CDN ni terceros).

Detalles que no hay que olvidar al publicarlo:

1. `landing/index.html` lleva `meta robots="noindex, nofollow"` mientras sea una versión de prueba.
   **Quitar esas dos líneas el día del lanzamiento**, o el dominio no aparecerá en Google.
2. El correo de contacto es `hola@winopo.es`: hay que crear el buzón o el alias antes de publicar.
3. Las llamadas a la acción apuntan a `https://app.winopo.es/login`. Si cambia el subdominio, se
   cambia en `landing/index.html` y en `infra/caddy/Caddyfile`.
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
cd /srv/winopo
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
cd /srv/winopo
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


