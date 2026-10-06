class_name Roster
extends RefCounted
## Colección del jugador: todos los Pokémon, el equipo (máx. 6), el compañero y las bayas.
## También aplica las necesidades (hambre, energía, PS en casa) y la amistad.

signal changed
signal berries_changed
## Monedas, mochila o árbol cambiaron (la PC se actualiza sin reconstruir al equipo en ruta).
signal wallet_changed

const TEAM_MAX := 6
## Por segundo de juego.
const FULLNESS_DECAY_HOME := 100.0 / (10.0 * 3600.0)   # de lleno a vacío en ~10 h
const FULLNESS_DECAY_BATTLE_MULT := 2.0
const ENERGY_DRAIN_BATTLE := 1.0 / 60.0                 # 100 min de pelea seguida
const ENERGY_REGEN_HOME := 1.0 / 30.0                   # ~50 min en casa
const ENERGY_REGEN_SLEEP_MULT := 2.0
const HP_REGEN_HOME := 0.004                            # fracción del máximo por segundo (~4 min)
const PETS_PER_HOUR := 10
## El compañero gana amistad paseando contigo (como en HGSS).
const COMPANION_FRIEND_EVERY := 600.0
## Energía mínima para pelear y para volver a la ruta después de descansar.
const ENERGY_TO_FIGHT := 10.0
const ENERGY_TO_RETURN := 60.0

var members := {}            # uid → PokemonInstance
var team: Array[int] = []    # uids en orden
var companion := 0
var berries := {}            # nombre → cantidad
var gold := 0
var skills := {}             # id del nodo → nivel
var bag := {}                # "id:nivel" → cantidad
var next_uid := 1
var _companion_timer := 0.0
var _fx := {}                # caché de efectos del árbol


func new_game() -> void:
	members.clear()
	team.clear()
	var starter := PokemonInstance.create("charmander", 5)
	add(starter)
	companion = starter.uid
	berries = {"oran": 3, "pecha": 2, "cheri": 2, "mago": 1}
	gold = 0
	skills = {}
	bag = {}
	_fx.clear()
	changed.emit()
	berries_changed.emit()


func add(p: PokemonInstance) -> void:
	p.uid = next_uid
	next_uid += 1
	p.wild = false
	p.caught_at = Time.get_unix_time_from_system()
	members[p.uid] = p
	if team.size() < TEAM_MAX:
		team.append(p.uid)
	changed.emit()


func get_member(uid: int) -> PokemonInstance:
	return members.get(uid)


func team_members() -> Array[PokemonInstance]:
	var out: Array[PokemonInstance] = []
	for u in team:
		out.append(members[u])
	return out


func box_members() -> Array[PokemonInstance]:
	var out: Array[PokemonInstance] = []
	for u in members:
		if u not in team:
			out.append(members[u])
	return out


func companion_member() -> PokemonInstance:
	return members.get(companion)


func set_companion(uid: int) -> void:
	if members.has(uid):
		companion = uid
		changed.emit()


func set_team(uids: Array) -> void:
	team.assign(uids.slice(0, TEAM_MAX).map(func(x): return int(x)))
	changed.emit()


## ¿Puede pelear ahora? (sin debilitarse y con energía)
func can_fight(p: PokemonInstance) -> bool:
	return not p.is_fainted() and p.energy >= ENERGY_TO_FIGHT


## Avanza las necesidades. `battling`: uids peleando ahora; `sleeping`: uids dormidos en casa.
func tick(dt: float, battling: Array, sleeping: Array) -> void:
	if dt <= 0.0:
		return
	for u in members:
		var p: PokemonInstance = members[u]
		var in_battle: bool = u in battling
		var decay := FULLNESS_DECAY_HOME * (FULLNESS_DECAY_BATTLE_MULT if in_battle else 1.0) * maxf(0.2, 1.0 - fx("hunger") / 100.0)
		p.fullness = maxf(0.0, p.fullness - decay * dt)
		if in_battle:
			p.energy = maxf(0.0, p.energy - ENERGY_DRAIN_BATTLE * dt)
		else:
			var regen := ENERGY_REGEN_HOME * (ENERGY_REGEN_SLEEP_MULT if u in sleeping else 1.0) * (1.0 + fx("regen") / 100.0)
			p.energy = minf(100.0, p.energy + regen * dt)
			if p.hp < p.max_hp():
				var heal := HP_REGEN_HOME * (2.0 if u in sleeping else 1.0) * (1.0 + fx("regen") / 100.0) * p.max_hp() * dt
				p.hp_regen_acc += heal
				var whole := int(p.hp_regen_acc)
				if whole > 0:
					p.hp = mini(p.max_hp(), p.hp + whole)
					p.hp_regen_acc -= whole
	_companion_timer += dt
	if _companion_timer >= COMPANION_FRIEND_EVERY:
		_companion_timer = 0.0
		var c := companion_member()
		if c:
			c.add_friendship(1)


