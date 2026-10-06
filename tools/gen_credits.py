"""Genera CREDITS.md a partir de data/sprite_credits.json (creado por fetch_sprites.py)
y de los assets de terceros documentados aquí. Uso: python -I tools/gen_credits.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

THIRD_PARTY = [
    ("Ark Pixel Font (10px proporcional, latín)", "TakWolf", "SIL Open Font License 1.1",
     "https://github.com/TakWolf/ark-pixel-font", "assets/fonts/ark-pixel-OFL.txt"),
    ("Datos de especies, movimientos, naturalezas y bayas", "PokéAPI", "BSD-3-Clause (datos)",
     "https://pokeapi.co", ""),
]


def main():
    with open(os.path.join(ROOT, "data", "sprite_credits.json"), encoding="utf-8") as f:
        sc = json.load(f)
    L = ["# Créditos", "",
         "Proyecto personal y **no comercial**. Pokémon y sus nombres son marcas de Nintendo, Creatures Inc. y GAME FREAK inc.; "
         "este juego no está afiliado ni respaldado por ellos.", "",
         "## Sprites y retratos — PMD SpriteCollab", "",
         "Licencia **%s**. Fuente: %s" % (sc["license"], sc["source"]), "",
         "| # | Especie | Sprites | Retratos |", "|---|---|---|---|"]
    def fmt(lst):
        return ", ".join(("[%s](%s)" % (a["name"], a["contact"]) if a["contact"].startswith("http") else a["name"]) for a in lst) or "—"
    for e in sc["species"]:
        L.append("| %04d | %s | %s | %s |" % (e["dex"], e["name"].capitalize(), fmt(e.get("sprite_authors", [])), fmt(e.get("portrait_authors", []))))
    L += ["", "## Otros recursos", ""]
    for name, author, lic, url, lic_file in THIRD_PARTY:
        L.append("- **%s** — %s · %s · %s%s" % (name, author, lic, url, (" · texto de la licencia: `%s`" % lic_file) if lic_file else ""))
    L += ["", "## Arte propio", "",
          "Marcos de UI, íconos, bayas, Poké Ball, fondos de parallax, cielo y partículas: hechos para este proyecto "
          "(`tools/gen_ui.py`, `tools/gen_backgrounds.py`, `world/*.gdshader`) con la paleta de `docs/arte.md`.", ""]
    with open(os.path.join(ROOT, "CREDITS.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print("wrote CREDITS.md")


if __name__ == "__main__":
    main()
