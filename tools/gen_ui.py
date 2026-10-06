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


Z_SMALL = [
    "pppp",
    "..p.",
    ".p..",
    "pppp",
]
Z_BIG = [
    "ppppp",
    "...p.",
    "..p..",
    ".p...",
    "ppppp",
]
ANGER = [
    ".e.e.",
    "ee.ee",
    ".....",
    "ee.ee",
    ".e.e.",
]
DROP = [
    "..h..",
    ".hhs.",
    "hhpss",
    "hpsss",
    ".sss.",
]


def outlined(img, color="ink"):
    """Contorno de 1 px (4 vecinos) alrededor de los píxeles opacos."""
    w, h = img.size
    out = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    src = img.load()
    o = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] > 0:
                for dx, dy in ((0, 1), (2, 1), (1, 0), (1, 2), (1, 1)):
                    if o[x + dx, y + dy][3] == 0:
                        o[x + dx, y + dy] = rgba(color)
    out.alpha_composite(img, (1, 1))
    return out


def dust_sheet():
    """Nubecita de polvo al aterrizar: 3 cuadros de 9x5 que se expanden y se deshacen."""
    sheet = Image.new("RGBA", (27, 5), (0, 0, 0, 0))
    frames = [
        ["..m...m..", ".mpm.mpm.", "..m...m..", ".........", "........."],
        [".m.....m.", "mpm...mpm", ".mm...mm.", "........."[0:9], "........."],
        ["m.......m", ".m.....m.", ".........", ".........", "........."],
    ]
    for i, fr in enumerate(frames):
        sheet.alpha_composite(from_map(fr, {"m": "mist", "p": "paper"}), (i * 9, 0))
    return sheet


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


