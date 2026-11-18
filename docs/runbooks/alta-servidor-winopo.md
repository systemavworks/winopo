# Runbook · Alta de WinOpo en la caja compartida (CAX11)

**Estado a 18-nov-2026: publicado y en servicio.** `winopo.es` y `www.winopo.es` los sirve el Worker de
Cloudflare (`ok` verificado byte a byte contra `landing/index.html`); `app.winopo.es` resuelve por el edge
y entra por el túnel `winopo-cax11` a la caja compartida: proyecto Compose `winopo`, seis contenedores y
ningún puerto publicado. Medido desde fuera ese día: `200` en `/` (18 296 b), `200` en `/login`, `200` en
`/healthz`, HSTS presente, `server: cloudflare` y cuatro conexiones del túnel.

Queda fuera de este runbook: los secretos de SSH del workflow «Desplegar» (los despliegues de hoy se hacen
a mano por SSH) y las cuentas de R2, Stripe, IA y SMTP, que siguen vacías.

Este runbook publica WinOpo **en la misma caja que Komanda**, aislado y sin tocar su borde. Se ejecuta
una vez; después se despliega por SSH con `infra/scripts/deploy.sh` (§5) o con el workflow «Desplegar»
cuando tenga sus secretos (§6).

## 0. Dónde vive cada cosa

| Host | Dónde | Estado |
|---|---|---|
| Komanda | esta caja, `/opt/komanda`, Caddy en 80/443 | Publicado · **no se toca** |
| `app.billka.es` | Cloudflare Workers (`billka-app`) | Publicado · no se toca |
| `api.billka.es` + su Postgres | esta caja, previsto en `billka/docs/runbook/despliegue-en-caja-compartida.md` | **Propuesta, sin ejecutar** |
| `winopo.es` + `www` | Cloudflare Workers (`winopo`), `landing/` del repositorio | **Publicado** |
| `app.winopo.es` | esta caja, `/opt/winopo`, sin puertos, entrada por Cloudflare Tunnel | **Publicado** · este runbook |

Medido el 18-nov-2026 con `free -m`, `df -h /`, `docker stats` y `uptime`:

| Medida | Valor |
|---|---|
| RAM | 3 796 MiB total · **2 753 disponibles** · swap 2 GB (79 MiB usados) |
| Disco | 38 G · **27 G libres (27 % usado)** |
| Carga | 0.14 en 2 vCPU, 13 días de uptime |
| Komanda | caddy 23 MiB · core 203 · web 97 · postgres 57 → **≈ 380 MiB** |
| `/opt` | `komanda` (ya estaba) y `winopo`: usuario propio desde el 18-nov-2026 |

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

En la caja real (18-nov-2026) el usuario `winopo` **ya existía** (uid 1001, ya en el grupo `docker`): no
hubo que crearlo. El primer clon se hizo con el usuario `komanda` y se pasó a `winopo` el mismo día
(`chown -R winopo:winopo /opt/winopo` + clave propia) para que la clave de despliegue de WinOpo no quedara
en el home de Komanda, junto a su `.env`.

Y ojo con esto: el `sshd` de la caja está endurecido por Komanda con `AllowUsers komanda`
(`/etc/ssh/sshd_config.d/99-komanda.conf`). Sin añadir `winopo` ahí, la clave no sirve para nada: el login
responde `Permission denied (publickey)` aunque `authorized_keys` esté perfecto. El 18-nov-2026 se dejó en
`AllowUsers komanda winopo`, con copia previa en `99-komanda.conf.bak-winopo-20261118`, `sshd -t` antes de
recargar y `systemctl reload ssh` (recargar no corta sesiones abiertas). Si Komanda reescribe ese fichero,
hay que volver a añadirlo.

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

## 2. Código y secretos en `/opt/winopo`

```bash
sudo install -d -o winopo -g winopo -m 750 /opt/winopo
sudo -u winopo -H ssh-keygen -t ed25519 -C "deploy@winopo" -f /home/winopo/.ssh/winopo_deploy -N ''
sudo -u winopo cat /home/winopo/.ssh/winopo_deploy.pub
# -> Settings > Deploy keys del repositorio, SOLO LECTURA
```

```bash
sudo -u winopo -H git clone git@github.com:systemavworks/winopo.git /opt/winopo
cd /opt/winopo
# El workflow hace `git fetch` después: la clave tiene que estar configurada en el repo, no
# solo en el `clone`. Esto es lo que evita el fallo de credenciales en el segundo despliegue.
git config core.sshCommand "ssh -i /home/winopo/.ssh/winopo_deploy -o IdentitiesOnly=yes"
git fetch --dry-run origin && echo "fetch OK"
```

