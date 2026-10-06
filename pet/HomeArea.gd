class_name HomeArea
extends Node2D
## "Casa": la franja sobre la barra de tareas donde los Pokémon que no pelean viven
## como mascotas. Coordina lo que involucra a varias: la pelota, los juegos entre ellas,
## los vuelos por la pantalla y las reacciones a lo que pasa en la PC (PcSense).

signal pc_requested

## Pausa mínima entre dos vuelos cualesquiera, y entre dos vuelos del mismo Pokémon (s).
const FLIGHT_GAP := Vector2(120.0, 300.0)
const FLIGHT_GAP_SAME := Vector2(480.0, 900.0)
## Solo vuelan si estás usando la PC (si no hay nadie mirando, no gastan).
const FLIGHT_MAX_USER_IDLE := 60.0
const SOCIAL_RANGE := 220.0

var desk: DesktopWindow
var hud: Control
var ground_y := 93.0
var x_min := 8.0
var x_max := 500.0
## Ganas de moverse según la app activa (1 = normal; menos = trabajas y están tranquilos).
var calm := 1.0
## Estás viendo un video: se sientan a mirar contigo.
var watching := false
## Estás con música: bailan más.
var music := false
var ball: ToyBall
var flight: FlightWindow
var sense: PcSense

var _brains := {}   # uid → PetBrain
var _flier: PetBrain
var _next_flight_at := 0.0
var _flight_ready_at := {}  # uid → segundos (ticks) desde que puede volver a volar


func setup(d: DesktopWindow, h: Control) -> void:
	desk = d
	hud = h
	y_sort_enabled = true
	_next_flight_at = _now() + randf_range(40.0, 90.0)
	sense = PcSense.new()
	sense.name = "PcSense"
	add_child(sense)
	sense.app_changed.connect(_on_app_changed)
	sense.user_returned.connect(greet_user)
	sense.break_suggested.connect(suggest_break)
	sense.break_taken.connect(break_taken)
	sense.late_night.connect(late_night)
	sense.battery_low.connect(func(pct: int) -> void:
		var s := _speaker()
		if s:
			s.react("sweat")
			Bubble.say(hud, s.actor, "Batería: %d%%" % pct))
	sense.battery_charging.connect(func() -> void:
		var s := _speaker()
		if s:
			s.react("exclaim", "Joy"))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func set_bounds(left: float, right: float, ground: float) -> void:
	x_min = left
	x_max = right
	ground_y = ground
	for u in _brains:
		var b: PetBrain = _brains[u]
		if b.state not in [PetBrain.State.DRAG, PetBrain.State.FALL, PetBrain.State.AWAY]:
			b.actor.position.x = clampf(b.actor.position.x, x_min, x_max)
			b.actor.position.y = ground_y


func random_x() -> float:
	return randf_range(x_min, x_max)


## Destino de un paseo: a veces vuelve a su lugar favorito.
func wander_x(b: PetBrain) -> float:
	if b.mon.fav_x >= 0.0 and randf() < 0.4:
		var fav := lerpf(x_min, x_max, b.mon.fav_x)
		return clampf(fav + randf_range(-30.0, 30.0), x_min, x_max)
	return random_x()


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
			if b == _flier:
				_flier = null
				if flight:
					flight.abort()
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
		a.position = Vector2(wander_x(brain), ground_y)
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


## Quien habla por la casa: el compañero si está, si no el primero libre.
func _speaker() -> PetBrain:
	var first: PetBrain = null
	for u in _brains:
		var b: PetBrain = _brains[u]
		if b.state == PetBrain.State.AWAY:
			continue
		if b.is_companion:
			return b
		if first == null and b.is_free():
			first = b
	return first


# ------------------------------------------------------------------ pelota

func ball_available() -> bool:
	return is_instance_valid(ball)


## Saca la pelota junto a `a` y la lanza un poco (si ya hay una, la trae).
func throw_ball_from(a: PokemonActor) -> void:
	if not is_instance_valid(ball):
		ball = ToyBall.new()
		ball.home = self
		add_child(ball)
		ball.thrown.connect(_on_ball_thrown)
	ball.position = Vector2(clampf(a.position.x + randf_range(-6.0, 6.0), x_min, x_max), ground_y - 20.0)
	var dir := 1.0 if a.position.x < (x_min + x_max) / 2.0 else -1.0
	ball.kick(Vector2(dir * randf_range(60.0, 110.0), -120.0), true)


