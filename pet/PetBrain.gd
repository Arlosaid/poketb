class_name PetBrain
extends Node
## Comportamiento de un Pokémon en casa (sobre la barra de tareas).
## Hijo de un PokemonActor. El movimiento usa tiempo real (las mascotas siguen vivas
## en pausa); las necesidades las lleva Roster con el tiempo de juego.

enum State { IDLE, WANDER, SIT, SLEEP, WAKE, LOOK, PETTED, EAT, DRAG, FALL }

const WALK_SPEED := 20.0
const LOOK_RANGE := 56.0
const GRAVITY := 520.0
## Segundos sin tocar teclado/mouse para que se acurruquen a dormir.
const USER_IDLE_SLEEP := 300.0
const DRAG_THRESHOLD := 3.0

var actor: PokemonActor
var mon: PokemonInstance
var home: HomeArea
var state := State.IDLE
var is_companion := false

var _timer := 0.0
var _target_x := 0.0
var _vy := 0.0
var _pressing := false
var _press_pos := Vector2.ZERO
var _grab_offset := Vector2.ZERO
var _zzz_timer := 0.0
var _look_lost := 0.0
var _mood_timer := 0.0
var _forced_sleep := false
var _bubble: Bubble
var _menu: BerryMenu


func setup(a: PokemonActor, p: PokemonInstance, h: HomeArea) -> void:
	actor = a
	mon = p
	home = h
	actor.clicked.connect(_on_clicked)
	_mood_timer = randf_range(10.0, 25.0)
	_enter(State.IDLE, randf_range(0.5, 2.0))


# ------------------------------------------------------------------ estados

func _enter(s: State, duration := 0.0) -> void:
	state = s
	_timer = duration
	match s:
		State.IDLE:
			actor.play_anim("Idle", "S" if randf() < 0.5 else actor.dir)
		State.WANDER:
			_target_x = home.random_x()
			actor.play_anim("Walk", "E" if _target_x > actor.position.x else "W")
		State.SIT:
			actor.play_anim("Sit", "S")
		State.SLEEP:
			actor.play_anim("Sleep", "S")
			_zzz_timer = 0.6
		State.WAKE:
			actor.play_anim("Wake", "S", true)
			_timer = maxf(0.6, actor.anim_length("Wake"))
		State.LOOK:
			_look_lost = 0.0
		State.PETTED:
			actor.play_anim("Joy", "S", true)
			_timer = actor.anim_length("Joy") + 0.5
		State.EAT:
			actor.play_anim("Eat", "S", true)
		State.DRAG:
			actor.play_anim("Idle", "S")
		State.FALL:
			_vy = 0.0


func _choose_next() -> void:
	var night := Game.clock.is_night()
	var w := {
		State.WANDER: 4.0 * (0.5 if night else 1.0),
		State.IDLE: 3.0 * (1.5 if mon.is_grumpy() else 1.0),
		State.SIT: 1.5 if actor.has_real("Sit") else 0.0,
		State.SLEEP: 0.6 * (4.0 if night else 1.0) * (3.0 if mon.energy < 30.0 else 1.0),
	}
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			match k:
				State.WANDER: _enter(State.WANDER)
				State.IDLE: _enter(State.IDLE, randf_range(2.0, 5.0))
				State.SIT: _enter(State.SIT, randf_range(5.0, 12.0))
				State.SLEEP: _enter(State.SLEEP, randf_range(60.0, 180.0) if night else randf_range(20.0, 60.0))
			return
	_enter(State.IDLE, 2.0)


