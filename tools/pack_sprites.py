"""Empaqueta los sprites PMD de SpriteCollab en una hoja compacta por especie.

Lee la caché de tools/fetch_sprites.py (~/.cache/spritecollab) y, para cada especie de
data/pokemon_roster.json, escribe en pokemon/species/<nombre>/:

  sheet.png      todos los cuadros que usa el juego, recortados, sin repetidos y empacados
  portraits.png  los retratos de 40x40 que usa el juego, en una tira
  meta.json      animaciones (cuadros por dirección, duraciones, ancla de suelo, bbox,
                 HitFrame...), alias lógicos y el índice de retratos

El juego arma el SpriteFrames en tiempo de ejecución a partir de esto (PokemonActor),
así que no hace falta importar miles de PNG sueltos.

Uso:  python -I tools/pack_sprites.py [--cache DIR] [--only nombre,nombre] [--workers N]
"""
import argparse
import hashlib
import json
import os
import sys
import xml.etree.ElementTree as ET
from concurrent.futures import ProcessPoolExecutor

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CACHE = os.path.join(os.path.expanduser("~"), ".cache", "spritecollab")
OUT = os.path.join(ROOT, "pokemon", "species")
LOG_PATH = os.path.join(ROOT, "tools", "import_log.txt")
with open(os.path.join(ROOT, "tools", "sprite_forms.json"), encoding="utf-8") as _f:
    FORM_FALLBACK = {int(k): v for k, v in json.load(_f).items() if not k.startswith("_")}
DIRS = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]

# Animaciones que empacamos (si existen). El resto no se usa y no ocupa espacio.
WANTED = [
    "Walk", "Idle", "Sleep", "EventSleep", "Wake", "Laying", "Sit", "Eat", "Hop", "Nod",
    "Pose", "LookUp", "Attack", "Strike", "Shoot", "Charge", "Swing", "Double", "Rotate",
    "Hurt", "Pain", "Faint", "Tumble", "FlapAround", "TailWhip", "Twirl",
    "DeepBreath", "Trip", "LeapForth",
    # movimientos (fase 9): cuerpos de ataque específicos (los tiene ~20 % de las especies)
    "Kick", "Head", "SpAttack", "Float", "Hover", "Sink", "Withdraw", "Dance", "Punch", "Uppercut",
    "Jab", "Bite", "Lick", "Scratch", "MultiScratch", "MultiStrike", "QuickStrike", "Slice", "Chop",
    "Slap", "Slam", "Stomp", "HitGround", "Sound", "Sing", "Shock", "Emit", "Gas", "RearUp",
    "Rumble", "Appeal", "Swell", "Shake", "Pull", "Ricochet",
]
# Animaciones lógicas que usa el juego → candidatas en orden de preferencia.
# La última candidata de cada lista debe existir siempre (Walk, Idle o Attack).
ALTERNATIVES = {
    "Walk": ["Walk"],
    "Idle": ["Idle", "Walk"],
    "Sleep": ["Sleep", "EventSleep", "Laying", "Idle"],
    "Wake": ["Wake", "Idle"],
    "Laying": ["Laying", "Sleep", "Idle"],
    "Sit": ["Sit", "Idle"],
    "Eat": ["Eat", "Nod", "Idle"],
    "Hop": ["Hop", "Walk"],
    "Nod": ["Nod", "Hop", "Idle"],
    "Pose": ["Pose", "Hop", "Idle"],
    "LookUp": ["LookUp", "Idle"],
    "Attack": ["Attack", "Strike", "Swing", "Shoot", "Walk"],
    "Strike": ["Strike", "Attack", "Walk"],
    "Shoot": ["Shoot", "SpAttack", "Attack", "Walk"],
    "Charge": ["Charge", "SpAttack", "Idle"],
    "Hurt": ["Hurt", "Pain", "Idle"],
    "Faint": ["Faint", "Hurt", "Idle"],
    "Joy": ["Hop", "Pose", "Nod", "Idle"],
    # Modo mascota (fase 8): estirarse, bailar, lucirse, reírse, tropezar y saltar.
    "Stretch": ["DeepBreath", "Nod", "Idle"],
    "Dance": ["Dance", "Twirl", "Rotate", "Double", "Hop", "Idle"],
    "Show": ["FlapAround", "TailWhip", "Pose", "Twirl", "Rotate", "Hop", "Idle"],
    "Laugh": ["Rotate", "Twirl", "Double", "Hop", "Idle"],
    "Tumble": ["Tumble", "Trip", "Hurt", "Idle"],
    "Trip": ["Trip", "Tumble", "Hurt", "Idle"],
    "Leap": ["LeapForth", "Hop", "Walk"],
    # Movimientos (fase 9): cuerpo de cada estilo de ataque (ver data/move_fx_rules.json).
    "Punch": ["Punch", "Uppercut", "Jab", "Strike", "Attack", "Walk"],
    "Kick": ["Kick", "Stomp", "Strike", "Attack", "Walk"],
    "Bite": ["Bite", "Lick", "Attack", "Walk"],
    "Claw": ["Scratch", "MultiScratch", "Slice", "Strike", "Attack", "Walk"],
    "Chop": ["Chop", "Slice", "Slap", "Swing", "Strike", "Attack", "Walk"],
    "Slam": ["Slam", "HitGround", "Stomp", "Attack", "Walk"],
    "Head": ["Head", "Attack", "Walk"],
    "Swing": ["Swing", "TailWhip", "Strike", "Attack", "Walk"],
    "Spin": ["Rotate", "Twirl", "Double", "Attack", "Walk"],
    "Multi": ["MultiStrike", "MultiScratch", "Double", "Strike", "Attack", "Walk"],
    "Quick": ["QuickStrike", "LeapForth", "Attack", "Walk"],
    "SpAttack": ["SpAttack", "Emit", "Shoot", "Charge", "Attack", "Walk"],
    "Sound": ["Sound", "Sing", "Shoot", "Charge", "Idle"],
    "Sing": ["Sing", "Sound", "Dance", "Charge", "Idle"],
    "Shock": ["Shock", "Emit", "Charge", "Idle"],
    "Gas": ["Gas", "Shoot", "Charge", "Idle"],
    "Rumble": ["Rumble", "Stomp", "HitGround", "Charge", "Idle"],
    "Rise": ["RearUp", "LookUp", "Charge", "Idle"],
    "Float": ["Float", "Hover", "Idle"],
    "Sink": ["Sink", "Withdraw", "Laying", "Idle"],
    "Flap": ["FlapAround", "Hover", "Hop", "Idle"],
    "Appeal": ["Appeal", "Pose", "Twirl", "Hop", "Idle"],
    "Swell": ["Swell", "DeepBreath", "Charge", "Idle"],
    "Shake": ["Shake", "Rotate", "Idle"],
}
LOOPING = {"Walk", "Idle", "Sleep", "EventSleep", "Laying", "Sit", "Eat", "Charge", "FlapAround", "Float", "Hover", "Dance"}
# Retratos que usa el juego (cadenas de respaldo en ui/Bubble.gd).
PORTRAITS = ["Normal", "Happy", "Joyous", "Inspired", "Sad", "Teary-Eyed", "Worried", "Angry",
             "Determined", "Sigh", "Surprised", "Stunned", "Pain", "Crying", "Shouting", "Dizzy"]
