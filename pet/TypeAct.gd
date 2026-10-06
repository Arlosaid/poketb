class_name TypeAct
extends Node2D
## Acción propia del tipo de una mascota (data/pet_types.json): brasas, fuente, chispas,
## excavar, teletransporte, atravesar como fantasma, colgarse de un hilo de seda...
## Vive como hijo de la casa mientras dura; si la mascota cambia de estado a mitad
## (la arrastras, la acaricias), se cancela y deja al actor como estaba.

static var _data: Dictionary

var brain: PetBrain
var actor: PokemonActor
var act: Dictionary
## Tipo del Pokémon que da los colores de las partículas.
var ptype := "normal"
var _alive := true
var _thread: Line2D


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/pet_types.json"))
	return _data


## Acciones posibles para estos tipos a esta hora: [[acto, tipo], ...].
static func options(types: Array, night: bool) -> Array:
	var out := []
	for t in types:
		for a in data()["types"].get(t, []):
			var when: String = a.get("when", "")
			if when == "" or (when == "night") == night:
				out.append([a, t])
	return out


static func pick(types: Array, night: bool) -> Array:
	var opts := options(types, night)
	var total := 0.0
	for o in opts:
		total += float(o[0].get("weight", 1.0))
	var r := randf() * total
	for o in opts:
		r -= float(o[0].get("weight", 1.0))
		if r <= 0.0:
			return o
	return opts.back() if not opts.is_empty() else []


static func start(b: PetBrain, a: Dictionary, t: String) -> TypeAct:
	var ta := TypeAct.new()
	ta.brain = b
	ta.actor = b.actor
	ta.act = a
	ta.ptype = t
	ta.z_index = 12
	b.home.add_child(ta)
	ta._run()
	return ta


func _still_mine() -> bool:
	return _alive and is_instance_valid(brain) and brain.state == PetBrain.State.ACT and brain._type_act == self


func _wait(sec: float) -> bool:
	var left := sec
	while left > 0.0:
		await get_tree().process_frame
		if not _still_mine():
			_cancel()
			return false
		left -= get_process_delta_time()
		brain.home.desk.keep_ambient()
	return true


func _run() -> void:
	var kind := String(act.get("kind", "particles"))
	var dur := float(act.get("dur", 2.0))
	var anim := String(act.get("anim", "Idle"))
	actor.play_anim(anim, actor.dir if anim in ["Walk", "Shoot", "Punch", "Kick"] else "S", true)
	if act.has("say"):
		Emote.show_on(brain.home, actor, String(act["say"]), 1.2)
	var ok := true
	match kind:
		"teleport": ok = await _teleport()
		"dig": ok = await _dig(dur)
		"phase": ok = await _phase(dur)
		"hover": ok = await _hover(dur, anim)
		"roll": ok = await _roll(dur, anim)
		"web": ok = await _web(dur)
		_: ok = await _particles(dur, anim, int(act.get("repeat", 1)))
	if ok:
		_finish()


## Termina bien: la mascota vuelve a quedarse quieta.
func _finish() -> void:
	var mine := _still_mine()
	_restore()
	if mine:
		brain.end_type_act()
	_alive = false
	queue_free()


func _cancel() -> void:
	if not _alive:
		return
	_alive = false
	_restore()
	queue_free()


func _restore() -> void:
	if not is_instance_valid(actor):
		return
	actor.modulate.a = 1.0
	actor.visible = true
	if is_instance_valid(_thread):
		_thread.queue_free()
	if is_instance_valid(brain) and brain.state not in [PetBrain.State.DRAG, PetBrain.State.FALL]:
		actor.position.y = brain.home.ground_y
		actor.air = 0.0
	actor.play_anim("Idle", "S", true)


# ------------------------------------------------------------------ partículas

func _center() -> Vector2:
	return MoveFx.body_center(actor)


func _part(pos: Vector2, part := "") -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = MoveFx.part_tex(ptype, part if part != "" else String(act.get("part", "orb_s")))
	s.position = pos.round()
	add_child(s)
	return s


func _float_part(a: Vector2, b: Vector2, dur: float, part := "") -> void:
	var s := _part(a, part)
	var t := s.create_tween()
	t.tween_property(s, "position", b, dur).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(s, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.6)
	t.tween_callback(s.queue_free)