```bash
# Sin known_hosts, el primer `git fetch` muere con «Host key verification failed». Se fija la huella
# que publica GitHub en vez de aceptar la primera que llegue:
sudo -u winopo ssh-keyscan -t ed25519 github.com > /tmp/gh_ed
ssh-keygen -lf /tmp/gh_ed     # tiene que imprimir SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
sudo install -o winopo -g winopo -m 600 /tmp/gh_ed /home/winopo/.ssh/known_hosts
```

La misma clave pública va en *Settings > Deploy keys* (solo lectura, para `git fetch`) y en
`/home/winopo/.ssh/authorized_keys` (para que el workflow entre por SSH como `winopo`).

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
3. En el túnel → **Public hostname**, una entrada (el landing **no** va por aquí: lo sirve el Worker):

| Hostname | Servicio |
|---|---|
| `app.winopo.es` | `HTTP` → `caddy:80` |

`caddy` resuelve por la red `winopo_default` porque `cloudflared` y `caddy` van en el mismo proyecto
Compose. El túnel crea el CNAME en *proxied*: **no hace falta `Origin CA`, ni modo "Full (strict)", ni
abrir el 80 al mundo**.

**Hecho el 18-nov-2026**: túnel `winopo-cax11`, id `b2690a74-b65b-4909-9f4b-82ad29b7693c`, *remotely
managed* (`config_src: cloudflare`), con ingress `app.winopo.es → http://caddy:80` y `http_status:404` de
reserva. Se creó con la sesión OAuth de `wrangler` (`npx wrangler login`) porque `API_TOKEN_CLOUDFLARE`
solo tiene `Cloudflare Tunnel: Read`: con él `GET /cfd_tunnel` responde, pero `POST /cfd_tunnel` devuelve
`10000 Authentication error` y `PUT .../configurations` devuelve `1001 Not authorized`. Alternativas: ese
mismo `wrangler` logueado, o un token con `Account → Cloudflare Tunnel → Edit` (el permiso `Read` y
`Zero Trust → Edit` **no** lo incluyen).

Si el token se filtra: rotarlo en el panel y actualizar `.env`, y recrear solo el conector
(`docker compose --env-file .env -f infra/docker-compose.prod.yml up -d cloudflared`).
No se guarda en git ni se pega en un chat.

Si hay que reinstalar y el token no está a mano, donde se vuelve a ver es el panel: Zero Trust →
Networks → Tunnels → `winopo-cax11` → **Configure**, y en el bloque del conector está el `--token eyJ…`.
Por API **no** se puede con el token del repositorio: `GET /accounts/<cuenta>/cfd_tunnel/<uuid>/token`
responde `1001 Not authorized`, porque leer el token del conector exige `Cloudflare Tunnel → Edit`, que
se dejó fuera a propósito. Con un token que sí lo tenga, ese `GET` devuelve una sola cadena de 240
caracteres que empieza por `eyJ`; si sale `null` o un error, no es el token.

Por eso, además del `.env` del servidor (con su copia `.env.bak-…` al lado), conviene tener el
`TUNNEL_TOKEN` en el gestor de contraseñas del equipo: es el único valor del despliegue que no se puede
reconstruir sin entrar al panel.

En `/opt/winopo/.env` van **solo esas cuatro claves** (`POSTGRES_PASSWORD`, `POSTGRES_APP_PASSWORD`,
`SESSION_SECRET`, `TUNNEL_TOKEN`): el resto —dominios, `APP_ENV=prod`, `DATABASE_URL`— lo pone el
`docker-compose.prod.yml`. Ni una credencial de Komanda. Antes de desplegar conviene mirar que el
fichero no tenga sorpresas (espacios alrededor del `=`, `\r`, claves repetidas o restos de un pegado
fallido), sin enseñar los valores:

```bash
sudo awk -F= '{printf "%-22s %d chars\n", $1, length($2)}' /opt/winopo/.env
```

Y el detalle que cuesta un rato: el `.env` está en la **raíz** del repositorio y los compose en `infra/`,
así que `docker compose -f infra/docker-compose.prod.yml …` **no** lo lee (Compose busca el `.env` junto
al fichero `-f`) y falla con `required variable POSTGRES_PASSWORD is missing a value` aunque el fichero
esté perfecto. Siempre con `--env-file .env`, que es lo que hace `deploy.sh`.

## 4. DNS (Cloudflare)

Hay dos mitades y las gestiona gente distinta:

| Nombre | Tipo | Valor | Quién lo mantiene |
|---|---|---|---|
| `winopo.es` | AAAA proxied | `100::` | Worker `winopo` (`custom_domain` en `wrangler.jsonc`) |
| `www.winopo.es` | AAAA proxied | `100::` | Worker `winopo` (`custom_domain` en `wrangler.jsonc`) |
| `app.winopo.es` | CNAME proxied | `b2690a74-b65b-4909-9f4b-82ad29b7693c.cfargotunnel.com` | este runbook, vía túnel |

