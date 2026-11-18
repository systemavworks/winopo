#!/usr/bin/env bash
# Registros DNS de winopo.es en Cloudflare. El apex y www **no se tocan aquí**: los posee el Worker
# «winopo» (`wrangler.jsonc` con `custom_domain`) y los mantiene `tools/deploy-landing.sh`. Si este
# script reapuntara el apex al túnel, se llevaría por delante la web comercial. Solo gestiona
# app.winopo.es, que es lo único que sigue fuera de Cloudflare.
#
#   --tunnel   La plataforma entra por Cloudflare Tunnel: deja app.winopo.es en CNAME proxied al
#              <id>.cfargotunnel.com del túnel, que es lo que hace que el tráfico llegue al caddy
#              interno de la caja. El túnel se busca por nombre (`winopo-cax11`); si el token no
#              puede listar túneles, pásalo a mano con --tunnel-id. Sin túnel no se toca el DNS:
#              sale con 2 y dice qué falta, para no dejar la zona a medias.
#
#   --ip IP    Caja dedicada con IP pública: deja app.winopo.es en A (gris), para que Caddy saque
#              el certificado por HTTP-01. En naranja habría dos TLS y Cloudflare exigiría un
#              certificado de origen (Origin CA) o modo "Full (strict)".
#
# Simula por defecto: enseña qué cambiaría y no toca nada. Con --apply escribe.
# Idempotente: dos ejecuciones seguidas con el mismo destino no cambian nada la segunda.
#
#   tools/dns-cloudflare.sh --tunnel                      # simulación del modo túnel
#   tools/dns-cloudflare.sh --tunnel --apply              # limpia Pages y apunta al túnel
#   tools/dns-cloudflare.sh --tunnel --tunnel-id <uuid>   # sin permiso para listar túneles
#   tools/dns-cloudflare.sh --ip 203.0.113.10             # caja propia (IP de ejemplo, RFC 5737)
#   tools/dns-cloudflare.sh --ip 203.0.113.10 --apply
#
# Token: API_TOKEN_CLOUDFLARE en el entorno, o en .env en la raíz del repositorio.
# Zone.DNS:Edit sobre winopo.es y, para encontrar el túnel por nombre, Account →
# Cloudflare Tunnel → Read. Crear el túnel es otra cosa: eso se hace una vez en el panel
# (o con un token que tenga Tunnel → Edit) y el proyecto de Pages muerto se borra desde
# el panel, que aquí no hay permiso de Pages.
# Los registros del apex y de www los crea Cloudflare al atar el custom domain del Worker
# (Workers Routes:Edit, permiso que usa `wrangler deploy`, no este script).
set -euo pipefail
cd "$(dirname "$0")/.."

DOMINIO="winopo.es"
IP=""
MODO=""            # tunnel | ip. Obligatorio y explícito: el script escribe en el DNS real.
APLICAR=0
PROXIED="false"
CON_STAGING=0
TUNEL="winopo-cax11"   # nombre del túnel en Zero Trust → Networks → Tunnels
TUNEL_ID_USER=""
API="https://api.cloudflare.com/client/v4"

# Ayuda = todas las líneas de comentario entre el shebang y `set -euo pipefail`.
uso() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tunnel)  CON_TUNNEL=1; shift ;;
    --tunnel-id) CON_TUNNEL=1; TUNEL_ID_USER="${2:-}"; shift 2 ;;
    --ip)      CON_IP=1; IP="${2:-}"; shift 2 ;;
    --apply)   APLICAR=1; shift ;;
    --proxied) PROXIED="true"; shift ;;
    --staging) CON_STAGING=1; shift ;;
    -h|--help) uso 0 ;;
    *) echo "opción desconocida: $1" >&2; uso 1 ;;
  esac
done

# Los dos modos se excluyen; se comprueba después de parsear porque el orden de los
# argumentos no debe decidir cuál gana.
if [ "${CON_TUNNEL:-0}" -eq 1 ] && [ "${CON_IP:-0}" -eq 1 ]; then
  echo "--tunnel y --ip se excluyen: el túnel crea los CNAME, la IP crea los A." >&2; exit 1
fi
if [ "${CON_TUNNEL:-0}" -eq 1 ]; then MODO="tunnel"; fi
if [ "${CON_IP:-0}" -eq 1 ]; then MODO="ip"; fi

