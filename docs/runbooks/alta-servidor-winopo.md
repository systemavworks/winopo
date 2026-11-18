# Runbook · Alta de WinOpo en la caja compartida (CAX11)

**Estado a 18-nov-2026: WinOpo no está publicado y `winopo.es` no resuelve.** La zona de Cloudflare
apunta a registros muertos (`*.winopo.es` y `www` → CNAME `winopo.pages.dev`, que ya no existe;
Cloudflare responde `error code: 1014`) y el apex no tiene registro. Cualquier visita falla hoy.

Este runbook publica WinOpo **en la misma caja que Komanda**, aislado y sin tocar su borde. Se ejecuta
una vez; después se despliega con el workflow (§6).

## 0. Dónde vive cada cosa

| Host | Dónde | Estado |
|---|---|---|
| Komanda | esta caja, `/opt/komanda`, Caddy en 80/443 | Publicado · **no se toca** |
| `app.billka.es` | Cloudflare Workers (`billka-app`) | Publicado · no se toca |
| `api.billka.es` + su Postgres | esta caja, previsto en `billka/docs/runbook/despliegue-en-caja-compartida.md` | **Propuesta, sin ejecutar** |
| `winopo.es`, `app.winopo.es` | esta caja, `/srv/winopo`, sin puertos, entrada por Cloudflare Tunnel | Este runbook |

Medido el 18-nov-2026 con `free -m`, `df -h /`, `docker stats` y `uptime`:

| Medida | Valor |
|---|---|
| RAM | 3 796 MiB total · **2 753 disponibles** · swap 2 GB (79 MiB usados) |
| Disco | 38 G · **27 G libres (27 % usado)** |
| Carga | 0.14 en 2 vCPU, 13 días de uptime |
| Komanda | caddy 23 MiB · core 203 · web 97 · postgres 57 → **≈ 380 MiB** |
| `/srv` | vacío: WinOpo es el primer ocupante |

**Criterio de corte**, el mismo del runbook de Billka (ADR `B0009`), antes de arrancar:

| Medida | Umbral | Si no se cumple |
|---|---|---|
| `available` en `free -m` | **≥ 1 600 MiB** | No entra: se separa la caja (§8) |
| Disco libre en `/` | **≥ 8 GB** | No entra: `pgdata` y dumps crecen |
| Suma de `mem_limit` de WinOpo | ≤ RAM disponible | Bajar límites o separar caja |

Los `mem_limit` del compose suman **2 208 MiB** (512 db + 640 core + 512 worker + 320 web + 96 caddy
+ 128 cloudflared) y en uso real se espera ~800 MiB. Son válvulas anti-fuga, no reservas: con
2 753 MiB disponibles no pueden coincidir todos en su techo sin swap. Si `available` baja de 800 MiB
de forma recurrente, se separa la caja (§8).

### Las cinco cosas que no se comparten con Komanda

| Recurso | WinOpo | Por qué |
|---|---|---|
| Proyecto Compose | `winopo` → red `winopo_default` | Ningún servicio de Komanda está en esa red |
| Base de datos | contenedor `winopo-db-1` + volumen `winopo_prod-db` | Sin credenciales ni tablas cruzadas |
| Usuarios de BD | `winopo` (administra y migra) y `winopo_app` (sirve, sin `BYPASSRLS`) | La RLS solo protege si la app no es superusuario |
| Puertos | **ninguno publicado**; `cloudflared` entra a `caddy:80` por la red interna | 80/443 son del Caddy de Komanda |
| Backups | `pg_dump` propio, fuera de la caja | Un dump en el mismo disco no es un backup |

Lo que **sí** se comparte, y hay que decirlo: kernel, disco, IP y `root`. Por eso los límites por
contenedor, los backups off-box y los disparadores de separación del §8.

Los datos de la máquina (IP, ID de Hetzner) viven en `privado/infra-real.md`, que está en `.gitignore`.
Nunca en este repositorio, que es público.

## 1. Preparar el host (sin tocar nada de Komanda)

```bash
# como root, en la caja
adduser --disabled-password --gecos "" winopo
usermod -aG sudo winopo
usermod -aG docker winopo          # ver la nota de abajo antes de hacerlo

install -d -m 700 -o winopo -g winopo /home/winopo/.ssh
# pegar aquí la clave pública de despliegue (no la personal) en authorized_keys, 600 y dueño winopo
```

