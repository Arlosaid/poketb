class_name PetBrain
extends Node
## Comportamiento de un Pokémon en casa (sobre la barra de tareas).
## Hijo de un PokemonActor. El movimiento usa tiempo real (las mascotas siguen vivas
## en pausa); las necesidades las lleva Roster con el tiempo de juego.
##
## Cada mascota tiene un rasgo (Personality, sale de su característica canon) que cambia
## cuánto pasea, duerme, juega, baila o se luce. Interacciones:
## - clic: caricia (si está herido, los mimos curan un poco);
## - 4 clics rápidos: cosquillas;
## - frotar el mouse encima (sin clic): rascarle;
## - arrastrar y soltar: se puede lanzar (los voladores planean);
## - quedarse quieto encima: ficha compacta;
## - clic derecho: barrita de acciones (baya, pelota, dormir/despertar, ficha).
##
## Además, cada tipo tiene acciones propias (TypeAct, data/pet_types.json), entrena sus
## movimientos con su animación (MoveFx) y a veces hace combates de práctica con otra.

enum State { IDLE, WANDER, SIT, LAY, SLEEP, WAKE, LOOK, PETTED, EAT, DRAG, FALL, ACT, CHASE, SOCIAL, FOLLOW, AWAY }

const WALK_SPEED := 20.0
const LOOK_RANGE := 56.0
const GRAVITY := 520.0
## Los voladores planean al soltarlos.
const GLIDE_GRAVITY := 90.0
const GLIDE_MAX_VY := 45.0
## Segundos sin tocar teclado/mouse para que se acurruquen a dormir.
const USER_IDLE_SLEEP := 300.0
const DRAG_THRESHOLD := 3.0
const THROW_MAX := Vector2(240, 280)
## Clics seguidos (dentro de CLICK_WINDOW s) que cuentan como cosquillas.
const TICKLE_CLICKS := 4
const CLICK_WINDOW := 1.3
## Cambios de dirección del mouse encima (dentro de RUB_WINDOW s) que cuentan como rascar.
const RUB_REVERSALS := 5
const RUB_WINDOW := 1.6
const RUB_COOLDOWN := 2.5
## Segundos con el mouse quieto encima para ver la ficha.
const CARD_DWELL := 1.2

var actor: PokemonActor
var mon: PokemonInstance
var home: HomeArea
var state := State.IDLE
var is_companion := false
## Pesos de comportamiento según el rasgo (ver data/personality.json).
var w: Dictionary

var _timer := 0.0
var _target_x := 0.0
var _speed := 1.0
var _vx := 0.0
var _vy := 0.0
var _pressing := false
var _press_pos := Vector2.ZERO
var _grab_offset := Vector2.ZERO
var _drag_last := Vector2.ZERO
var _drag_vel := Vector2.ZERO
var _zzz_timer := 0.0
var _look_lost := 0.0
var _mood_timer := 0.0
var _forced_sleep := false
var _menu: Control
var _clicks: Array[float] = []
var _rub_last_x := INF
var _rub_dir := 0
var _rub_flips: Array[float] = []
var _rub_travel := 0.0
var _rub_ready_at := 0.0
var _hover_still := 0.0
var _hover_last := Vector2.INF
var _card_shown := false
var _partner: PetBrain
var _social_kind := ""
var _chase_kicks := 0
var _chase_max := 3
## Cada uno corre a un lado distinto de la pelota (así no se amontonan).
var _chase_off := 0.0
var _land_hard := false
## Acción de tipo en curso (si la hay).
var _type_act: TypeAct


func setup(a: PokemonActor, p: PokemonInstance, h: HomeArea) -> void:
	actor = a
	mon = p
	home = h
	w = Personality.weights(p)
	actor.clicked.connect(_on_clicked)
	_mood_timer = randf_range(10.0, 25.0)
	_enter(State.IDLE, randf_range(0.5, 2.0))


func _wv(key: String) -> float:
	return float(w.get(key, 1.0))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------ estados