case "$MODO" in
  tunnel)
    if [ "$PROXIED" = "true" ]; then echo "--proxied no aplica con --tunnel (el CNAME lo pone Cloudflare)." >&2; exit 1; fi
    ;;
  ip)
    if [ -z "$IP" ]; then echo "Falta la IPv4: --ip <IP>." >&2; uso 1; fi
    if ! printf '%s' "$IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
      echo "--ip no parece una IPv4: $IP" >&2; exit 1
    fi
    ;;
  *)
    echo "Elige modo: --tunnel (caja compartida) o --ip <IPv4> (caja propia)." >&2; uso 1
    ;;
esac


TOKEN="${API_TOKEN_CLOUDFLARE:-}"
if [ -z "$TOKEN" ] && [ -f .env ]; then
  TOKEN=$(grep -E '^API_TOKEN_CLOUDFLARE=' .env | cut -d= -f2- | tr -d '"'"'"' \r')
fi
if [ -z "$TOKEN" ]; then
  echo "Falta API_TOKEN_CLOUDFLARE (entorno o .env)." >&2; exit 1
fi

api() { # api METODO RUTA [CUERPO]
  if [ -n "${3:-}" ]; then
    curl -sS -X "$1" "$API$2" -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" --data "$3"
  else
    curl -sS -X "$1" "$API$2" -H "Authorization: Bearer $TOKEN"
  fi
}

comprobar() { # falla con el mensaje de Cloudflare si la respuesta no es success
  if [ "$(printf '%s' "$1" | jq -r '.success')" != "true" ]; then
    printf '%s' "$1" | jq -r '.errors[]? | "Cloudflare: \(.code) \(.message)"' >&2
    exit 1
  fi
}

comprobar "$(api GET /user/tokens/verify)"

ZID=$(api GET "/zones?name=$DOMINIO" | jq -r '.result[0].id // empty')
if [ -z "$ZID" ]; then
  echo "La zona $DOMINIO no está en esta cuenta." >&2; exit 1
fi

if [ "$MODO" = "tunnel" ]; then
  # El CNAME tiene que apuntar al túnel concreto: sin túnel no hay destino y tocar el DNS
  # solo cambiaría un error 1014 (Pages borrado) por un NXDOMAIN. Se resuelve antes de
  # escribir nada, por eso el script puede abortar sin dejar la zona a medias.
  TUNEL_ID="$TUNEL_ID_USER"
  if [ -z "$TUNEL_ID" ]; then
    AID=$(api GET "/zones/$ZID" | jq -r '.result.account.id // empty')
    if [ -z "$AID" ]; then
      echo "No se pudo leer la cuenta de la zona $DOMINIO." >&2; exit 1
    fi
    respuesta=$(api GET "/accounts/$AID/cfd_tunnel?is_deleted=false")
    if [ "$(printf '%s' "$respuesta" | jq -r '.success')" != "true" ]; then
      printf '%s' "$respuesta" | jq -r '.errors[]? | "Cloudflare: \(.code) \(.message)"' >&2
      echo "El token no puede listar túneles: repite con --tunnel-id <uuid>." >&2
      exit 2
    fi
    TUNEL_ID=$(printf '%s' "$respuesta" \
      | jq -r --arg n "$TUNEL" '[.result[] | select(.name==$n)][0].id // empty')
  fi
  if [ -z "$TUNEL_ID" ]; then
    cat >&2 <<FIN
No hay túnel «$TUNEL» en la cuenta. Un CNAME a cfargotunnel sin túnel detrás no lleva a
ninguna parte, así que no se toca el DNS.

Crear el túnel, una sola vez:
  Zero Trust → Networks → Tunnels → Create a tunnel → Cloudflared → nombre «$TUNEL»

Luego, o declaras los hostnames públicos en el panel (el túnel crea los CNAME él solo),
o vuelves aquí y los pone este script:
  tools/dns-cloudflare.sh --tunnel --apply

Lo que hay dentro del túnel, si lo prefieres por API:
  app.winopo.es → HTTP  caddy:80
FIN
    exit 2
  fi
  DESTINO="$TUNEL_ID.cfargotunnel.com"
  PROXIED=true
fi

if [ "$MODO" = "ip" ]; then
  echo "Zona $DOMINIO ($ZID) · modo: caja propia · IP $IP · proxied=$PROXIED"
else
  echo "Zona $DOMINIO ($ZID) · modo: túnel «$TUNEL» ($TUNEL_ID) · CNAME -> $DESTINO"
fi
echo "Ejecución: $([ "$APLICAR" -eq 1 ] && echo APLICAR || echo SIMULACIÓN)"
echo

