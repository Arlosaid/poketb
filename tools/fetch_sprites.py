"""Descarga SOLO los sprites/retratos de las especies del roster desde PMDCollab/SpriteCollab.

El repo completo pesa ~2 GB, así que usamos clon parcial (blob:none) + sparse-checkout
en una caché fuera del proyecto, y copiamos la forma base (archivos raíz de cada carpeta;
las subcarpetas 0000/0001 son formas alternativas/shinies y se omiten) a assets/raw/spritecollab/.

También genera data/sprite_credits.json, que usan CREDITS.md y la pantalla de créditos.

Usage:  python -I tools/fetch_sprites.py [--cache DIR]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "https://github.com/PMDCollab/SpriteCollab"


def run(cmd, cwd=None):
    print("$", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def parse_credit_names(path):
    """credit_names.txt: Name \t Discord \t Contact. credits.txt usa el nombre o el ID de Discord."""
    names = {}
    with open(path, encoding="utf-8") as f:
        next(f)  # encabezado
        for line in f:
            parts = line.rstrip("\n").split("\t") + ["", ""]
            name, discord, contact = parts[0], parts[1], parts[2]
            if not name and not discord:
                continue
            info = {"name": name or discord, "contact": contact}
            if name:
                names[name] = info
            if discord:
                names[discord] = info
                names[discord.replace("<@!", "<@")] = info
    return names


def parse_credits_txt(path):
    """credits.txt: fecha \t autor \t estado(CUR/OLD) \t ? \t cambios."""
    authors = []
    if not os.path.exists(path):
        return authors
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3 and parts[1] not in authors:
                authors.append(parts[1])
    return authors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(os.path.expanduser("~"), ".cache", "spritecollab"))
    args = ap.parse_args()

    with open(os.path.join(ROOT, "data", "pokemon_roster.json"), encoding="utf-8") as f:
        roster = json.load(f)["species"]
    folders = []
    for sp in roster:
        d = "%04d" % sp["dex"]
        folders += ["sprite/" + d, "portrait/" + d]

    cache = args.cache
    if not os.path.isdir(os.path.join(cache, ".git")):
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        run(["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse", REPO, cache])
    run(["git", "sparse-checkout", "set", "--no-cone", "/credit_names.txt", "/LICENSE.md"] + ["/" + x + "/*" for x in folders], cwd=cache)
    run(["git", "pull", "--depth", "1", "--ff-only"], cwd=cache)

    dest_root = os.path.join(ROOT, "assets", "raw", "spritecollab")
    names = parse_credit_names(os.path.join(cache, "credit_names.txt"))
    credits = {"license": "CC BY-NC 4.0", "source": REPO, "species": []}

    for sp in roster:
        d = "%04d" % sp["dex"]
        entry = {"dex": sp["dex"], "name": sp["name"]}
        for kind in ("sprite", "portrait"):
            src = os.path.join(cache, kind, d)
            dst = os.path.join(dest_root, kind, d)
            if not os.path.isdir(src):
                print("WARN: missing", kind, d)
                continue
            os.makedirs(dst, exist_ok=True)
            for fn in os.listdir(src):
                p = os.path.join(src, fn)
                if os.path.isfile(p) and (fn.endswith(".png") or fn.endswith(".xml") or fn == "credits.txt"):
                    shutil.copy2(p, os.path.join(dst, fn))
            authors = parse_credits_txt(os.path.join(src, "credits.txt"))
            entry[kind + "_authors"] = [names.get(a, {"name": a, "contact": ""}) for a in authors]
        credits["species"].append(entry)
        print("ok", d, sp["name"])

    shutil.copy2(os.path.join(cache, "LICENSE.md"), os.path.join(dest_root, "LICENSE.md"))
    with open(os.path.join(ROOT, "data", "sprite_credits.json"), "w", encoding="utf-8") as f:
        json.dump(credits, f, ensure_ascii=False, indent=1)
    print("done:", len(roster), "species")


if __name__ == "__main__":
    sys.exit(main())