## Caricia: devuelve cuánta amistad ganó (0 si ya lo acariciaste mucho esta hora).
func pet(p: PokemonInstance) -> int:
	var now := Time.get_unix_time_from_system()
	if now - p.pets_hour_start > 3600.0:
		p.pets_hour_start = now
		p.pets_this_hour = 0
	if p.pets_this_hour >= PETS_PER_HOUR + int(fx("pets")):
		return 0
	p.pets_this_hour += 1
	var before := p.friendship
	p.add_friendship(1)
	return p.friendship - before


## Da una baya. Devuelve {reaction, flavor, friendship, healed}.
func feed(p: PokemonInstance, berry_name: String) -> Dictionary:
	if int(berries.get(berry_name, 0)) <= 0:
		return {}
	berries[berry_name] = int(berries[berry_name]) - 1
	if berries[berry_name] <= 0:
		berries.erase(berry_name)
	var flavor := SpeciesDB.dominant_flavor(berry_name)
	var reaction := p.flavor_reaction(flavor)
	if flavor != "":
		p.known_flavors[flavor] = reaction
	var gain: int = {"likes": 3, "neutral": 2, "hates": 1}[reaction]
	var before := p.friendship
	p.add_friendship(gain)
	p.fullness = minf(100.0, p.fullness + (40.0 if berry_name == "sitrus" else 30.0))
	var healed := 0
	if berry_name == "oran":
		healed = mini(10, p.max_hp() - p.hp)
	elif berry_name == "sitrus":
		healed = mini(p.max_hp() / 4, p.max_hp() - p.hp)
	if not p.is_fainted():
		p.hp += healed
	berries_changed.emit()
	changed.emit()
	return {"reaction": reaction, "flavor": flavor, "friendship": p.friendship - before, "healed": healed}


func add_berry(berry_name: String, n := 1) -> void:
	berries[berry_name] = int(berries.get(berry_name, 0)) + n
	berries_changed.emit()


# ------------------------------------------------------------------ progresión

## Efecto acumulado del árbol (porcentaje, salvo que el nodo diga otra cosa).
func fx(effect: String) -> float:
	if not _fx.has(effect):
		_fx[effect] = Progression.skill_effect(skills, effect)
	return float(_fx[effect])


func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)
	wallet_changed.emit()


func skill_level(id: String) -> int:
	return int(skills.get(id, 0))


## "ok", "max", "locked" o "poor".
func skill_state(id: String) -> String:
	var lv := skill_level(id)
	if lv >= int(Progression.node(id)["max"]):
		return "max"
	if not Progression.requirement_met(skills, id):
		return "locked"
	return "ok" if gold >= Progression.node_cost(id, lv) else "poor"


func buy_skill(id: String) -> bool:
	if skill_state(id) != "ok":
		return false
	var lv := skill_level(id)
	gold -= Progression.node_cost(id, lv)
	skills[id] = lv + 1
	_fx.clear()
	_heal_growth(_hp_snapshot())
	wallet_changed.emit()
	changed.emit()
	return true


func add_item(key: String, n := 1) -> void:
	bag[key] = int(bag.get(key, 0)) + n
	wallet_changed.emit()


func _take_item(key: String) -> bool:
	if int(bag.get(key, 0)) <= 0:
		return false
	bag[key] = int(bag[key]) - 1
	if bag[key] <= 0:
		bag.erase(key)
	return true


func can_merge(key: String) -> bool:
	return int(bag.get(key, 0)) >= Progression.merge_count() and Progression.key_tier(key) < Progression.max_tier()


## 3 iguales del mismo nivel → 1 del siguiente.
func merge(key: String) -> bool:
	if not can_merge(key):
		return false
	bag[key] = int(bag[key]) - Progression.merge_count()
	if bag[key] <= 0:
		bag.erase(key)
	add_item(Progression.item_key(Progression.key_id(key), Progression.key_tier(key) + 1))
	return true


