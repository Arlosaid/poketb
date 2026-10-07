class_name HomeArea
extends Node2D
## "Casa": la franja sobre la barra de tareas donde los Pokémon que no pelean viven
## como mascotas. Coordina lo que involucra a varias: la pelota, los juegos entre ellas,
## los vuelos por la pantalla y las reacciones a lo que pasa en la PC (PcSense).

signal pc_requested

## Pausas entre vuelos y vuelos simultáneos: data/personality.json → "flight".
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
## Última ventana de vuelo usada (los escenarios la capturan).
var flight: FlightWindow
var sense: PcSense

var _brains := {}   # uid → PetBrain
var _flight_windows: Array[FlightWindow] = []
var _fliers := {}  # FlightWindow → PetBrain
var _next_flight_at := 0.0
var _flight_ready_at := {}  # uid → segundos (ticks) desde que puede volver a volar
var _climb_windows: Array[ClimbWindow] = []
var _climbers := {}  # ClimbWindow → PetBrain
var _next_climb_at := 0.0
var _climb_ready_at := {}  # uid → segundos desde que puede volver a escalar
var _warp_windows: Array[WarpWindow] = []
var _warpers := {}  # WarpWindow → PetBrain
var _next_warp_at := 0.0
var _warp_ready_at := {}  # uid → segundos desde que puede volver a teletransportarse


func setup(d: DesktopWindow, h: Control) -> void:
	desk = d
	hud = h
	y_sort_enabled = true
	_next_flight_at = _now() + randf_range(20.0, 50.0)
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
			_abort_flight_of(b)
			_abort_climb_of(b)
			_abort_warp_of(b)
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
	elif b.mon.energy > 40.0 and o.mon.energy > 40.0 and randf() < float(TypeAct.data()["spar_chance"]) * b._wv("train"):
		kind = "spar"
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
	var cfg := Personality.flight_cfg()
	if _fliers.size() >= int(cfg.get("max_fliers", 2)) or _now() < _next_flight_at or not _flights_allowed():
		return false
	if not Personality.can_fly(b.mon.species) or b.mon.energy < 30.0 or b.mon.hp_frac() < 0.5:
		return false
	if Game.clock.is_night() != Personality.is_nocturnal(b.mon.species):
		return false
	return _now() >= float(_flight_ready_at.get(b.mon.uid, 0.0))


## Ventana de vuelo libre (se reusan; hay tantas como vuelos simultáneos).
func _free_flight_window() -> FlightWindow:
	for f in _flight_windows:
		if not f.visible and not _fliers.has(f):
			return f
	var fw := FlightWindow.new(desk.scale)
	fw.name = "FlightWindow%d" % _flight_windows.size()
	fw.desk = desk
	get_tree().root.add_child(fw)
	fw.finished.connect(_on_flight_finished.bind(fw))
	_flight_windows.append(fw)
	return fw


## Despega: lo esconde en casa y lo lleva una ventanita por TODA la pantalla: cruza de
## un borde al otro a distintas alturas, a veces da un rizo o se queda flotando un
## momento, y vuelve a aterrizar en casa.
func start_flight(b: PetBrain) -> void:
	var fw := _free_flight_window()
	flight = fw
	var root := get_tree().root
	var sc := float(desk.scale)
	var start := Vector2(root.position) + b.actor.position * sc
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var top := float(usable.position.y) + 30.0 * sc
	var bottom := float(usable.end.y) - 90.0 * sc
	var left := float(usable.position.x) + 40.0 * sc
	var right := float(usable.end.x) - 40.0 * sc
	var style := Personality.flight_style(b.mon.species)
	var land_x := randf_range(x_min, x_max)
	var land := Vector2(float(root.position.x) + land_x * sc, float(root.position.y) + (ground_y - 26.0) * sc)
	var pts := PackedVector2Array()
	var pauses := {}
	var side := 1.0 if b.actor.position.x < (x_min + x_max) / 2.0 else -1.0
	pts.append(Vector2(start.x + side * 70.0 * sc, lerpf(start.y, bottom, 0.5)))
	var legs := randi_range(3, 5) if style != "float" else randi_range(2, 3)
	for i in legs:
		# cruza la pantalla en zigzag, de un borde al otro y a alturas distintas
		if i > 0:
			side = -side
		var x := right - randf_range(0.0, 0.25) * (right - left) if side > 0.0 else left + randf_range(0.0, 0.25) * (right - left)
		var y := randf_range(top, bottom)
		var mid := Vector2(lerpf(pts[pts.size() - 1].x, x, 0.5), randf_range(top, bottom))
		pts.append(mid)
		if style in ["bird", "dragon"] and randf() < 0.35:
			# rizo: una vuelta completa alrededor de un punto
			var c := mid + Vector2(0, -40.0 * sc)
			for k in range(1, 7):
				var ang := PI / 2.0 + side * TAU * k / 6.0
				pts.append(c + Vector2(cos(ang), sin(ang)) * 40.0 * sc)
		pts.append(Vector2(x, y))
		if randf() < 0.4:
			pauses[pts.size() - 1] = randf_range(1.5, 3.5)  # se queda flotando un momento
	pts.append(Vector2(land.x, lerpf(top, bottom, 0.7)))
	pts.append(Vector2(land.x, land.y - 50.0 * sc))
	pts.append(land)
	for i in pts.size():
		pts[i] = Vector2(clampf(pts[i].x, left, right), clampf(pts[i].y, top, land.y))
	_fliers[fw] = b
	var cfg := Personality.flight_cfg()
	var gap: Array = cfg.get("gap", [45, 120])
	var gap_same: Array = cfg.get("gap_same", [180, 360])
	_next_flight_at = _now() + randf_range(float(gap[0]), float(gap[1]))
	_flight_ready_at[b.mon.uid] = _now() + randf_range(float(gap_same[0]), float(gap_same[1]))
	Emote.show_on(self, b.actor, "exclaim", 0.8)
	b.leave_flying()
	fw.fly(b.mon.species, start, pts, desk.scale, style, pauses)


