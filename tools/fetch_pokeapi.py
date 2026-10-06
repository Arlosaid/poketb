"""Descarga de PokeAPI (solo en desarrollo) los datos canon que usa el juego y los
guarda normalizados en data/*.json. El juego nunca se conecta a internet.

Genera:
  data/pokemon_roster.json  las 1025 especies (dex y nombre), en orden de la Pokédex nacional
  data/species.json   stats base, tipos, habilidades, captura, EXP base, crecimiento,
                      evolución, rareza (legendario/singular/bebé), hábitat, color, forma
                      y movimientos por nivel
  data/moves.json     los movimientos que aparecen en algún learnset (+ datos para su animación)
  data/abilities.json habilidades: nombre y descripción corta en español
  data/types.json     tabla de efectividad 18x18 y nombres en español
  data/natures.json   naturalezas: stat +/- y sabor favorito/odiado
  data/berries.json   bayas del MVP con sabores y potencia
  data/growth.json    EXP total por nivel para cada curva de crecimiento
  data/characteristics.json  características (IV más alto, Gen 4+): texto en español

Uso:  python -I tools/fetch_pokeapi.py [--max-dex 1025] [--workers 8]
Las respuestas se cachean en tools/.cache/pokeapi/ para no repetir peticiones
(la primera vez son ~4000 peticiones; con 8 hilos tarda unos minutos).
"""
import argparse
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", ".cache", "pokeapi")
API = "https://pokeapi.co/api/v2/"
MAX_DEX = 1025
# Preferencia de juego para los learnsets (el primero que tenga datos de la especie).
# Si ninguno tiene datos se usa el version group con más movimientos por nivel.
VERSION_GROUPS = ["scarlet-violet", "sword-shield", "brilliant-diamond-shining-pearl", "legends-arceus",
                  "ultra-sun-ultra-moon", "sun-moon", "x-y"]
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
    for attempt in range(6):
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
    tmp = cp + ".tmp%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, cp)
    time.sleep(0.05)
    return data


def get_many(paths, workers):
    """Baja en paralelo (y deja en caché) una lista de rutas; devuelve los JSON en el mismo orden."""
    with ThreadPoolExecutor(max_workers=workers) as ex:
        return list(ex.map(get, paths))


def es_name(names, fallback):
    for n in names:
        if n["language"]["name"] == "es":
            return n["name"]
    return fallback


def es_text(entries, key, fallback=""):
    """Último texto en español de una lista multilenguaje (o en inglés si no hay)."""
    es = [e[key] for e in entries if e["language"]["name"] == "es"]
    en = [e[key] for e in entries if e["language"]["name"] == "en"]
    txt = (es or en or [fallback])[-1]
    return " ".join(txt.split())


def id_from_url(url):
    return int(url.rstrip("/").split("/")[-1])


def walk_chain(node, out, alt):
    """Aplana una cadena evolutiva.

    out: {especie: {'to': x, 'level': n}}  (subir de nivel con nivel mínimo; la primera rama)
    alt: {especie: [{'to', 'trigger', 'level', 'happiness', 'time', 'item'}]}  (todas las ramas:
         amistad, piedra, intercambio...)
    """
    for nxt in node["evolves_to"]:
        for det in nxt["evolution_details"]:
            trig = det["trigger"]["name"]
            entry = {"to": nxt["species"]["name"], "trigger": trig}
            if det.get("min_level"):
                entry["level"] = det["min_level"]
            if det.get("min_happiness"):
                entry["happiness"] = det["min_happiness"]
            if det.get("time_of_day"):
                entry["time"] = det["time_of_day"]
            if det.get("item"):
                entry["item"] = det["item"]["name"]
            alt.setdefault(node["species"]["name"], []).append(entry)
            if trig == "level-up" and det.get("min_level") and node["species"]["name"] not in out:
                out[node["species"]["name"]] = {"to": nxt["species"]["name"], "level": det["min_level"]}
        walk_chain(nxt, out, alt)


