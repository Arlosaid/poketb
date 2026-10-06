"""Asigna una animación a cada movimiento de data/moves.json según data/move_fx_rules.json.

Escribe data/move_fx.json: movimiento → {body, style, part, hits}. El juego (battle/MoveFx.gd)
solo lee ese archivo; para cambiar la animación de un movimiento se edita "overrides" en las
reglas y se vuelve a correr esto.

Uso:  python -I tools/gen_move_fx.py
"""
import collections
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
        return json.load(f)


def fx_for(name, mv, R):
    t = mv["type"]
    out = None
    if mv["damage_class"] == "status":
        for rule in R["status_rules"]:
            if mv.get("category") in rule["category"]:
                out = {"body": rule["body"], "style": rule["style"]}
                break
        out = out or dict(R["status_default"])
        # algunos de estado comparten forma con los de daño (polvos, cantos, viento)
        for rule in R["rules"]:
            if rule["style"] in ("sound", "wind") and any(m in name for m in rule["match"]):
                out = {"body": rule.get("body", out["body"]), "style": rule["style"]}
                break
    else:
        for rule in R["rules"]:
            if any(m in name for m in rule["match"]):
                out = {"body": rule.get("body", "Attack"), "style": rule["style"]}
                break
        if out is None:
            d = R["defaults"]["physical"] if mv["damage_class"] == "physical" else R["defaults"]["special"][t]
            out = dict(d)
        # los especiales de contacto no existen: un "golpe" especial se lanza como proyectil
        if mv["damage_class"] == "special" and out["style"] in ("contact", "punch", "kick", "bite", "slash", "slam", "swing"):
            out["style"] = "projectile"
        # drenar (canon: meta.drain > 0) siempre se ve como drenaje
        if (mv.get("drain") or 0) > 0 and out["style"] not in ("explosion",):
            out["style"] = "drain"
    out["part"] = R["type_part"][t]
    hits = mv.get("max_hits") or 1
    if hits > 1 and out["style"] in ("contact", "punch", "kick", "slash", "projectile"):
        out["style"] = "barrage" if out["style"] == "projectile" else out["style"]
    out["hits"] = min(int(hits), 5)
    if mv.get("target") in ("all-opponents", "all-other-pokemon", "entire-field", "opponents-field", "all-pokemon") \
            and out["style"] in ("projectile", "spray"):
        out["style"] = "wave"
    out.update({k: v for k, v in R["overrides"].get(name, {}).items()})
    assert out["part"] in R["parts"], (name, out["part"])
    return out


def main():
    R = load("move_fx_rules.json")
    moves = load("moves.json")
    out = {}
    for name in sorted(moves):
        out[name] = fx_for(name, moves[name], R)
    with open(os.path.join(ROOT, "data", "move_fx.json"), "w", encoding="utf-8") as f:
        json.dump({"_comment": "Generado por tools/gen_move_fx.py desde data/move_fx_rules.json.", "moves": out},
                  f, ensure_ascii=False, indent=0, sort_keys=True)
    c = collections.Counter(v["style"] for v in out.values())
    print("movimientos:", len(out))
    print(", ".join("%s %d" % kv for kv in c.most_common()))


if __name__ == "__main__":
    sys.exit(main())