**Aplicado el 18-nov-2026** con `API_TOKEN_CLOUDFLARE` (`Zone.DNS:Edit` basta para el CNAME). Antes de
escribirlo se comprobó que el nombre no existía (`NXDOMAIN`, no un 1014): el comodín muerto y los CNAME a
`winopo.pages.dev` ya se habían borrado, y en la cuenta **no queda ningún proyecto Pages `winopo`**.

El apex y `www` **no se tocan a mano**: los crea Cloudflare al atar el custom domain y los mantiene
`tools/deploy-landing.sh` (o el workflow «landing»). Si alguien los reapunta al túnel, la web comercial
deja de servirse.

`API_TOKEN_CLOUDFLARE` del `.env` necesita `Zone.DNS:Edit` sobre `winopo.es` y, para encontrar el túnel por
nombre, `Account → Cloudflare Tunnel → Read`. El script simula por defecto:

```bash
tools/dns-cloudflare.sh --tunnel                      # enseña el cambio
tools/dns-cloudflare.sh --tunnel --apply              # aplica
tools/dns-cloudflare.sh --tunnel --tunnel-id <uuid>   # si el token no puede listar túneles
```

Solo escribe `app.winopo.es`, en CNAME *proxied* a `<uuid>.cfargotunnel.com`. Además borra los restos
muertos de la zona: el comodín `*.winopo.es` y cualquier CNAME a `winopo.pages.dev` (un proyecto que ya no
existe y devolvía `error code: 1014` en todo subdominio). No toca el `TXT` del SPF ni los `MX`, y deja
intacto el `AAAA 100::` del Worker.

Si el túnel todavía no existe, el script sale con **2** y no escribe nada: un CNAME a `cfargotunnel` sin
túnel detrás solo cambia el 1014 por un NXDOMAIN. Crearlo necesita `Account → Cloudflare Tunnel → Edit`,
que este token no tiene: se hace una vez en el panel (§3).

Ojo: el DNS solo no publica `app.winopo.es`. El túnel necesita dentro ese hostname apuntando a
`HTTP caddy:80`; si falta, `cloudflared` contesta 404 aunque el registro esté perfecto.

Comprobar:

```bash
dig +short app.winopo.es @1.1.1.1   # CNAME a <uuid>.cfargotunnel.com, achatado
dig +short winopo.es @1.1.1.1       # IPs del edge: el Worker del landing, no la caja
```

`staging.winopo.es` no se publica aquí: staging **publica 80/443** y en esta caja eso es de Komanda
(`infra/scripts/deploy.sh` aborta si detecta esos puertos ocupados). Staging va en el portátil o en una
caja propia.

## 5. Primer despliegue

```bash
cd /opt/winopo
infra/scripts/deploy.sh prod
```

Cinco pasos, y para en el primero que falle: build de las imágenes (se construyen **en la caja**, ARM64,
no hay registry), rol `winopo_app` sin `BYPASSRLS`, migraciones en orden, arranque y estado. Antes de
construir comprueba que existe `TUNNEL_TOKEN` y, al terminar, que `/healthz` responde a través de
`caddy` (el camino real del túnel, porque el puerto no está publicado en el host).

El primer despliegue del 18-nov-2026 se paró en el paso 2: `up -d db` vuelve en cuanto arranca el
contenedor, no cuando Postgres escucha, y el `psql` del rol moría con `No such file or directory` en el
socket. El script ya espera con `pg_isready` (hasta 60 s) antes de tocar la base.

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
| `DEPLOY_PATH` | `/opt/winopo` |

**Estado real (18-nov-2026): ninguno de estos secretos está todavía en el repositorio**, así que el job
fallaría en «Comprobar secretos». Mientras tanto se despliega a mano por SSH. El usuario `winopo` ya
existe con su clave (`/home/winopo/.ssh/winopo_deploy`), registrada como *deploy key* de solo lectura y en
su `authorized_keys`: falta copiar `SSH_KEY`, `SSH_HOST` y `SSH_KNOWN_HOSTS` cuando se quiera automatizar.

Después: *Actions > Desplegar > Run workflow*, con `entorno` y `ref` (rama o etiqueta). El workflow hace
`git fetch` + `git checkout --detach <ref>`: despliega el commit pedido, no lo que haya en el directorio.
`.env` no está en git, así que sobrevive al checkout. Si el `fetch` falla por credenciales, falta el
`core.sshCommand` del §2.

Opcional: crear los *Environments* `prod` y `staging` con revisor obligatorio; el job ya declara
`environment:`, así que la aprobación se pide sola.

## 7. Verificación

