"""Genera las rutas 2..N (data/routes/ruta_*.json) para que TODAS las especies con sprite
aparezcan en el modo pelea. Cada especie va a una sola ruta según sus tipos y el nivel en
el que tiene sentido encontrarla (las evoluciones por nivel aparecen desde ese nivel canon;
las de piedra, intercambio o amistad, ~14 niveles después que su forma previa). Los
legendarios y singulares viven en el Santuario del final. La Ruta 1 (tutorial) se conserva
y solo se le agrega "next".

Uso:  python -I tools/gen_routes.py
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# id, nombre, tipos del tema, rango de niveles, secciones de bioma (desde, bioma)
ROUTES = [
    ("ruta_2", "Bosque Verde", ["bug", "grass", "normal"], [6, 14], [(0.0, "bosque"), (0.6, "pradera")]),
    ("ruta_3", "Costa Celeste", ["water", "flying", "normal"], [10, 19], [(0.0, "pradera"), (0.3, "playa")]),
    ("ruta_4", "Monte Roca", ["rock", "ground", "fighting"], [14, 24], [(0.0, "montana")]),
    ("ruta_5", "Prado Chispa", ["electric", "fairy", "normal", "grass"], [18, 28], [(0.0, "pradera"), (0.5, "bosque")]),
    ("ruta_6", "Pantano Sombrío", ["ghost", "poison", "dark", "bug"], [22, 32], [(0.0, "bosque"), (0.4, "pantano")]),
    ("ruta_7", "Volcán Ascuas", ["fire", "ground", "rock"], [26, 37], [(0.0, "montana"), (0.5, "volcan")]),
    ("ruta_8", "Cumbre Helada", ["ice", "steel", "fighting"], [30, 42], [(0.0, "montana"), (0.4, "nieve")]),
    ("ruta_9", "Mar Abierto", ["water", "dragon", "flying"], [36, 48], [(0.0, "playa")]),
    ("ruta_10", "Ruinas Psíquicas", ["psychic", "fairy", "steel", "ghost"], [42, 54], [(0.0, "pradera"), (0.5, "pantano")]),
    ("ruta_11", "Picos del Cielo", ["flying", "dragon", "rock", "electric"], [48, 60], [(0.0, "montana"), (0.6, "nieve")]),
    ("ruta_12", "Calle Victoria", [], [55, 70], [(0.0, "montana"), (0.5, "volcan")]),
    ("ruta_13", "Santuario Legendario", [], [60, 80], [(0.0, "pradera"), (0.35, "nieve"), (0.7, "volcan")]),
]
NOCTURNAL_TYPES = {"ghost", "dark"}


def load(*path):
    with open(os.path.join(ROOT, *path), encoding="utf-8") as f:
        return json.load(f)


def main():
    species = load("data", "species.json")
    with_sprite = set(load("data", "sprite_index.json")["species"])
    personality = load("data", "personality.json")
    nocturnal = set(personality["species"]["nocturnal"])
    base = load("data", "routes", "ruta_1.json")
    in_route_1 = {e["species"] for e in base["day"] + base["night"]}

    # nivel mínimo razonable de cada especie (sigue la cadena evolutiva)
    min_lv = {}

    def lv(name):
        if name in min_lv:
            return min_lv[name]
        sp = species[name]
        prev = sp.get("evolves_from")
        if not prev or prev not in species:
            v = 2
        else:
            pe = species[prev].get("evolution")
            if pe and pe["to"] == name:
                v = int(pe["level"])
            else:
                v = lv(prev) + 14
        min_lv[name] = v
        return v

    for n in species:
        lv(n)

    def bst(n):
        return sum(species[n]["base_stats"].values())

    pools = {r[0]: [] for r in ROUTES}
    for name, sp in species.items():
        if name not in with_sprite or name in in_route_1:
            continue
        if sp["legendary"] or sp["mythical"]:
            pools["ruta_13"].append(name)
            continue
        m = min(lv(name), 66)
        evolved = m > 2
        best, best_score = None, None
        for rid, _nm, types, lr, _secs in ROUTES[:-1]:
            if m > lr[1] + 2:
                continue  # demasiado evolucionado para esta ruta
            match = len(set(sp["types"]) & set(types))
            score = -match * 10.0
            if not types:
                # Calle Victoria: la élite (formas finales fuertes)
                score += -12.0 if bst(name) >= 500 else 30.0
            # las evoluciones prefieren la ruta donde cae su nivel; las básicas, cualquiera
            score += abs(m - (lr[0] + lr[1]) / 2.0) * (0.6 if evolved else 0.05)
            # reparto parejo entre rutas
            score += len(pools[rid]) / 12.0
            if best_score is None or score < best_score:
                best, best_score = rid, score
        pools[best].append(name)

    def weight(n):
        return max(1, int(species[n]["capture_rate"]) // 15)

    out_ids = [r[0] for r in ROUTES]
    for i, (rid, nm, types, lr, secs) in enumerate(ROUTES):
        names = sorted(pools[rid], key=lambda n: species[n]["dex"])
        day, night = [], []
        for n in names:
            w = weight(n)
            noct = n in nocturnal or (set(species[n]["types"]) & NOCTURNAL_TYPES)
            e = {"species": n, "min_level": min(lv(n), lr[1])}
            day.append(dict(e, weight=max(1, w // 3) if noct else w))
            night.append(dict(e, weight=w * 2 if noct else max(1, w // 2)))
        final = rid == "ruta_13"
        if final:
            boss_name = "arceus" if "arceus" in with_sprite else max(names, key=bst)
        else:
            # el más fuerte que tenga sentido a ese nivel (sin paradojas ni pseudolegendarios al inicio)
            cap = 330 + i * 32
            fit = [n for n in names if lv(n) <= lr[1] + 4 and bst(n) <= cap] or names
            boss_name = max(fit, key=bst)
        boss_lv = lr[1] + (10 if final else 4)
        nxt = out_ids[i + 1] if i + 1 < len(out_ids) else None
        route = {
            "id": rid,
            "name_es": "%s (%s)" % (nm, "Ruta %d" % (i + 2)) if not final else nm,
            "encounters_to_boss": 30 if final else 24,
            "level_range": lr,
            "walk_seconds": base["walk_seconds"],
            "sections": [{"from": f, "biome": b} for f, b in secs],
            "day": day,
            "night": night,
            "boss": {"species": boss_name, "level": boss_lv,
                     "title_es": "¡Un %s imponente bloquea el camino!" % species[boss_name]["name_es"]},
            "cleared_es": ("¡Ruta despejada! Rumbo a %s…" % ROUTES[i + 1][1]) if nxt else
                          "¡Santuario despejado! Ya viste a los más raros del mundo.",
            "next": nxt,
            "capture": base["capture"],
            "drops": base["drops"],
            "rewards": base["rewards"],
            "item_drops": base["item_drops"],
        }
        with open(os.path.join(ROOT, "data", "routes", rid + ".json"), "w", encoding="utf-8") as f:
            json.dump(route, f, ensure_ascii=False, indent=1)
        print("%s %-22s Nv %2d-%2d  %3d especies  jefe %s" % (rid, nm, lr[0], lr[1], len(names), boss_name))

    base["next"] = out_ids[0]
    base["cleared_es"] = "¡Ruta despejada! Rumbo al %s…" % ROUTES[0][1]
    with open(os.path.join(ROOT, "data", "routes", "ruta_1.json"), "w", encoding="utf-8") as f:
        json.dump(base, f, ensure_ascii=False, indent="\t")
    total = sum(len(v) for v in pools.values()) + len(in_route_1)
    print("especies en rutas:", total, "de", len(with_sprite), "con sprite")


if __name__ == "__main__":
    sys.exit(main())