`docker` equivale a `root`: quien esté en ese grupo puede montar `/` dentro de un contenedor. Aquí se
acepta porque `winopo` es un usuario de despliegue al que solo entra el workflow con su clave dedicada.
Si se quiere lo estricto, se le quita el grupo y se arranca con una unidad de systemd `User=root` y
`ExecStart=` acotado, como hace Billka; entonces el despliegue por SSH necesita `sudoers` para tres
comandos concretos.

**No se reconfigura** `ufw`, `fail2ban` ni `sshd`: ya están endurecidos por Komanda. Se comprueba:

```bash
sudo ufw status verbose            # 22 (idealmente solo desde tu IP), 80, 443
sudo fail2ban-client status sshd   # maxretry=5, bantime=2h
```

⚠️ **Regla de oro al entrar por SSH**: `IdentitiesOnly yes` y una sola clave (`-i`). Si el agente ofrece
varias claves, cada una cuenta como intento, `MaxAuthTries 3` corta la conexión y fail2ban banea la IP.
El incidente real y cómo se sale de él están en `komanda/docs/RUNBOOK.md` §3 y §4.

El swap de 2 GB que ya tiene la caja no arregla un OOM, pero evita que el kernel elija víctima al azar.

## 2. Código y secretos en `/srv/winopo`

```bash
sudo install -d -o winopo -g winopo -m 750 /srv/winopo
sudo -u winopo -H ssh-keygen -t ed25519 -C "deploy@winopo" -f /home/winopo/.ssh/winopo_deploy -N ''
sudo -u winopo cat /home/winopo/.ssh/winopo_deploy.pub
# -> Settings > Deploy keys del repositorio, SOLO LECTURA
```

```bash
sudo -u winopo -H git clone git@github.com:systemavworks/winopo.git /srv/winopo
cd /srv/winopo
# El workflow hace `git fetch` después: la clave tiene que estar configurada en el repo, no
# solo en el `clone`. Esto es lo que evita el fallo de credenciales en el segundo despliegue.
git config core.sshCommand "ssh -i /home/winopo/.ssh/winopo_deploy -o IdentitiesOnly=yes"
git fetch --dry-run origin && echo "fetch OK"
```

```bash
cp .env.example .env && chmod 600 .env
# Hex, no base64, en las contraseñas de base: el DATABASE_URL las lleva en la cadena de consulta
# y `+ / =` obligarían a escaparlas.
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|"         .env
sed -i "s|^POSTGRES_APP_PASSWORD=.*|POSTGRES_APP_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|^SESSION_SECRET=.*|SESSION_SECRET=$(openssl rand -base64 48 | tr -d '\n')|" .env
sed -i "s|^TUNNEL_TOKEN=.*|TUNNEL_TOKEN=<pegar el token del túnel>|"                 .env
```

El `DATABASE_URL` del `.env` es para desarrollo local: en el servidor lo compone el
`docker-compose.prod.yml` con `POSTGRES_APP_PASSWORD`. Obligatorias para que `core` arranque
(`core/.../config/Settings.kt`): **`DATABASE_URL`** (la del compose) y **`SESSION_SECRET`** (≥ 32
caracteres). R2, IA, TTS, Stripe y SMTP se rellenan cuando exista cada cuenta; sin ellas arranca igual.

## 3. El túnel: publicar sin tocar el 80/443 de Komanda

Un segundo Caddy publicando 80/443 no puede: el puerto ya es del proxy de Komanda y el intento deja
los dos productos caídos. Cloudflare Tunnel no abre puertos, no necesita certificado de origen ni
reglas nuevas de firewall, y el TLS lo termina el edge.

1. Zero Trust → **Networks → Tunnels → Create a tunnel** → tipo `cloudflared` → nombre `winopo-cax11`.
2. Copiar el token y pegarlo en `TUNNEL_TOKEN` del `.env` (§2).
3. En el túnel → **Public hostname**, tres entradas al **mismo** servicio:

| Hostname | Servicio |
|---|---|
| `winopo.es` | `HTTP` → `caddy:80` |
| `www.winopo.es` | `HTTP` → `caddy:80` |
| `app.winopo.es` | `HTTP` → `caddy:80` |

