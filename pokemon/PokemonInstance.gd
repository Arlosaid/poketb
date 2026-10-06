class_name PokemonInstance
extends RefCounted
## Un Pokémon concreto del jugador (o un salvaje): datos canon + estado de mascota.

const MAX_MOVES := 4
const HELD_MAX := 2
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
## Diversión 0..100 (como en Poké Recreo). Baja con el tiempo y sube jugando con él.
var fun := 80.0
## Valor de personalidad (como el PID de los juegos): desempata la característica.
var pid := 0
## Lugar favorito en casa (0..1 del ancho); se elige al azar la primera vez.
var fav_x := -1.0
## Sabores descubiertos: {"spicy": "likes" | "hates" | "neutral"}
var known_flavors := {}
## Control anti-abuso de caricias: caricias contadas en la hora actual.
var pets_this_hour := 0
var pets_hour_start := 0.0
var caught_at := 0.0
var wild := false
## Combates ganados (cada 5 suman +1 de amistad).
var wins := 0
## PS fraccionarios acumulados al descansar (no se guardan).
var hp_regen_acc := 0.0
## Vitaminas tomadas por stat: {"atk": 3} (cada dosis cuesta monedas, ver Progression).
var doses := {}
## Maestría de movimientos: {"ember": 2}.
var move_mastery := {}
## Objetos equipados (llaves "id:nivel"), máximo HELD_MAX.
var held: Array[String] = []
## Si el jugador eligió los movimientos a mano, subir de nivel no los cambia.
var custom_moves := false


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
	p.pid = r.randi()
	p.fav_x = r.randf()
	p.moves = p.moves_at_level(lvl)
	p.hp = p.max_hp()
	return p


func data() -> Dictionary:
	return SpeciesDB.species(species)


func display_name() -> String:
	return nickname if nickname != "" else String(data()["name_es"])


func types() -> Array:
	return data()["types"]


## Habilidad canon (una de las normales de su especie, fija por su pid).
func ability() -> String:
	var ab: Array = data().get("abilities", [])
	return String(ab[pid % ab.size()]) if not ab.is_empty() else ""


func ability_es() -> String:
	var a := ability()
	return String(SpeciesDB.ability(a)["name_es"]) if a != "" else ""


## Stat canon (EV = 0). HP: ((2B+IV)·L/100)+L+10; resto: (((2B+IV)·L/100)+5)·naturaleza.
## Los Pokémon del jugador (uid != 0) suman encima el árbol, los objetos y las vitaminas.
func stat(s: String) -> int:
	var v := canon_stat(s)
	if uid == 0:
		return v
	var out := int(round(v * (1.0 + bonus_pct(s) / 100.0)))
	var d := vitamin_doses(s)
	if d > 0:
		out += maxi(d, int(round(v * d * float(Progression.vitamin_cfg()["pct_per_dose"]) / 100.0)))
	return out


func canon_stat(s: String) -> int:
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


## Porcentaje extra de un stat por el árbol y los objetos.
func bonus_pct(s: String) -> float:
	var pct := Progression.held_effect(held, s)
	match s:
		"hp":
			pct += Game.roster.fx("hp")
		"def", "spd":
			pct += Game.roster.fx("def")
		"spe":
			pct += Game.roster.fx("spe")
	return pct


func vitamin_doses(s: String) -> int:
	return int(doses.get(s, 0))


func mastery(move_name: String) -> int:
	return int(move_mastery.get(move_name, 0))


func max_hp() -> int:
	return stat("hp")


func hp_frac() -> float:
	return clampf(float(hp) / max_hp(), 0.0, 1.0)


func is_fainted() -> bool:
	return hp <= 0


## Movimientos de daño aprendidos hasta `lvl` (en el MVP no hay movimientos de estado).
func moves_known_at(lvl: int) -> Array[String]:
	var out: Array[String] = []
	for m in data()["learnset"]:
		if int(m["level"]) <= lvl and m["move"] not in out:
			var md := SpeciesDB.move(m["move"])
			if md["damage_class"] != "status" and md["power"] != null:
				out.append(m["move"])
	if out.is_empty():
		out.append("tackle")
	return out


func available_moves() -> Array[String]:
	return moves_known_at(level)


## Últimos 4 movimientos de daño aprendidos hasta `lvl`.
func moves_at_level(lvl: int) -> Array[String]:
	var out := moves_known_at(lvl)
	while out.size() > MAX_MOVES:
		out.pop_front()
	return out


