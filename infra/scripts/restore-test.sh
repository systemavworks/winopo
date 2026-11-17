#!/usr/bin/env bash
# Restauración probada una vez por trimestre. Una copia que nunca se restaura no es una copia.
set -euo pipefail

: "${FICHERO:?uso: FICHERO=winopo-XXXX.dump DATABASE_URL=... ./restore-test.sh}"
: "${DATABASE_URL:?falta DATABASE_URL}"

echo "ATENCION: esto sobrescribe el contenido de ${DATABASE_URL}"
read -r -p "Escribe RESTAURAR para continuar: " respuesta
[[ "${respuesta}" == RESTAURAR ]] || { echo "cancelado"; exit 1; }

pg_restore --clean --if-exists --no-owner --dbname="${DATABASE_URL}" "${FICHERO}"

echo "restauracion completada"