func _enter(s: State, duration := 0.0) -> void:
	_type_act = null
	state = s
	_timer = duration
	_speed = 1.0
	match s:
		State.IDLE:
			actor.play_anim("Idle", "S" if randf() < 0.5 else actor.dir)
		State.WANDER:
			_target_x = home.wander_x(self)
			actor.play_anim("Walk", "E" if _target_x > actor.position.x else "W")
		State.SIT:
			# "Sit" de PMD está de espaldas: contempla la pantalla (o mira contigo un video)
			if actor.has_real("Sit"):
				actor.play_anim("Sit", "S")
			else:
				actor.play_anim("Idle", "N")
		State.LAY:
			actor.play_anim("Laying", "S")
		State.SLEEP:
			actor.play_anim("Sleep", "S")
			_zzz_timer = 0.6
		State.WAKE:
			actor.play_anim("Wake", "S", true)
			_timer = maxf(0.6, actor.anim_length("Wake"))
		State.LOOK:
			_look_lost = 0.0
		State.PETTED:
			var anim := "Nod" if (mon.is_fainted() or mon.hp_frac() < 0.5) else "Joy"
			actor.play_anim(anim, "S", true)
			_timer = actor.anim_length(anim) + 0.5
		State.EAT:
			actor.play_anim("Eat", "S", true)
		State.DRAG:
			actor.play_anim("Idle", "S")
			_drag_last = Passthrough.mouse_in_viewport()
			_drag_vel = Vector2.ZERO
		State.FALL:
			_land_hard = false
		State.AWAY:
			actor.visible = false


## Animación de una vez (estirarse, bailar, lucirse...) y luego vuelve a estar quieto.
func _act(anim: String, dir := "S", extra := 0.4) -> void:
	_type_act = null
	state = State.ACT
	_speed = 1.0
	actor.play_anim(anim, dir, true)
	_timer = actor.anim_length(anim) + extra


func _choose_next() -> void:
	var night := Game.clock.is_night()
	var sleepy_time := night != Personality.is_nocturnal(mon.species)
	var weak := mon.is_fainted() or mon.hp_frac() < 0.5
	var tired := mon.energy < 30.0
	var bored := mon.fun < 30.0
	var calm: float = home.calm
	var c := {
		"wander": 4.0 * _wv("wander") * calm * (0.5 if sleepy_time else 1.0),
		"idle": 3.0 * _wv("idle") * (1.5 if mon.is_grumpy() else 1.0),
		"sit": (1.4 if actor.has_real("Sit") else 0.4) * _wv("sit") * (3.0 if home.watching else 1.0),
		"lay": (1.0 if actor.has_real("Laying") else 0.3) * _wv("lay") * (2.0 if tired else 1.0),
		"sleep": 0.6 * _wv("sleep") * (4.0 if sleepy_time else 1.0) * (3.0 if tired else 1.0),
		"stretch": 0.5 * _wv("stretch"),
		"dance": 0.35 * _wv("dance") * calm * (3.0 if home.music else 1.0),
		"show": 0.3 * _wv("show") * calm,
		"sky": (0.5 if actor.has_real("LookUp") else 0.0) * _wv("sky") * (2.0 if night else 1.0),
		"social": (1.0 * _wv("social") * calm * (1.6 if bored else 1.0)) if home.has_partner_for(self) else 0.0,
		"ball": (3.0 * _wv("ball") * (1.6 if bored else 1.0)) if home.ball_available() and mon.energy > 20.0 else 0.0,
		"fly": (1.4 * _wv("fly")) if home.can_start_flight(self) else 0.0,
		"climb": (1.2 * _wv("climb")) if home.can_start_climb(self) else 0.0,
		"warp": (1.3 * _wv("warp")) if home.can_start_warp(self) else 0.0,
		# propio de su tipo (brasas, chispas, excavar...) y practicar sus movimientos
		"type": float(TypeAct.data()["base_weight"]) * _wv("type") * calm,
		"train": (float(TypeAct.data()["train_weight"]) * _wv("train") * calm) if mon.energy > 25.0 else 0.0,
	}
	if weak:
		# Débil: descansa para recuperarse (y los mimos le curan un poco).
		for k in ["dance", "show", "social", "ball", "fly", "climb", "warp", "type", "train"]:
			c[k] = 0.0
		c["wander"] *= 0.3
		c["lay"] *= 4.0
		c["sleep"] *= 3.0
	if mon.is_fainted():
		c = {"lay": 2.0, "sleep": 3.0}
	var total := 0.0
	for k in c:
		total += c[k]
	var r := randf() * total
	for k in c:
		r -= c[k]
		if r > 0.0:
			continue
		match k:
			"wander": _enter(State.WANDER)
			"idle": _enter(State.IDLE, randf_range(2.0, 5.0))
			"sit": _enter(State.SIT, randf_range(20.0, 50.0) if home.watching else randf_range(5.0, 12.0))
			"lay": _enter(State.LAY, randf_range(10.0, 30.0))
			"sleep": _enter(State.SLEEP, randf_range(60.0, 180.0) if sleepy_time else randf_range(20.0, 60.0))
			"stretch": _act("Stretch")
			"dance": _act("Dance", "S", 0.2)
			"show": _act("Show", "S" if randf() < 0.5 else actor.dir)
			"sky":
				_act("LookUp", "S", 1.5)
				if night and randf() < 0.4:
					Emote.show_on(home, actor, "star")
			"social": home.start_social(self)
			"ball": start_chase()
			"fly": home.start_flight(self)
			"climb": home.start_climb(self)
			"warp": home.start_warp(self)
			"type": start_type_act()
			"train": train()
		return
	_enter(State.IDLE, 2.0)


