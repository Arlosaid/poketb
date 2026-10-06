class_name HomeArea
extends Node2D
## "Casa": la parte de la franja (a la izquierda del panel de pelea) donde los
## Pokémon que no pelean viven como mascotas sobre la barra de tareas.

signal pc_requested

var desk: DesktopWindow
var hud: Control
var ground_y := 93.0
var x_min := 8.0
var x_max := 500.0

var _brains := {}   # uid → PetBrain


func setup(d: DesktopWindow, h: Control) -> void:
	desk = d
	hud = h
	y_sort_enabled = true


func set_bounds(left: float, right: float, ground: float) -> void:
	x_min = left
	x_max = right
	ground_y = ground
	for u in _brains:
		var b: PetBrain = _brains[u]
		if b.state != PetBrain.State.DRAG and b.state != PetBrain.State.FALL:
			b.actor.position.x = clampf(b.actor.position.x, x_min, x_max)
			b.actor.position.y = ground_y


func random_x() -> float:
	return randf_range(x_min, x_max)


## Mientras lo arrastras, se queda dentro de la ventana.
func clamp_drag(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(clampf(p.x, 8.0, vp.x - 8.0), clampf(p.y, 30.0, ground_y))


## Muestra en casa exactamente a estos Pokémon. Los nuevos llegan con un saltito;
## `enter_from_x` (si es >= 0) los hace aparecer caminando desde ese borde.
func sync(uids: Array, companion_uid: int, enter_from_x := -1.0) -> void:
	for u in _brains.keys():
		if u not in uids:
			var b: PetBrain = _brains[u]
			_brains.erase(u)
			_leave(b.actor)
	for u in uids:
		var mon: PokemonInstance = Game.roster.get_member(u)
		if mon == null:
			continue
		if _brains.has(u):
			var b: PetBrain = _brains[u]
			b.is_companion = (u == companion_uid)
			if b.actor.species != mon.species:
				b.actor.species = mon.species  # evolucionó
			continue
		_spawn(mon, u == companion_uid, enter_from_x)


func _spawn(mon: PokemonInstance, companion: bool, enter_from_x: float) -> void:
	var a := PokemonActor.new()
	a.species = mon.species
	add_child(a)
	var brain := PetBrain.new()
	brain.name = "Brain"
	a.add_child(brain)
	brain.setup(a, mon, self)
	brain.is_companion = companion
	_brains[mon.uid] = brain
	if enter_from_x >= 0.0:
		a.position = Vector2(enter_from_x, ground_y)
		brain.force_state(PetBrain.State.WANDER)
	else:
		a.position = Vector2(random_x(), ground_y)
		a.modulate.a = 0.0
		var t := a.create_tween()
		t.tween_property(a, "modulate:a", 1.0, 0.3)


func _leave(a: PokemonActor) -> void:
	a.interactive = false
	Passthrough.unregister(a)
	var t := a.create_tween()
	t.tween_property(a, "modulate:a", 0.0, 0.3)
	t.tween_callback(a.queue_free)


func brain_for(uid: int) -> PetBrain:
	return _brains.get(uid)


func actor_for(uid: int) -> PokemonActor:
	var b: PetBrain = _brains.get(uid)
	return b.actor if b else null


func sleeping_uids() -> Array:
	var out := []
	for u in _brains:
		if (_brains[u] as PetBrain).is_sleeping():
			out.append(u)
	return out


func home_uids() -> Array:
	return _brains.keys()