# Estado actual, para reconciliar sin depender de cómo esté ahora.
registros() { api GET "/zones/$ZID/dns_records?per_page=100"; }
existente() { # existente NOMBRE TIPO -> id o vacío
  registros | jq -r --arg n "$1" --arg t "$2" '[.result[] | select(.name==$n and .type==$t)][0].id // empty'
}
detalle() { # detalle NOMBRE -> "tipo contenido proxied" del primer registro con ese nombre
  registros | jq -r --arg n "$1" '[.result[] | select(.name==$n)][0] | "\(.type) \(.content) proxied=\(.proxied)"'
}
tipo_actual() { # tipo_actual NOMBRE -> A, CNAME o vacío. Ignora TXT, MX, NS…: el SPF no se toca.
  registros | jq -r --arg n "$1" \
    '[.result[] | select(.name==$n and (.type=="A" or .type=="CNAME"))][0].type // empty'
}

mutar() { # mutar DESCRIPCIÓN METODO RUTA [CUERPO]
  local desc="$1" metodo="$2" ruta="$3" cuerpo="${4:-}"
  if [ "$APLICAR" -eq 1 ]; then
    comprobar "$(api "$metodo" "$ruta" "$cuerpo")"
    echo "    hecho: $desc"
  else
    echo "    simulación: $desc"
  fi
}

nuevo() { # nuevo TIPO NOMBRE CONTENIDO -> cuerpo JSON
  jq -nc --arg t "$1" --arg n "$2" --arg c "$3" --argjson p "$PROXIED" \
    '{type:$t, name:$n, content:$c, proxied:$p, ttl:1}'
}

poner_a() { # poner_a NOMBRE  (A -> IP; si había un CNAME u otro tipo, se sustituye)
  local nombre="$1" tipo id actual
  tipo=$(tipo_actual "$nombre")
  if [ -n "$tipo" ] && [ "$tipo" != "A" ]; then
    id=$(existente "$nombre" "$tipo")
    echo "  $nombre: hay $tipo ($(detalle "$nombre")) y debe ser A · se borra y se crea"
    mutar "borrar $nombre $tipo" DELETE "/zones/$ZID/dns_records/$id"
    tipo=""
  fi
  if [ -z "$tipo" ]; then
    echo "  $nombre: crear A -> $IP"
    mutar "crear $nombre A -> $IP" POST "/zones/$ZID/dns_records" "$(nuevo A "$nombre" "$IP")"
  else
    actual=$(registros | jq -r --arg n "$nombre" '[.result[] | select(.name==$n and .type=="A")][0].content')
    if [ "$actual" != "$IP" ]; then
      id=$(existente "$nombre" A)
      echo "  $nombre: actualizar A ($actual) -> $IP"
      mutar "actualizar $nombre A -> $IP" PATCH "/zones/$ZID/dns_records/$id" \
        "$(jq -nc --arg c "$IP" --argjson p "$PROXIED" '{content:$c, proxied:$p}')"
    else
      echo "  $nombre: A -> $IP ya correcto"
    fi
  fi
}

poner_cname() { # poner_cname NOMBRE DESTINO
  local nombre="$1" destino="$2" tipo id actual
  tipo=$(tipo_actual "$nombre")
  if [ -n "$tipo" ] && [ "$tipo" != "CNAME" ]; then
    id=$(existente "$nombre" "$tipo")
    echo "  $nombre: hay $tipo y debe ser CNAME · se borra y se crea"
    mutar "borrar $nombre $tipo" DELETE "/zones/$ZID/dns_records/$id"
    tipo=""
  fi
  if [ -z "$tipo" ]; then
    echo "  $nombre: crear CNAME -> $destino"
    mutar "crear $nombre CNAME -> $destino" POST "/zones/$ZID/dns_records" "$(nuevo CNAME "$nombre" "$destino")"
  else
    actual=$(registros | jq -r --arg n "$nombre" '[.result[] | select(.name==$n and .type=="CNAME")][0].content')
    if [ "$actual" != "$destino" ]; then
      id=$(existente "$nombre" CNAME)
      echo "  $nombre: actualizar CNAME ($actual) -> $destino"
      mutar "actualizar $nombre CNAME -> $destino" PATCH "/zones/$ZID/dns_records/$id" \
        "$(jq -nc --arg c "$destino" --argjson p "$PROXIED" '{content:$c, proxied:$p}')"
    else
      echo "  $nombre: CNAME -> $destino ya correcto"
    fi
  fi
}

