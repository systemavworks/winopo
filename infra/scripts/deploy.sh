#!/usr/bin/env bash
# Despliegue: staging y producción separados, bases distintas, misma imagen.
# Se ejecuta DESDE CUALQUIER SITIO; el script se coloca en la raíz del repositorio.
# El .env del servidor no está en git: vive aquí al lado con permisos 600.
#
# Producción vive en la caja compartida con Komanda: el tráfico entra por Cloudflare
# Tunnel y este stack NO publica puertos (ver docs/runbooks/alta-servidor-winopo.md).
# Con WINOPO_EDGE=propia se añade el override de caja dedicada (80/443 + ACME).
set -euo pipefail

ENTORNO="${1:-}"
case "${ENTORNO}" in
  staging) COMPOSE_FILES=(-f infra/docker-compose.staging.yml) ;;
  prod)    COMPOSE_FILES=(-f infra/docker-compose.prod.yml) ;;
  *) echo "uso: deploy.sh staging|prod  [WINOPO_EDGE=propia]"; exit 1 ;;
esac

if [ "${WINOPO_EDGE:-compartida}" = "propia" ]; then
  if [ "$ENTORNO" != "prod" ]; then
    echo "WINOPO_EDGE=propia solo tiene sentido con prod." >&2; exit 1
  fi
  COMPOSE_FILES+=(-f infra/docker-compose.caja-propia.yml)
fi

cd "$(dirname "$0")/../.."

if [ ! -f .env ]; then
  echo "Falta .env en $(pwd). Sin POSTGRES_PASSWORD y SESSION_SECRET no se arranca." >&2
  exit 1
fi

# El .env no se exporta solo: se carga para poder usar POSTGRES_APP_PASSWORD aquí.
set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${POSTGRES_APP_PASSWORD:?falta POSTGRES_APP_PASSWORD en .env}"

# Sin token del túnel, cloudflared arranca y muere en bucle: el stack quedaría arriba pero
# inalcanzable. Se comprueba antes de construir nada.
if [ "$ENTORNO" = "prod" ] && [ "${WINOPO_EDGE:-compartida}" != "propia" ]; then
  : "${TUNNEL_TOKEN:?falta TUNNEL_TOKEN en .env (token del túnel de Cloudflare Zero Trust)}"
fi

# Staging publica 80/443. En la caja compartida eso es el Caddy de Komanda: abortar antes
# de intentarlo es más barato que explicar por qué se cayó Komanda.
if [ "$ENTORNO" = "staging" ]; then
  for puerto in 80 443; do
    if ss -ltn "sport = :$puerto" 2>/dev/null | grep -q LISTEN; then
      echo "El puerto $puerto está ocupado: staging publica 80/443 y aquí eso tumba Komanda." >&2
      echo "Staging va en el portátil o en una caja propia." >&2
      exit 1
    fi
  done
fi

COMPOSE=(docker compose --env-file .env "${COMPOSE_FILES[@]}")

echo "==> 1/5 Construyendo imágenes (código actual del directorio de trabajo)"
"${COMPOSE[@]}" build --pull

echo "==> 2/5 Base de datos y rol de aplicación"
"${COMPOSE[@]}" up -d db
# El rol de aplicación se crea aquí y no en una migración: una migración con CREATE ROLE
# ... PASSWORD acaba metiendo credenciales en el repositorio. Sin BYPASSRLS y sin superusuario:
# es lo que hace que la RLS proteja de verdad.
"${COMPOSE[@]}" exec -T db psql -U winopo -d winopo -v ON_ERROR_STOP=1 \
  -v app_pwd="${POSTGRES_APP_PASSWORD}" <<'SQL'
select format('create role winopo_app login password %L nosuperuser nocreatedb nocreaterole noinherit', :'app_pwd')
 where not exists (select 1 from pg_roles where rolname = 'winopo_app')
\gexec
alter role winopo_app with login password :'app_pwd';
grant connect on database winopo to winopo_app;
grant usage on schema public to winopo_app;
grant select, insert, update, delete on all tables in schema public to winopo_app;
grant usage, select on all sequences in schema public to winopo_app;
alter default privileges in schema public grant select, insert, update, delete on tables to winopo_app;
alter default privileges in schema public grant usage, select on sequences to winopo_app;
SQL

echo "==> 3/5 Aplicando migraciones"
# Se aplican antes de levantar core: si una migración falla, se para aquí y no se
# levanta una versión que espera tablas que no existen.
for f in migrations/*.sql; do
  echo "    -> $f"
  "${COMPOSE[@]}" exec -T db psql -U winopo -d winopo -v ON_ERROR_STOP=1 < "$f" || {
    echo "Migración fallida: $f. No se levanta la aplicación." >&2
    exit 1
  }
done

echo "==> 4/5 Levantando servicios"
"${COMPOSE[@]}" up -d --remove-orphans

echo "==> 5/5 Estado"
"${COMPOSE[@]}" ps

# En la caja compartida no hay puerto publicado: se comprueba por dentro de la red, que es
# exactamente el camino que usa el túnel (cloudflared -> caddy:80 -> core:8080).
if [ "$ENTORNO" = "prod" ] && [ "${WINOPO_EDGE:-compartida}" != "propia" ]; then
  if "${COMPOSE[@]}" exec -T caddy wget -qO- -T 5 http://127.0.0.1/healthz >/dev/null 2>&1; then
    echo "    caddy -> core /healthz: 200"
  else
    echo "    AVISO: /healthz no responde a través de caddy." >&2
    echo "    Mira: docker compose --env-file .env ${COMPOSE_FILES[*]} logs --tail=30 core" >&2
  fi
  echo "    último log del túnel:"
  "${COMPOSE[@]}" logs --tail=5 cloudflared 2>/dev/null || true
fi
