"""Genera el arte de UI propio (siempre con colores de la paleta de docs/arte.md).

Para dibujar a mano píxel a píxel se usan mapas de caracteres, donde cada letra es un
color de la paleta. Los marcos 9-patch se construyen con anillos concéntricos.
Al final se verifica que TODO píxel opaco pertenezca a la paleta.

Salida en assets/ui/. Uso:  python -I tools/gen_ui.py
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")

PALETTE = {
    "ink": "#2b1d1a", "bark": "#4a3128", "wood": "#6e4a35", "oak": "#9a6b47",
    "tan": "#c99a65", "sand": "#e8c895", "cream": "#f6e7c1", "paper": "#fffaf0",
    "pine": "#1f3a33", "forest": "#2f5a3d", "leaf": "#4b8049", "grass": "#77ab55",
    "sprout": "#a9d16a", "lime": "#d6ec9a", "midnight": "#1b2140", "night": "#2c3a6b",
    "dusk": "#45609c", "sky": "#6b93cf", "haze": "#9cc4ec", "mist": "#d2ebf7",
    "plum": "#5a2238", "berry": "#9c3b4a", "ember": "#d8584f", "flame": "#f08a5a",
    "amber": "#f9b860", "honey": "#ffe08a", "lilac": "#8a5a9c", "orchid": "#c48ac8",
    "blush": "#f2a7b8", "petal": "#ffd4dc", "teal": "#3f8f8f", "mint": "#8fd3c7",
}
_PAL_RGB = set()
for _h in PALETTE.values():
    _PAL_RGB.add((int(_h[1:3], 16), int(_h[3:5], 16), int(_h[5:7], 16)))

_written = []


def rgba(name, alpha=255):
    h = PALETTE[name].lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def from_map(rows, key):
    """Mapa de caracteres → imagen. '.' = transparente. key: char → nombre o (nombre, alfa)."""
    w, h = len(rows[0]), len(rows)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        assert len(row) == w, "fila %d mide %d (esperado %d): %r" % (y, len(row), w, row)
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            v = key[ch]
            img.putpixel((x, y), rgba(*v) if isinstance(v, tuple) else rgba(v))
    return img


def with_drop_shadow(body, dx=1, dy=1, alpha=110):
    """Sombra dura de 1 px en INK translúcido (estilo panel PMD)."""
    w, h = body.size
    out = Image.new("RGBA", (w + dx, h + dy), (0, 0, 0, 0))
    sh = Image.new("RGBA", body.size, rgba("ink", alpha))
    mask = body.split()[3].point(lambda a: 255 if a > 0 else 0)
    out.paste(sh, (dx, dy), mask)
    out.alpha_composite(body, (0, 0))
    return out


def save(img, name, scale=1):
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))
    _written.append(name)
    print("wrote assets/ui/%s %s" % (name, img.size))


def ring(img, inset, color, top_left=None, round_corner=False):
    """Borde rectangular a `inset` px del exterior. top_left: color distinto arriba/izquierda (bisel)."""
    w, h = img.size
    x0, y0, x1, y1 = inset, inset, w - 1 - inset, h - 1 - inset
    for x in range(x0, x1 + 1):
        for y in (y0, y1):
            c = top_left if (top_left and y == y0) else color
            img.putpixel((x, y), c)
    for y in range(y0, y1 + 1):
        for x in (x0, x1):
            c = top_left if (top_left and x == x0) else color
            img.putpixel((x, y), c)
    if round_corner:
        for (x, y) in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            img.putpixel((x, y), (0, 0, 0, 0))


def fill(img, inset, color):
    w, h = img.size
    for y in range(inset, h - inset):
        for x in range(inset, w - inset):
            img.putpixel((x, y), color)


# ---------------------------------------------------------------- marcos 9-patch

def panel(fill_c, outer, inner, hi, shade, size=15):
    """Panel PMD: borde exterior redondeado, borde interior, bisel de 1 px y relleno."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    fill(img, 1, rgba(fill_c))
    ring(img, 0, rgba(outer), round_corner=True)
    ring(img, 1, rgba(inner))
    ring(img, 2, rgba(shade), top_left=rgba(hi))
    # esquinas interiores suavizadas
    w = size
    for (x, y) in ((1, 1), (w - 2, 1), (1, w - 2), (w - 2, w - 2)):
        img.putpixel((x, y), rgba(outer))
    return with_drop_shadow(img)