PORTRAIT_SIZE = 40
SHEET_W = 512


def rnd(v):
    """Redondeo como Godot (mitades lejos del cero)."""
    return float(int(v + 0.5) if v >= 0 else -int(-v + 0.5))


def parse_anim_data(path):
    root = ET.parse(path).getroot()
    shadow = int(root.findtext("ShadowSize", "1"))
    anims = {}
    for a in root.iter("Anim"):
        name = a.findtext("Name")
        d = {"durations": [int(x.text) for x in a.iter("Duration")]}
        for tag, key in (("FrameWidth", "fw"), ("FrameHeight", "fh"), ("RushFrame", "rush"),
                         ("HitFrame", "hit"), ("ReturnFrame", "ret")):
            if a.findtext(tag) is not None:
                d[key] = int(a.findtext(tag))
        if a.findtext("CopyOf"):
            d["copy_of"] = a.findtext("CopyOf")
        anims[name] = d
    return shadow, anims


def used_rect(img):
    """Rect de píxeles opacos (alfa > 0) o None."""
    return img.getchannel("A").getbbox()


def shadow_center(shadow_img, fw, fh):
    """Centro del marcador de sombra del primer cuadro (fila S), relativo al centro del cuadro."""
    if shadow_img is None:
        return (0.0, rnd(fh * 0.25))
    cell = shadow_img.crop((0, 0, fw, fh))
    a = cell.getchannel("A").load()
    sx = sy = n = 0
    for y in range(fh):
        for x in range(fw):
            if a[x, y] > 127:
                sx += x
                sy += y
                n += 1
    if n == 0:
        return (0.0, rnd(fh * 0.25))
    return (rnd(sx / n + 0.5 - fw / 2.0), rnd(sy / n + 0.5 - fh / 2.0))