func _process(delta: float) -> void:
	if state == State.AWAY:
		return
	var cursor := Passthrough.mouse_in_viewport()
	if _pressing and state != State.DRAG and cursor.distance_to(_press_pos) > DRAG_THRESHOLD:
		_close_popups()
		_enter(State.DRAG)
	_hover(cursor, delta)

	# PC inactiva: los de casa se acurrucan; al volver, se despiertan de a poco.
	var user_idle := Game.user_idle_seconds() >= USER_IDLE_SLEEP
	# (si va caminando, primero llega a su lugar y luego se duerme)
	if user_idle and state in [State.IDLE, State.SIT, State.LOOK, State.LAY]:
		_forced_sleep = true
		_enter(State.SLEEP, 1e9)
	elif not user_idle and _forced_sleep and state == State.SLEEP:
		_forced_sleep = false
		_timer = randf_range(0.5, 3.0)

	match state:
		State.IDLE, State.SIT, State.LAY:
			if state == State.IDLE and _cursor_near(cursor):
				_enter(State.LOOK)
			else:
				_tick_timer(delta)
		State.WANDER:
			if _cursor_near(cursor) and randf() < 0.02:
				_enter(State.LOOK)
			else:
				_walk(delta, _target_x)
		State.LOOK:
			_look(cursor, delta)
		State.SLEEP:
			_zzz_timer -= delta
			if _zzz_timer <= 0.0:
				_zzz_timer = 1.4
				Fx.zzz(home, actor.position + actor.head_point() + Vector2(4, 2))
			_timer -= delta
			if _timer <= 0.0:
				_enter(State.WAKE)
		State.WAKE, State.PETTED, State.ACT:
			_timer -= delta
			if _timer <= 0.0:
				_enter(State.LOOK if _cursor_near(cursor) else State.IDLE, randf_range(1.0, 3.0))
		State.DRAG:
			var p := cursor + _grab_offset
			actor.position = home.clamp_drag(p).round()
			actor.air = home.ground_y - actor.position.y
			_drag_vel = _drag_vel.lerp((cursor - _drag_last) / maxf(delta, 0.001), 0.5)
			_drag_last = cursor
			home.desk.keep_awake()
		State.FALL:
			_fall(delta)
		State.CHASE:
			_chase(delta)
		State.SOCIAL:
			_social(delta)
		State.FOLLOW:
			_timer -= delta
			if _timer <= 0.0 or absf(cursor.x - actor.position.x) < 8.0:
				_act("Joy")
				mon.fun = minf(100.0, mon.fun + 2.0)
			else:
				_walk(delta, cursor.x, false)
		State.EAT:
			pass  # lo termina feed()

	if state in [State.IDLE, State.SIT, State.LOOK, State.LAY]:
		_mood(delta)


func _tick_timer(delta: float) -> void:
	if is_instance_valid(_menu):
		return  # mientras le muestras un menú, te espera
	_timer -= delta
	if _timer <= 0.0:
		_choose_next()


## Camina hacia `x`. Devuelve true al llegar. Con `finish` elige qué hacer al llegar.
func _walk(delta: float, x: float, finish := true) -> bool:
	var dx := x - actor.position.x
	if absf(dx) < 1.0:
		if finish:
			_choose_next()
		return true
	actor.play_anim("Walk", "E" if dx > 0.0 else "W")
	actor.position.x += signf(dx) * minf(absf(dx), WALK_SPEED * _wv("walk_speed") * _speed * delta)
	home.desk.keep_ambient()
	return false