func _process(delta: float) -> void:
	var cursor := Passthrough.mouse_in_viewport()
	if _pressing and state != State.DRAG and cursor.distance_to(_press_pos) > DRAG_THRESHOLD:
		_close_popups()
		_enter(State.DRAG)

	# PC inactiva: los de casa se acurrucan; al volver, se despiertan de a poco.
	var user_idle := Game.user_idle_seconds() >= USER_IDLE_SLEEP
	# (si va caminando, primero llega a su lugar y luego se duerme)
	if user_idle and state in [State.IDLE, State.SIT, State.LOOK]:
		_forced_sleep = true
		_enter(State.SLEEP, 1e9)
	elif not user_idle and _forced_sleep and state == State.SLEEP:
		_forced_sleep = false
		_timer = randf_range(0.5, 3.0)

	match state:
		State.IDLE, State.SIT:
			if _cursor_near(cursor):
				_enter(State.LOOK)
			else:
				_tick_timer(delta)
		State.WANDER:
			if _cursor_near(cursor) and randf() < 0.02:
				_enter(State.LOOK)
			else:
				_walk(delta)
		State.LOOK:
			_face_cursor(cursor)
			if _cursor_near(cursor):
				_look_lost = 0.0
			else:
				_look_lost += delta
				if _look_lost > 1.5:
					_enter(State.IDLE, randf_range(1.0, 3.0))
		State.SLEEP:
			_zzz_timer -= delta
			if _zzz_timer <= 0.0:
				_zzz_timer = 1.4
				Fx.zzz(home, actor.position + actor.head_point() + Vector2(4, 2))
			_timer -= delta
			if _timer <= 0.0:
				_enter(State.WAKE)
		State.WAKE, State.PETTED:
			_timer -= delta
			if _timer <= 0.0:
				_enter(State.LOOK if _cursor_near(cursor) else State.IDLE, randf_range(1.0, 3.0))
		State.DRAG:
			var p := cursor + _grab_offset
			actor.position = home.clamp_drag(p).round()
			actor.air = home.ground_y - actor.position.y
			home.desk.keep_awake()
		State.FALL:
			_fall(delta)
		State.EAT:
			pass  # lo termina feed()

	if state in [State.IDLE, State.SIT, State.LOOK]:
		_mood(delta)


