class_name Progression
extends RefCounted
## Progresión del jugador: árbol del entrenador, objetos equipables, vitaminas y maestría
## de movimientos. Solo datos y fórmulas; el estado vive en Roster y PokemonInstance.
## Todo esto es una capa de juego encima de las stats canon (ver docs/decisiones.md).

const SHEET_CELL := 12

static var _tree: Dictionary
static var _items: Dictionary
static var _items_tex: Texture2D
static var _vit_tex: Texture2D
static var _coin_tex: Texture2D


# ------------------------------------------------------------------ datos

static func tree() -> Dictionary:
	if _tree.is_empty():
		_tree = JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_tree.json"))
	return _tree


static func nodes() -> Array:
	return tree()["nodes"]


static func node(id: String) -> Dictionary:
	for n in nodes():
		if n["id"] == id:
			return n
	return {}


static func branches() -> Array:
	return tree()["branches"]


static func _items_data() -> Dictionary:
	if _items.is_empty():
		_items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	return _items


static func item_defs() -> Dictionary:
	return _items_data()["items"]


static func item_def(id: String) -> Dictionary:
	return item_defs()[id]


static func tiers() -> Array:
	return _items_data()["tiers"]


static func max_tier() -> int:
	return tiers().size() - 1


static func merge_count() -> int:
	return int(_items_data()["merge_count"])


static func vitamins() -> Dictionary:
	return _items_data()["vitamins"]


static func vitamin_stats() -> Array[String]:
	var out: Array[String] = []
	out.assign(vitamins().keys())
	return out


static func vitamin_cfg() -> Dictionary:
	return _items_data()["vitamin"]


static func mastery_cfg() -> Dictionary:
	return _items_data()["mastery"]


# ------------------------------------------------------------------ iconos

static func item_icon(id: String) -> Texture2D:
	if _items_tex == null:
		_items_tex = load("res://assets/ui/items.png")
	var at := AtlasTexture.new()
	at.atlas = _items_tex
	at.region = Rect2(int(item_def(id)["icon"]) * SHEET_CELL, 0, SHEET_CELL, SHEET_CELL)
	return at


static func vitamin_icon(stat: String) -> Texture2D:
	if _vit_tex == null:
		_vit_tex = load("res://assets/ui/vitamins.png")
	var at := AtlasTexture.new()
	at.atlas = _vit_tex
	at.region = Rect2(vitamin_stats().find(stat) * SHEET_CELL, 0, SHEET_CELL, SHEET_CELL)
	return at


static func coin_icon() -> Texture2D:
	if _coin_tex == null:
		_coin_tex = load("res://assets/ui/coin.png")
	return _coin_tex


# ------------------------------------------------------------------ árbol

## Costo de subir el nodo desde su nivel actual.
static func node_cost(id: String, level_now: int) -> int:
	var n := node(id)
	return int(round(float(n["cost_base"]) * pow(float(n["cost_growth"]), level_now)))


static func requirement_met(skills: Dictionary, id: String) -> bool:
	for r in node(id)["requires"]:
		if int(skills.get(r["id"], 0)) < int(r["level"]):
			return false
	return true


## Suma de `per_level * nivel` de todos los nodos con ese efecto.
static func skill_effect(skills: Dictionary, effect: String) -> float:
	var total := 0.0
	for n in nodes():
		if n["effect"] == effect:
			total += float(n["per_level"]) * int(skills.get(n["id"], 0))
	return total


# ------------------------------------------------------------------ objetos

static func item_key(id: String, tier: int) -> String:
	return "%s:%d" % [id, tier]


static func key_id(key: String) -> String:
	return key.get_slice(":", 0)


static func key_tier(key: String) -> int:
	return int(key.get_slice(":", 1))


static func item_value(key: String) -> float:
	return float(item_def(key_id(key))["tiers"][key_tier(key)])


static func item_name(key: String) -> String:
	return String(item_def(key_id(key))["name_es"])


## "+6% Ataque" (el crítico va en puntos, no en porcentaje).
static func item_summary(key: String) -> String:
	var d := item_def(key_id(key))
	var num := ("%.1f" % item_value(key)).trim_suffix(".0")
	return "+%s %s" % [num, d["desc_es"]] if d["effect"] == "crit" else "+%s%% %s" % [num, d["desc_es"]]


static func tier_name(tier: int) -> String:
	return tiers()[tier]["name_es"]


static func tier_color(tier: int) -> Color:
	return Palette.by_name(tiers()[tier]["color"])


## Suma de un efecto en una lista de objetos equipados.
static func held_effect(held: Array, effect: String) -> float:
	var total := 0.0
	for k in held:
		if item_def(key_id(k))["effect"] == effect:
			total += item_value(k)
	return total


# ------------------------------------------------------------------ entrenamiento

static func vitamin_cost(p: PokemonInstance, stat: String) -> int:
	var c := vitamin_cfg()
	var n := p.vitamin_doses(stat)
	return int(round((float(c["cost_base"]) + float(c["cost_per_dose"]) * n) * (1.0 + p.level / float(c["cost_level_div"]))))


static func mastery_cost(p: PokemonInstance, move_name: String) -> int:
	var c := mastery_cfg()
	var md := SpeciesDB.move(move_name)
	var power := float(md["power"]) if md["power"] != null else 40.0
	return int(round(float(c["cost_base"]) * (p.mastery(move_name) + 1) * (1.0 + power / float(c["power_div"]))))


# ------------------------------------------------------------------ recompensas

## Monedas por una victoria. `fighters`: los que pelearon (la Moneda Amuleto suma).
static func gold_for_win(foe: PokemonInstance, boss: bool, route: Dictionary, fighters: Array) -> int:
	var rw: Dictionary = route.get("rewards", {})
	var base := float(foe.data()["base_experience"]) * foe.level * float(rw.get("gold_per_exp_unit", 0.1)) / 5.0
	if boss:
		base *= float(rw.get("boss_gold_mult", 5))
	var pct := Game.roster.fx("gold")
	for p in fighters:
		pct += held_effect(p.held, "gold")
	return maxi(1, int(round(base * (1.0 + pct / 100.0))))


## Multiplicador de EXP para un Pokémon (árbol + Huevo Suerte + ánimo por cuidarlo).
static func exp_mult(p: PokemonInstance) -> float:
	return 1.0 + (Game.roster.fx("exp") + held_effect(p.held, "exp") + Game.roster.cheer_exp_pct(p)) / 100.0


## Sorteo de un objeto soltado: devuelve la llave "id:nivel". El jefe asegura un nivel mínimo.
static func roll_item(drops: Dictionary, rng: RandomNumberGenerator, boss: bool) -> String:
	var id := BattleMath.pick_weighted(drops["table"], "item", rng)
	var tier := int(drops.get("boss_min_tier", 1)) if boss else 0
	var r := rng.randf()
	if r < 0.04:
		tier = maxi(tier, 2)
	elif r < 0.20:
		tier = maxi(tier, 1)
	return item_key(id, mini(tier, max_tier()))