def battle_frame(size=16):
    """Marco del panel de pelea: madera con bisel y línea interior; centro transparente."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ring(img, 0, rgba("ink"), round_corner=True)
    ring(img, 1, rgba("oak"), top_left=rgba("sand"))
    ring(img, 2, rgba("wood"))
    ring(img, 3, rgba("ink"))
    for (x, y) in ((1, 1), (size - 2, 1), (1, size - 2), (size - 2, size - 2)):
        img.putpixel((x, y), rgba("ink"))
    # esquinas interiores redondeadas: 1 px de tinta hacia dentro
    for (x, y) in ((4, 4), (size - 5, 4), (4, size - 5), (size - 5, size - 5)):
        img.putpixel((x, y), rgba("ink"))
    return with_drop_shadow(img)


BUBBLE_TAIL = [
    "#ccc#",
    ".#c#.",
    "..#..",
]

# ---------------------------------------------------------------- íconos

HEART = [
    ".ee.ee.",
    "ebpebbe",
    "ebbbbbe",
    ".ebbbe.",
    "..ebe..",
    "...e...",
]
HEART_KEY = {"e": "ember", "b": "blush", "p": "petal"}
HEART_EMPTY_KEY = {"e": "tan", "b": "sand", "p": "sand"}

POKEBALL_16 = [
    "................",
    ".....######.....",
    "...##FFEEEE##...",
    "..#FFEEEEEEEE#..",
    ".#FEEEEEEEEEEB#.",
    ".#EEEEEEEEEEEB#.",
    "#EEEEE####EEEBB#",
    "######WWWW######",
    "######WWWW######",
    "#WWWWW####WWWSC#",
    ".#PWWWWWWWWWSC#.",
    ".#WWWWWWWWWWSC#.",
    "..#WWWWWWWWSC#..",
    "...##SSSSSS##...",
    ".....######.....",
    "................",
]
POKEBALL_8 = [
    "..####..",
    ".#FEEE#.",
    "#EEEEEB#",
    "###WW###",
    "#WW##WS#",
    "#WWWWWS#",
    ".#SSSS#.",
    "..####..",
]
POKEBALL_KEY = {"#": "ink", "E": "ember", "F": "flame", "B": "berry",
                "W": "paper", "P": "paper", "S": "cream", "C": "sand"}

SPARKLE = [
    "..h..",
    "..p..",
    "hpPph",
    "..p..",
    "..h..",
]
SPARKLE_KEY = {"h": "honey", "p": "paper", "P": "paper"}

BERRY_ROUND = [
    ".....Gg.....",
    "....OGgO....",
    "..OOBBBBOO..",
    ".OBLLBBBBDO.",
    ".OBLBBBBBDO.",
    "OBBBBBBBBBDO",
    "OBBBBBBBBBDO",
    "OBBBBBBBBDDO",
    ".OBBBBBBDDO.",
    ".ODBBBBDDDO.",
    "..OODDDDOO..",
    "....OOOO....",
]
BERRY_LONG = [
    ".....gG.....",
    "....gGgG....",
    "...OOOOOO...",
    "..OBLLBBDO..",
    "..OBLBBBDO..",
    "..OBLBBBDO..",
    "..OBBBBBDO..",
    "..OBBBBBDO..",
    "...OBBBDO...",
    "...OBBBDO...",
    "....OBDO....",
    ".....OO.....",
]
BERRY_PEAR = [
    "......Gg....",
    ".....OGO....",
    "....OBBDO...",
    "....OLBDO...",
    "...OBLBBDO..",
    "..OBLBBBBDO.",
    ".OBLBBBBBBDO",
    ".OBBBBBBBBDO",
    ".OBBBBBBBDDO",
    "..OBBBBBDDO.",
    "...ODDDDDO..",
    "....OOOOO...",
]
SHAPES = {"round": BERRY_ROUND, "long": BERRY_LONG, "pear": BERRY_PEAR}
# baya: (forma, oscuro, base, claro). El orden define el índice en berries.png.
BERRIES = [
    ("cheri", "round", "berry", "ember", "flame"),
    ("chesto", "round", "night", "dusk", "sky"),
    ("pecha", "round", "berry", "blush", "petal"),
    ("rawst", "long", "forest", "leaf", "sprout"),
    ("aspear", "pear", "amber", "honey", "paper"),
    ("oran", "round", "night", "sky", "haze"),
    ("sitrus", "round", "amber", "honey", "paper"),
    ("figy", "long", "berry", "ember", "flame"),
    ("wiki", "long", "plum", "lilac", "orchid"),
    ("mago", "long", "berry", "blush", "petal"),
    ("aguav", "pear", "forest", "grass", "sprout"),
    ("iapapa", "pear", "flame", "amber", "honey"),
]


def berries_sheet():
    sheet = Image.new("RGBA", (12 * len(BERRIES), 12), (0, 0, 0, 0))
    index = {}
    for i, (name, shape, dark, base, light) in enumerate(BERRIES):
        key = {"O": "ink", "D": dark, "B": base, "L": light, "g": "grass", "G": "forest"}
        sheet.alpha_composite(from_map(SHAPES[shape], key), (i * 12, 0))
        index[name] = i
    save(sheet, "berries.png")
    with open(os.path.join(OUT, "berries_index.json"), "w", encoding="utf-8") as f:
        json.dump({"cell": 12, "index": index}, f, indent=1)


def palette_png():
    names = list(PALETTE.keys())
    img = Image.new("RGBA", (len(names), 1))
    for i, n in enumerate(names):
        img.putpixel((i, 0), rgba(n))
    img.save(os.path.join(ROOT, "assets", "palette.png"))
    sw = Image.new("RGBA", (8 * 12, 4 * 12))
    for i, n in enumerate(names):
        sw.paste(Image.new("RGBA", (12, 12), rgba(n)), ((i % 8) * 12, (i // 8) * 12))
    save(sw, "palette_swatches.png", 4)


def check_palette():
    bad = 0
    for name in _written:
        if name == "palette_swatches.png":
            continue
        img = Image.open(os.path.join(OUT, name)).convert("RGBA")
        for px in img.getdata():
            if px[3] > 0 and px[:3] not in _PAL_RGB:
                bad += 1
    if bad:
        raise SystemExit("ERROR: %d píxeles fuera de la paleta" % bad)
    print("paleta OK en", len(_written), "imágenes")


def main():
    palette_png()
    ball = from_map(POKEBALL_16, POKEBALL_KEY)
    save(ball, "icon.png", 2)
    save(ball, "pokeball_16.png")
    save(from_map(POKEBALL_8, POKEBALL_KEY), "pokeball_8.png")
    # Panel crema (PC, menús, burbujas): 9-patch con margen 5 (+1 de sombra abajo/derecha).
    save(panel("cream", "wood", "oak", "paper", "tan"), "panel.png")
    # Panel de diálogo oscuro estilo Explorers (mensajes de combate).
    save(panel("night", "ink", "haze", "dusk", "midnight"), "dialog.png")
    # Botón: normal, encima y presionado.
    save(panel("sand", "wood", "oak", "cream", "tan", size=11), "button.png")
    save(panel("cream", "wood", "oak", "paper", "sand", size=11), "button_hover.png")
    save(panel("tan", "wood", "oak", "sand", "oak", size=11), "button_pressed.png")
    save(panel("paper", "oak", "tan", "paper", "sand", size=11), "slot.png")
    save(battle_frame(), "battle_frame.png")
    tail = from_map(BUBBLE_TAIL, {"#": "wood", "c": "cream"})
    save(with_drop_shadow(tail), "bubble_tail.png")
    save(from_map(HEART, HEART_KEY), "heart.png")
    save(from_map(HEART, HEART_EMPTY_KEY), "heart_empty.png")
    save(from_map(SPARKLE, SPARKLE_KEY), "sparkle.png")
    berries_sheet()
    check_palette()


if __name__ == "__main__":
    sys.exit(main())
