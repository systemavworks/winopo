# Runbook · Alta del servidor de WinOpo

**Estado a 18-nov-2026: WinOpo no está publicado y `winopo.es` no resuelve.**
La zona de Cloudflare apunta a registros muertos (`*.winopo.es` y `www` → CNAME `winopo.pages.dev`,
que ya no existe; Cloudflare responde `error code: 1014`) y el apex no tiene registro `A`.
No es un problema de configuración menor: cualquier visita al dominio falla hoy.

Este runbook convierte una caja vacía en el servidor de producción. Se ejecuta una vez.

## 0. Qué caja, y qué no

- **CAX21** (4 vCPU · 8 GB · 80 GB, ARM64), Ubuntu 24.04, región `fsn1`. Es la recomendación de
  [`docs/infra-servidor.md`](../infra-servidor.md) §3.
- **No** la caja actual (la de Komanda): aloja Komanda, su Caddy ya ocupa 80/443 y quedan 2,7 GB de RAM.
  Meter WinOpo ahí es compartir memoria y borde con otro producto; el propio documento lo descarta.
- Los datos de la máquina (IP, ID) van a `privado/infra-real.md`, que está en `.gitignore`. Nunca aquí.

## 1. Endurecer la caja (antes de abrir nada)

```bash
# como root, recién creada
adduser --disabled-password --gecos "" winopo
mkdir -p /home/winopo/.ssh && chmod 700 /home/winopo/.ssh
# pegar la clave pública de despliegue (no la personal) y dejarla en 600
usermod -aG sudo winopo
apt update && apt upgrade -y

# Docker + compose v2
curl -fsSL https://get.docker.com | sh
usermod -aG docker winopo

# Solo estos puertos. 5432, 8080 y 3000 no se publican nunca.
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable

# Fuerza bruta y parches
apt install -y fail2ban unattended-upgrades
printf '[sshd]\nmaxretry = 3\nbantime = 24h\n' > /etc/fail2ban/jail.d/sshd.local
systemctl enable --now fail2ban
```

En `/etc/ssh/sshd_config`: `PermitRootLogin no`, `PasswordAuthentication no`.
**Antes** de recargar sshd, comprobar en otra sesión que la clave de `winopo` entra.

Reloj en hora (`timedatectl`): un desfase rompe TLS y las fechas de sesión.

## 2. DNS (Cloudflare)

El token `API_TOKEN_CLOUDFLARE` del `.env` solo tiene `Zone.DNS:Edit`; basta para esto.
El script es idempotente y **simula por defecto**:

```bash
tools/dns-cloudflare.sh --ip <IP_DE_LA_CAJA>            # enseña qué cambiaría
tools/dns-cloudflare.sh --ip <IP_DE_LA_CAJA> --apply    # escribe
```

Qué deja:

| Nombre | Tipo | Valor | Proxied |
|---|---|---|---|
| `winopo.es` | A | IP de la caja | no (gris) |
| `www.winopo.es` | CNAME | `winopo.es` | no |
| `app.winopo.es` | A | IP de la caja | no |

Además **borra** `*.winopo.es → winopo.pages.dev` (el comodín que hoy rompe todos los subdominios,
incluido `mail.`) y no toca el `TXT` del SPF ni ningún `MX`.

Gris y no naranja porque **Caddy termina el TLS** y saca el certificado con HTTP-01. En naranja hay dos
TLS por medio y Cloudflare exige un certificado de origen (Origin CA) y modo "Full (strict)";
si algún día se quiere así, se cambia en [`DEPLOY.md`](../../DEPLOY.md) §10, no aquí.