## Fusiona todo lo que se pueda (de menor a mayor nivel). Devuelve cuántas fusiones hizo.
func merge_all() -> int:
	var n := 0
	for tier in Progression.max_tier():
		for key in bag.keys():
			if Progression.key_tier(key) == tier:
				while merge(key):
					n += 1
	return n


## Equipa un objeto de la mochila. Con los 2 espacios llenos, cambia el primero.
func equip(p: PokemonInstance, key: String) -> bool:
	if not _take_item(key):
		return false
	var snap := _hp_snapshot()
	if p.held.size() >= PokemonInstance.HELD_MAX:
		add_item(p.held.pop_front())
	p.held.append(key)
	_heal_growth(snap)
	wallet_changed.emit()
	changed.emit()
	return true


func unequip(p: PokemonInstance, slot: int) -> void:
	if slot < 0 or slot >= p.held.size():
		return
	var snap := _hp_snapshot()
	add_item(p.held.pop_at(slot))
	_clamp_hp(snap)
	wallet_changed.emit()
	changed.emit()


## "ok", "max" o "poor".
func vitamin_state(p: PokemonInstance, stat: String) -> String:
	if p.vitamin_doses(stat) >= int(Progression.vitamin_cfg()["max"]):
		return "max"
	return "ok" if gold >= Progression.vitamin_cost(p, stat) else "poor"


func buy_vitamin(p: PokemonInstance, stat: String) -> bool:
	if vitamin_state(p, stat) != "ok":
		return false
	var snap := _hp_snapshot()
	gold -= Progression.vitamin_cost(p, stat)
	p.doses[stat] = p.vitamin_doses(stat) + 1
	_heal_growth(snap)
	wallet_changed.emit()
	changed.emit()
	return true


func mastery_state(p: PokemonInstance, move_name: String) -> String:
	if p.mastery(move_name) >= int(Progression.mastery_cfg()["max"]):
		return "max"
	return "ok" if gold >= Progression.mastery_cost(p, move_name) else "poor"


func buy_mastery(p: PokemonInstance, move_name: String) -> bool:
	if mastery_state(p, move_name) != "ok":
		return false
	gold -= Progression.mastery_cost(p, move_name)
	p.move_mastery[move_name] = p.mastery(move_name) + 1
	wallet_changed.emit()
	changed.emit()
	return true


## Pone o quita un movimiento del repertorio activo (mínimo 1, máximo 4).
func toggle_move(p: PokemonInstance, move_name: String) -> void:
	var cur: Array[String] = p.moves.duplicate()
	if move_name in cur:
		if cur.size() <= 1:
			return
		cur.erase(move_name)
	elif cur.size() < PokemonInstance.MAX_MOVES:
		cur.append(move_name)
	else:
		return
	p.set_moves(cur)
	changed.emit()


## Al subir el máximo de PS (árbol, objeto, vitamina) sube también el PS actual, como al subir de nivel.
func _hp_snapshot() -> Dictionary:
	var d := {}
	for u in members:
		d[u] = members[u].max_hp()
	return d


func _heal_growth(snap: Dictionary) -> void:
	for u in members:
		var p: PokemonInstance = members[u]
		var gain := p.max_hp() - int(snap.get(u, p.max_hp()))
		if gain > 0 and not p.is_fainted():
			p.hp += gain
	_clamp_hp(snap)


func _clamp_hp(_snap: Dictionary) -> void:
	for u in members:
		var p: PokemonInstance = members[u]
		p.hp = mini(p.hp, p.max_hp())


## JSON devuelve números como flotantes: los contadores se guardan como enteros.
static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out


func to_dict() -> Dictionary:
	var ms := []
	for u in members:
		ms.append(members[u].to_dict())
	return {"members": ms, "team": team, "companion": companion, "berries": berries, "next_uid": next_uid, "gold": gold, "skills": skills, "bag": bag}


func from_dict(d: Dictionary) -> void:
	members.clear()
	for md in d["members"]:
		var p := PokemonInstance.from_dict(md)
		members[p.uid] = p
	team.assign(d["team"].map(func(x): return int(x)))
	companion = int(d.get("companion", 0))
	berries = d.get("berries", {})
	next_uid = int(d.get("next_uid", members.size() + 1))
	gold = int(d.get("gold", 0))
	skills = _ints(d.get("skills", {}))
	bag = _ints(d.get("bag", {}))
	_fx.clear()
	changed.emit()
	berries_changed.emit()
