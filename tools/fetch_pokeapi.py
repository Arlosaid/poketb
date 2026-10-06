"""Descarga de PokeAPI (solo en desarrollo) los datos canon que usa el juego y los
guarda normalizados en data/*.json. El juego nunca se conecta a internet.

Genera:
  data/species.json   stats base, tipos, captura, EXP base, crecimiento, evolución, movimientos por nivel
  data/moves.json     los movimientos que aparecen en algún learnset
  data/types.json     tabla de efectividad 18x18 y nombres en español
  data/natures.json   naturalezas: stat +/- y sabor favorito/odiado
  data/berries.json   bayas del MVP con sabores y potencia
  data/growth.json    EXP total por nivel para cada curva de crecimiento

Uso:  python -I tools/fetch_pokeapi.py
Las respuestas se cachean en tools/.cache/pokeapi/ para no repetir peticiones.
"""
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", ".cache", "pokeapi")
API = "https://pokeapi.co/api/v2/"
# Preferencia de juego para los learnsets (el primero que tenga datos de la especie).
VERSION_GROUPS = ["scarlet-violet", "sword-shield", "ultra-sun-ultra-moon", "sun-moon", "x-y"]
BERRIES = ["cheri", "chesto", "pecha", "rawst", "aspear", "oran", "sitrus",
           "figy", "wiki", "mago", "aguav", "iapapa"]
# PokeAPI no trae los sabores en español; nombres de los juegos en español.
FLAVORS_ES_FALLBACK = {"spicy": "Picante", "dry": "Seco", "sweet": "Dulce", "bitter": "Amargo", "sour": "Ácido"}
STAT_KEYS = {"hp": "hp", "attack": "atk", "defense": "def",
             "special-attack": "spa", "special-defense": "spd", "speed": "spe"}