## Cambia los movimientos elegidos a mano (1–4, todos disponibles).
func set_moves(chosen: Array) -> void:
	var ok: Array[String] = []
	var avail := available_moves()
	for m in chosen:
		if m in avail and m not in ok and ok.size() < MAX_MOVES:
			ok.append(m)
	if ok.is_empty():
		return
	moves = ok
	custom_moves = true


## Tras subir de nivel o evolucionar: automático, o los elegidos que sigan siendo válidos.
func refresh_moves() -> void:
	if custom_moves:
		var keep: Array[String] = []
		var avail := available_moves()
		for m in moves:
			if m in avail:
				keep.append(m)
		if not keep.is_empty():
			moves = keep
			return
		custom_moves = false
	moves = moves_at_level(level)


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
		refresh_moves()
	return ups


## Especie a la que evoluciona ahora mismo (o "" si no toca o no tenemos sus sprites).
## Por nivel, o por amistad alta al subir de nivel (canon; algunas solo de día o de noche).
func evolution_ready() -> String:
	var evo = data()["evolution"]
	if evo != null and level >= int(evo["level"]) and SpeciesDB.has_sprite(evo["to"]):
		return evo["to"]
	for e in data().get("evolutions", []):
		if e["trigger"] != "level-up" or not e.has("happiness") or e.has("level") or e.has("item"):
			continue
		if friendship < int(e["happiness"]) or not SpeciesDB.has_sprite(e["to"]):
			continue
		var t: String = e.get("time", "")
		if t == "" or (t == "night") == Game.clock.is_night():
			return e["to"]
	return ""


func evolve(to: String) -> void:
	var frac := hp_frac()
	species = to
	hp = maxi(1, int(round(max_hp() * frac)))
	refresh_moves()


## Ánimo: bien atendido o de mal humor (gana menos amistad, nunca castigos crueles).
func is_grumpy() -> bool:
	return fullness < 25.0 or energy < 15.0


func add_friendship(amount: int) -> void:
	if amount > 0 and is_grumpy():
		amount = maxi(1, amount / 2)
	friendship = clampi(friendship + amount, 0, 255)


## Característica canon (Gen 4+): stat con el IV más alto; los empates se resuelven
## empezando por el stat (PID mod 6) en el orden PS, Ata, Def, Vel, AtEsp, DefEsp.
## Devuelve la llave de data/characteristics.json ("hp_0", "spe_3"...).
func characteristic_key() -> String:
	const ORDER: Array[String] = ["hp", "atk", "def", "spe", "spa", "spd"]
	var start := pid % 6
	var best := ""
	var best_iv := -1
	for i in 6:
		var s: String = ORDER[(start + i) % 6]
		var iv := int(ivs.get(s, 0))
		if iv > best_iv:
			best_iv = iv
			best = s
	return "%s_%d" % [best, best_iv % 5]


## Contento: bien comido, descansado y entretenido (da un pequeño extra de EXP).
func is_cheerful() -> bool:
	return fullness >= 50.0 and energy >= 40.0 and fun >= 60.0


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
		"fullness": fullness, "energy": energy, "fun": fun, "pid": pid, "fav_x": fav_x, "known_flavors": known_flavors,
		"pets_this_hour": pets_this_hour, "pets_hour_start": pets_hour_start, "caught_at": caught_at, "wins": wins,
		"doses": doses, "move_mastery": move_mastery, "held": held, "custom_moves": custom_moves,
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
	p.fun = float(d.get("fun", 80.0))
	# Partidas anteriores a la fase 8: un PID estable derivado del uid y la especie.
	p.pid = int(d.get("pid", hash("%d:%s" % [p.uid, p.species]) & 0x7fffffff))
	p.fav_x = float(d.get("fav_x", float(p.pid % 1000) / 1000.0))
	p.known_flavors = d.get("known_flavors", {})
	p.pets_this_hour = int(d.get("pets_this_hour", 0))
	p.pets_hour_start = float(d.get("pets_hour_start", 0.0))
	p.caught_at = float(d.get("caught_at", 0.0))
	p.wins = int(d.get("wins", 0))
	p.doses = Roster._ints(d.get("doses", {}))
	p.move_mastery = Roster._ints(d.get("move_mastery", {}))
	p.held.assign(d.get("held", []))
	p.custom_moves = bool(d.get("custom_moves", false))
	return p
