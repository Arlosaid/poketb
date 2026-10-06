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
	return species in _data["species"]["nocturnal"]


## Vuela a veces por la pantalla: los de tipo volador (y los de la lista "fly"), salvo "no_fly".
static func can_fly(species: String) -> bool:
	_load()
	var sp: Dictionary = _data["species"]
	if species in sp["no_fly"]:
		return false
	return species in sp["fly"] or "flying" in SpeciesDB.species(species)["types"]
