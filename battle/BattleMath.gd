class_name BattleMath
extends RefCounted
## Fórmulas canon (simplificadas al MVP: solo movimientos de daño, sin estados).

## Probabilidad base de crítico (Gen 7+: 1/24, x1.5).
const CRIT_CHANCE := 1.0 / 24.0
const CRIT_MULT := 1.5
## Con amistad alta (efecto de afecto Gen 6+).
const AFFECTION_FRIENDSHIP := 200
const AFFECTION_CRIT_CHANCE := 1.0 / 8.0
const AFFECTION_ENDURE_CHANCE := 0.10


## Elige un movimiento: pondera potencia × efectividad × STAB, con algo de azar.
static func choose_move(att: PokemonInstance, def: PokemonInstance, rng: RandomNumberGenerator) -> String:
	var best := att.moves[0]
	var best_score := -1.0
	for m in att.moves:
		var md := SpeciesDB.move(m)
		var power := float(md["power"]) if md["power"] != null else 40.0
		power *= 1.0 + att.mastery(m) * float(Progression.mastery_cfg()["pct_per_level"]) / 100.0
		var eff := SpeciesDB.effectiveness(md["type"], def.types())
		var stab := 1.5 if md["type"] in att.types() else 1.0
		var acc := float(md["accuracy"]) / 100.0 if md["accuracy"] != null else 1.0
		var score := power * eff * stab * acc * rng.randf_range(0.7, 1.0)
		if score > best_score:
			best_score = score
			best = m
	return best


## Resultado de un ataque: {damage, eff, crit, miss, move, type, affection_crit}
static func attack(att: PokemonInstance, def: PokemonInstance, move_name: String, rng: RandomNumberGenerator, affection := false) -> Dictionary:
	var md := SpeciesDB.move(move_name)
	var r := {"move": move_name, "type": md["type"], "damage": 0, "eff": 1.0, "crit": false, "miss": false, "affection_crit": false}
	if md["accuracy"] != null and rng.randf() * 100.0 >= float(md["accuracy"]):
		r["miss"] = true
		return r
	var physical: bool = md["damage_class"] == "physical"
	var a := att.stat("atk" if physical else "spa")
	var d := def.stat("def" if physical else "spd")
	var power := float(md["power"])
	var owned := att.uid != 0
	if owned:
		# maestría del movimiento (+10% de potencia por nivel)
		power *= 1.0 + att.mastery(move_name) * float(Progression.mastery_cfg()["pct_per_level"]) / 100.0
	var lvl := float(att.level)
	var base := floorf(floorf(floorf(2.0 * lvl / 5.0 + 2.0) * power * a / d) / 50.0) + 2.0
	var stab := 1.5 if md["type"] in att.types() else 1.0
	var eff := SpeciesDB.effectiveness(md["type"], def.types())
	var crit_p := AFFECTION_CRIT_CHANCE if affection else CRIT_CHANCE
	if owned:
		crit_p += (Game.roster.fx("crit") + Progression.held_effect(att.held, "crit")) / 100.0
	var crit := rng.randf() < crit_p
	r["crit"] = crit
	r["affection_crit"] = crit and affection and rng.randf() < 0.5
	r["eff"] = eff
	if eff == 0.0:
		return r
	var dmg: float = base * (CRIT_MULT if crit else 1.0) * rng.randf_range(0.85, 1.0) * stab * eff
	if owned:
		dmg *= 1.0 + Game.roster.fx("dmg") / 100.0
	r["damage"] = maxi(1, int(floor(dmg)))
	return r


## EXP (fórmula Gen 7+ escalada). Jefe x1.5.
static func exp_gain(winner_level: int, foe: PokemonInstance, boss: bool) -> int:
	var b := float(foe.data()["base_experience"])
	var l := float(foe.level)
	var lp := float(winner_level)
	var scale := pow((2.0 * l + 10.0) / (l + lp + 10.0), 2.5)
	var e := floorf(b * l / 5.0 * scale) + 1.0
	return int(e * (1.5 if boss else 1.0))


## Captura Gen 5+: devuelve las comprobaciones superadas (0..4). 4 = atrapado;
## el número de sacudidas que se ven es min(resultado, 3).
static func capture_checks(foe: PokemonInstance, rng: RandomNumberGenerator, ball := 1.0) -> int:
	var m := float(foe.max_hp())
	var h := float(maxi(1, foe.hp))
	var rate := float(foe.data()["capture_rate"])
	var a := ((3.0 * m - 2.0 * h) * rate * ball) / (3.0 * m)
	if a >= 255.0:
		return 4
	var b := 65536.0 / pow(255.0 / a, 0.1875)
	for i in 4:
		if rng.randi_range(0, 65535) >= b:
			return i
	return 4


## Elige de una tabla [{key: x, weight: n}, ...].
static func pick_weighted(table: Array, key: String, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for e in table:
		total += float(e["weight"])
	var r := rng.randf() * total
	for e in table:
		r -= float(e["weight"])
		if r <= 0.0:
			return e[key]
	return table[-1][key]