func _on_flight_finished(land: Vector2i, fw: FlightWindow) -> void:
	var b: PetBrain = _fliers.get(fw)
	_fliers.erase(fw)
	if b == null or not is_instance_valid(b):
		return
	var x := (float(land.x) - float(get_tree().root.position.x)) / float(desk.scale)
	b.land_from_flight(x)


## Cancela los vuelos en curso (pantalla completa, esconder mascotas).
func abort_flight() -> void:
	for f in _flight_windows:
		if f.visible:
			f.abort()


## Aterriza ya a este Pokémon si estaba volando (se fue de casa).
func _abort_flight_of(b: PetBrain) -> void:
	for f in _fliers.keys():
		if _fliers[f] == b:
			_fliers.erase(f)
			f.abort()


## Para los escenarios: hace volar ya a este Pokémon.
func force_flight(b: PetBrain) -> void:
	_next_flight_at = 0.0
	_flight_ready_at.erase(b.mon.uid)
	start_flight(b)


# ------------------------------------------------------------------ escalada por el borde

func can_start_climb(b: PetBrain) -> bool:
	var cfg := Personality.climb_cfg()
	if _climbers.size() >= int(cfg.get("max_climbers", 1)) or _now() < _next_climb_at:
		return false
	if not _flights_allowed():
		return false
	if not Personality.can_climb(b.mon.species) or b.mon.energy < 20.0 or b.mon.is_fainted():
		return false
	return _now() >= float(_climb_ready_at.get(b.mon.uid, 0.0))


func _free_climb_window() -> ClimbWindow:
	for c in _climb_windows:
		if not c.visible and not _climbers.has(c):
			return c
	var cw := ClimbWindow.new(desk.scale)
	cw.name = "ClimbWindow%d" % _climb_windows.size()
	cw.desk = desk
	get_tree().root.add_child(cw)
	cw.finished.connect(_on_climb_finished.bind(cw))
	_climb_windows.append(cw)
	return cw


## Sube al Pokémon por el borde izquierdo o derecho de la pantalla.
func start_climb(b: PetBrain) -> void:
	var cw := _free_climb_window()
	var root := get_tree().root
	var sc := float(desk.scale)
	var start_screen := Vector2(root.position) + b.actor.position * sc
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var top_y := float(usable.position.y) + 20.0 * sc
	var bottom_y := float(usable.end.y) - 90.0 * sc
	var left_x := float(usable.position.x) + 2.0
	var right_x := float(usable.end.x) - float(cw.size.x) - 2.0
	# Escala por el borde más cercano a su posición actual.
	var use_left := b.actor.position.x < (x_min + x_max) / 2.0
	var wall_x := left_x if use_left else right_x
	var wall_name := "left" if use_left else "right"
	var land_x := randf_range(x_min, x_max)
	var land_screen := Vector2(float(root.position.x) + land_x * sc, start_screen.y)
	# Ruta: home → borde → sube a altura aleatoria → (pausa) → baja → home
	var peak_y := randf_range(top_y, (top_y + bottom_y) * 0.55)
	var pts := PackedVector2Array()
	pts.append(Vector2(wall_x, bottom_y))
	pts.append(Vector2(wall_x, peak_y))
	var pauses := {}
	if randf() < 0.5:
		pauses[pts.size() - 1] = randf_range(1.5, 4.0)
	pts.append(Vector2(wall_x, bottom_y))
	pts.append(land_screen)
	_climbers[cw] = b
	var cfg := Personality.climb_cfg()
	var gap: Array = cfg.get("gap", [60, 150])
	var gap_same: Array = cfg.get("gap_same", [240, 480])
	_next_climb_at = _now() + randf_range(float(gap[0]), float(gap[1]))
	_climb_ready_at[b.mon.uid] = _now() + randf_range(float(gap_same[0]), float(gap_same[1]))
	Emote.show_on(self, b.actor, "exclaim", 0.8)
	b.leave_climbing()
	cw.climb(b.mon.species, start_screen, pts, desk.scale, wall_name, pauses)


func _on_climb_finished(land: Vector2i, cw: ClimbWindow) -> void:
	var b: PetBrain = _climbers.get(cw)
	_climbers.erase(cw)
	if b == null or not is_instance_valid(b):
		return
	var x := (float(land.x) - float(get_tree().root.position.x)) / float(desk.scale)
	b.land_from_climb(x)