```bash
# Landing: lo sirve Cloudflare, no la caja
tools/deploy-landing.sh --check      # compara index.html y los assets con el repositorio

# Plataforma: lo sirve la caja por el túnel
dig +short app.winopo.es @1.1.1.1
curl -sS -o /dev/null -w '%{http_code}\n' https://app.winopo.es/healthz
curl -sSI https://app.winopo.es/login | grep -iE 'strict-transport-security|^server'
```

Esperado: `LANDING_OK` en el landing (con HSTS, CSP y la redirección de `/login` a `app.winopo.es`),
CNAME a `cfargotunnel.com` en `app`, `200` en `/healthz`, HSTS presente y `server: cloudflare`.

Medido el 18-nov-2026 tras el primer despliegue: `/` `200` (18 296 b, título «WinOpo · preparación de
oposiciones»), `/login` `200`, `/healthz` `{"estado":"ok","servicio":"winopo"}`, `winopo.es` `200`
(35 949 b), `winopo.es/login` `301` a `app.winopo.es/login`, túnel `healthy` con 4 conexiones y `2 571 MiB`
disponibles en la caja con los seis contenedores arriba.

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
| CI/CD automático en cada push | la **plataforma** no (despliegue manual, a propósito); el **landing** sí, vía workflow «landing» |
| Alta de preparadores | manual, por `psql` |
| R2, Stripe, SMTP, IA | variables vacías hasta que existan las cuentas |
| Proyecto Pages `winopo` | **no existe** en la cuenta (comprobado el 18-nov-2026 con `wrangler pages project list`): no hay nada que borrar |
| Workflow «Desplegar» | sin secretos de SSH: hoy se despliega a mano por SSH como `winopo` (§6) |
| Límite de tasa / WAF en el edge | no configurado; se puede añadir sobre `winopo.es` sin tocar la caja |
| `vinopo.es`, aviso legal, precio (D9) | decisiones de negocio, no de infraestructura |

## 10. Si algo falla

| Síntoma | Dónde mirar | Causa típica |
|---|---|---|
| `error 1033` (túnel sin conexión) | `logs cloudflared` | token inválido o `cloudflared` caído |
| `GET /cfd_tunnel/<id>/token` devuelve `null` o `1001` | el token usado | leer el token del conector exige `Tunnel → Edit`, que no tenemos: se copia del panel (§3) |
| `error 1014` en un subdominio | DNS | quedó un CNAME a `*.pages.dev` en ese nombre; repetir §4 |
| `winopo.es` sirve el landing viejo | `tools/deploy-landing.sh --check` | falta desplegar: `make landing-deploy`, o el workflow «landing» falló |
| `winopo.es` sin HSTS ni CSP | `landing/_headers` | el fichero falta o el último deploy no lo subió (`wrangler deploy`) |
| `502` en `app.winopo.es` | `logs caddy`, `ps` | `core` o `web` caídos o reiniciándose |
| `502` en el túnel con `caddy` sano | hostname público mal declarado | el servicio debe ser `HTTP caddy:80`, no un puerto del host |
| `cloudflared` en bucle | `logs cloudflared` | `TUNNEL_TOKEN` vacío o revocado |
| `core` en bucle de reinicio | `logs core` | falta `DATABASE_URL` o `SESSION_SECRET` < 32 caracteres |
| Caddy no resuelve `core`/`web` | `docker compose --env-file .env -f infra/docker-compose.prod.yml ps` | proyecto Compose distinto al de la red (`name: winopo`) |
| `required variable POSTGRES_PASSWORD is missing a value` con el `.env` relleno | el comando | falta `--env-file .env`: Compose busca el `.env` junto al `-f`, no en la raíz |
| Login correcto pero sin acceso | `psql` sobre `membership` | `estado` distinto de `activo` |
| Komanda lento tras el despliegue | `free -m`, `docker stats` | build sin `nice`, o techos coincidiendo: §8 |
| `psql: ... No such file or directory` en el primer despliegue | paso 2/5 | Postgres aún no escuchaba: el script ya espera con `pg_isready` |
| `worker` en «unhealthy» con `worker arrancado` en el log | `docker inspect` | el `HEALTHCHECK` de la imagen sondea 8080 y el perfil `worker` no abre puerto: `healthcheck: disable: true` en el compose |
| `Permission denied (publickey)` al entrar como `winopo` | `sshd_config.d/99-komanda.conf` | falta `winopo` en `AllowUsers`: §1 |
| `Host key verification failed` al hacer `git fetch` como `winopo` | `/home/winopo/.ssh/known_hosts` | falta la huella de `github.com`: §2 |
| `10000 Authentication error` al crear el túnel | `npx wrangler login` | el token del `.env` solo tiene `Cloudflare Tunnel: Read`: §3 |
