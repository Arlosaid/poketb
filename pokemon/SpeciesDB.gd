class_name SpeciesDB
extends RefCounted
## Acceso de solo lectura a los datos canon de data/*.json (generados desde PokeAPI).

static var _species: Dictionary
static var _moves: Dictionary
static var _types: Dictionary
static var _natures: Dictionary
static var _berries: Dictionary
static var _growth: Dictionary
static var _abilities: Dictionary
## Especies con sprites empacados (data/sprite_index.json). Solo estas aparecen en el mundo.
static var _with_sprite: Dictionary


static func _load(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func species(name: String) -> Dictionary:
	if _species.is_empty():
		_species = _load("res://data/species.json")
	return _species[name]


static func has_species(name: String) -> bool:
	if _species.is_empty():
		_species = _load("res://data/species.json")
	return _species.has(name)


## Nombres de todas las especies (orden de data/species.json).
static func all_species() -> Array:
	if _species.is_empty():
		_species = _load("res://data/species.json")
	return _species.keys()


## true si la especie tiene sprites (las que SpriteCollab aún no dibujó quedan fuera del mundo).
static func has_sprite(name: String) -> bool:
	if _with_sprite.is_empty():
		for n in _load("res://data/sprite_index.json")["species"]:
			_with_sprite[n] = true
	return _with_sprite.has(name)


## Especies con sprite (para encuentros, sorteos y escenarios).
static func species_with_sprite() -> Array:
	has_sprite("")
	return _with_sprite.keys()


static func ability(name: String) -> Dictionary:
	if _abilities.is_empty():
		_abilities = _load("res://data/abilities.json")
	return _abilities.get(name, {"name_es": name.capitalize(), "desc_es": ""})


static func has_move(name: String) -> bool:
	if _moves.is_empty():
		_moves = _load("res://data/moves.json")
	return _moves.has(name)


static func move(name: String) -> Dictionary:
	if _moves.is_empty():
		_moves = _load("res://data/moves.json")
	return _moves[name]


static func natures() -> Dictionary:
	if _natures.is_empty():
		_natures = _load("res://data/natures.json")
	return _natures


static func nature(name: String) -> Dictionary:
	return natures()[name]


static func berries() -> Dictionary:
	if _berries.is_empty():
		_berries = _load("res://data/berries.json")
	return _berries["berries"]


static func berry(name: String) -> Dictionary:
	return berries()[name]


static func flavor_es(flavor: String) -> String:
	berries()
	return _berries["flavors_es"].get(flavor, flavor)


static func type_es(t: String) -> String:
	if _types.is_empty():
		_types = _load("res://data/types.json")
	return _types["names_es"].get(t, t)


## Multiplicador canon de un tipo atacante contra los tipos del defensor.
static func effectiveness(atk_type: String, def_types: Array) -> float:
	if _types.is_empty():
		_types = _load("res://data/types.json")
	var row: Dictionary = _types["chart"].get(atk_type, {})
	var m := 1.0
	for t in def_types:
		m *= float(row.get(t, 1.0))
	return m


## EXP total necesaria para estar en `level` con la curva `growth`.
static func exp_for_level(growth: String, level: int) -> int:
	if _growth.is_empty():
		_growth = _load("res://data/growth.json")
	return int(_growth[growth][clampi(level, 1, 100)])


## Sabor dominante de una baya ("" si no tiene uno claro, como la Aranja).
static func dominant_flavor(berry_name: String) -> String:
	var fl: Dictionary = berry(berry_name)["flavors"]
	var best := ""
	var best_v := 0
	var tie := false
	for f in fl:
		var v := int(fl[f])
		if v > best_v:
			best = f
			best_v = v
			tie = false
		elif v == best_v:
			tie = true
	return "" if tie else best
