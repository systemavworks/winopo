#!/usr/bin/env bash
# Despliegue: staging y producción separados, bases distintas, misma imagen.
# Se ejecuta DESDE CUALQUIER SITIO; el script se coloca en la raíz del repositorio.
# El .env del servidor no está en git: vive aquí al lado con permisos 600.
set -euo pipefail

ENTORNO="${1:-}"
case "${ENTORNO}" in
  staging) COMPOSE_FILE="infra/docker-compose.staging.yml" ;;
  prod)    COMPOSE_FILE="infra/docker-compose.prod.yml" ;;
  *) echo "uso: deploy.sh staging|prod"; exit 1 ;;
esac

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

COMPOSE=(docker compose --env-file .env -f "${COMPOSE_FILE}")

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

