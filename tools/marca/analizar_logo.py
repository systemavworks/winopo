import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert("RGB")
W, H = im.size
px = im.load()
FONDO = (244, 243, 238)


def lejos(c, umbral=30):
    return sum((c[i] - FONDO[i]) ** 2 for i in range(3)) ** 0.5 > umbral


def filas():
    out = []
    for y in range(H):
        n = sum(1 for x in range(W) if lejos(px[x, y]))
        out.append(n)
    return out


def columnas(y0, y1):
    out = []
    for x in range(W):
        n = sum(1 for y in range(y0, y1) if lejos(px[x, y]))
        out.append(n)
    return out


def bloques(v, minimo):
    res, ini = [], None
    for i, n in enumerate(v):
        if n >= minimo and ini is None:
            ini = i
        elif n < minimo and ini is not None:
            res.append((ini, i - 1))
            ini = None
    if ini is not None:
        res.append((ini, len(v) - 1))
    return res


print("imagen %dx%d" % (W, H))
f = filas()
for y0, y1 in bloques(f, 3):
    c = columnas(y0, y1 + 1)
    cb = bloques(c, 1)
    x0, x1 = (cb[0][0], cb[-1][1]) if cb else (0, 0)
    print("bloque y=%d..%d (alto %d)  x=%d..%d (ancho %d)" % (y0, y1, y1 - y0 + 1, x0, x1, x1 - x0 + 1))
