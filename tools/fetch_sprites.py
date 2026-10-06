"""Descarga los sprites y retratos de TODAS las especies desde PMDCollab/SpriteCollab.

El repo completo pesa ~2 GB, así que usamos clon parcial (blob:none) + sparse-checkout
en una caché fuera del proyecto. Solo se bajan los archivos raíz de cada carpeta de especie
(la forma base): AnimData.xml, las hojas -Anim y -Shadow, los retratos y los créditos. Las
subcarpetas (formas alternativas, shinies) y las hojas -Offsets se omiten.

Nada de esto entra al proyecto: tools/pack_sprites.py lee la caché y deja una hoja
compacta por especie en pokemon/species/<nombre>/.

También genera data/sprite_credits.json (lo usan CREDITS.md y la pantalla de créditos).

Uso:  python -I tools/fetch_sprites.py [--cache DIR] [--no-pull]
"""
import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "https://github.com/PMDCollab/SpriteCollab"
DEFAULT_CACHE = os.path.join(os.path.expanduser("~"), ".cache", "spritecollab")
SPARSE = [
    "/credit_names.txt", "/LICENSE.md",
    "/sprite/*/AnimData.xml", "/sprite/*/*-Anim.png", "/sprite/*/*-Shadow.png", "/sprite/*/credits.txt",
    "/portrait/*/*.png", "/portrait/*/credits.txt",
]
# Especies sin sprite de la forma base pero con el de una forma alternativa (dex → subcarpeta).
with open(os.path.join(ROOT, "tools", "sprite_forms.json"), encoding="utf-8") as _f:
    FORM_FALLBACK = {int(k): v for k, v in json.load(_f).items() if not k.startswith("_")}


def run(cmd, cwd=None):
    print("$", " ".join(cmd), flush=True)
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


def write_credits(cache, roster):
    """data/sprite_credits.json con los autores de cada especie que tenga arte en la caché."""
    names = parse_credit_names(os.path.join(cache, "credit_names.txt"))
    credits = {"license": "CC BY-NC 4.0", "source": REPO, "species": []}
    for sp in roster:
        d = "%04d" % sp["dex"]
        entry = {"dex": sp["dex"], "name": sp["name"]}
        for kind in ("sprite", "portrait"):
            folder = os.path.join(cache, kind, d)
            if kind == "sprite" and sp["dex"] in FORM_FALLBACK:
                folder = os.path.join(folder, FORM_FALLBACK[sp["dex"]])
            authors = parse_credits_txt(os.path.join(folder, "credits.txt"))
            entry[kind + "_authors"] = [names.get(a, {"name": a, "contact": ""}) for a in authors]
        credits["species"].append(entry)
    with open(os.path.join(ROOT, "data", "sprite_credits.json"), "w", encoding="utf-8") as f:
        json.dump(credits, f, ensure_ascii=False, indent=1)
    print("créditos:", len(credits["species"]), "especies")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    ap.add_argument("--no-pull", action="store_true", help="no tocar git; solo regenerar créditos")
    args = ap.parse_args()
    cache = args.cache

    if not args.no_pull:
        if not os.path.isdir(os.path.join(cache, ".git")):
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            run(["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse", REPO, cache])
        forms = []
        for dex, sub in FORM_FALLBACK.items():
            base = "/sprite/%04d/%s/" % (dex, sub)
            forms += [base + "AnimData.xml", base + "*-Anim.png", base + "*-Shadow.png", base + "credits.txt"]
        run(["git", "sparse-checkout", "set", "--no-cone"] + SPARSE + forms, cwd=cache)
        # clon superficial: un pull --ff-only falla si upstream reescribió; la caché es solo nuestra
        run(["git", "fetch", "--depth", "1", "origin"], cwd=cache)
        run(["git", "reset", "--hard", "FETCH_HEAD"], cwd=cache)

    with open(os.path.join(ROOT, "data", "pokemon_roster.json"), encoding="utf-8") as f:
        roster = json.load(f)["species"]
    write_credits(cache, roster)
    missing = [sp["name"] for sp in roster
               if not os.path.exists(os.path.join(cache, "sprite", "%04d" % sp["dex"], FORM_FALLBACK.get(sp["dex"], ""), "AnimData.xml"))]
    print("sin sprites:", len(missing), missing)


if __name__ == "__main__":
    sys.exit(main())