func abort_climb() -> void:
	for c in _climb_windows:
		if c.visible:
			c.abort()


func _abort_climb_of(b: PetBrain) -> void:
	for c in _climbers.keys():
		if _climbers[c] == b:
			_climbers.erase(c)
			c.abort()


# ------------------------------------------------------------------ teletransporte psíquico

func can_start_warp(b: PetBrain) -> bool:
	var cfg := Personality.warp_cfg()
	if _warpers.size() >= int(cfg.get("max_warpers", 1)) or _now() < _next_warp_at:
		return false
	if not _flights_allowed():
		return false
	if not Personality.can_warp(b.mon.species) or b.mon.energy < 15.0 or b.mon.is_fainted():
		return false
	return _now() >= float(_warp_ready_at.get(b.mon.uid, 0.0))


func _free_warp_window() -> WarpWindow:
	for w in _warp_windows:
		if not w.visible and not _warpers.has(w):
			return w
	var ww := WarpWindow.new(desk.scale)
	ww.name = "WarpWindow%d" % _warp_windows.size()
	ww.desk = desk
	get_tree().root.add_child(ww)
	ww.finished.connect(_on_warp_finished.bind(ww))
	_warp_windows.append(ww)
	return ww


## Teletransporta al Pokémon a 2-4 posiciones aleatorias de la pantalla y vuelve.
func start_warp(b: PetBrain) -> void:
	var ww := _free_warp_window()
	var root := get_tree().root
	var sc := float(desk.scale)
	var home_screen := Vector2(root.position) + b.actor.position * sc
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var margin := 60.0 * sc
	var x_lo := float(usable.position.x) + margin
	var x_hi := float(usable.end.x) - margin
	var y_lo := float(usable.position.y) + margin
	var y_hi := float(usable.end.y) - margin
	var stops := randi_range(2, 4)
	var pts := PackedVector2Array()
	for i in stops:
		pts.append(Vector2(randf_range(x_lo, x_hi), randf_range(y_lo, y_hi)))
	_warpers[ww] = b
	var cfg := Personality.warp_cfg()
	var gap: Array = cfg.get("gap", [50, 130])
	var gap_same: Array = cfg.get("gap_same", [200, 420])
	_next_warp_at = _now() + randf_range(float(gap[0]), float(gap[1]))
	_warp_ready_at[b.mon.uid] = _now() + randf_range(float(gap_same[0]), float(gap_same[1]))
	Emote.show_on(self, b.actor, "exclaim", 0.6)
	b.leave_warping()
	ww.warp(b.mon.species, pts, home_screen, desk.scale)


func _on_warp_finished(land: Vector2i, ww: WarpWindow) -> void:
	var b: PetBrain = _warpers.get(ww)
	_warpers.erase(ww)
	if b == null or not is_instance_valid(b):
		return
	var x := (float(land.x) - float(get_tree().root.position.x)) / float(desk.scale)
	b.land_from_warp(x)


func abort_warp() -> void:
	for w in _warp_windows:
		if w.visible:
			w.abort()


func _abort_warp_of(b: PetBrain) -> void:
	for w in _warpers.keys():
		if _warpers[w] == b:
			_warpers.erase(w)
			w.abort()


# ------------------------------------------------------------------ combate de práctica

## Se turnan para lucir movimientos (sin daño: solo el efecto y un "¡ay!" de juego).
func run_spar(a: PetBrain, b: PetBrain) -> void:
	var busy := [PetBrain.State.DRAG, PetBrain.State.FALL, PetBrain.State.AWAY]
	for t in [[a, b], [b, a], [a, b], [b, a]]:
		if not (is_instance_valid(t[0]) and is_instance_valid(t[1])):
			return
		var att: PetBrain = t[0]
		var def: PetBrain = t[1]
		if att.state in busy or def.state in busy:
			return
		# el que espera se queda quieto mirando
		def._act("Idle", "E" if att.actor.position.x > def.actor.position.x else "W", 2.5)
		var fx: MoveFx = await att.perform_move(att.pick_move(), MoveFx.body_center(def.actor), def.actor)
		if fx == null:
			return
		await fx.wait_impact()
		if is_instance_valid(def) and def.state == PetBrain.State.ACT:
			def.actor.play_anim("Hurt", def.actor.dir, true)
		await get_tree().create_timer(1.0).timeout
	if not (is_instance_valid(a) and is_instance_valid(b)):
		return
	for p: PetBrain in [a, b]:
		if p.state == PetBrain.State.ACT:
			var other: PetBrain = b if p == a else a
			p._act("Nod", "E" if other.actor.position.x > p.actor.position.x else "W")
			Fx.hearts(self, p.actor.position + p.actor.head_point(), 2)
			p.mon.fun = minf(100.0, p.mon.fun + 6.0)
	Game.roster.add_bond(a.mon.uid, b.mon.uid, 1)


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
		abort_climb()
		abort_warp()
		if is_instance_valid(ball):
			ball.queue_free()
