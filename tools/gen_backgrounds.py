"""Genera las capas de parallax de cada bioma (data/biomes/*.json) como pixel art
procedural, siempre con colores de la paleta y repetible en horizontal (tileable).

Generadores disponibles (campo "gen" de cada capa):
  clouds  nubes esponjosas de base plana
  hills   colinas suaves (suma de senos periódicos) con borde de luz
  trees   hilera de copas redondas sombreadas con luz desde arriba a la izquierda
  meadow  pradera con camino de tierra, piedritas, hierba y flores
  tufts   matas de hierba y flores sueltas en primer plano (transparente entre ellas)

Salida: assets/bg/<bioma>/<capa>.png y una vista previa en shots/bg_<bioma>.png.
Uso: python -I tools/gen_backgrounds.py
"""
import glob
import json
import math
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_ui import PALETTE, rgba  # noqa: E402  (misma paleta que la UI)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLEAR = (0, 0, 0, 0)


def wrap_dx(a, b, w):
    d = (a - b) % w
    return d - w if d > w / 2 else d


def put(img, x, y, c):
    w, h = img.size
    if 0 <= y < h:
        img.putpixel((x % w, y), c)


def bayer4(x, y):
    m = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
    return (m[y % 4][x % 4] + 0.5) / 16.0


# ---------------------------------------------------------------- generadores

def gen_clouds(L, W, H, rnd):
    img = Image.new("RGBA", (W, H), CLEAR)
    top, mid, shade = (rgba(c) for c in L["colors"])
    y0, y1 = L["y"]
    for i in range(L["count"]):
        cx = int((i + rnd.uniform(0.1, 0.9)) * W / L["count"])
        base = rnd.randint(y0 + 6, y1)
        puffs = []
        n = rnd.randint(3, 5)
        width = rnd.randint(14, 26)
        for k in range(n):
            px = cx + int((k - (n - 1) / 2) * width / n) + rnd.randint(-1, 1)
            r = rnd.randint(3, 6) if k not in (0, n - 1) else rnd.randint(2, 4)
            puffs.append((px, base - r + 1, r))
        for x in range(cx - width, cx + width + 1):
            for y in range(y0, base + 1):
                inside = None
                for (px, py, r) in puffs:
                    dx = wrap_dx(x, px, W)
                    if dx * dx + (y - py) ** 2 <= r * r + r * 0.6:
                        inside = (px, py, r)
                        break
                if inside is None:
                    continue
                px, py, r = inside
                ny = (y - py) / r
                if y == base:
                    c = shade
                elif ny < -0.35 and wrap_dx(x, px, W) < r * 0.4:
                    c = top
                else:
                    c = mid
                put(img, x, y, c)
    return img


def gen_hills(L, W, H, rnd):
    img = Image.new("RGBA", (W, H), CLEAR)
    light, base, dark = (rgba(c) for c in L["colors"])
    phases = [rnd.uniform(0, math.tau) for _ in L["waves"]]
    norm = sum(a for _, a in L["waves"])
    heights = []
    for x in range(W):
        v = sum(a * math.sin(math.tau * f * x / W + p) for (f, a), p in zip(L["waves"], phases)) / norm
        heights.append(int(round(L["base_y"] - L["amp"] * (v * 0.5 + 0.5))))
    for x in range(W):
        top = heights[x]
        for y in range(top, H):
            depth = y - top
            if depth == 0:
                c = light
            elif depth > 14 and bayer4(x, y) < min(0.5, (depth - 14) / 8.0):
                c = dark
            else:
                c = base
            put(img, x, y, c)
        # brillo extra en las laderas que miran a la izquierda (luz arriba-izquierda)
        if heights[(x + 1) % W] > top and top + 1 < H:
            put(img, x, top + 1, light)
    return img


def gen_trees(L, W, H, rnd):
    img = Image.new("RGBA", (W, H), CLEAR)
    light, base, dark, deep = (rgba(c) for c in L["colors"])
    rmin, rmax = L["r"]
    n = L["count"]
    crowns = []
    for i in range(n):
        cx = (i + rnd.uniform(-L["gap"], L["gap"]) * 0.5 + 0.5) * W / n
        r = rnd.randint(rmin, rmax)
        cy = L["base_y"] - r + rnd.randint(0, 2)
        crowns.append((cx, cy, r))
        # copa pequeña secundaria al lado para que no se vea repetitivo
        if rnd.random() < 0.7:
            r2 = max(3, r - rnd.randint(1, 3))
            side = rnd.choice((-1, 1))
            crowns.append((cx + side * (r * 0.9), L["base_y"] - r2 + 2, r2))
    # las copas más bajas (más cercanas) se dibujan encima
    crowns.sort(key=lambda c: c[1])
    lx, ly = -0.6, -0.8
    for y in range(H):
        for x in range(W):
            hit = None
            for (cx, cy, r) in crowns:
                dx = wrap_dx(x + 0.5, cx, W)
                dy = y + 0.5 - cy
                if dx * dx + dy * dy <= r * r:
                    hit = (dx / r, dy / r)
            if hit is None:
                if y >= L["base_y"]:
                    put(img, x, y, dark)
                continue
            nx, ny = hit
            d = nx * lx + ny * ly
            if d > 0.45:
                c = light
            elif d > -0.25:
                c = base
            elif d > -0.6 or bayer4(x, y) < 0.5:
                c = dark
            else:
                c = deep
            put(img, x, y, c)
    if L.get("trunks"):
        bark = rgba("bark")
        for (cx, cy, r) in crowns[::2]:
            for y in range(int(cy + r * 0.6), L["base_y"] + 2):
                put(img, int(cx), y, bark)
    return img


