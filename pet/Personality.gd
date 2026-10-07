class_name Personality
extends RefCounted
## Personalidad de mascota: sale de la característica canon del Pokémon
## (data/characteristics.json) y se traduce en un rasgo de data/personality.json
## que cambia los pesos y tiempos de su comportamiento en casa. Nunca toca stats.

static var _data: Dictionary
static var _chars: Dictionary
static var _weights := {}


static func _load() -> void:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/personality.json"))
		_chars = JSON.parse_string(FileAccess.get_file_as_string("res://data/characteristics.json"))


## Id del rasgo ("gloton", "payaso"...).
static func trait_id(p: PokemonInstance) -> String:
	_load()
	return String(_data["by_characteristic"].get(p.characteristic_key(), "tranquilo"))


static func trait_name(p: PokemonInstance) -> String:
	_load()
	return String(_data["traits"][trait_id(p)]["name_es"])


## Texto canon de la característica ("Le encanta comer").
static func characteristic_text(p: PokemonInstance) -> String:
	_load()
	return String(_chars.get(p.characteristic_key(), {}).get("es", ""))


## Multiplicadores del comportamiento (los que falten valen lo de "defaults").
## Es de solo lectura (se comparte por rasgo).
static func weights(p: PokemonInstance) -> Dictionary:
	_load()
	var id := trait_id(p)
	if not _weights.has(id):
		var out: Dictionary = _data["defaults"].duplicate()
		var t: Dictionary = _data["traits"][id]
		for k in t:
			if k != "name_es":
				out[k] = t[k]
		_weights[id] = out
	return _weights[id]


static func is_nocturnal(species: String) -> bool:
	_load()
	if species in _data["species"]["nocturnal"]:
		return true
	for t in SpeciesDB.species(species)["types"]:
		if t in _data["species"].get("nocturnal_types", []):
			return true
	return false


## Formas de PokeAPI que vuelan (alas de ave o de insecto) y fantasmas que flotan.
const WING_SHAPES := ["wings", "bug-wings"]
const FLOATING_SHAPES := ["ball", "arms", "blob", "tentacles", "heads", "squiggle"]


## Vuela a veces por toda la pantalla: tipo volador, forma con alas, Levitación,
## fantasmas sin patas y la lista "fly"; nunca los de "no_fly".
static func can_fly(species: String) -> bool:
	_load()
	var sp: Dictionary = _data["species"]
	if species in sp["no_fly"]:
		return false
	if species in sp["fly"]:
		return true
	var d := SpeciesDB.species(species)
	if "flying" in d["types"] or d.get("shape", "") in WING_SHAPES or "levitate" in d.get("abilities", []):
		return true
	return "ghost" in d["types"] and d.get("shape", "") in FLOATING_SHAPES


## Estilo de vuelo: "bird", "bug", "dragon" o "float" (ver FlightWindow).
static func flight_style(species: String) -> String:
	_load()
	var forced: Dictionary = _data["species"].get("flight_style", {})
	if forced.has(species):
		return String(forced[species])
	var d := SpeciesDB.species(species)
	var types: Array = d["types"]
	if "flying" not in types and ("levitate" in d.get("abilities", []) or "ghost" in types or "psychic" in types):
		return "float"
	if "bug" in types or d.get("shape", "") == "bug-wings":
		return "bug"
	if "dragon" in types:
		return "dragon"
	return "bird"


static func flight_cfg() -> Dictionary:
	_load()
	return _data.get("flight", {})


## Sube por el borde de la pantalla: bichos, especies con ventosas/agarre pegajoso y la
## lista "climb" de personality.json; nunca las de "no_climb".
static func can_climb(species: String) -> bool:
	_load()
	var sp: Dictionary = _data["species"]
	if species in sp.get("no_climb", []):
		return false
	if species in sp.get("climb", []):
		return true
	var d := SpeciesDB.species(species)
	if "bug" in d["types"]:
		return true
	var abilities: Array = d.get("abilities", [])
	return "suction-cups" in abilities or "sticky-hold" in abilities


static func climb_cfg() -> Dictionary:
	_load()
	return _data.get("climb", {})