def shadow_frames(shadow_img, fw, fh, n_frames, n_dirs, ground):
    """Desplazamiento del marcador de sombra por [dir][cuadro] respecto a `ground` ([] si no se mueve)."""
    if shadow_img is None:
        return []
    out, moves = [], False
    for r in range(n_dirs):
        row = []
        for c in range(n_frames):
            used = used_rect(shadow_img.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)))
            off = (0.0, 0.0)
            if used:
                cx = (used[0] + used[2]) / 2.0
                cy = (used[1] + used[3]) / 2.0
                off = (rnd(cx - fw / 2.0) - ground[0], rnd(cy - fh / 2.0) - ground[1])
            if off != (0.0, 0.0):
                moves = True
            row.append([off[0], off[1]])
        out.append(row)
    return out if moves else []


class Packer:
    """Empaque por estantes de cuadros recortados (sin repetidos)."""

    def __init__(self):
        self.cells = []      # [x, y, w, h, mx, my, fw, fh]
        self.images = []
        self.index = {}      # hash → índice de celda

    def add(self, img, fw, fh):
        bb = used_rect(img)
        if bb is None:
            bb = (0, 0, 1, 1)
        crop = img.crop(bb)
        key = hashlib.blake2b(crop.tobytes() + bytes(str((bb, fw, fh)), "ascii"), digest_size=12).digest()
        if key in self.index:
            return self.index[key]
        i = len(self.cells)
        self.index[key] = i
        self.cells.append([0, 0, crop.width, crop.height, bb[0], bb[1], fw, fh])
        self.images.append(crop)
        return i

    def pack(self):
        order = sorted(range(len(self.cells)), key=lambda i: (-self.cells[i][3], -self.cells[i][2]))
        width = max(SHEET_W, max((c[2] for c in self.cells), default=1) + 2)
        x = y = shelf_h = 0
        for i in order:
            c = self.cells[i]
            if x + c[2] > width:
                x = 0
                y += shelf_h + 1
                shelf_h = 0
            c[0], c[1] = x, y
            x += c[2] + 1
            shelf_h = max(shelf_h, c[3])
        height = y + shelf_h
        sheet = Image.new("RGBA", (width, max(1, height)), (0, 0, 0, 0))
        for c, im in zip(self.cells, self.images):
            sheet.paste(im, (c[0], c[1]))
        return sheet


def save_png(img, path):
    """PNG indexado si cabe en 256 colores (los sprites PMD usan pocos), si no RGBA."""
    colors = img.getcolors(256)
    if colors is not None:
        pal_img = Image.new("P", img.size)
        palette, lookup = [], {}
        for _, rgba in colors:
            if rgba[3] == 0:
                rgba = (0, 0, 0, 0)
            if rgba not in lookup:
                lookup[rgba] = len(palette)
                palette.append(rgba)
        px = img.load()
        data = [lookup[px[x, y] if px[x, y][3] else (0, 0, 0, 0)] for y in range(img.height) for x in range(img.width)]
        pal_img.putdata(data)
        flat = []
        for p in palette:
            flat += p[:3]
        pal_img.putpalette(flat + [0] * (768 - len(flat)))
        pal_img.info["transparency"] = bytes(p[3] for p in palette)
        pal_img.save(path, optimize=True, transparency=pal_img.info["transparency"])
    else:
        img.save(path, optimize=True)


