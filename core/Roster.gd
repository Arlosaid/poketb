class_name Roster
extends RefCounted
## Colección del jugador: todos los Pokémon, el equipo (máx. 6), el compañero y las bayas.
## También aplica las necesidades (hambre, energía, PS en casa) y la amistad.

signal changed
signal berries_changed

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
var next_uid := 1
var _companion_timer := 0.0


func new_game() -> void:
	members.clear()
	team.clear()
	var starter := PokemonInstance.create("charmander", 5)
	add(starter)
	companion = starter.uid
	berries = {"oran": 3, "pecha": 2, "cheri": 2, "mago": 1}
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


func set_team(uids: Array[int]) -> void:
	team = uids.slice(0, TEAM_MAX)
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
		var decay := FULLNESS_DECAY_HOME * (FULLNESS_DECAY_BATTLE_MULT if in_battle else 1.0)
		p.fullness = maxf(0.0, p.fullness - decay * dt)
		if in_battle:
			p.energy = maxf(0.0, p.energy - ENERGY_DRAIN_BATTLE * dt)
		else:
			var regen := ENERGY_REGEN_HOME * (ENERGY_REGEN_SLEEP_MULT if u in sleeping else 1.0)
			p.energy = minf(100.0, p.energy + regen * dt)
			if p.hp < p.max_hp():
				var heal := HP_REGEN_HOME * (2.0 if u in sleeping else 1.0) * p.max_hp() * dt
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
	var now := Game.clock.elapsed
	if now - p.pets_hour_start > 3600.0:
		p.pets_hour_start = now
		p.pets_this_hour = 0
	if p.pets_this_hour >= PETS_PER_HOUR:
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


func to_dict() -> Dictionary:
	var ms := []
	for u in members:
		ms.append(members[u].to_dict())
	return {"members": ms, "team": team, "companion": companion, "berries": berries, "next_uid": next_uid}


func from_dict(d: Dictionary) -> void:
	members.clear()
	for md in d["members"]:
		var p := PokemonInstance.from_dict(md)
		members[p.uid] = p
	team.assign(d["team"].map(func(x): return int(x)))
	companion = int(d.get("companion", 0))
	berries = d.get("berries", {})
	next_uid = int(d.get("next_uid", members.size() + 1))
	changed.emit()
	berries_changed.emit()
