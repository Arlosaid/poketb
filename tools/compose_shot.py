"""Compone una captura del viewport (fondo transparente) sobre un escritorio neutro con
una barra de tareas simulada, para revisar el acabado sin capturar el escritorio real.

Uso: python -I tools/compose_shot.py shots/x.png [--x0 0 --x1 600] [--zoom 2] [--bg light|dark]
Salida: shots/x_view.png
"""
import argparse
import os

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("--x0", type=int, default=0)
ap.add_argument("--x1", type=int, default=0)
ap.add_argument("--zoom", type=int, default=2)
ap.add_argument("--bg", default="light")
a = ap.parse_args()

src = Image.open(a.src).convert("RGBA")
w, h = src.size
x1 = a.x1 or w
src = src.crop((a.x0, 0, x1, h))
w = src.width
desk = (196, 206, 214, 255) if a.bg == "light" else (38, 44, 58, 255)
bar_h = 24  # barra de tareas (px lógicos, 48 px físicos a x2)
canvas = Image.new("RGBA", (w, h + bar_h), desk)
bar = Image.new("RGBA", (w, bar_h), (32, 32, 36, 255))
canvas.paste(bar, (0, h))
canvas.alpha_composite(src, (0, 0))
canvas = canvas.resize((w * a.zoom, (h + bar_h) * a.zoom), Image.NEAREST)
out = os.path.splitext(a.src)[0] + "_view.png"
canvas.convert("RGB").save(out)
print("wrote", out, canvas.size)
