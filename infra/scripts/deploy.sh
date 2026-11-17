#!/usr/bin/env bash
# Despliegue: staging y producción separados, bases distintas, misma imagen.
set -euo pipefail

ENTORNO="${1:-}"
case "${ENTORNO}" in
  staging) COMPOSE_FILE="infra/docker-compose.staging.yml" ;;
  prod)    COMPOSE_FILE="infra/docker-compose.prod.yml" ;;
  *) echo "uso: deploy.sh staging|prod"; exit 1 ;;
esac

docker compose -f "${COMPOSE_FILE}" pull
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans
docker compose -f "${COMPOSE_FILE}" ps