`caddy` resuelve por la red `winopo_default` porque `cloudflared` y `caddy` van en el mismo proyecto
Compose. El túnel crea los CNAME en *proxied* y el apex por *CNAME flattening*: **no hace falta
`Origin CA`, ni modo "Full (strict)", ni abrir el 80 al mundo**.

Si el token se filtra: rotarlo en el panel y actualizar `.env` (`docker compose up -d cloudflared`).
No se guarda en git ni se pega en un chat.

## 4. DNS (Cloudflare)

El token `API_TOKEN_CLOUDFLARE` del `.env` solo tiene `Zone.DNS:Edit`: suficiente para limpiar, no para
crear los CNAME (los crea el túnel). El script simula por defecto:

```bash
tools/dns-cloudflare.sh --tunnel            # enseña qué borraría
tools/dns-cloudflare.sh --tunnel --apply    # borra restos muertos de Pages
```

Deja intactos el `TXT` del SPF, los `MX` y cualquier registro que no apunte a `pages.dev`. El proyecto
Pages muerto no se puede borrar desde aquí (el token no tiene permiso de Pages): se hace en el panel,
y no estorba.

Comprobar cuando el túnel esté conectado:

```bash
dig +short winopo.es @1.1.1.1       # CNAME a <uuid>.cfargotunnel.com, achatado
```

`staging.winopo.es` no se publica aquí: staging **publica 80/443** y en esta caja eso es de Komanda
(`infra/scripts/deploy.sh` aborta si detecta esos puertos ocupados). Staging va en el portátil o en una
caja propia.

## 5. Primer despliegue

```bash
cd /srv/winopo
infra/scripts/deploy.sh prod
```

Cinco pasos, y para en el primero que falle: build de las imágenes (se construyen **en la caja**, ARM64,
no hay registry), rol `winopo_app` sin `BYPASSRLS`, migraciones en orden, arranque y estado. Antes de
construir comprueba que existe `TUNNEL_TOKEN` y, al terminar, que `/healthz` responde a través de
`caddy` (el camino real del túnel, porque el puerto no está publicado en el host).

El primer build en 2 vCPU es lento (Gradle + `npm ci`) y **comparte CPU con Komanda**, que está sirviendo
clientes. Se baja la prioridad y se vigila:

```bash
nice -n 19 ionice -c3 infra/scripts/deploy.sh prod
# en otra terminal
docker stats --no-stream
free -m
```

Si Komanda empieza a responder lento, se para el build y se repite en una ventana de menos tráfico. Los
despliegues siguientes reutilizan capas de Docker y tardan mucho menos.

## 6. Conectar el repositorio con el servidor (despliegue manual desde GitHub)

El workflow [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) despliega un commit
concreto por SSH. Es **manual a propósito** (`workflow_dispatch`): recrea contenedores y hay unos
segundos de 502 en `app.winopo.es`.

Secretos en *Settings > Secrets and variables > Actions*:

| Secreto | Valor |
|---|---|
| `SSH_HOST` | IP de la caja |
| `SSH_USER` | `winopo` |
| `SSH_KEY` | clave privada dedicada a despliegues (ed25519) |
| `SSH_KNOWN_HOSTS` | `ssh-keyscan -H <IP>` ejecutado desde tu máquina |
| `DEPLOY_PATH` | `/srv/winopo` |

Después: *Actions > Desplegar > Run workflow*, con `entorno` y `ref` (rama o etiqueta). El workflow hace
`git fetch` + `git checkout --detach <ref>`: despliega el commit pedido, no lo que haya en el directorio.
`.env` no está en git, así que sobrevive al checkout. Si el `fetch` falla por credenciales, falta el
`core.sshCommand` del §2.

Opcional: crear los *Environments* `prod` y `staging` con revisor obligatorio; el job ya declara
`environment:`, así que la aprobación se pide sola.

## 7. Verificación

```bash
# Desde tu máquina
dig +short winopo.es @1.1.1.1
curl -sS -o /dev/null -w '%{http_code}\n' https://winopo.es
curl -sS -o /dev/null -w '%{http_code}\n' https://app.winopo.es/healthz
curl -sSI https://winopo.es | grep -iE 'strict-transport-security|^server'
```

Esperado: CNAME a `cfargotunnel.com`, `200` en el landing y en `/healthz`, HSTS presente y
`server: cloudflare`.

