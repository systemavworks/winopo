"""Genera los recursos de marca del landing desde winopo_logo.jpeg.

El original es un JPEG de 1376x768 con fondo crema y bandas grises laterales, y un
lockup vertical (emblema arriba, nombre debajo, subtitulo al final). Una cabecera de
68 px no admite ese lockup entero, asi que se separa en piezas:

  winopo-emblema.png       emblema solo, recortado y con el fondo transpuesto a alfa
  winopo-lockup.png        emblema + nombre + subtitulo, para redes y documentos
  favicon.png              emblema sobre pastilla crema, 64x64
  apple-touch-icon.png     lo mismo a 180x180 (iOS rellena de negro si hay alfa)
  og-winopo.jpg            1200x630 para compartir en redes

No se sirve el JPEG original: pesa 355 KB y no esta optimizado.

Uso:  python3 tools/marca/generar_marca.py
"""

from collections import deque
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parents[2]
# El logo vive en la raiz (es el que se comparte a mano) y ademas hay una copia en docs/marca/.
ORIGEN = RAIZ / "winopo_logo.jpeg"
if not ORIGEN.exists():
    ORIGEN = RAIZ / "docs" / "marca" / "winopo_logo.jpeg"
DESTINO = RAIZ / "landing" / "assets"
DOCS = RAIZ / "docs" / "marca"

# En la cabecera el emblema se muestra a 44 px: 176 px cubre pantallas de doble densidad
# sin servir medio megapixel de más.
ALTO_EMBLEMA = 176

CREMA = (245, 244, 239)  # fondo del logo
CREMA_WEB = (250, 247, 242)  # --crema del landing
FUZZ = 26  # distancia al fondo por debajo de la cual un pixel es fondo


def caja(im, y0, y1, umbral=30):
    """Caja del contenido real entre dos filas, medida contra el color de fondo."""
    px = im.load()
    ancho = im.size[0]

    def fuera(c):
        return sum((c[i] - CREMA[i]) ** 2 for i in range(3)) ** 0.5 > umbral

    xs = [x for x in range(ancho) if any(fuera(px[x, y]) for y in range(y0, y1))]
    ys = [y for y in range(y0, y1) if any(fuera(px[x, y]) for x in range(ancho))]
    return (xs[0], ys[0], xs[-1] + 1, ys[-1] + 1)


def con_alfa(im, recorte):
    """Recorta y convierte el fondo crema en transparencia.

    El relleno se hace por inundacion desde los bordes: solo desaparece el fondo
    conectado con el exterior, no los blancos internos del emblema. Los pixeles
    del antialias reciben alfa proporcional para que no quede halo.
    """
    sub = im.crop(recorte).convert("RGB")
    w, h = sub.size
    px = sub.load()
    fondo = px[0, 0]

    def dist(c):
        return sum((c[i] - fondo[i]) ** 2 for i in range(3)) ** 0.5

    visto = [[False] * w for _ in range(h)]
    cola = deque()
    for x in range(w):
        for y in (0, h - 1):
            if dist(px[x, y]) < FUZZ:
                visto[y][x] = True
                cola.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visto[y][x] and dist(px[x, y]) < FUZZ:
                visto[y][x] = True
                cola.append((x, y))

    while cola:
        x, y = cola.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not visto[ny][nx] and dist(px[nx, ny]) < FUZZ:
                visto[ny][nx] = True
                cola.append((nx, ny))

    alfa = []
    for y in range(h):
        for x in range(w):
            if visto[y][x]:
                alfa.append(0)
            else:
                d = dist(px[x, y])
                if d < FUZZ * 1.9:  # borde suave
                    alfa.append(max(0, min(255, int(255 * (d - FUZZ) / (FUZZ * 0.9)))))
                else:
                    alfa.append(255)

    salida = sub.convert("RGBA")
    salida.putalpha(Image.frombytes("L", (w, h), bytes(alfa)))
    return salida.crop(salida.getbbox())


def escalar_alto(im, alto):
    ancho = round(im.size[0] * alto / im.size[1])
    return im.resize((ancho, alto), Image.LANCZOS)


def pastilla(emblema, lado, radio_ratio=0.19):
    """Emblema sobre cuadro crema redondeado: legible en modo claro y oscuro."""
    lienzo = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    fondo = Image.new("RGBA", (lado, lado), CREMA + (255,))
    mascara = Image.new("L", (lado, lado), 0)
    from PIL import ImageDraw

    ImageDraw.Draw(mascara).rounded_rectangle(
        (0, 0, lado - 1, lado - 1), radius=round(lado * radio_ratio), fill=255
    )
    lienzo.paste(fondo, (0, 0), mascara)
    interior = round(lado * 0.8)
    pieza = escalar_alto(emblema, interior)
    lienzo.paste(pieza, ((lado - pieza.size[0]) // 2, (lado - pieza.size[1]) // 2), pieza)
    return lienzo


def main():
    if not ORIGEN.exists():
        raise SystemExit("falta %s" % ORIGEN)
    DESTINO.mkdir(parents=True, exist_ok=True)
    im = Image.open(ORIGEN).convert("RGB")

    # El valle medido entre emblema y nombre esta en y=421..424.
    caja_emblema = caja(im, 168, 421)
    caja_lockup = caja(im, 168, 600)

    emblema = con_alfa(im, caja_emblema)
    lockup = con_alfa(im, caja_lockup)
    print("emblema %dx%d   lockup %dx%d" % (emblema.size + lockup.size))

    emblema_out = escalar_alto(emblema, ALTO_EMBLEMA)
    emblema_out.save(DESTINO / "winopo-emblema.png", optimize=True)

    # El lockup completo no se sirve en la web: va a docs, para prensa y documentos.
    DOCS.mkdir(parents=True, exist_ok=True)
    escalar_alto(lockup, 480).save(DOCS / "winopo-lockup.png", optimize=True)

    pastilla(emblema, 64).save(DESTINO / "favicon.png", optimize=True)
    pastilla(emblema, 180, radio_ratio=0).save(DESTINO / "apple-touch-icon.png", optimize=True)

    og = Image.new("RGB", (1200, 630), CREMA_WEB)
    pieza = escalar_alto(lockup, 430)
    og.paste(pieza, ((1200 - pieza.size[0]) // 2, (630 - pieza.size[1]) // 2), pieza)
    og.save(DESTINO / "og-winopo.jpg", quality=88, optimize=True, progressive=True)

    for p in sorted(DESTINO.iterdir()):
        if p.is_file():
            print("%-24s %6.1f KB" % (p.name, p.stat().st_size / 1024))


if __name__ == "__main__":
    main()