def gen_meadow(L, W, H, rnd):
    img = Image.new("RGBA", (W, H), CLEAR)
    c = [rgba(x) for x in L["colors"]]
    lime, sprout, grass, leaf, path, pebble, pebble_dark, path_hi = c
    flowers = [rgba(x) for x in L["flowers"]]
    top_y = L["top_y"]
    p0, p1 = L["path"]
    # borde superior irregular (periódico)
    ph = [rnd.uniform(0, math.tau) for _ in range(3)]
    for x in range(W):
        edge = top_y + int(round(math.sin(math.tau * 3 * x / W + ph[0]) * 0.8 + math.sin(math.tau * 7 * x / W + ph[1]) * 0.6))
        for y in range(edge, H):
            if p0 <= y < p1:
                continue
            col = grass
            if y == edge:
                col = sprout
            elif y > edge + 1 and bayer4(x, y) < 0.18:
                col = leaf
            put(img, x, y, col)
        # puntas de hierba sobre el borde
        if rnd.random() < 0.28:
            put(img, x, edge - 1, sprout)
            if rnd.random() < 0.3:
                put(img, x, edge - 2, lime)
    # camino de tierra
    for x in range(W):
        for y in range(p0, p1):
            col = path
            if y == p0:
                col = pebble          # borde superior con sombra de la hierba
            elif y == p1 - 1:
                col = path_hi if bayer4(x, y) < 0.5 else path
            put(img, x, y, col)
        # la hierba cae sobre el borde del camino
        if rnd.random() < 0.35:
            put(img, x, p0, grass)
            if rnd.random() < 0.4:
                put(img, x, p0 + 1, grass)
        if rnd.random() < 0.25:
            put(img, x, p1 - 1, grass)
    # piedritas
    for _ in range(W // 12):
        x = rnd.randrange(W)
        y = rnd.randint(p0 + 2, p1 - 3)
        put(img, x, y, pebble)
        put(img, x + 1, y, pebble)
        put(img, x, y + 1, pebble_dark)
        put(img, x + 1, y + 1, pebble_dark)
        put(img, x, y - 1, path_hi)
    # brotes oscuros en la hierba
    for _ in range(W // 5):
        x = rnd.randrange(W)
        y = rnd.choice([rnd.randint(top_y + 1, p0 - 1), rnd.randint(p1, H - 1)])
        put(img, x, y, leaf)
        put(img, x, y - 1, grass)
    # flores
    for _ in range(W // 14):
        x = rnd.randrange(W)
        y = rnd.choice([rnd.randint(top_y + 1, p0 - 2), rnd.randint(p1 + 1, H - 2)])
        fc = rnd.choice(flowers)
        put(img, x, y + 1, leaf)
        put(img, x, y, fc)
        if rnd.random() < 0.5:
            put(img, x - 1, y, fc)
            put(img, x + 1, y, fc)
            put(img, x, y - 1, fc)
            put(img, x, y, rgba("honey") if fc != rgba("honey") else rgba("paper"))
    return img


def gen_tufts(L, W, H, rnd):
    img = Image.new("RGBA", (W, H), CLEAR)
    sprout, grass, leaf, deep = (rgba(x) for x in L["colors"])
    flowers = [rgba(x) for x in L["flowers"]]
    for i in range(L["count"]):
        cx = int((i + rnd.uniform(0.2, 0.8)) * W / L["count"])
        width = rnd.randint(7, 13)
        height = rnd.randint(4, 7)
        for k in range(width):
            x = cx - width // 2 + k
            t = 1 - abs(k - width / 2) / (width / 2)
            hh = max(1, int(round(height * (0.35 + 0.65 * t) + rnd.choice((-1, 0, 0, 1)))))
            for j in range(hh):
                y = H - 1 - j
                if j == hh - 1:
                    col = sprout if k < width * 0.6 else grass
                elif j == 0:
                    col = deep
                else:
                    col = grass if (k + j) % 3 else leaf
                put(img, x, y, col)
        if rnd.random() < 0.7:
            fx = cx + rnd.randint(-width // 3, width // 3)
            fy = H - height - 1
            fc = rnd.choice(flowers)
            for (dx, dy) in ((0, 0), (-1, 0), (1, 0), (0, -1)):
                put(img, fx + dx, fy + dy, fc)
            put(img, fx, fy, rgba("honey") if fc != rgba("honey") else rgba("paper"))
            put(img, fx, fy + 1, leaf)
    return img


GENS = {"clouds": gen_clouds, "hills": gen_hills, "trees": gen_trees, "meadow": gen_meadow, "tufts": gen_tufts}


def build(biome_path):
    with open(biome_path, encoding="utf-8") as f:
        B = json.load(f)
    W, H = B["tile_w"], B["height"]
    out_dir = os.path.join(ROOT, "assets", "bg", B["id"])
    os.makedirs(out_dir, exist_ok=True)
    preview = Image.new("RGBA", (W * 2, H), rgba("haze"))
    for i, L in enumerate(B["layers"]):
        rnd = random.Random(B["seed"] * 100 + i)
        img = GENS[L["gen"]](L, W, H, rnd)
        img.save(os.path.join(out_dir, L["name"] + ".png"))
        preview.alpha_composite(img, (0, 0))
        preview.alpha_composite(img, (W, 0))
        print("wrote assets/bg/%s/%s.png" % (B["id"], L["name"]))
    os.makedirs(os.path.join(ROOT, "shots"), exist_ok=True)
    preview.resize((W * 2 * 3, H * 3), Image.NEAREST).convert("RGB").save(os.path.join(ROOT, "shots", "bg_%s.png" % B["id"]))


def main():
    for p in sorted(glob.glob(os.path.join(ROOT, "data", "biomes", "*.json"))):
        build(p)


if __name__ == "__main__":
    sys.exit(main())
