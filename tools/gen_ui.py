"""Genera el arte de UI propio (siempre con colores de la paleta de docs/arte.md).

Para dibujar a mano píxel a píxel se usan mapas de caracteres: cada letra es un color de la paleta.
Salida en assets/ui/. Uso:  python -I tools/gen_ui.py
"""
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


def rgba(name, alpha=255):
    h = PALETTE[name].lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def from_map(rows, key):
    """Convierte un mapa de caracteres en imagen. '.' = transparente."""
    w, h = len(rows[0]), len(rows)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        assert len(row) == w, "fila %d mide %d (esperado %d)" % (y, len(row), w)
        for x, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x, y), rgba(key[ch]))
    return img


def save(img, name, scale=1):
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name))
    print("wrote assets/ui/" + name, img.size)


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
POKEBALL_KEY = {"#": "ink", "E": "ember", "F": "flame", "B": "berry",
                "W": "paper", "P": "paper", "S": "cream", "C": "sand"}


def palette_png():
    names = list(PALETTE.keys())
    img = Image.new("RGBA", (len(names), 1))
    for i, n in enumerate(names):
        img.putpixel((i, 0), rgba(n))
    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    img.save(os.path.join(ROOT, "assets", "palette.png"))
    # Hoja de muestras para revisar a ojo.
    sw = Image.new("RGBA", (8 * 12, 4 * 12))
    for i, n in enumerate(names):
        tile = Image.new("RGBA", (12, 12), rgba(n))
        sw.paste(tile, ((i % 8) * 12, (i // 8) * 12))
    save(sw, "palette_swatches.png", 4)


def main():
    palette_png()
    ball = from_map(POKEBALL_16, POKEBALL_KEY)
    save(ball, "icon.png", 2)        # bandeja e ícono del proyecto (32x32)
    save(ball, "pokeball_16.png")


if __name__ == "__main__":
    sys.exit(main())