func _look(cursor: Vector2, delta: float) -> void:
	_face_cursor(cursor)
	if not _cursor_near(cursor):
		_look_lost += delta
		if _look_lost > 1.5:
			_enter(State.IDLE, randf_range(1.0, 3.0))
		return
	_look_lost = 0.0
	var dx := cursor.x - actor.position.x
	# Tímido: si el cursor se le viene encima, se aleja un poco.
	if _wv("shy") > 0.0 and absf(dx) < 14.0 and cursor.y > 40.0 and randf() < 0.03:
		state = State.WANDER
		_target_x = clampf(actor.position.x - signf(dx) * randf_range(30.0, 60.0), home.x_min, home.x_max)
		_speed = 1.6
		Emote.show_on(home, actor, "sweat")
		return
	# Juguetón o enérgico: a veces persigue al cursor por la barra.
	if absf(dx) > 20.0 and _wv("ball") * _wv("walk_speed") >= 1.4 and mon.energy > 30.0 and randf() < 0.01:
		state = State.FOLLOW
		_timer = 4.0
		_speed = 1.5
		Emote.show_on(home, actor, "exclaim", 1.0)


func _fall(delta: float) -> void:
	var glide := Personality.can_fly(mon.species)
	_vy += (GLIDE_GRAVITY if glide else GRAVITY) * delta
	if glide:
		_vy = minf(_vy, GLIDE_MAX_VY)
		_vx = move_toward(_vx, 0.0, 60.0 * delta)
		if absf(_vx) > 5.0 or actor.air > 2.0:
			actor.play_anim("Flap", "E" if _vx >= 0.0 else "W")
	actor.position.y += _vy * delta
	actor.position.x += _vx * delta
	var vp := actor.get_viewport_rect().size
	if actor.position.x < 8.0 or actor.position.x > vp.x - 8.0:
		actor.position.x = clampf(actor.position.x, 8.0, vp.x - 8.0)
		_vx = -_vx * 0.5
	home.desk.keep_awake()
	actor.air = maxf(0.0, home.ground_y - actor.position.y)
	if actor.position.y < home.ground_y:
		return
	actor.position.y = home.ground_y
	actor.air = 0.0
	if _vy > 160.0:
		_land_hard = _land_hard or _vy > 260.0 or absf(_vx) > 140.0
		_vy = -_vy * 0.25  # rebotito
		_vx *= 0.6
		Fx.dust(home, actor.position)
		return
	Fx.dust(home, actor.position)
	actor.position.x = clampf(actor.position.x, home.x_min, home.x_max)
	if _land_hard:
		# Un lanzamiento fuerte: da una voltereta, se marea un poco y le hace gracia.
		_act("Tumble", "E" if _vx >= 0.0 else "W", 0.6)
		Emote.show_on(home, actor, "star", 1.4)
		Game.roster.play(mon, 3.0)
	else:
		_enter(State.IDLE, randf_range(1.0, 2.0))


func _face_x(x: float) -> void:
	actor.play_anim("Idle", "E" if x >= actor.position.x else "W")


func _cursor_near(cursor: Vector2) -> bool:
	var vp := actor.get_viewport_rect().size
	return absf(cursor.x - actor.position.x) < LOOK_RANGE * _wv("look_range") and cursor.y > -80.0 and cursor.y < vp.y + 40.0


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


## De vez en cuando muestra cómo se siente (sin castigos): hambre, sueño, aburrimiento.
func _mood(delta: float) -> void:
	_mood_timer -= delta
	if _mood_timer > 0.0:
		return
	_mood_timer = randf_range(20.0, 40.0)
	var icon := ""
	if mon.is_fainted() or mon.hp_frac() < 0.3:
		icon = "sweat"
	elif mon.fullness < float(w.get("hungry_at", 25.0)):
		icon = "berry"
	elif mon.energy < 15.0:
		icon = "zzz"
	elif mon.fun < 25.0:
		icon = "ball"
	elif mon.is_grumpy():
		icon = "anger"
	elif mon.is_cheerful() and randf() < 0.3:
		icon = "note"
	if icon != "":
		Emote.show_on(home, actor, icon, 2.0)


# ------------------------------------------------------------------ tipo y movimientos

## Hace algo propio de su tipo (data/pet_types.json).
func start_type_act(forced: Dictionary = {}, forced_type := "") -> void:
	var pick := [forced, forced_type] if not forced.is_empty() else TypeAct.pick(mon.types(), Game.clock.is_night())
	if pick.is_empty():
		_enter(State.IDLE, 2.0)
		return
	_type_act = null
	state = State.ACT
	_speed = 1.0
	_timer = float(pick[0].get("dur", 2.0)) + 12.0  # red de seguridad: TypeAct avisa al terminar
	_type_act = TypeAct.start(self, pick[0], pick[1])