# --- Objetos, vitaminas y moneda (12x12; la moneda 8x8) -------------------------------------
# Orden = campo "icon" de data/items.json.
ITEM_ICONS = [
    # 0 Cinta Fuerte
    ["............", "............", "..OOOOOOOO..", ".OBBBBBBBBO.", ".OBLLLLLLBO.", ".OBBBBBBBBO.",
     ".OBDDDDDDBO.", ".OBBBBBBBBO.", ".OBBBBBBBBO.", "..OOOOOOOO..", "............", "............"],
    # 1 Gafas Especiales
    ["............", "............", "............", ".OOOO..OOOO.", "OLLLLOOLLLLO", "OLMMLOOLMMLO",
     "OLLLLOOLLLLO", ".OOOO..OOOO.", "............", "............", "............", "............"],
    # 2 Casco Dentado
    ["............", "....OOOO....", "..OOLLBBOO..", ".OLLBBBBBDO.", ".OLBBBBBBDO.", ".OBBBBBBBDO.",
     "OOOOOOOOOOOO", "OLOLOOOOLOLO", ".O.O....O.O.", "............", "............", "............"],
    # 3 Chaleco Asalto
    ["............", ".OOO....OOO.", ".OBBO..OBBO.", ".OBBBOOBBBO.", ".OBBBLLBBBO.", ".OBDBLLBDBO.",
     ".OBDBLLBDBO.", ".OBBBLLBBBO.", ".OBBBBBBBBO.", ".OOOOOOOOOO.", "............", "............"],
    # 4 Garra Rápida
    ["............", "......OO....", ".....OLLO...", "....OLLO....", "...OLLLO....", "..OLLLBO....",
     "..OLLBO.....", ".OLLBO......", ".OLBO.......", ".OBO........", ".OO.........", "............"],
    # 5 Restos
    ["............", "...OOOOOO...", "..OGGGGGGO..", ".OGLLGGLLGO.", ".OGLLGGLLGO.", ".OGGGGGGGGO.",
     ".OEEEEEEEEO.", "..OGGGGGGO..", "...OOOOOO...", "............", "............", "............"],
    # 6 Periscopio
    ["...OOOOOO...", "..OMMOOMMO..", ".OMMMOOMMMO.", "OMMMMOOMMMMO", "OMMMMOOMMMMO", "OOOOOOOOOOOO",
     "OOOOOOOOOOOO", "OMMMMOOMMMMO", "OMMMMOOMMMMO", ".OMMMOOMMMO.", "..OMMOOMMO..", "...OOOOOO..."],
    # 7 Huevo Suerte
    ["............", "....OOOO....", "...OPPPPO...", "..OPPLPPPO..", "..OPPPPPPO..", ".OPPPPPPPDO.",
     ".OPPBBPPPDO.", ".OPPBBPPPDO.", ".OPPPPPPDDO.", "..OPPPPDDO..", "...ODDDDO...", "....OOOO...."],
    # 8 Moneda Amuleto
    ["...OOOOOO...", "..OHHHHHHO..", ".OHHAAAAHHO.", "OHHAHHHHAHHO", "OHAHHPPHHAHO", "OHAHPHHHHAHO",
     "OHAHHHHHHAHO", "OHAHHHHHHAHO", ".OHAAAAAAHO.", "..OAAAAAAO..", "...OOOOOO...", "............"],
]
ITEM_KEY = {
    "O": "ink", "B": "ember", "D": "berry", "L": "honey", "M": "mist", "G": "grass", "E": "forest",
    "P": "petal", "H": "honey", "A": "amber",
}
# Casco y chaleco usan otros colores base: se pintan con su propia clave.
ITEM_KEYS = {
    2: {"O": "ink", "B": "dusk", "D": "night", "L": "haze"},
    3: {"O": "ink", "B": "teal", "D": "forest", "L": "mint"},
    4: {"O": "ink", "B": "tan", "L": "paper"},
    5: {"O": "ink", "G": "grass", "L": "lime", "E": "forest"},
    7: {"O": "ink", "P": "petal", "L": "paper", "B": "blush", "D": "blush"},
}
COIN = ["..OOOO..", ".OHHHAO.", "OHHPHHAO", "OHHHHHAO", "OHHHHHAO", "OHHHHAAO", ".OAAAAO.", "..OOOO.."]
VITAMIN = ["............", "....OOOO....", "....OTTO....", "....OOOO....", "...OLLLLO...", "..OLKKKKLO..",
           "..OLKPPKLO..", "..OLKPPKLO..", "..OLKKKKLO..", "..OLKKKKLO..", "...OOOOOO...", "............"]
VITAMIN_COLORS = ["ember", "flame", "honey", "orchid", "mint", "sky"]  # hp atk def spa spd spe


def items_sheet():
    sheet = Image.new("RGBA", (12 * len(ITEM_ICONS), 12), (0, 0, 0, 0))
    for i, rows in enumerate(ITEM_ICONS):
        key = dict(ITEM_KEY)
        key.update(ITEM_KEYS.get(i, {}))
        sheet.alpha_composite(from_map(rows, key), (i * 12, 0))
    save(sheet, "items.png")
    vit = Image.new("RGBA", (12 * len(VITAMIN_COLORS), 12), (0, 0, 0, 0))
    for i, c in enumerate(VITAMIN_COLORS):
        key = {"O": "ink", "T": "tan", "L": "paper", "K": c, "P": "paper"}
        vit.alpha_composite(from_map(VITAMIN, key), (i * 12, 0))
    save(vit, "vitamins.png")
    save(from_map(COIN, {"O": "ink", "H": "honey", "A": "amber", "P": "paper"}), "coin.png")


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


