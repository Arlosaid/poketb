class_name PokemonInstance
extends RefCounted
## Un Pokémon concreto del jugador (o un salvaje): datos canon + estado de mascota.

const MAX_MOVES := 4
const STATS: Array[String] = ["hp", "atk", "def", "spa", "spd", "spe"]

var uid := 0
var species := "charmander"
var nickname := ""
var level := 5
var xp := 0
var nature := "hardy"
var ivs := {}
var hp := 1
var moves: Array[String] = []
## Amistad canon 0..255.
var friendship := 70
## Saciedad 0..100 (100 = lleno). Baja con el tiempo y al pelear.
var fullness := 80.0
## Energía 0..100. Baja peleando y se recupera en casa.
var energy := 100.0
## Sabores descubiertos: {"spicy": "likes" | "hates" | "neutral"}
var known_flavors := {}
## Control anti-abuso de caricias: caricias contadas en la hora actual.
var pets_this_hour := 0
var pets_hour_start := 0.0
var caught_at := 0.0
var wild := false
## PS fraccionarios acumulados al descansar (no se guardan).
var hp_regen_acc := 0.0


static func create(sp: String, lvl: int, rng: RandomNumberGenerator = null) -> PokemonInstance:
	var r := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var p := PokemonInstance.new()
	p.species = sp
	p.level = lvl
	p.xp = SpeciesDB.exp_for_level(p.data()["growth_rate"], lvl)
	var nat_names := SpeciesDB.natures().keys()
	p.nature = nat_names[r.randi_range(0, nat_names.size() - 1)]
	for s in STATS:
		p.ivs[s] = r.randi_range(0, 31)
	p.friendship = int(p.data()["base_happiness"])
	p.moves = p.moves_at_level(lvl)
	p.hp = p.max_hp()
	return p


func data() -> Dictionary:
	return SpeciesDB.species(species)


func display_name() -> String:
	return nickname if nickname != "" else String(data()["name_es"])


func types() -> Array:
	return data()["types"]


## Stat canon (EV = 0). HP: ((2B+IV)·L/100)+L+10; resto: (((2B+IV)·L/100)+5)·naturaleza.
func stat(s: String) -> int:
	var base := int(data()["base_stats"][s])
	var iv := int(ivs.get(s, 15))
	if s == "hp":
		return int(floor((2 * base + iv) * level / 100.0)) + level + 10
	var v := int(floor((2 * base + iv) * level / 100.0)) + 5
	var n := SpeciesDB.nature(nature)
	if n["increased"] == s:
		v = int(floor(v * 1.1))
	elif n["decreased"] == s:
		v = int(floor(v * 0.9))
	return v


func max_hp() -> int:
	return stat("hp")


func hp_frac() -> float:
	return clampf(float(hp) / max_hp(), 0.0, 1.0)


func is_fainted() -> bool:
	return hp <= 0


## Últimos 4 movimientos de daño aprendidos hasta `lvl` (en el MVP no hay movimientos de estado).
func moves_at_level(lvl: int) -> Array[String]:
	var out: Array[String] = []
	for m in data()["learnset"]:
		if int(m["level"]) <= lvl:
			var md := SpeciesDB.move(m["move"])
			if md["damage_class"] != "status" and md["power"] != null and m["move"] not in out:
				out.append(m["move"])
	if out.is_empty():
		out.append("tackle")
	while out.size() > MAX_MOVES:
		out.pop_front()
	return out


func exp_to_next() -> int:
	return SpeciesDB.exp_for_level(data()["growth_rate"], level + 1) - xp


## Fracción de la barra de EXP dentro del nivel actual.
func exp_frac() -> float:
	var g: String = data()["growth_rate"]
	var a := SpeciesDB.exp_for_level(g, level)
	var b := SpeciesDB.exp_for_level(g, level + 1)
	return clampf(float(xp - a) / maxf(1.0, b - a), 0.0, 1.0)


## Suma EXP. Devuelve los niveles alcanzados (puede ser vacío).
func gain_exp(amount: int) -> Array[int]:
	var ups: Array[int] = []
	if level >= 100:
		return ups
	xp += amount
	var g: String = data()["growth_rate"]
	while level < 100 and xp >= SpeciesDB.exp_for_level(g, level + 1):
		var old_max := max_hp()
		level += 1
		hp += max_hp() - old_max  # como en los juegos: sube lo que subió el máximo
		ups.append(level)
	if not ups.is_empty():
		moves = moves_at_level(level)
	return ups


## Especie a la que evoluciona ahora mismo (o "" si no toca o no tenemos sus sprites).
func evolution_ready() -> String:
	var evo = data()["evolution"]
	if evo == null or level < int(evo["level"]):
		return ""
	if not SpeciesDB.has_species(evo["to"]):
		return ""
	return evo["to"]


func evolve(to: String) -> void:
	var frac := hp_frac()
	species = to
	hp = maxi(1, int(round(max_hp() * frac)))
	moves = moves_at_level(level)


## Ánimo: bien atendido o de mal humor (gana menos amistad, nunca castigos crueles).
func is_grumpy() -> bool:
	return fullness < 25.0 or energy < 15.0


func add_friendship(amount: int) -> void:
	if amount > 0 and is_grumpy():
		amount = maxi(1, amount / 2)
	friendship = clampi(friendship + amount, 0, 255)


## Reacción canon a un sabor según la naturaleza: "likes", "hates" o "neutral".
func flavor_reaction(flavor: String) -> String:
	if flavor == "":
		return "neutral"
	var n := SpeciesDB.nature(nature)
	if n["likes_flavor"] == flavor:
		return "likes"
	if n["hates_flavor"] == flavor:
		return "hates"
	return "neutral"


func to_dict() -> Dictionary:
	return {
		"uid": uid, "species": species, "nickname": nickname, "level": level, "xp": xp,
		"nature": nature, "ivs": ivs, "hp": hp, "moves": moves, "friendship": friendship,
		"fullness": fullness, "energy": energy, "known_flavors": known_flavors,
		"pets_this_hour": pets_this_hour, "pets_hour_start": pets_hour_start, "caught_at": caught_at,
	}


static func from_dict(d: Dictionary) -> PokemonInstance:
	var p := PokemonInstance.new()
	p.uid = int(d["uid"])
	p.species = d["species"]
	p.nickname = d.get("nickname", "")
	p.level = int(d["level"])
	p.xp = int(d["xp"])
	p.nature = d["nature"]
	p.ivs = d["ivs"]
	p.hp = int(d["hp"])
	p.moves.assign(d["moves"])
	p.friendship = int(d["friendship"])
	p.fullness = float(d.get("fullness", 80.0))
	p.energy = float(d.get("energy", 100.0))
	p.known_flavors = d.get("known_flavors", {})
	p.pets_this_hour = int(d.get("pets_this_hour", 0))
	p.pets_hour_start = float(d.get("pets_hour_start", 0.0))
	p.caught_at = float(d.get("caught_at", 0.0))
	return p