echo "1) Restos de Cloudflare Pages (dan error 1014)"
# El comodín se lleva por delante app., staging., mail. y cualquier subdominio futuro.
# Se borra solo si apunta a pages.dev: si alguien lo reapunta a mano, no se toca.
# El apex y www también se limpian si seguían en pages.dev: el registro bueno lo crea
# Cloudflare al atar el custom domain del Worker, y aquí no se escribe ninguno.
for nombre in "*.$DOMINIO" "$DOMINIO" "www.$DOMINIO"; do
  reg=$(registros | jq -c --arg n "$nombre" \
    '[.result[] | select(.name==$n and (.type=="A" or .type=="AAAA" or .type=="CNAME"))][0] // empty')
  [ -n "$reg" ] || continue
  contenido=$(printf '%s' "$reg" | jq -r '.content')
  tiporeg=$(printf '%s' "$reg" | jq -r '.type')
  case "$contenido" in
    *pages.dev*)
      id=$(printf '%s' "$reg" | jq -r '.id')
      echo "  $nombre: $tiporeg -> $contenido (muerto) · se borra"
      mutar "borrar $nombre" DELETE "/zones/$ZID/dns_records/$id" ;;
    *) echo "  $nombre: $tiporeg -> $contenido · no es de Pages, se deja como está" ;;
  esac
done
echo

if [ "$MODO" = "ip" ]; then
  echo "2) Plataforma: app.$DOMINIO -> $IP"
  poner_a "app.$DOMINIO"
  if [ "$CON_STAGING" -eq 1 ]; then poner_a "staging.$DOMINIO"; fi
else
  echo "2) Plataforma: app.$DOMINIO -> túnel $TUNEL"
  # Solo app.winopo.es. El apex y www son del Worker «winopo» (custom_domain); reapuntarlos
  # al túnel dejaría la web comercial sin servir.
  poner_cname "app.$DOMINIO" "$DESTINO"
  if [ "$CON_STAGING" -eq 1 ]; then
    echo "  staging.$DOMINIO: se omite; staging no corre en la caja compartida (publica 80/443)"
  fi
fi
echo

echo "3) Correo: no se toca"
registros | jq -r '.result[] | select(.type=="TXT" or .type=="MX") | "  \(.name) \(.type) \(.content)"'
echo

if [ "$MODO" = "tunnel" ]; then
  cat <<'FIN'
app.winopo.es va por aquí, pero un CNAME al túnel solo sirve si el túnel tiene dentro ese
hostname. Eso es configuración del túnel (Zero Trust), no de la zona:

  Tunnels → winopo-cax11 → Public hostname:
    app.winopo.es  → HTTP  caddy:80

  `caddy` resuelve por la red winopo_default: cloudflared y caddy van en el mismo proyecto
  Compose. Si el hostname no está en el túnel, cloudflared contesta 404 aunque el DNS esté
  perfecto.

El apex y www no aparecen aquí a propósito: los sirve el Worker «winopo». Se publican con
  tools/deploy-landing.sh   (o el workflow «landing» al hacer push a main)
y su registro lo crea Cloudflare al atar el custom domain (AAAA 100:: proxied).

Y dos cosas que este token no puede hacer y no hacen falta para publicar:
  · crear el túnel (necesita Account → Cloudflare Tunnel → Edit);
  · borrar el proyecto de Pages muerto (necesita Pages → Edit), que se va desde el panel.
FIN
  echo
fi

if [ "$APLICAR" -eq 0 ]; then
  echo "Simulación: no se ha escrito nada. Repetir con --apply para aplicar."
  exit 0
fi

echo "Estado final en Cloudflare:"
registros | jq -r '.result[] | "  \(.name) \(.type) \(.content) proxied=\(.proxied)"' | sort

if [ "$MODO" = "tunnel" ]; then
  cat <<'FIN'

Comprobar cuando el túnel esté arriba:
  dig +short app.winopo.es @1.1.1.1     # CNAME a <uuid>.cfargotunnel.com (achatado)
  curl -sS -o /dev/null -w '%{http_code}\n' https://app.winopo.es/healthz   # 200
  curl -sS -o /dev/null -w '%{http_code}\n' https://winopo.es/              # 200 (Worker)
FIN
else
  cat <<'FIN'

Comprobar (la propagación puede tardar; Cloudflare usa TTL automático):
  dig +short winopo.es @1.1.1.1
  dig +short app.winopo.es @1.1.1.1

Si los A ya resuelven pero Caddy no saca certificado, el problema es del servidor
(puerto 80 cerrado, compose caído), no del DNS.
FIN
fi
echo
echo "Detalle y orden de ejecución: docs/runbooks/alta-servidor-winopo.md"
