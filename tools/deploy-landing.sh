#!/usr/bin/env bash
# Publica la landing estática (./landing) en el Worker de Cloudflare «winopo» y comprueba que lo
# que se sirve en https://winopo.es y https://www.winopo.es es exactamente lo del repositorio.
#
#   ./tools/deploy-landing.sh          # publica y comprueba
#   ./tools/deploy-landing.sh --check  # solo comprueba (no publica)
#
# Contexto: la landing NO pasa por el servidor. Es un Worker de Cloudflare con assets estáticos
# (ver `wrangler.jsonc`, `assets.directory: ./landing`) atado a los dominios con `custom_domain`,
# que es lo mismo que hacen komanda.es y app.billka.es. Los caminos de publicación son este
# script o el workflow «landing» de GitHub Actions (push a main que toque landing/).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SITE="https://winopo.es"
EXTRA=(www.winopo.es)
WRANGLER=(npx --yes wrangler@4)
FAIL=0
ok()    { echo "  OK    $*"; }
fallo() { echo "  FALLO $*"; }

[ -d landing ] || { echo "FALLO: no existe ./landing"; exit 1; }

# ---------------------------------------------------------------------------------------------
# 1. Publicar (salvo --check)
# ---------------------------------------------------------------------------------------------
if [ "${1:-}" != "--check" ]; then
  command -v npx >/dev/null 2>&1 || { echo "FALLO: falta npx (instala Node)"; exit 1; }
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && ! "${WRANGLER[@]}" whoami >/dev/null 2>&1; then
    echo "FALLO: sin credenciales de Cloudflare."
    echo "       En tu máquina:  npx wrangler login  (o exporta CLOUDFLARE_API_TOKEN)"
    echo "       En CI:          secreto CLOUDFLARE_API_TOKEN (+ CLOUDFLARE_ACCOUNT_ID)"
    exit 1
  fi
  echo "== publicando landing/ en el Worker «winopo» =="
  "${WRANGLER[@]}" deploy || { echo "FALLO: wrangler deploy"; exit 1; }
  sleep 5   # Cloudflare tarda unos segundos en servir la versión nueva
fi

# ---------------------------------------------------------------------------------------------
# 2. Comprobar que lo publicado es el repositorio
# ---------------------------------------------------------------------------------------------
# El HTML no se puede comparar byte a byte: Cloudflare le inyecta al final su script anti-bot.
compara_html() {
  python3 - "$1" "$2" <<'PY'
import re, sys

def limpia(p):
    s = open(p, encoding="utf-8", errors="replace").read()
    s = re.sub(r"<script>(?:(?!</script>).)*__CF\$cv\$params(?:(?!</script>).)*</script>", "", s, flags=re.S)
    return re.sub(r"\s+", " ", s).strip()

a, b = limpia(sys.argv[1]), limpia(sys.argv[2])
if a == b:
    print("  OK    index.html idéntico (ignorando el script anti-bot de Cloudflare)")
    sys.exit(0)
print(f"  FALLO index.html difiere del repositorio ({len(b)} vs {len(a)} bytes normalizados)")
sys.exit(1)
PY
}

verifica() {
  local rc=0 tmp f host
  for host in "$SITE" "${EXTRA[@]/#/https://}"; do
    tmp=$(mktemp) || return 1
    if ! curl -fsS "$host/" -o "$tmp"; then
      fallo "$host/ no responde"; rc=1
    else
      echo "  host  $host -> $(curl -s -o /dev/null -w '%{http_code}' "$host/")"
      compara_html "$tmp" landing/index.html || rc=1
    fi
    rm -f "$tmp"
  done

  # Assets estáticos: estos sí se comparan byte a byte (Cloudflare no los toca).
  while IFS= read -r f; do
    rel=${f#landing/}
    tmp=$(mktemp)
    if [ "$(curl -s -o "$tmp" -w '%{http_code}' "$SITE/$rel")" != "200" ]; then
      fallo "$rel no responde 200"; rc=1
    elif cmp -s "$f" "$tmp"; then
      ok "$rel idéntico"
    else
      fallo "$rel difiere del repositorio"; rc=1
    fi
    rm -f "$tmp"
  done < <(find landing -type f ! -name '*.html' ! -name '_headers' ! -name '_redirects')

  # Cabeceras del landing: las pone `landing/_headers`, no el HTML. Si desaparecen, el apex
  # queda servido sin HSTS ni CSP (antes las ponía Caddy).
  cabeceras=$(curl -sSI "$SITE/" | tr -d '\r')
  for h in 'strict-transport-security' 'content-security-policy' 'x-content-type-options'; do
    if printf '%s\n' "$cabeceras" | grep -qi "^$h:"; then
      ok "cabecera $h presente"
    else
      fallo "falta la cabecera $h en $SITE/"; rc=1
    fi
  done

  # Redirección del landing a la plataforma (equivalente al `redir` de Caddy).
  destino=$(curl -sS -o /dev/null -w '%{redirect_url}' "$SITE/login")
  case "$destino" in
    *app.winopo.es/login*) ok "/login redirige a $destino" ;;
    *) fallo "/login no redirige a app.winopo.es (destino: ${destino:-ninguno})"; rc=1 ;;
  esac

  return $rc
}

echo "== lo publicado coincide con el repositorio =="
for intento in 1 2 3; do
  salida=$(verifica 2>&1); rc=$?
  [ $rc -eq 0 ] && break
  if [ $intento -lt 3 ]; then
    echo "  … reintentando en 5 s (Cloudflare puede estar sirviendo la versión anterior)"
    sleep 5
  fi
done
echo "$salida"
[ "$rc" -eq 0 ] || FAIL=1

echo
if [ "$FAIL" = "0" ]; then echo "LANDING_OK"; else echo "LANDING_FALLO"; exit 1; fi