def pick_learnset(pk):
    """Movimientos por nivel del primer version group preferido que tenga datos."""
    by_vg = {}
    for m in pk["moves"]:
        for d in m["version_group_details"]:
            if d["move_learn_method"]["name"] == "level-up":
                by_vg.setdefault(d["version_group"]["name"], []).append(
                    {"move": m["move"]["name"], "level": d["level_learned_at"]})
    vg = next((v for v in VERSION_GROUPS if v in by_vg), None)
    if vg is None and by_vg:
        vg = max(by_vg, key=lambda v: len(by_vg[v]))
    # sin duplicados (un movimiento en dos niveles: queda el primero)
    seen = {}
    for l in sorted(by_vg.get(vg, []), key=lambda x: (x["level"], x["move"])):
        seen.setdefault(l["move"], l)
    return vg, sorted(seen.values(), key=lambda x: (x["level"], x["move"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-dex", type=int, default=MAX_DEX)
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    listing = get("pokemon-species?limit=%d" % args.max_dex)["results"]
    roster = sorted(({"dex": id_from_url(r["url"]), "name": r["name"]} for r in listing), key=lambda r: r["dex"])
    roster = [r for r in roster if r["dex"] <= args.max_dex]
    print("especies:", len(roster))
    pks = get_many(["pokemon/%d" % sp["dex"] for sp in roster], args.workers)
    print("pokemon ok")
    pss = get_many(["pokemon-species/%d" % sp["dex"] for sp in roster], args.workers)
    print("pokemon-species ok")
    chain_urls = sorted({ps["evolution_chain"]["url"] for ps in pss if ps.get("evolution_chain")})
    evo, evo_alt = {}, {}
    for ch in get_many(chain_urls, args.workers):
        walk_chain(ch["chain"], evo, evo_alt)
    print("cadenas evolutivas ok")

    species_out = {}
    move_names = {"tackle", "struggle"}
    ability_names = set()
    growth_names = set()
    for sp, pk, ps in zip(roster, pks, pss):
        name = sp["name"]
        learnset_vg, learnset = pick_learnset(pk)
        for l in learnset:
            move_names.add(l["move"])
        abilities = [a["ability"]["name"] for a in sorted(pk["abilities"], key=lambda a: a["slot"]) if not a["is_hidden"]]
        hidden = next((a["ability"]["name"] for a in pk["abilities"] if a["is_hidden"]), None)
        ability_names.update(abilities + ([hidden] if hidden else []))
        growth_names.add(ps["growth_rate"]["name"])
        species_out[name] = {
            "dex": sp["dex"],
            "name": name,
            "name_es": es_name(ps["names"], name.capitalize()),
            "genus_es": next((g["genus"] for g in ps["genera"] if g["language"]["name"] == "es"), ""),
            "types": [t["type"]["name"] for t in sorted(pk["types"], key=lambda t: t["slot"])],
            "abilities": abilities,
            "hidden_ability": hidden,
            "base_stats": {STAT_KEYS[s["stat"]["name"]]: s["base_stat"] for s in pk["stats"]},
            "base_experience": pk["base_experience"] or 50,
            "capture_rate": ps["capture_rate"],
            "base_happiness": ps["base_happiness"] if ps["base_happiness"] is not None else 50,
            "growth_rate": ps["growth_rate"]["name"],
            "gender_rate": ps["gender_rate"],
            "generation": id_from_url(ps["generation"]["url"]),
            "legendary": ps["is_legendary"],
            "mythical": ps["is_mythical"],
            "baby": ps["is_baby"],
            "habitat": ps["habitat"]["name"] if ps.get("habitat") else None,
            "color": ps["color"]["name"] if ps.get("color") else None,
            "shape": ps["shape"]["name"] if ps.get("shape") else None,
            "height": pk["height"],
            "weight": pk["weight"],
            "evolves_from": ps["evolves_from_species"]["name"] if ps.get("evolves_from_species") else None,
            "evolution": evo.get(name),
            "evolutions": evo_alt.get(name, []),
            "learnset_version_group": learnset_vg,
            "learnset": learnset,
        }
    print("species", len(species_out))

    moves_out = {}
    move_list = sorted(move_names)
    for mn, mv in zip(move_list, get_many(["move/" + m for m in move_list], args.workers)):
        meta = mv.get("meta") or {}
        moves_out[mn] = {
            "name": mn,
            "name_es": es_name(mv["names"], mn),
            "type": mv["type"]["name"],
            "power": mv["power"],
            "accuracy": mv["accuracy"],
            "pp": mv["pp"],
            "priority": mv["priority"],
            "damage_class": mv["damage_class"]["name"],
            # para elegir su animación (tools/gen_move_fx.py)
            "target": mv["target"]["name"],
            "category": (meta.get("category") or {}).get("name", ""),
            "ailment": (meta.get("ailment") or {}).get("name", "none"),
            "min_hits": meta.get("min_hits"),
            "max_hits": meta.get("max_hits"),
            "drain": meta.get("drain") or 0,
            "healing": meta.get("healing") or 0,
        }
    print("moves", len(moves_out))

    abilities_out = {}
    ab_list = sorted(ability_names)
    for an, ab in zip(ab_list, get_many(["ability/" + a for a in ab_list], args.workers)):
        abilities_out[an] = {
            "name_es": es_name(ab["names"], an.replace("-", " ").title()),
            "desc_es": es_text(ab["flavor_text_entries"], "flavor_text"),
        }
    print("abilities", len(abilities_out))

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

    # Característica canon: stat con el IV más alto (empates por orden PS, Ata, Def, Vel,
    # AtEsp, DefEsp) y ese IV módulo 5. Ver PokemonInstance.characteristic().
    chars_out = {}
    for i in range(1, 31):
        c = get("characteristic/%d" % i)
        desc = c["descriptions"]
        es = next((d["description"] for d in desc if d["language"]["name"] == "es"), None)
        en = next((d["description"] for d in desc if d["language"]["name"] == "en"), "")
        key = "%s_%d" % (STAT_KEYS[c["highest_stat"]["name"]], c["gene_modulo"])
        chars_out[key] = {"es": es or en, "en": en}

    def dump(name, obj, indent=1):
        with open(os.path.join(ROOT, "data", name), "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=indent, sort_keys=True)
        print("wrote data/" + name)

    dump("pokemon_roster.json", {
        "_comment": "Generado por tools/fetch_pokeapi.py: todas las especies de la Pokédex nacional.",
        "species": roster})
    # species.json es grande: sin sangría para que el juego lo lea rápido
    dump("species.json", species_out, None)
    dump("moves.json", moves_out)
    dump("abilities.json", abilities_out)
    dump("types.json", types_out)
    dump("natures.json", natures_out)
    dump("berries.json", berries_out)
    dump("growth.json", growth_out)
    dump("characteristics.json", chars_out)


if __name__ == "__main__":
    sys.exit(main())