## TypeAct terminó bien.
func end_type_act() -> void:
	_type_act = null
	mon.fun = minf(100.0, mon.fun + 3.0)
	_enter(State.IDLE, randf_range(1.5, 3.0))


## Movimiento al azar de los que sabe.
func pick_move() -> String:
	return mon.moves.pick_random() if not mon.moves.is_empty() else "tackle"


## Practica un movimiento en el aire, con su animación de pelea en chiquito.
func train(move := "") -> void:
	var m := move if move != "" else pick_move()
	var face := 1.0 if actor.position.x < (home.x_min + home.x_max) / 2.0 else -1.0
	if randf() < 0.3:
		face = -face
	var aim := MoveFx.body_center(actor) + Vector2(face * 34.0, 0)
	perform_move(m, aim, null)
	mon.energy = maxf(0.0, mon.energy - 1.0)
	mon.fun = minf(100.0, mon.fun + 2.0)
	if randf() < 0.35:
		Bubble.say(home.hud, actor, "¡%s!" % SpeciesDB.move(m)["name_es"], 1.6)


## Usa `m` hacia `aim` (o hacia `target`): cuerpo + efecto. Queda en ACT mientras dura.
func perform_move(m: String, aim: Vector2, target: PokemonActor) -> MoveFx:
	_type_act = null
	state = State.ACT
	_speed = 1.0
	var body := MoveFx.body_anim(m)
	var d := "E" if aim.x >= actor.position.x else "W"
	actor.play_anim(body, d, true)
	_timer = maxf(actor.anim_length(body), 0.6) + 1.0
	home.desk.keep_awake()
	await get_tree().create_timer(actor.hit_time(body)).timeout
	if state != State.ACT or not is_instance_valid(actor):
		return null
	var fx := MoveFx.create(home, actor, aim, m, target, true)
	fx.start()
	return fx


# ------------------------------------------------------------------ juego y vida social

## Persigue la pelota de casa.
func start_chase() -> void:
	if not home.ball_available():
		_enter(State.IDLE, 1.0)
		return
	state = State.CHASE
	_timer = 15.0
	_chase_kicks = 0
	_chase_max = randi_range(2, 3 + int(_wv("ball") * 2.0))
	_chase_off = randf_range(-14.0, 14.0)
	if randf() < 0.5:
		Emote.show_on(home, actor, "exclaim", 1.0)


func _chase(delta: float) -> void:
	var ball := home.ball
	_timer -= delta
	if not is_instance_valid(ball) or _timer <= 0.0:
		_enter(State.IDLE, randf_range(1.0, 2.0))
		return
	_speed = 1.7
	var dx := ball.position.x - actor.position.x
	if absf(dx) > 5.0 or ball.position.y < home.ground_y - 12.0:
		# se acerca por su lado y, si está quieta y nadie más llegó, va directo a ella
		var off := 0.0 if ball.is_resting() and home.closest_to_ball() == self else _chase_off
		var tx := ball.position.x + off
		if absf(tx - actor.position.x) > 2.0:
			_walk(delta, tx, false)
		else:
			_face_x(ball.position.x)
		home.desk.keep_awake()
		return
	# ¡La alcanzó! La patea hacia adelante.
	var dir := signf(dx) if dx != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	ball.kick(Vector2(dir * randf_range(70.0, 150.0), -randf_range(70.0, 170.0)))
	actor.play_anim("Hop", "E" if dir > 0.0 else "W", true)
	mon.energy = maxf(0.0, mon.energy - 0.5)
	if ball.fresh_throw or _chase_kicks == 0:
		var gain := Game.roster.play(mon, 10.0)
		Fx.hearts(home, actor.position + actor.head_point(), 2 if gain > 0 else 1)
	else:
		mon.fun = minf(100.0, mon.fun + 3.0)
	_chase_kicks += 1
	if _chase_kicks >= _chase_max:
		_act("Joy")
		Emote.show_on(home, actor, "note")


## Otra mascota lo invita a jugar (lo llama HomeArea).
func social_invite(kind: String, from: PetBrain) -> void:
	_partner = from
	_social_kind = kind
	match kind:
		"greet", "spar":
			state = State.SOCIAL
			_timer = 6.0
		"chase":
			# huye riendo hacia el otro lado
			state = State.WANDER
			var away := signf(actor.position.x - from.actor.position.x)
			_target_x = clampf(actor.position.x + away * randf_range(60.0, 120.0), home.x_min, home.x_max)
			_speed = 1.6
			Emote.show_on(home, actor, "note", 1.2)