## La mascota que persigue la pelota y está más cerca de ella.
func closest_to_ball() -> PetBrain:
	var best: PetBrain = null
	var d := INF
	for u in _brains:
		var b: PetBrain = _brains[u]
		if b.state == PetBrain.State.CHASE:
			var dd := absf(b.actor.position.x - ball.position.x)
			if dd < d:
				d = dd
				best = b
	return best


## Lanzaste la pelota: los juguetones salen corriendo detrás.
func _on_ball_thrown() -> void:
	for u in _brains:
		var b: PetBrain = _brains[u]
		if b.is_free() and b.mon.energy > 20.0 and not b.mon.is_fainted() and randf() < clampf(0.35 * b._wv("ball"), 0.0, 0.9):
			b.start_chase()


# ------------------------------------------------------------------ vida social

func has_partner_for(b: PetBrain) -> bool:
	return _pick_partner(b) != null


func _pick_partner(b: PetBrain) -> PetBrain:
	var best: PetBrain = null
	var best_score := 0.0
	for u in _brains:
		var o: PetBrain = _brains[u]
		if o == b or absf(o.actor.position.x - b.actor.position.x) > SOCIAL_RANGE:
			continue
		if not (o.is_free() or o.is_sleeping()) or o.mon.is_fainted():
			continue
		var score := (1.0 + Game.roster.bond(b.mon.uid, o.mon.uid) / 10.0) * randf()
		if score > best_score:
			best_score = score
			best = o
	return best


func start_social(b: PetBrain) -> void:
	var o := _pick_partner(b)
	if o == null:
		b.force_state(PetBrain.State.IDLE, 2.0)
		return
	var kind := "greet"
	if o.is_sleeping():
		if b.mon.energy > 60.0 and b._wv("sleep") <= 1.0:
			b.force_state(PetBrain.State.IDLE, 2.0)
			return
		kind = "nap"
	elif b.mon.energy > 30.0 and o.mon.energy > 30.0 and randf() < 0.45:
		kind = "chase"
	b.social_start(kind, o)
	if kind != "nap":
		o.social_invite(kind, b)


# ------------------------------------------------------------------ vuelos

func _flights_allowed() -> bool:
	return Game.settings.get("flights", true) and not Game.pets_hidden() and not desk.fullscreen_app \
		and Game.user_idle_seconds() < FLIGHT_MAX_USER_IDLE and Game.scenario == ""


func can_start_flight(b: PetBrain) -> bool:
	if _flier != null or _now() < _next_flight_at or not _flights_allowed():
		return false
	if not Personality.can_fly(b.mon.species) or b.mon.energy < 30.0 or b.mon.hp_frac() < 0.5:
		return false
	if Game.clock.is_night() != Personality.is_nocturnal(b.mon.species):
		return false
	return _now() >= float(_flight_ready_at.get(b.mon.uid, 0.0))


