#!/usr/bin/env bash
# Registros DNS de winopo.es en Cloudflare. Dos modos:
#
#   --tunnel   (el de producción hoy) La entrada es un Cloudflare Tunnel: los CNAME los
#              crea el propio túnel al declarar los hostnames públicos. Este script solo
#              borra los restos muertos de Pages y recuerda qué hostnames declarar.
#
#   --ip IP    Caja dedicada con IP pública: deja winopo.es y app.winopo.es en A (gris) y
#              www en CNAME al apex, para que Caddy saque el certificado por HTTP-01.
#              En naranja habría dos TLS y Cloudflare exigiría un certificado de origen
#              (Origin CA) o modo "Full (strict)".
#
# Simula por defecto: enseña qué cambiaría y no toca nada. Con --apply escribe.
# Idempotente: dos ejecuciones seguidas con el mismo destino no cambian nada la segunda.
#
#   tools/dns-cloudflare.sh --tunnel                      # simulación del modo túnel
#   tools/dns-cloudflare.sh --tunnel --apply              # borra restos de Pages
#   tools/dns-cloudflare.sh --ip 203.0.113.10             # caja propia (IP de ejemplo, RFC 5737)
#   tools/dns-cloudflare.sh --ip 203.0.113.10 --apply
#
# Token: API_TOKEN_CLOUDFLARE en el entorno, o en .env en la raíz del repositorio.
# Solo necesita Zone.DNS:Edit sobre winopo.es. Nada más (ni Pages, ni cuenta): el proyecto
# de Pages muerto se borra desde el panel, no desde aquí.
set -euo pipefail
cd "$(dirname "$0")/.."

DOMINIO="winopo.es"
IP=""
MODO=""            # tunnel | ip. Obligatorio y explícito: el script escribe en el DNS real.
APLICAR=0
PROXIED="false"
CON_STAGING=0
API="https://api.cloudflare.com/client/v4"

# Ayuda = todas las líneas de comentario entre el shebang y `set -euo pipefail`.
uso() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tunnel)  CON_TUNNEL=1; shift ;;
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

if [ "$MODO" = "ip" ]; then
  echo "Zona $DOMINIO ($ZID) · modo: caja propia · IP $IP · proxied=$PROXIED"
else
  echo "Zona $DOMINIO ($ZID) · modo: túnel (los CNAME los crea Cloudflare Zero Trust)"
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

echo "1) Restos de Cloudflare Pages (dan error 1014 y hoy tienen el dominio caído)"
# El comodín se lleva por delante app., staging., mail. y cualquier subdominio futuro.
# Se borra solo si apunta a pages.dev: si alguien lo reapunta a mano, no se toca.
# www no entra aquí: en modo --ip se reapunta abajo y en modo --tunnel lo trata el paso 2.
nombre="*.$DOMINIO"
tipo=$(tipo_actual "$nombre")
if [ -n "$tipo" ]; then
  contenido=$(registros | jq -r --arg n "$nombre" '[.result[] | select(.name==$n)][0].content')
  case "$contenido" in
    *pages.dev*)
      id=$(existente "$nombre" "$tipo")
      echo "  $nombre: $tipo -> $contenido (muerto) · se borra"
      mutar "borrar $nombre" DELETE "/zones/$ZID/dns_records/$id" ;;
    *) echo "  $nombre: $tipo -> $contenido · no es de Pages, se deja como está" ;;
  esac
fi
echo

if [ "$MODO" = "ip" ]; then
  echo "2) Dominios del producto (infra/caddy/Caddyfile)"
  poner_a "$DOMINIO"
  poner_cname "www.$DOMINIO" "$DOMINIO"
  poner_a "app.$DOMINIO"
  if [ "$CON_STAGING" -eq 1 ]; then poner_a "staging.$DOMINIO"; fi
else
  echo "2) Dominios del producto: los crea el túnel, aquí solo se limpian restos"
  # Lo que el túnel va a necesitar como hostname público. Si el registro existe y apunta
  # a pages.dev está muerto (error 1014) y estorba: se borra. Si apunta a otra cosa, se deja
  # y se avisa: puede ser un servicio que alguien montó a mano.
  for nombre in "$DOMINIO" "www.$DOMINIO" "app.$DOMINIO"; do
    tipo=$(tipo_actual "$nombre")
    if [ -z "$tipo" ]; then
      echo "  $nombre: sin A/CNAME · lo creará el túnel"
      continue
    fi
    contenido=$(registros | jq -r --arg n "$nombre" '[.result[] | select(.name==$n)][0].content')
    case "$contenido" in
      *pages.dev*)
        id=$(existente "$nombre" "$tipo")
        echo "  $nombre: $tipo -> $contenido (muerto) · se borra para que lo cree el túnel"
        mutar "borrar $nombre" DELETE "/zones/$ZID/dns_records/$id" ;;
      *)
        echo "  $nombre: $tipo -> $contenido · ya existe, no se toca. El túnel reutiliza el hostname" ;;
    esac
  done
  if [ "$CON_STAGING" -eq 1 ]; then
    echo "  staging.$DOMINIO: añadirlo también como hostname público si hace falta"
  fi
fi
echo

echo "3) Correo: no se toca"
registros | jq -r '.result[] | select(.type=="TXT" or .type=="MX") | "  \(.name) \(.type) \(.content)"'
echo

if [ "$MODO" = "tunnel" ]; then
  cat <<'FIN'
Lo que este token no puede hacer y hay que hacer en el panel:

  1. Zero Trust → Networks → Tunnels → crear `winopo-cax11` y copiar el token.
     Ese token es TUNNEL_TOKEN en el .env del servidor.
  2. En el túnel → Public hostname, tres entradas al mismo servicio:
       winopo.es      → HTTP  caddy:80
       www.winopo.es  → HTTP  caddy:80
       app.winopo.es  → HTTP  caddy:80
     `caddy` resuelve por la red winopo_default: cloudflared y caddy van en el mismo
     proyecto Compose. El túnel crea los CNAME en proxied y el apex por CNAME flattening.
  3. El proyecto Pages muerto no se puede borrar desde aquí (el token no tiene Pages).
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
  dig +short winopo.es @1.1.1.1        # CNAME a <uuid>.cfargotunnel.com (achatado)
  curl -sI https://winopo.es | head -3  # 200 y `server: cloudflare`
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