Comprobar antes de seguir (Let's Encrypt necesita que ya resuelva):

```bash
dig +short winopo.es @1.1.1.1
dig +short app.winopo.es @1.1.1.1
```

`staging.winopo.es` solo cuando haya entorno de staging: `--staging` añade el registro.

## 3. Repositorio y secretos en el servidor

```bash
sudo mkdir -p /srv && sudo chown winopo:winopo /srv
# deploy key de SOLO LECTURA (Settings > Deploy keys del repositorio, sin "write access")
ssh-keygen -t ed25519 -C "deploy@winopo" -f ~/.ssh/winopo_deploy -N ''
cat ~/.ssh/winopo_deploy.pub

GIT_SSH_COMMAND='ssh -i ~/.ssh/winopo_deploy -o IdentitiesOnly=yes' \
  git clone git@github.com:systemavworks/winopo.git /srv/winopo

# La clave se fija en la configuración del repositorio: si solo se pasa al clonar, el
# `git fetch` del workflow se queda sin credenciales y el despliegue falla por SSH.
cd /srv/winopo
git config core.sshCommand "ssh -i $HOME/.ssh/winopo_deploy -o IdentitiesOnly=yes"
git fetch --dry-run origin
```

```bash
cd /srv/winopo
cp .env.example .env && chmod 600 .env
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
echo "POSTGRES_APP_PASSWORD=$(openssl rand -hex 24)"
echo "SESSION_SECRET=$(openssl rand -base64 48)"
```

Editar `.env`: `APP_ENV=prod`, `APP_BASE_URL=https://app.winopo.es`, `DATABASE_URL` con la contraseña
de aplicación, y los valores generados. Hex y no base64 en las contraseñas de base: el `DATABASE_URL`
las lleva en la cadena de consulta y `+ / =` obligan a escaparlas.

Obligatorias para que `core` arranque (`core/.../config/Settings.kt`): **`DATABASE_URL`** y
**`SESSION_SECRET`** (mínimo 32 caracteres). El resto (R2, IA, TTS, Stripe, SMTP) se rellena cuando se
active cada función; sin ellas la plataforma arranca igual.

## 4. Primer despliegue

```bash
cd /srv/winopo
infra/scripts/deploy.sh prod
```

Hace cinco cosas y para en la primera que falle: build de las imágenes (se construyen **en la caja**,
ARM64, no hay registry), rol `winopo_app` sin `BYPASSRLS`, migraciones en orden, arranque y `ps`.
El primer build en 2 vCPU es lento (Gradle + `npm ci`); los siguientes reutilizan capas.

## 5. Conectar el repositorio con el servidor (despliegue manual desde GitHub)

El workflow [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) despliega un commit
concreto por SSH. Es **manual a propósito** (`workflow_dispatch`): recrea contenedores y hay unos
segundos de 502.

Secretos en *Settings > Secrets and variables > Actions*:

| Secreto | Valor |
|---|---|
| `SSH_HOST` | IP de la caja |
| `SSH_USER` | `winopo` |
| `SSH_KEY` | clave privada dedicada a despliegues (ed25519) |
| `SSH_KNOWN_HOSTS` | `ssh-keyscan -H <IP>` ejecutado desde tu máquina |
| `DEPLOY_PATH` | `/srv/winopo` |

Después: *Actions > Desplegar > Run workflow*, con `entorno` y `ref` (rama o etiqueta).
El workflow hace `git fetch` + `git checkout --detach <ref>`: despliega el commit pedido, no lo que
haya en el directorio. `.env` no está en git, así que sobrevive al checkout.

Opcional: crear los *Environments* `prod` y `staging` con revisor obligatorio; el job ya declara
`environment:`, así que la aprobación se pide sola.

## 6. Verificación

```bash
dig +short winopo.es @1.1.1.1
curl -sS -o /dev/null -w '%{http_code}\n' https://winopo.es
curl -sS -o /dev/null -w '%{http_code}\n' https://app.winopo.es/healthz
curl -sSI https://winopo.es | grep -i strict-transport-security
docker compose -f infra/docker-compose.prod.yml ps
```

Esperado: `200` en el landing, `200` en `/healthz`, cabecera HSTS presente y los cinco contenedores
arriba (`db`, `core`, `worker`, `web`, `caddy`).

## 7. Lo que este runbook **no** hace

| Tema | Sigue pendiente |
|---|---|
| Copia programada | script listo, `cron`/temporizador sin configurar → [`backup-restauracion.md`](backup-restauracion.md) |
| Monitorización | nada: ni disco, ni memoria, ni caída |
| CI/CD automático en cada push | no: el despliegue es manual, a propósito |
| Alta de preparadores | manual, por `psql` |
| R2, Stripe, SMTP, IA | variables vacías hasta que existan las cuentas |
| Proyecto Pages borrado | su rastro solo se limpia en el panel; el token de DNS no tiene permiso de Pages |
| `vinopo.es`, aviso legal, precio (D9) | decisiones de negocio, no de infraestructura |

## 8. Si algo falla

| Síntoma | Dónde mirar | Causa típica |
|---|---|---|
| `error 1014` en el dominio | DNS | queda algún CNAME a `*.pages.dev`; repetir el script del §2 |
| Caddy no saca certificado | `logs caddy`, `dig` | DNS sin resolver o puerto 80 cerrado |
| 502 en `app.winopo.es` | `logs caddy`, `ps` | `core` o `web` caídos o reiniciándose |
| `core` en bucle de reinicio | `logs core` | falta `DATABASE_URL` o `SESSION_SECRET` < 32 caracteres |
| Login correcto pero sin acceso | `psql` sobre `membership` | `estado` distinto de `activo` |