func _tick_timer(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_choose_next()


func _walk(delta: float) -> void:
	var dx := _target_x - actor.position.x
	if absf(dx) < 1.0:
		_choose_next()
		return
	actor.play_anim("Walk", "E" if dx > 0.0 else "W")
	actor.position.x += signf(dx) * minf(absf(dx), WALK_SPEED * delta)
	home.desk.keep_ambient()


func _fall(delta: float) -> void:
	_vy += GRAVITY * delta
	actor.position.y += _vy * delta
	home.desk.keep_awake()
	actor.air = maxf(0.0, home.ground_y - actor.position.y)
	if actor.position.y >= home.ground_y:
		actor.position.y = home.ground_y
		actor.air = 0.0
		if _vy > 160.0:
			_vy = -_vy * 0.25  # rebotito
			Fx.dust(home, actor.position)
			return
		Fx.dust(home, actor.position)
		_enter(State.IDLE, randf_range(1.0, 2.0))


func _cursor_near(cursor: Vector2) -> bool:
	var vp := actor.get_viewport_rect().size
	return absf(cursor.x - actor.position.x) < LOOK_RANGE and cursor.y > -80.0 and cursor.y < vp.y + 40.0


## Mira hacia el cursor. Nunca de espaldas: E/W de lado, S si estás justo encima,
## y en diagonal hacia abajo (SE/SW) si el cursor está a la altura de la barra.
func _face_cursor(cursor: Vector2) -> void:
	var head := actor.position + actor.head_point()
	var dx := cursor.x - head.x
	var dy := cursor.y - head.y
	var d: String
	if absf(dx) < 10.0:
		d = "S"
	elif dy > 18.0:
		d = "SE" if dx > 0.0 else "SW"
	else:
		d = "E" if dx > 0.0 else "W"
	actor.play_anim("Idle", d)


## De vez en cuando muestra cómo se siente si está desatendido (sin castigos).
func _mood(delta: float) -> void:
	_mood_timer -= delta
	if _mood_timer > 0.0:
		return
	_mood_timer = randf_range(20.0, 40.0)
	if mon.fullness < 25.0:
		Fx.pop_icon(home, actor.position + actor.head_point() + Vector2(6, 0), preload("res://assets/ui/anger.png"))
	elif mon.energy < 15.0:
		Fx.pop_icon(home, actor.position + actor.head_point() + Vector2(6, 0), preload("res://assets/ui/sweat.png"))


# ------------------------------------------------------------------ interacción

func _on_clicked(_a: PokemonActor, button: int) -> void:
	if state in [State.DRAG, State.FALL, State.EAT]:
		return
	if button == MOUSE_BUTTON_LEFT:
		_pressing = true
		_press_pos = Passthrough.mouse_in_viewport()
		_grab_offset = actor.position - _press_pos
		Passthrough.capture_count += 1
	elif button == MOUSE_BUTTON_RIGHT:
		open_berries()


func _input(event: InputEvent) -> void:
	if _pressing and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pressing = false
		Passthrough.capture_count = maxi(0, Passthrough.capture_count - 1)
		if state == State.DRAG:
			_enter(State.FALL)
		else:
			pet()


## Acariciar (clic). Si dormía, se despierta con calma.
func pet() -> void:
	_close_popups()
	if state == State.SLEEP:
		_forced_sleep = false
		_enter(State.WAKE)
		_say("Sigh", "¿Mmm…?")
		return
	var gain := Game.roster.pet(mon)
	Fx.hearts(home, actor.position + actor.head_point() + Vector2(0, -2), 3 if gain > 0 else 1)
	_enter(State.PETTED)
	var actions := [["berry", "Baya"]]
	if is_companion:
		actions.append(["pc", "PC"])
	if mon.fullness < 25.0:
		_say("Worried", "Tiene hambre…", actions)
	elif mon.energy < 15.0:
		_say("Sigh", "Está cansado…", actions)
	else:
		_say("Happy", "", actions)


func open_berries() -> void:
	_close_popups()
	_menu = BerryMenu.open(home.hud, actor, Game.roster.berries)
	_menu.chosen.connect(feed)


## Darle una baya: come y luego reacciona según su naturaleza (regla canon).
func feed(berry: String) -> void:
	_close_popups()
	_enter(State.EAT)
	await get_tree().create_timer(1.8).timeout
	if not is_instance_valid(actor):
		return
	var r := Game.roster.feed(mon, berry)
	if r.is_empty():
		_enter(State.IDLE, 1.0)
		return
	var flavor_txt := SpeciesDB.flavor_es(r["flavor"]) if r["flavor"] != "" else ""
	match r["reaction"]:
		"likes":
			Fx.hearts(home, actor.position + actor.head_point(), 4)
			_enter(State.PETTED)
			_say("Joyous", "¡Le encanta! (%s)" % flavor_txt)
		"hates":
			_enter(State.IDLE, 2.0)
			actor.play_anim("Idle", "S")
			Fx.pop_icon(home, actor.position + actor.head_point() + Vector2(6, 0), preload("res://assets/ui/sweat.png"))
			_say("Sad", "No le gustó… (%s)" % flavor_txt)
		_:
			Fx.hearts(home, actor.position + actor.head_point(), 1)
			_enter(State.PETTED)
			_say("Happy", "¡Ñam!" if flavor_txt == "" else "¡Ñam! (%s)" % flavor_txt)


func _say(emotion: String, text := "", actions: Array = []) -> void:
	if is_instance_valid(_bubble):
		_bubble.close()
	_bubble = Bubble.show_for(home.hud, actor, emotion, text, actions)
	_bubble.action.connect(_on_bubble_action)


func _on_bubble_action(id: String) -> void:
	match id:
		"berry":
			open_berries()
		"pc":
			_close_popups()
			home.pc_requested.emit()


func _close_popups() -> void:
	if is_instance_valid(_bubble):
		_bubble.close()
	if is_instance_valid(_menu):
		_menu.close()


func is_sleeping() -> bool:
	return state == State.SLEEP


func force_state(s: State, duration := 3.0) -> void:
	_enter(s, duration)