## Empieza a jugar con `partner` (lo llama HomeArea).
func social_start(kind: String, partner: PetBrain) -> void:
	_partner = partner
	_social_kind = kind
	state = State.SOCIAL
	_timer = 8.0 if kind == "chase" else 10.0
	_speed = 1.6 if kind == "chase" else 1.0


func _social(delta: float) -> void:
	_timer -= delta
	if not is_instance_valid(_partner) or _partner.state in [State.DRAG, State.FALL, State.AWAY] or _timer <= 0.0:
		_social_end(false)
		return
	var other := _partner
	var pa := other.actor
	var dx := pa.position.x - actor.position.x
	match _social_kind:
		"greet":
			if absf(dx) > 14.0:
				_walk(delta, pa.position.x - signf(dx) * 13.0, false)
				return
			# cara a cara: se saludan
			_social_end(true)
			_act("Nod", "E" if dx > 0.0 else "W")
			other._act("Nod", "W" if dx > 0.0 else "E")
			Emote.show_on(home, actor, "heart")
			Emote.show_on(home, pa, "heart")
		"chase":
			if absf(dx) > 9.0:
				_walk(delta, pa.position.x, false)
				return
			_social_end(true)
			_act("Joy", "E" if dx > 0.0 else "W")
			other._act("Laugh")
			Emote.show_on(home, actor, "note")
		"spar":
			# se ponen a unos pasos y se turnan para lucir sus movimientos
			if absf(dx) > 36.0:
				_walk(delta, pa.position.x - signf(dx) * 32.0, false)
				return
			_social_end(true)
			home.run_spar(self, other)
		"nap":
			if absf(dx) > 15.0:
				_walk(delta, pa.position.x - signf(dx) * 14.0, false)
				return
			_social_end(true)
			_enter(State.SLEEP, randf_range(40.0, 90.0))
			actor.play_anim("Sleep", "S")


func _social_end(ok: bool) -> void:
	if ok and is_instance_valid(_partner):
		Game.roster.add_bond(mon.uid, _partner.mon.uid, 1)
		mon.fun = minf(100.0, mon.fun + 5.0)
		_partner.mon.fun = minf(100.0, _partner.mon.fun + 5.0)
	if is_instance_valid(_partner) and _partner.state == State.SOCIAL and _partner._partner == self:
		_partner._enter(State.IDLE, randf_range(1.0, 2.0))
	_partner = null
	if not ok:
		_enter(State.IDLE, randf_range(1.0, 2.0))


## Se va de paseo volando (HomeArea lo esconde y lo lleva la FlightWindow).
func leave_flying() -> void:
	_close_popups()
	_enter(State.AWAY)


## Vuelve de volar: baja planeando en `x` (coordenadas de casa).
func land_from_flight(x: float) -> void:
	actor.visible = true
	actor.position = Vector2(clampf(x, home.x_min, home.x_max), home.ground_y - 26.0)
	actor.air = 26.0
	_vx = 0.0
	_vy = 0.0
	_enter(State.FALL)
	mon.fun = minf(100.0, mon.fun + 6.0)


## Se teletransporta por la pantalla (HomeArea lo esconde y lo lleva la WarpWindow).
func leave_warping() -> void:
	_close_popups()
	_enter(State.AWAY)


## Vuelve del teletransporte: aparece en `x` con efecto de sparkle.
func land_from_warp(x: float) -> void:
	actor.visible = true
	actor.modulate.a = 0.0
	actor.position = Vector2(clampf(x, home.x_min, home.x_max), home.ground_y)
	var tw := actor.create_tween()
	tw.tween_property(actor, "modulate:a", 1.0, 0.3)
	_enter(State.IDLE, randf_range(1.0, 3.0))
	mon.fun = minf(100.0, mon.fun + 4.0)


## Se va a escalar por el borde de la pantalla (HomeArea lo esconde y lo lleva la ClimbWindow).
func leave_climbing() -> void:
	_close_popups()
	_enter(State.AWAY)


## Vuelve de escalar: aterriza en `x` caminando.
func land_from_climb(x: float) -> void:
	actor.visible = true
	actor.position = Vector2(clampf(x, home.x_min, home.x_max), home.ground_y)
	actor.air = 0.0
	_enter(State.IDLE, randf_range(1.0, 2.5))
	mon.fun = minf(100.0, mon.fun + 5.0)