## Un "paso" del patrón de partículas (se llama varias veces durante el acto).
func _emit(pattern: String, k: int) -> void:
	var c := _center()
	var head := actor.position + actor.head_point()
	match pattern:
		"rise":
			var p := c + Vector2(randf_range(-7, 7), randf_range(-2, 4))
			_float_part(p, p + Vector2(randf_range(-2, 2), -randf_range(10, 16)), 0.9)
		"fall":
			var x := actor.position.x + randf_range(-16, 16)
			_float_part(Vector2(x, head.y - 12.0), Vector2(x + randf_range(-4, 4), brain.home.ground_y - 2.0), 1.4)
		"orbit":
			var ang := float(k) * 1.3
			var s := _part(c)
			var t := s.create_tween()
			t.tween_method(func(u: float) -> void:
				s.position = (c + Vector2(cos(ang + u * TAU), sin(ang + u * TAU) * 0.5) * 11.0).round(), 0.0, 1.0, 0.9)
			t.tween_callback(s.queue_free)
		"fountain":
			var side := -1.0 if k % 2 == 0 else 1.0
			var a := head + Vector2(0, -1)
			var b := Vector2(actor.position.x + side * randf_range(8, 16), brain.home.ground_y - 2.0)
			var s2 := _part(a)
			var t2 := s2.create_tween()
			t2.tween_method(func(u: float) -> void:
				s2.position = (a.lerp(b, u) + Vector2(0, -14.0 * sin(u * PI))).round(), 0.0, 1.0, 0.7)
			t2.tween_property(s2, "modulate:a", 0.0, 0.1)
			t2.tween_callback(s2.queue_free)
		"zap":
			var s3 := _part(head + Vector2(randf_range(-9, 9), randf_range(-2, 9)))
			var t3 := s3.create_tween()
			t3.tween_interval(0.15)
			t3.tween_callback(s3.queue_free)
		"puff":
			for i in 3:
				var ang2 := randf() * TAU
				_float_part(c, c + Vector2(cos(ang2), sin(ang2) * 0.6) * 10.0, 0.45)
		"sparkle":
			var bb: Array = actor.meta["anims"][actor.resolve("Idle")]["bbox"]
			var p2 := actor.position + Vector2(randf_range(bb[0], float(bb[0]) + float(bb[2])), randf_range(bb[1], float(bb[1]) + float(bb[3])))
			var s4 := _part(p2)
			s4.modulate.a = 0.0
			var t4 := s4.create_tween()
			t4.tween_property(s4, "modulate:a", 1.0, 0.1)
			t4.tween_interval(0.25)
			t4.tween_property(s4, "modulate:a", 0.0, 0.15)
			t4.tween_callback(s4.queue_free)


func _pattern_step() -> float:
	match String(act.get("fx", "puff")):
		"rise": return 0.28
		"fall": return 0.35
		"orbit": return 0.22
		"fountain": return 0.12
		"zap": return 0.14
		"sparkle": return 0.3
	return 0.4


func _particles(dur: float, anim: String, repeat: int) -> bool:
	var pattern := String(act.get("fx", "puff"))
	var step := _pattern_step()
	var each := dur / maxf(1.0, float(repeat))
	var k := 0
	for r in repeat:
		if r > 0:
			actor.play_anim(anim, actor.dir, true)
		var t := 0.0
		while t < each:
			_emit(pattern, k)
			k += 1
			if not await _wait(step):
				return false
			t += step
	return true


# ------------------------------------------------------------------ movimientos especiales

func _fade(to_alpha: float, dur: float) -> void:
	var t := actor.create_tween()
	t.tween_property(actor, "modulate:a", to_alpha, dur)


func _teleport() -> bool:
	for i in 4:
		_emit(String(act.get("fx", "sparkle")), i)
	_fade(0.0, 0.25)
	if not await _wait(0.45):
		return false
	actor.position.x = brain.home.random_x()
	for i in 4:
		_emit("puff", i)
	_fade(1.0, 0.25)
	actor.play_anim("Joy", "S", true)
	return await _wait(0.6)