# ---------------------------------------------------------------- modo mascota (fase 8)
# Globo de emoción chiquito (estilo de los compañeros de HGSS): 11x13 + sombra.
EMOTE_BUBBLE = [
    "..#######..",
    ".#ppppppp#.",
    "#ppppppppp#",
    "#ppppppppp#",
    "#ppppppppp#",
    "#ppppppppp#",
    "#ppppppppp#",
    "#ppppppppp#",
    "#ppppppppp#",
    ".#ppppppp#.",
    "..###p###..",
    "....#p#....",
    ".....#.....",
]
# Íconos de 7x7 que van dentro del globo. El orden define el índice en emotes.png
# (ver ui/Emote.gd).
EMOTE_ICONS = [
    ("heart", [
        ".ee.ee.",
        "ebpebbe",
        "ebbbbbe",
        ".ebbbe.",
        "..ebe..",
        "...e...",
        ".......",
    ], {"e": "ember", "b": "blush", "p": "petal"}),
    ("note", [
        "..nnnnn",
        "..n...n",
        "..n...n",
        "..n...n",
        "nnn.nnn",
        "nnn.nnn",
        ".n...n.",
    ], {"n": "night"}),
    ("exclaim", [
        "..eee..",
        "..eee..",
        "..eee..",
        "...e...",
        "...e...",
        ".......",
        "..eee..",
    ], {"e": "ember"}),
    ("question", [
        "..ddd..",
        ".d...d.",
        ".....d.",
        "...dd..",
        "...d...",
        ".......",
        "...d...",
    ], {"d": "dusk"}),
    ("dots", [
        ".......",
        ".......",
        ".......",
        ".o.o.o.",
        ".......",
        ".......",
        ".......",
    ], {"o": "wood"}),
    ("anger", [
        ".......",
        ".e.e...",
        "ee.ee..",
        ".......",
        "ee.ee..",
        ".e.e...",
        ".......",
    ], {"e": "ember"}),
    ("sweat", [
        "...h...",
        "...h...",
        "..hhs..",
        ".hpsss.",
        ".hssss.",
        "..sss..",
        ".......",
    ], {"h": "haze", "p": "paper", "s": "sky"}),
    ("zzz", [
        ".......",
        ".ddddd.",
        "....d..",
        "...d...",
        "..d....",
        ".ddddd.",
        ".......",
    ], {"d": "dusk"}),
    ("star", [
        "...a...",
        "...a...",
        "..aha..",
        "aahhhaa",
        "..aha..",
        "...a...",
        "...a...",
    ], {"a": "amber", "h": "honey"}),
    ("berry", [
        "....g..",
        "...g...",
        ".BBBBB.",
        "BLBBBBD",
        "BBBBBBD",
        ".BBBDD.",
        "..DDD..",
    ], {"g": "leaf", "B": "ember", "L": "petal", "D": "berry"}),
    ("ball", [
        "..FFF..",
        ".aFFwF.",
        "FFwFFFF",
        "FFFFFwE",
        "FwFFFEE",
        ".FFFEE.",
        "..EEE..",
    ], {"F": "flame", "a": "amber", "w": "paper", "E": "ember"}),
]
# Pelota de juguete (se lanza, rebota y la persiguen).
TOY_BALL = [
    "..####..",
    ".#aFFF#.",
    "#aFFwFF#",
    "#FwFFFF#",
    "#FFFFwE#",
    "#FFwFEE#",
    ".#FEEE#.",
    "..####..",
]
TOY_BALL_KEY = {"#": "ink", "a": "amber", "F": "flame", "w": "paper", "E": "ember"}
# Botón compacto (9-patch, margen 2): normal, encima y presionado.
CHIP = [
    ".####.",
    "#hhhh#",
    "#hccs#",
    "#hccs#",
    "#ssss#",
    ".####.",
]
# Globo de texto delgado (9-patch, margen 2) y su colita.
TEXT_BUBBLE = [
    ".#####.",
    "#ppppp#",
    "#ppppp#",
    "#ppppp#",
    "#ppppp#",
    "#ppppp#",
    ".#####.",
]
TEXT_TAIL = [
    "#ppp#",
    ".#p#.",
    "..#..",
]


def _disc(img, cx, cy, r, color, hole=None):
    for y in range(img.height):
        for x in range(img.width):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                if hole and (x + 0.5 - hole[0]) ** 2 + (y + 0.5 - hole[1]) ** 2 <= hole[2] ** 2:
                    continue
                img.putpixel((x, y), rgba(color))


