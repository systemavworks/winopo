#!/usr/bin/env bash
# pg_dump diario a almacenamiento externo, retención 30 días.
# Nunca deja la copia en el mismo host que la base.
set -euo pipefail

: "${DATABASE_URL:?falta DATABASE_URL}"
: "${BACKUP_DESTINO:?falta BACKUP_DESTINO (ruta o rclone:remoto)}"

FECHA="$(date -u +%Y%m%dT%H%M%SZ)"
FICHERO="winopo-${FECHA}.dump"

pg_dump --format=custom --no-owner --file="/tmp/${FICHERO}" "${DATABASE_URL}"

if [[ "${BACKUP_DESTINO}" == rclone:* ]]; then
  rclone copy "/tmp/${FICHERO}" "${BACKUP_DESTINO}"
else
  mkdir -p "${BACKUP_DESTINO}"
  mv "/tmp/${FICHERO}" "${BACKUP_DESTINO}/"
fi

rm -f "/tmp/${FICHERO}"
echo "copia terminada: ${FICHERO}"