## Reacción breve a algo que pasa en la PC (app nueva, volviste, etc.).
func react(icon: String, anim := "") -> void:
	if state not in [State.IDLE, State.SIT, State.LOOK, State.WANDER, State.LAY]:
		return
	if icon != "":
		Emote.show_on(home, actor, icon, 1.8)
	if anim != "":
		_act(anim)


## Se sienta "a mirar la pantalla contigo" (videos).
func watch_screen() -> void:
	if state in [State.IDLE, State.LOOK, State.WANDER, State.LAY]:
		_enter(State.SIT, randf_range(30.0, 60.0))


## Camina hasta la x del cursor (para saludarte o proponerte una pausa).
func come_to_cursor() -> void:
	if state in [State.DRAG, State.FALL, State.AWAY, State.EAT]:
		return
	if state == State.SLEEP:
		_forced_sleep = false
	state = State.FOLLOW
	_timer = 5.0
	_speed = 1.5


# ------------------------------------------------------------------ interacción

func _on_clicked(_a: PokemonActor, button: int) -> void:
	if state in [State.DRAG, State.FALL, State.EAT, State.AWAY]:
		return
	if button == MOUSE_BUTTON_LEFT:
		_pressing = true
		_press_pos = Passthrough.mouse_in_viewport()
		_grab_offset = actor.position - _press_pos
		Passthrough.capture_count += 1
	elif button == MOUSE_BUTTON_RIGHT:
		open_actions()


func _input(event: InputEvent) -> void:
	if _pressing and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pressing = false
		Passthrough.capture_count = maxi(0, Passthrough.capture_count - 1)
		if state == State.DRAG:
			_vx = clampf(_drag_vel.x, -THROW_MAX.x, THROW_MAX.x)
			_vy = clampf(_drag_vel.y, -THROW_MAX.y, THROW_MAX.y * 0.5)
			_enter(State.FALL)
		else:
			_click()


func _click() -> void:
	var now := _now()
	_clicks.append(now)
	while not _clicks.is_empty() and now - _clicks[0] > CLICK_WINDOW:
		_clicks.pop_front()
	if _clicks.size() >= TICKLE_CLICKS and not mon.is_fainted():
		_clicks.clear()
		tickle()
	else:
		pet()


## Mouse encima: frotar = rascar; quieto un rato = ficha compacta.
func _hover(cursor: Vector2, delta: float) -> void:
	if Passthrough.hovered() != actor or _pressing or state in [State.DRAG, State.FALL, State.AWAY]:
		_rub_last_x = INF
		_rub_flips.clear()
		_rub_travel = 0.0
		_hover_still = 0.0
		_hover_last = Vector2.INF
		_card_shown = false
		return
	# ficha: el mouse quieto encima
	if _hover_last.is_finite() and cursor.distance_to(_hover_last) < 1.5:
		_hover_still += delta
		if _hover_still >= CARD_DWELL and not _card_shown:
			_card_shown = true
			show_card()
	else:
		_hover_still = 0.0
	_hover_last = cursor
	# rascar: ida y vuelta rápida
	if _rub_last_x != INF:
		var dx := cursor.x - _rub_last_x
		if absf(dx) >= 1.0:
			_rub_travel += absf(dx)
			var d := int(signf(dx))
			if d != _rub_dir and _rub_dir != 0:
				_rub_flips.append(_now())
			_rub_dir = d
	_rub_last_x = cursor.x
	var now := _now()
	while not _rub_flips.is_empty() and now - _rub_flips[0] > RUB_WINDOW:
		_rub_flips.pop_front()
	if _rub_flips.size() >= RUB_REVERSALS and _rub_travel > 24.0 and now >= _rub_ready_at:
		_rub_flips.clear()
		_rub_travel = 0.0
		_rub_ready_at = now + RUB_COOLDOWN
		rub()