def action_icons():
    """Íconos de 9x9 (con contorno) para la barrita de acciones: baya, pelota,
    dormir, despertar y ficha. Orden = índice en actions.png (ver ui/ActionBar.gd)."""
    icons = []
    berry = dict((n, (m, k)) for n, m, k in EMOTE_ICONS)["berry"]
    icons.append(outlined(from_map(*berry)))
    icons.append(from_map(TOY_BALL, TOY_BALL_KEY))
    moon = Image.new("RGBA", (7, 7), (0, 0, 0, 0))
    _disc(moon, 3.5, 3.5, 3.5, "honey", hole=(5.3, 2.4, 2.9))
    icons.append(outlined(moon, "wood"))
    sun = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
    _disc(sun, 4.5, 4.5, 2.6, "amber")
    sun.putpixel((4, 4), rgba("honey"))
    sun.putpixel((3, 3), rgba("honey"))
    for (x, y) in ((4, 0), (4, 8), (0, 4), (8, 4), (1, 1), (7, 1), (1, 7), (7, 7)):
        sun.putpixel((x, y), rgba("flame"))
    icons.append(sun)
    card = from_map([
        "#########",
        "#ppppppp#",
        "#bbpooop#",
        "#bbppppp#",
        "#pppooop#",
        "#ppppppp#",
        "#pooooop#",
        "#ppppppp#",
        "#########",
    ], {"#": "wood", "p": "paper", "b": "blush", "o": "oak"})
    icons.append(card)
    sheet = Image.new("RGBA", (9 * len(icons), 9), (0, 0, 0, 0))
    for i, ic in enumerate(icons):
        sheet.alpha_composite(ic, (i * 9 + (9 - ic.width) // 2, (9 - ic.height) // 2))
    save(sheet, "actions.png")


def pet_ui():
    save(with_drop_shadow(from_map(EMOTE_BUBBLE, {"#": "wood", "p": "paper"})), "emote_bubble.png")
    sheet = Image.new("RGBA", (7 * len(EMOTE_ICONS), 7), (0, 0, 0, 0))
    for i, (_n, rows, key) in enumerate(EMOTE_ICONS):
        sheet.alpha_composite(from_map(rows, key), (i * 7, 0))
    save(sheet, "emotes.png")
    with open(os.path.join(OUT, "emotes_index.json"), "w", encoding="utf-8") as f:
        json.dump({"size": 7, "index": {n: i for i, (n, _r, _k) in enumerate(EMOTE_ICONS)}}, f, indent=1)
    save(from_map(TOY_BALL, TOY_BALL_KEY), "toy_ball.png")
    save(with_drop_shadow(from_map(CHIP, {"#": "wood", "h": "paper", "c": "cream", "s": "sand"})), "chip.png")
    save(with_drop_shadow(from_map(CHIP, {"#": "wood", "h": "paper", "c": "paper", "s": "cream"})), "chip_hover.png")
    save(with_drop_shadow(from_map(CHIP, {"#": "wood", "h": "tan", "c": "sand", "s": "sand"})), "chip_pressed.png")
    save(with_drop_shadow(from_map(TEXT_BUBBLE, {"#": "wood", "p": "paper"})), "text_bubble.png")
    save(with_drop_shadow(from_map(TEXT_TAIL, {"#": "wood", "p": "paper"})), "text_tail.png")
    action_icons()


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
    save(outlined(from_map(Z_SMALL, {"p": "paper"}), "dusk"), "z_small.png")
    save(outlined(from_map(Z_BIG, {"p": "paper"}), "dusk"), "z_big.png")
    save(from_map(ANGER, {"e": "ember"}), "anger.png")
    save(outlined(from_map(DROP, {"h": "mist", "p": "paper", "s": "haze"}), "dusk"), "sweat.png")
    save(dust_sheet(), "dust.png")
    berries_sheet()
    items_sheet()
    pet_ui()
    check_palette()


if __name__ == "__main__":
    sys.exit(main())