def pack_species(job):
    dex, name, cache = job
    notes = []
    sdir = os.path.join(cache, "sprite", "%04d" % dex, FORM_FALLBACK.get(dex, ""))
    xml_path = os.path.join(sdir, "AnimData.xml")
    if not os.path.exists(xml_path):
        return name, False, ["SKIP %s: sin sprites en SpriteCollab" % name]
    shadow_size, defs = parse_anim_data(xml_path)
    packer = Packer()
    meta = {"dex": dex, "name": name, "shadow_size": shadow_size, "anims": {}, "alias": {}, "portraits": {}}

    for anim_name in WANTED:
        if anim_name not in defs:
            continue
        d = defs[anim_name]
        src_name = d.get("copy_of", anim_name)
        src = defs.get(src_name, d)
        tex_path = os.path.join(sdir, src_name + "-Anim.png")
        if not os.path.exists(tex_path) or "fw" not in src:
            notes.append("WARN %s: falta %s" % (name, src_name + "-Anim.png"))
            continue
        tex = Image.open(tex_path).convert("RGBA")
        fw, fh, durations = src["fw"], src["fh"], src["durations"]
        cols, rows = tex.width // fw, tex.height // fh
        n_frames = min(cols, len(durations))
        if n_frames == 0:
            continue
        n_dirs = 8 if rows >= 8 else 1
        cells = []
        for r in range(n_dirs):
            cells.append([packer.add(tex.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)), fw, fh)
                          for c in range(n_frames)])
        shadow_path = os.path.join(sdir, src_name + "-Shadow.png")
        shadow_img = Image.open(shadow_path).convert("RGBA") if os.path.exists(shadow_path) else None
        ground = shadow_center(shadow_img, fw, fh)
        # bbox: unión de los cuadros de la fila S, relativa al punto de suelo
        bb = None
        for c in range(n_frames):
            u = used_rect(tex.crop((c * fw, 0, (c + 1) * fw, fh)))
            if u:
                bb = u if bb is None else (min(bb[0], u[0]), min(bb[1], u[1]), max(bb[2], u[2]), max(bb[3], u[3]))
        if bb is None:
            bb = (0, 0, fw, fh)
        info = {
            "fw": fw, "fh": fh, "frames": n_frames, "dirs": n_dirs,
            "ground": [ground[0], ground[1]],
            "bbox": [bb[0] - fw / 2.0 - ground[0], bb[1] - fh / 2.0 - ground[1], bb[2] - bb[0], bb[3] - bb[1]],
            "rush": src.get("rush", -1), "hit": src.get("hit", -1), "return": src.get("ret", -1),
            "length_ticks": sum(durations[:n_frames]),
            "durations": durations[:n_frames],
            "loop": anim_name in LOOPING,
            "cells": cells,
        }
        track = shadow_frames(shadow_img, fw, fh, n_frames, n_dirs, ground)
        if track:
            info["shadow"] = track
        meta["anims"][anim_name] = info

    if "Walk" not in meta["anims"] and "Idle" in meta["anims"]:
        meta["anims"]["Walk"] = meta["anims"]["Idle"]
        notes.append("alt %s: Walk -> Idle (copia)" % name)
    for logical, cands in ALTERNATIVES.items():
        found = next((c for c in cands if c in meta["anims"]), "")
        if not found:
            notes.append("ERROR %s: sin animación para %s" % (name, logical))
            continue
        meta["alias"][logical] = found
    if "Idle" not in meta["anims"] and "Walk" not in meta["anims"]:
        return name, False, notes + ["ERROR %s: ni Idle ni Walk" % name]

    # Retratos: tira de 40x40 con los que existan.
    pdir = os.path.join(cache, "portrait", "%04d" % dex)
    ports = []
    for emo in PORTRAITS:
        p = os.path.join(pdir, emo + ".png")
        if os.path.exists(p):
            im = Image.open(p).convert("RGBA")
            if im.size == (PORTRAIT_SIZE, PORTRAIT_SIZE):
                meta["portraits"][emo] = len(ports)
                ports.append(im)
    if "Normal" not in meta["portraits"]:
        notes.append("WARN %s: sin retrato Normal" % name)

    out_dir = os.path.join(OUT, name)
    os.makedirs(out_dir, exist_ok=True)
    sheet = packer.pack()  # asigna las posiciones de las celdas
    meta["cells"] = [c[:6] for c in packer.cells]
    save_png(sheet, os.path.join(out_dir, "sheet.png"))
    strip_path = os.path.join(out_dir, "portraits.png")
    if ports:
        strip = Image.new("RGBA", (PORTRAIT_SIZE * len(ports), PORTRAIT_SIZE), (0, 0, 0, 0))
        for i, im in enumerate(ports):
            strip.paste(im, (i * PORTRAIT_SIZE, 0))
        save_png(strip, strip_path)
    elif os.path.exists(strip_path):
        os.remove(strip_path)
    with open(os.path.join(out_dir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, separators=(",", ":"))
    # el formato viejo (frames.res de tools/import_sprites.gd) ya no se usa
    old = os.path.join(out_dir, "frames.res")
    if os.path.exists(old):
        os.remove(old)
    return name, True, notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    ap.add_argument("--only", default="")
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    args = ap.parse_args()
    with open(os.path.join(ROOT, "data", "pokemon_roster.json"), encoding="utf-8") as f:
        roster = json.load(f)["species"]
    only = set(filter(None, args.only.split(",")))
    jobs = [(sp["dex"], sp["name"], args.cache) for sp in roster if not only or sp["name"] in only]
    log, ok, packed = [], 0, []
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        for name, good, notes in ex.map(pack_species, jobs, chunksize=4):
            log += notes
            if good:
                ok += 1
                packed.append(name)
    if not only:
        # índice de especies con arte (el juego solo usa estas)
        with open(os.path.join(ROOT, "data", "sprite_index.json"), "w", encoding="utf-8") as f:
            json.dump({"_comment": "Generado por tools/pack_sprites.py: especies con sprites empacados.",
                       "species": sorted(packed)}, f, ensure_ascii=False, indent=0)
        with open(LOG_PATH, "w", encoding="utf-8") as f:
            f.write("# Generado por tools/pack_sprites.py\n" + "\n".join(log) + "\n")
    for line in log:
        if line.startswith(("ERROR", "SKIP", "WARN")):
            print(line)
    print("empacadas %d/%d especies" % (ok, len(jobs)))


if __name__ == "__main__":
    sys.exit(main())