## Acariciar (clic). Si dormía, se despierta con calma. Si está herido, los mimos curan.
func pet() -> void:
	_close_popups()
	var heal := Game.roster.cuddle_heal(mon)
	var head := actor.position + actor.head_point()
	if heal > 0:
		Fx.float_text(home, head + Vector2(0, -10), "+%d PS" % heal, Palette.MINT, Palette.FOREST)
	if state == State.SLEEP:
		_forced_sleep = false
		_enter(State.WAKE)
		Emote.show_on(home, actor, "question")
		return
	var gain := Game.roster.pet(mon)
	Fx.hearts(home, head + Vector2(0, -2), 3 if gain > 0 else 1)
	if mon.is_fainted():
		return  # se queda tumbado, pero agradecido
	_enter(State.PETTED)
	if mon.fullness < float(w.get("hungry_at", 25.0)):
		Emote.show_on(home, actor, "berry", 2.0)
	elif mon.energy < 15.0:
		Emote.show_on(home, actor, "zzz", 2.0)
	elif mon.fun < 25.0:
		Emote.show_on(home, actor, "ball", 2.0)


## Cosquillas (varios clics rápidos): se ríe, se divierte.
func tickle() -> void:
	_close_popups()
	var gain := Game.roster.play(mon, 8.0)
	_act("Laugh")
	Emote.show_on(home, actor, "note", 1.6)
	Fx.hearts(home, actor.position + actor.head_point(), 2 if gain > 0 else 1)
	home.desk.keep_awake()


## Rascar (frotar con el mouse): se estira de gusto.
func rub() -> void:
	if state in [State.EAT, State.SLEEP] or mon.is_fainted():
		return
	var gain := Game.roster.play(mon, 5.0)
	Game.roster.cuddle_heal(mon)
	_act("Stretch")
	Emote.show_on(home, actor, "heart", 1.6)
	Fx.sparkles(home, actor.position + actor.head_point() + Vector2(0, 4), 8.0, 3 if gain > 0 else 2)


func show_card() -> void:
	PetCard.open(home.hud, actor, mon)


func open_actions() -> void:
	_close_popups()
	var actions := [["berry", "Baya"], ["ball", "Pelota"]]
	if state == State.SLEEP:
		actions.append(["wake", "Despertar"])
	else:
		actions.append(["sleep", "A dormir"])
	actions.append(["card", "Ficha"])
	var bar := ActionBar.open(home.hud, actor, actions)
	bar.chosen.connect(_on_action)
	_menu = bar


func _on_action(id: String) -> void:
	match id:
		"berry":
			open_berries()
		"ball":
			home.throw_ball_from(actor)
			start_chase()
		"sleep":
			_forced_sleep = false
			_enter(State.SLEEP, randf_range(90.0, 150.0))
		"wake":
			_forced_sleep = false
			_enter(State.WAKE)
		"card":
			show_card()


func open_berries() -> void:
	_close_popups()
	var m := BerryMenu.open(home.hud, actor, Game.roster.berries)
	m.chosen.connect(feed)
	_menu = m


## Darle una baya: come y luego reacciona según su naturaleza (regla canon).
func feed(berry: String) -> void:
	_close_popups()
	_enter(State.EAT)
	await get_tree().create_timer(1.8).timeout
	if not is_instance_valid(actor) or state != State.EAT:
		return
	var r := Game.roster.feed(mon, berry)
	if r.is_empty():
		_enter(State.IDLE, 1.0)
		return
	var flavor_txt := SpeciesDB.flavor_es(r["flavor"]) if r["flavor"] != "" else ""
	var head := actor.position + actor.head_point()
	if int(r.get("healed", 0)) > 0:
		Fx.float_text(home, head + Vector2(0, -10), "+%d PS" % int(r["healed"]), Palette.MINT, Palette.FOREST)
	match r["reaction"]:
		"likes":
			Fx.hearts(home, head, 4)
			_enter(State.PETTED)
			Bubble.say(home.hud, actor, "¡Le encanta! (%s)" % flavor_txt)
		"hates":
			_enter(State.IDLE, 2.0)
			actor.play_anim("Idle", "S")
			Emote.show_on(home, actor, "sweat", 2.0)
			Bubble.say(home.hud, actor, "No le gustó (%s)" % flavor_txt)
		_:
			Fx.hearts(home, head, 1)
			_enter(State.PETTED)
			Emote.show_on(home, actor, "note")


func _close_popups(all := true) -> void:
	if is_instance_valid(_menu):
		_menu.call("close")
	_menu = null
	if all:
		var b := actor.attached(&"bubble") if actor else null
		if b:
			(b as Bubble).close()


func is_sleeping() -> bool:
	return state == State.SLEEP


## Quieto o paseando: disponible para jugar con otra mascota o reaccionar.
func is_free() -> bool:
	return state in [State.IDLE, State.SIT, State.LOOK, State.WANDER, State.LAY] and not _pressing


func force_state(s: State, duration := 3.0) -> void:
	_enter(s, duration)