```bash
# En la caja: aislamiento y convivencia
docker compose --env-file .env -f infra/docker-compose.prod.yml ps   # 6 arriba, ningún puerto del host
docker network inspect winopo_default --format '{{range .Containers}}{{.Name}} {{end}}'
                                                                     # solo contenedores winopo_*
ss -tlnp | grep -E ':(80|443)\b'                                     # solo el docker-proxy de Komanda
ss -tlnp | grep 5432                                                 # sin resultados
docker compose --env-file .env -f infra/docker-compose.prod.yml logs --tail=20 cloudflared
                                                                     # "Registered tunnel connection" x4
free -m                                                              # available sigue > 1 600 MiB
```

Y que el vecino siga en pie: abrir el panel de Komanda y comprobar que responde. El punto de partida
medido (380 MiB de Komanda, 2 753 MiB disponibles) deja margen de sobra para ~800 MiB de WinOpo; si
`available` cae por debajo de 1 600 MiB con el stack en reposo, hay una fuga y se mira `docker stats`.

## 8. Cuándo esta caja deja de servir

Se cumple **cualquiera** de estos y WinOpo se muda a una caja propia (CAX21, 8 GB):

| Disparador | Cómo se detecta |
|---|---|
| Primer **cliente de pago** | Decisión comercial, no técnica |
| `available` < 800 MiB de forma recurrente | `free -m` |
| Disco > 70 % o `pgdata` creciendo sin techo | `df -h /`, `du -sh` del volumen |
| CPU sostenida > 60 % entre los dos productos | `docker stats`, `uptime` |
| Ventanas de mantenimiento independientes o HA | Operación, no tecnología |
| Incidente de seguridad o aislamiento insuficiente | Post-mortem |

La mudanza no cambia el dominio: `WINOPO_EDGE=propia infra/scripts/deploy.sh prod` añade
`docker-compose.caja-propia.yml` (Caddy publica 80/443 y saca el certificado por HTTP-01), se apuntan
los registros con `tools/dns-cloudflare.sh --ip <nueva IP>` y se borran los hostnames públicos del túnel.
`pg_dump` cifrado → restaurar → arrancar → cambiar DNS → apagar el stack viejo.

## 9. Lo que este runbook **no** hace

| Tema | Sigue pendiente |
|---|---|
| Copia programada | script listo, `cron`/temporizador sin configurar → [`backup-restauracion.md`](backup-restauracion.md) |
| Monitorización | nada: ni disco, ni memoria, ni caída, ni del túnel |
| CI/CD automático en cada push | no: el despliegue es manual, a propósito |
| Alta de preparadores | manual, por `psql` |
| R2, Stripe, SMTP, IA | variables vacías hasta que existan las cuentas |
| Proyecto Pages borrado | su rastro solo se limpia en el panel; el token de DNS no tiene permiso de Pages |
| Límite de tasa / WAF en el edge | no configurado; se puede añadir sobre `winopo.es` sin tocar la caja |
| `vinopo.es`, aviso legal, precio (D9) | decisiones de negocio, no de infraestructura |

## 10. Si algo falla

| Síntoma | Dónde mirar | Causa típica |
|---|---|---|
| `error 1033` (túnel sin conexión) | `logs cloudflared` | token inválido o `cloudflared` caído |
| `error 1014` en el dominio | DNS | queda algún CNAME a `*.pages.dev`; repetir §4 |
| `502` en `app.winopo.es` | `logs caddy`, `ps` | `core` o `web` caídos o reiniciándose |
| `502` en el túnel con `caddy` sano | hostname público mal declarado | el servicio debe ser `HTTP caddy:80`, no un puerto del host |
| `cloudflared` en bucle | `logs cloudflared` | `TUNNEL_TOKEN` vacío o revocado |
| `core` en bucle de reinicio | `logs core` | falta `DATABASE_URL` o `SESSION_SECRET` < 32 caracteres |
| Caddy no resuelve `core`/`web` | `docker compose ps` | proyecto Compose distinto al de la red (`name: winopo`) |
| Login correcto pero sin acceso | `psql` sobre `membership` | `estado` distinto de `activo` |
| Komanda lento tras el despliegue | `free -m`, `docker stats` | build sin `nice`, o techos coincidiendo: §8 |