## Despega: lo esconde en casa y lo lleva la ventanita de vuelo por la pantalla.
func start_flight(b: PetBrain) -> void:
	if flight == null:
		flight = FlightWindow.new(desk.scale)
		flight.name = "FlightWindow"
		flight.desk = desk
		get_tree().root.add_child(flight)
		flight.finished.connect(_on_flight_finished)
	var root := get_tree().root
	var sc := float(desk.scale)
	var start := Vector2(root.position) + b.actor.position * sc
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var top := float(usable.position.y) + 40.0 * sc
	var h := float(usable.size.y)
	var cruise_y := clampf(float(usable.end.y) - h * randf_range(0.45, 0.8), top, float(usable.end.y) - 80.0 * sc)
	var dir := 1.0 if b.actor.position.x < (x_min + x_max) / 2.0 else -1.0
	var margin := 50.0 * sc
	var far_x := float(usable.end.x) - margin if dir > 0.0 else float(usable.position.x) + margin
	var land_x := randf_range(x_min, x_max)
	var land := Vector2(float(root.position.x) + land_x * sc, float(root.position.y) + (ground_y - 26.0) * sc)
	var pts := PackedVector2Array([
		Vector2(start.x + dir * 90.0 * sc, lerpf(start.y, cruise_y, 0.6)),
		Vector2(lerpf(start.x, far_x, 0.5), cruise_y - h * 0.08),
		Vector2(far_x, cruise_y),
		Vector2(lerpf(far_x, land.x, 0.5), cruise_y + h * randf_range(-0.12, 0.05)),
		Vector2(land.x, land.y - 50.0 * sc),
		land,
	])
	for i in pts.size():
		pts[i].y = clampf(pts[i].y, top, land.y)
	_flier = b
	_next_flight_at = _now() + randf_range(FLIGHT_GAP.x, FLIGHT_GAP.y)
	_flight_ready_at[b.mon.uid] = _now() + randf_range(FLIGHT_GAP_SAME.x, FLIGHT_GAP_SAME.y)
	Emote.show_on(self, b.actor, "exclaim", 0.8)
	b.leave_flying()
	flight.fly(b.mon.species, start, pts, desk.scale)


func _on_flight_finished(land: Vector2i) -> void:
	var b := _flier
	_flier = null
	if b == null or not is_instance_valid(b):
		return
	var x := (float(land.x) - float(get_tree().root.position.x)) / float(desk.scale)
	b.land_from_flight(x)


## Cancela un vuelo en curso (pantalla completa, esconder mascotas).
func abort_flight() -> void:
	if flight and flight.visible:
		flight.abort()


## Para los escenarios: hace volar ya a este Pokémon.
func force_flight(b: PetBrain) -> void:
	_next_flight_at = 0.0
	_flight_ready_at.erase(b.mon.uid)
	start_flight(b)


# ------------------------------------------------------------------ reacciones a la PC

func _on_app_changed(cat: String) -> void:
	var r := sense.reaction(cat)
	calm = float(r.get("calm", 1.0))
	watching = bool(r.get("watch", false))
	music = cat == "music"
	for u in _brains:
		var b: PetBrain = _brains[u]
		if not b.is_free():
			continue
		if watching and randf() < 0.6:
			b.watch_screen()
		elif (b.is_companion or randf() < 0.4) and (r.get("emote", "") != "" or r.has("anim")):
			b.react(String(r.get("emote", "")), String(r.get("anim", "")) if randf() < 0.6 else "")


## Volviste a la PC: te reciben.
func greet_user(_away: float) -> void:
	var s := _speaker()
	for u in _brains:
		var b: PetBrain = _brains[u]
		if b == s:
			b.come_to_cursor()
			Emote.show_on(self, b.actor, "exclaim", 1.4)
		elif randf() < 0.6:
			b.react("exclaim")


## Llevas mucho rato seguido: te propone una pausa.
func suggest_break() -> void:
	var s := _speaker()
	if s == null:
		return
	s.come_to_cursor()
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(s) and s.state != PetBrain.State.AWAY:
		Emote.show_on(self, s.actor, "dots", 2.0)
		Bubble.say(hud, s.actor, "¿Una pausa? Estira un poco", 5.0)


## Descansaste: el equipo se anima (más EXP un rato).
func break_taken() -> void:
	var wb := sense.wellbeing()
	Game.roster.start_cheer(float(wb["cheer_exp_pct"]), float(wb["cheer_minutes"]))
	for u in _brains:
		var b: PetBrain = _brains[u]
		b.react("heart", "Joy")
	var s := _speaker()
	if s:
		Bubble.say(hud, s.actor, "¡Ánimo! +%d%% EXP" % int(wb["cheer_exp_pct"]), 4.0)


func late_night() -> void:
	var s := _speaker()
	if s:
		s.react("zzz", "Stretch")
		Bubble.say(hud, s.actor, "Ya es tarde… ¿a dormir?", 4.5)


## Esconder/mostrar (pantalla completa o "Esconder mascotas").
func set_hidden(h: bool) -> void:
	visible = not h
	if h:
		abort_flight()
		if is_instance_valid(ball):
			ball.queue_free()