def get(path):
    url = path if path.startswith("http") else API + path
    key = url.replace(API, "").strip("/").replace("/", "_").replace("?", "_").replace("=", "_") or "root"
    cp = os.path.join(CACHE, key + ".json")
    if os.path.exists(cp):
        with open(cp, encoding="utf-8") as f:
            return json.load(f)
    req = urllib.request.Request(url, headers={"User-Agent": "taskbar-pokemon-dev-tool/1.0"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.load(r)
            break
        except Exception as e:  # noqa: BLE001 - reintento simple
            print("  retry", url, e)
            time.sleep(1.5 * (attempt + 1))
    else:
        raise RuntimeError("no se pudo bajar " + url)
    os.makedirs(CACHE, exist_ok=True)
    with open(cp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    time.sleep(0.05)
    return data


def es_name(names, fallback):
    for n in names:
        if n["language"]["name"] == "es":
            return n["name"]
    return fallback


def id_from_url(url):
    return int(url.rstrip("/").split("/")[-1])


def walk_chain(node, out):
    """Aplana una cadena evolutiva en {especie: {'to': x, 'level': n}} (solo level-up por nivel)."""
    for nxt in node["evolves_to"]:
        for det in nxt["evolution_details"]:
            if det["trigger"]["name"] == "level-up" and det.get("min_level"):
                out[node["species"]["name"]] = {"to": nxt["species"]["name"], "level": det["min_level"]}
                break
        walk_chain(nxt, out)


def main():
    with open(os.path.join(ROOT, "data", "pokemon_roster.json"), encoding="utf-8") as f:
        roster = json.load(f)["species"]

    species_out = {}
    move_names = set()
    growth_names = set()
    for sp in roster:
        name = sp["name"]
        print("species", name)
        pk = get("pokemon/%d" % sp["dex"])
        ps = get("pokemon-species/%d" % sp["dex"])
        chain = get(ps["evolution_chain"]["url"])
        evo = {}
        walk_chain(chain["chain"], evo)

        learnset = []
        for vg in VERSION_GROUPS:
            for m in pk["moves"]:
                for d in m["version_group_details"]:
                    if d["version_group"]["name"] == vg and d["move_learn_method"]["name"] == "level-up":
                        learnset.append({"move": m["move"]["name"], "level": d["level_learned_at"]})
            if learnset:
                learnset_vg = vg
                break
        else:
            learnset_vg = None
        learnset.sort(key=lambda x: (x["level"], x["move"]))
        for l in learnset:
            move_names.add(l["move"])

        growth_names.add(ps["growth_rate"]["name"])
        species_out[name] = {
            "dex": sp["dex"],
            "name": name,
            "name_es": es_name(ps["names"], name.capitalize()),
            "genus_es": next((g["genus"] for g in ps["genera"] if g["language"]["name"] == "es"), ""),
            "types": [t["type"]["name"] for t in sorted(pk["types"], key=lambda t: t["slot"])],
            "base_stats": {STAT_KEYS[s["stat"]["name"]]: s["base_stat"] for s in pk["stats"]},
            "base_experience": pk["base_experience"] or 50,
            "capture_rate": ps["capture_rate"],
            "base_happiness": ps["base_happiness"] if ps["base_happiness"] is not None else 50,
            "growth_rate": ps["growth_rate"]["name"],
            "gender_rate": ps["gender_rate"],
            "evolution": evo.get(name),
            "learnset_version_group": learnset_vg,
            "learnset": learnset,
        }

    moves_out = {}
    for mn in sorted(move_names):
        mv = get("move/" + mn)
        moves_out[mn] = {
            "name": mn,
            "name_es": es_name(mv["names"], mn),
            "type": mv["type"]["name"],
            "power": mv["power"],
            "accuracy": mv["accuracy"],
            "pp": mv["pp"],
            "priority": mv["priority"],
            "damage_class": mv["damage_class"]["name"],
        }
    print("moves", len(moves_out))

    types_out = {"names_es": {}, "chart": {}}
    type_list = [t["name"] for t in get("type?limit=100")["results"]]
    type_list = [t for t in type_list if t not in ("unknown", "shadow", "stellar")]
    for tn in type_list:
        t = get("type/" + tn)
        types_out["names_es"][tn] = es_name(t["names"], tn)
        rel = t["damage_relations"]
        row = {}
        for x in rel["double_damage_to"]:
            row[x["name"]] = 2.0
        for x in rel["half_damage_to"]:
            row[x["name"]] = 0.5
        for x in rel["no_damage_to"]:
            row[x["name"]] = 0.0
        types_out["chart"][tn] = row  # atacante -> defensor -> multiplicador (1.0 si falta)

    natures_out = {}
    for n in get("nature?limit=100")["results"]:
        nd = get("nature/" + n["name"])
        natures_out[n["name"]] = {
            "name": n["name"],
            "name_es": es_name(nd["names"], n["name"]),
            "increased": STAT_KEYS.get(nd["increased_stat"]["name"]) if nd["increased_stat"] else None,
            "decreased": STAT_KEYS.get(nd["decreased_stat"]["name"]) if nd["decreased_stat"] else None,
            "likes_flavor": nd["likes_flavor"]["name"] if nd["likes_flavor"] else None,
            "hates_flavor": nd["hates_flavor"]["name"] if nd["hates_flavor"] else None,
        }

    flavors_es = {}
    for fl in get("berry-flavor?limit=20")["results"]:
        fd = get("berry-flavor/" + fl["name"])
        flavors_es[fl["name"]] = es_name(fd["names"], FLAVORS_ES_FALLBACK.get(fl["name"], fl["name"]))

    berries_out = {"flavors_es": flavors_es, "berries": {}}
    for bn in BERRIES:
        b = get("berry/" + bn)
        item = get(b["item"]["url"])
        berries_out["berries"][bn] = {
            "name": bn,
            "name_es": es_name(item["names"], bn.capitalize() + " Berry"),
            "flavors": {f["flavor"]["name"]: f["potency"] for f in b["flavors"] if f["potency"] > 0},
            "firmness": b["firmness"]["name"],
            "size_mm": b["size"],
            "smoothness": b["smoothness"],
        }

    growth_out = {}
    for gn in sorted(growth_names):
        g = get("growth-rate/" + gn)
        growth_out[gn] = [0] * 101
        for lv in g["levels"]:
            growth_out[gn][lv["level"]] = lv["experience"]

    def dump(name, obj):
        with open(os.path.join(ROOT, "data", name), "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1, sort_keys=True)
        print("wrote data/" + name)

    dump("species.json", species_out)
    dump("moves.json", moves_out)
    dump("types.json", types_out)
    dump("natures.json", natures_out)
    dump("berries.json", berries_out)
    dump("growth.json", growth_out)


if __name__ == "__main__":
    sys.exit(main())