func _dig(dur: float) -> bool:
	_emit("puff", 0)
	var spr := actor.sprite
	var t := spr.create_tween()
	t.tween_property(spr, "position:y", spr.position.y + 6.0, 0.4)
	_fade(0.0, 0.4)
	if not await _wait(0.45):
		return false
	# bajo tierra: un rastro de polvo avanza hasta donde va a salir
	var from_x := actor.position.x
	var to_x := clampf(from_x + randf_range(-90.0, 90.0), brain.home.x_min, brain.home.x_max)
	var steps := maxi(4, int(dur / 0.18))
	for i in steps:
		var x := lerpf(from_x, to_x, float(i + 1) / steps)
		_float_part(Vector2(x, brain.home.ground_y - 1.0), Vector2(x, brain.home.ground_y - 5.0), 0.4, "dust")
		if not await _wait(0.18):
			return false
	actor.position.x = to_x
	actor.play_anim("Hop", "S", true)
	_fade(1.0, 0.15)
	for i in 2:
		_emit("puff", i)
	return await _wait(0.5)


func _phase(dur: float) -> bool:
	_fade(0.45, 0.4)
	var to_x := clampf(actor.position.x + randf_range(-70.0, 70.0), brain.home.x_min, brain.home.x_max)
	actor.play_anim(String(act.get("anim", "Float")), "E" if to_x > actor.position.x else "W")
	var from := actor.position
	var t := 0.0
	var k := 0
	while t < dur:
		var u := t / dur
		var lift := 8.0 * sin(u * PI)
		actor.position = Vector2(lerpf(from.x, to_x, u), brain.home.ground_y - lift).round()
		actor.air = lift
		if k % 8 == 0:
			_emit(String(act.get("fx", "rise")), k)
		k += 1
		if not await _wait(0.05):
			return false
		t += 0.05
	_fade(1.0, 0.3)
	return await _wait(0.3)


func _hover(dur: float, anim: String) -> bool:
	var t := 0.0
	var k := 0
	var top := randf_range(8.0, 14.0)
	while t < dur:
		var u := t / dur
		var lift := top * minf(1.0, minf(u, 1.0 - u) * 5.0) + sin(t * 4.0) * 1.5
		actor.position.y = roundf(brain.home.ground_y - lift)
		actor.air = maxf(0.0, lift)
		if k % 6 == 0:
			_emit(String(act.get("fx", "orbit")), k)
			if not actor.sprite.is_playing():
				actor.play_anim(anim, actor.dir, true)
		k += 1
		if not await _wait(0.05):
			return false
		t += 0.05
	return true


func _roll(dur: float, anim: String) -> bool:
	var to_x := clampf(actor.position.x + randf_range(-100.0, 100.0), brain.home.x_min, brain.home.x_max)
	var d := "E" if to_x > actor.position.x else "W"
	var t := 0.0
	var k := 0
	var from_x := actor.position.x
	while t < dur:
		actor.position.x = roundf(lerpf(from_x, to_x, t / dur))
		if not actor.sprite.is_playing():
			actor.play_anim(anim, d, true)
		if k % 5 == 0:
			_float_part(Vector2(actor.position.x, brain.home.ground_y - 1.0), Vector2(actor.position.x - signf(to_x - from_x) * 6.0, brain.home.ground_y - 4.0), 0.35, "dust")
		k += 1
		if not await _wait(0.05):
			return false
		t += 0.05
	actor.position.x = to_x
	return true


## Se cuelga de un hilo de seda desde arriba y se mece un rato.
func _web(dur: float) -> bool:
	_thread = Line2D.new()
	_thread.width = 1.0
	_thread.default_color = Palette.a(Palette.TAN, 0.9)
	_thread.antialiased = false
	add_child(_thread)
	var top := Vector2(actor.position.x, 2.0)
	var height := randf_range(14.0, 22.0)
	var t := 0.0
	var k := 0
	while t < dur:
		var u := t / dur
		var lift := height * minf(1.0, minf(u, 1.0 - u) * 4.0)
		var sway := sin(t * 2.2) * 2.0 * minf(1.0, lift / 6.0)
		actor.position = Vector2(top.x + roundf(sway), roundf(brain.home.ground_y - lift))
		actor.air = lift
		var head := actor.position + actor.head_point()
		_thread.points = PackedVector2Array([top, head.round()])
		_thread.visible = lift > 1.0
		if k % 12 == 0 and lift > 4.0:
			_emit("sparkle", k)
		k += 1
		if not await _wait(0.05):
			return false
		t += 0.05
	actor.position.x = top.x
	return true
