class_name MoveFx
extends Node2D
## Animación de un movimiento: partículas y trazos de la paleta entre el atacante y su
## objetivo. La usan la pelea (BattleController._attack) y la casa (PetBrain: entrenar y
## combates de práctica). Cada movimiento tiene cuerpo, estilo, partícula y golpes en
## data/move_fx.json (tools/gen_move_fx.py desde data/move_fx_rules.json); los colores
## salen del tipo del movimiento.
##
## Uso:
##   var fx := MoveFx.create(stage, atacante, punto, "flamethrower", defensor)
##   fx.start()
##   await fx.wait_impact()   # el momento del golpe (aplicar daño, Hurt, número)
## El nodo se borra solo al terminar.

signal impact

const PARTS := preload("res://assets/ui/fx_parts.png")
const PART := 8
const DEFAULT := {"body": "Attack", "style": "contact", "part": "star", "hits": 1}

static var _table: Dictionary
static var _rules: Dictionary
static var _atlas := {}

var move_name := ""
var info: Dictionary
var mtype := "normal"
## Colores del tipo: claro, medio y oscuro.
var c_hi: Color
var c_mid: Color
var c_dark: Color
var src: PokemonActor
var target: PokemonActor
var from := Vector2.ZERO
var to := Vector2.ZERO
## Altura del suelo bajo el objetivo.
var ground := 0.0
## Hacia dónde mira el atacante (+1 derecha, -1 izquierda).
var face := 1.0
## En casa: menos partículas y sin sacudidas.
var small := false
var miss := false
## Sacude el escenario (opcional): func(px: float) -> void.
var shake := Callable()

var _impacted := false
var _done := false
var _strokes: Array[Dictionary] = []


# ------------------------------------------------------------------ datos

static func data(m: String) -> Dictionary:
	if _table.is_empty():
		_table = JSON.parse_string(FileAccess.get_file_as_string("res://data/move_fx.json"))["moves"]
	return _table.get(m, DEFAULT)


static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/move_fx_rules.json"))
	return _rules


## Animación lógica del cuerpo para este movimiento (PokemonActor.play_anim).
static func body_anim(m: String) -> String:
	return String(data(m)["body"])


static func type_colors(t: String) -> Array[Color]:
	var names: Array = rules()["type_colors"].get(t, rules()["type_colors"]["normal"])
	var out: Array[Color] = []
	for n in names:
		out.append(Palette.by_name(n))
	return out


## Partícula de 8x8 (forma `part` con los colores del tipo `t`).
static func part_tex(t: String, part: String) -> Texture2D:
	var key := t + "/" + part
	if not _atlas.has(key):
		var r := rules()
		var types: Array = r["type_colors"].keys()
		var at := AtlasTexture.new()
		at.atlas = PARTS
		at.region = Rect2(maxi(0, r["parts"].find(part)) * PART, maxi(0, types.find(t)) * PART, PART, PART)
		_atlas[key] = at
	return _atlas[key]


## Centro del cuerpo de un actor (en coordenadas de su padre).
static func body_center(a: PokemonActor) -> Vector2:
	var bb: Array = a.meta["anims"][a.resolve("Idle")]["bbox"]
	return a.position + Vector2(0, float(bb[1]) + float(bb[3]) * 0.5 - a.air)


static func create(parent: Node2D, attacker: PokemonActor, target_pos: Vector2, m: String,
		target_actor: PokemonActor = null, is_small := false) -> MoveFx:
	var fx := MoveFx.new()
	fx.move_name = m
	fx.info = data(m)
	var md: Dictionary = SpeciesDB.move(m) if SpeciesDB.has_move(m) else {"type": "normal"}
	fx.mtype = String(md["type"])
	var cs := type_colors(fx.mtype)
	fx.c_hi = cs[0]
	fx.c_mid = cs[1]
	fx.c_dark = cs[2]
	fx.src = attacker
	fx.target = target_actor
	fx.small = is_small
	fx.face = 1.0 if target_pos.x >= attacker.position.x else -1.0
	var bb: Array = attacker.meta["anims"][attacker.resolve("Idle")]["bbox"]
	var half_w := float(bb[2]) * 0.5
	fx.from = (attacker.position + Vector2(fx.face * maxf(3.0, half_w - 3.0), float(bb[1]) + float(bb[3]) * 0.45 - attacker.air)).round()
	fx.to = target_pos.round()
	fx.ground = target_actor.position.y if target_actor else attacker.position.y
	fx.z_index = 15
	parent.add_child(fx)
	return fx


# ------------------------------------------------------------------ flujo

func start() -> void:
	if miss:
		to += Vector2(face * 12.0, -9.0)
	var style := String(info.get("style", "contact"))
	var hits := clampi(int(info.get("hits", 1)), 1, 5)
	match style:
		"contact": await _contact(hits, 1.0)
		"punch": await _contact(hits, 1.25)
		"kick": await _kick(hits)
		"slam": await _slam()
		"bite": await _bite()
		"slash": await _slash(hits)
		"swing": await _swing()
		"spin": await _spin()
		"vine": await _vine()
		"projectile": await _projectile(String(info["part"]), 1)
		"barrage": await _projectile(String(info["part"]), maxi(3, hits))
		"beam": await _beam()
		"spray": await _spray()
		"bolt": await _bolt()
		"rain": await _rain()
		"rise": await _rise()
		"quake": await _quake()
		"wave": await _wave()
		"wind": await _wind()
		"sound": await _sound()
		"psychic": await _psychic()
		"drain": await _drain()
		"explosion": await _explosion()
		"vanish": await _vanish()
		"dive_bomb": await _dive_bomb()
		"heal": await _aura(true)
		"aura": await _aura(false)
		"status": await _status()
		"shield": await _shield()
		"field": await _field()
		_: await _contact(hits, 1.0)
	_hit(to)  # por si el estilo no lo marcó
	_done = true


## Espera el momento del golpe (vuelve enseguida si ya pasó).
func wait_impact() -> void:
	if not _impacted:
		await impact


func _hit(_at: Vector2) -> void:
	if _impacted:
		return
	_impacted = true
	impact.emit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _n(count: int) -> int:
	return maxi(1, int(round(count * (0.6 if small else 1.0))))


func _process(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for s in _strokes:
		s["t"] += delta
		if s["t"] < s["life"]:
			alive.append(s)
	_strokes = alive
	queue_redraw()
	if _done and _strokes.is_empty() and get_child_count() == 0:
		queue_free()


# ------------------------------------------------------------------ piezas

## Partícula suelta (se borra sola al terminar su tween).
func _part(pos: Vector2, part := "", t := "") -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = part_tex(t if t != "" else mtype, part if part != "" else String(info["part"]))
	s.position = pos.round()
	if face < 0.0:
		s.flip_h = true
	add_child(s)
	return s


## Partícula que viaja de `a` a `b` y desaparece.
func _travel(a: Vector2, b: Vector2, dur: float, part := "", arc := 0.0, fade := true) -> Sprite2D:
	var s := _part(a, part)
	var t := s.create_tween()
	if arc == 0.0:
		t.tween_property(s, "position", b, dur).set_trans(Tween.TRANS_SINE)
	else:
		t.tween_method(func(k: float) -> void:
			s.position = (a.lerp(b, k) + Vector2(0, -arc * sin(k * PI))).round(), 0.0, 1.0, dur)
	if fade:
		t.tween_property(s, "modulate:a", 0.0, 0.12)
	t.tween_callback(s.queue_free)
	return s


## Partícula fija que se muestra `hold` segundos y se apaga.
func _flash_part(pos: Vector2, part: String, hold: float) -> void:
	var s := _part(pos, part)
	var t := s.create_tween()
	t.tween_interval(hold)
	t.tween_property(s, "modulate:a", 0.0, 0.1)
	t.tween_callback(s.queue_free)


## Estallido: partículas que salen en abanico desde `at` y se apagan.
func _burst(at: Vector2, count: int, radius: float, part := "", dur := 0.35) -> void:
	var n := _n(count)
	for i in n:
		var ang := TAU * float(i) / float(n) + randf() * 0.5
		var s := _part(at, part)
		var t := s.create_tween()
		t.tween_property(s, "position", (at + Vector2(cos(ang), sin(ang)) * radius * randf_range(0.7, 1.0)).round(), dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(s, "modulate:a", 0.0, dur * 0.5).set_delay(dur * 0.5)
		t.tween_callback(s.queue_free)


## Estrella de impacto que aparece y se apaga (más un anillo chico).
func _impact_star(at: Vector2, big := 1.0) -> void:
	var s := _part(at, "star", "normal" if mtype in ["normal", "fighting"] else mtype)
	var t := s.create_tween()
	t.tween_interval(0.12 * big)
	t.tween_property(s, "modulate:a", 0.0, 0.1)
	t.tween_callback(s.queue_free)
	_ring(at, 2.0, 8.0 * big * (0.7 if small else 1.0), c_hi, 0.2)


func _stroke(d: Dictionary) -> void:
	d["t"] = 0.0
	_strokes.append(d)


func _line(a: Vector2, b: Vector2, color: Color, life: float, width := 1.0, grow := 0.0) -> void:
	_stroke({"kind": "line", "a": a, "b": b, "color": color, "life": life, "width": width, "grow": grow})


func _ring(center: Vector2, r0: float, r1: float, color: Color, life: float) -> void:
	_stroke({"kind": "ring", "a": center, "r0": r0, "r1": r1, "color": color, "life": life})


func _shake(px: float) -> void:
	if not small and shake.is_valid():
		shake.call(px)


func _draw() -> void:
	for s in _strokes:
		var k: float = clampf(s["t"] / s["life"], 0.0, 1.0)
		var col: Color = s["color"]
		# se apaga en el último tercio
		col.a = 1.0 if k < 0.66 else (1.0 - k) * 3.0
		match s["kind"]:
			"line":
				var a: Vector2 = s["a"]
				var b: Vector2 = s["b"]
				var g: float = s["grow"]
				if g > 0.0:
					b = a.lerp(b, clampf(s["t"] / g, 0.0, 1.0))
				draw_line(a.round(), b.round(), col, s["width"])
			"poly":
				var pts: PackedVector2Array = s["pts"]
				draw_polyline(pts, col, s.get("width", 1.0))
			"ring":
				var r := lerpf(s["r0"], s["r1"], k)
				draw_arc(s["a"], r, 0.0, TAU, maxi(8, int(r * 2.0)), col, 1.0)
			"arc":
				var r2: float = s["r"]
				var a1: float = lerpf(s["a0"], s["a1"], clampf(k * 1.6, 0.0, 1.0))
				draw_arc(s["a"], r2, s["a0"], a1, 10, col, s.get("width", 1.0))
			"tooth":
				# colmillo relleno que baja (o sube) desde la encía hasta la punta
				var base: Vector2 = s["a"]
				var tip: Vector2 = base.lerp(s["b"], clampf(s["t"] / s["grow"], 0.0, 1.0))
				var tri := PackedVector2Array([base + Vector2(-2, 0), base + Vector2(2, 0), tip])
				var edge: Color = s["edge"]
				edge.a = col.a
				draw_colored_polygon(tri, col)
				draw_polyline(PackedVector2Array([tri[0], tri[2], tri[1]]), edge, 1.0)
			"rect":
				var rr: Rect2 = s["rect"]
				if int(s["t"] * 20.0) % 2 == 0 or k < 0.5:
					draw_rect(rr, col, false, 1.0)


# ------------------------------------------------------------------ estilos de contacto

func _contact(hits: int, big: float) -> void:
	for i in hits:
		var at := to + Vector2(randf_range(-3, 3), randf_range(-3, 3)) * float(mini(i, 1))
		_hit(at)
		_impact_star(at, big)
		if mtype not in ["normal", "fighting"] or big > 1.0:
			_burst(at, 4, 9.0)
		_shake(1.0)
		if i < hits - 1:
			await _wait(0.13)


func _kick(hits: int) -> void:
	await _contact(hits, 1.1)
	_burst(Vector2(to.x, ground - 2), 3, 6.0, "dust", 0.3)


func _slam() -> void:
	_hit(to)
	_impact_star(to, 1.3)
	_shake(2.0)
	for sx: float in [-1.0, 1.0]:
		_travel(Vector2(to.x, ground - 2), Vector2(to.x + sx * 12.0, ground - 3), 0.3, "dust")
	if mtype != "normal":
		_burst(to, 5, 10.0)


func _bite() -> void:
	# dos filas de colmillos que se cierran sobre el objetivo
	var teeth := 3
	var w := 4.0
	for row: float in [-1.0, 1.0]:
		var y0 := to.y + row * 9.0
		var y1 := to.y + row * 2.0
		for i in teeth:
			var x := to.x + (float(i) - 1.0) * w
			_stroke({"kind": "tooth", "a": Vector2(x, y0), "b": Vector2(x, y1), "color": Palette.PAPER,
				"edge": Palette.INK, "life": 0.32, "grow": 0.12})
	await _wait(0.12)
	_hit(to)
	_impact_star(to, 0.9)
	if mtype != "normal":
		_burst(to, 4, 8.0)
	_shake(1.0)


func _slash(hits: int) -> void:
	var n := maxi(3, hits)
	for i in n:
		var off := Vector2((float(i) - (n - 1) / 2.0) * 4.0, 0)
		var a := to + off + Vector2(-7, -8) * Vector2(face, 1)
		var b := to + off + Vector2(7, 8) * Vector2(face, 1)
		_line(a + Vector2(1, 0), b + Vector2(1, 0), c_dark, 0.28, 1.0, 0.06)
		_line(a, b, Palette.PAPER if mtype == "normal" else c_hi, 0.28, 1.0, 0.06)
		if i == 0:
			_hit(to)
			_shake(1.0)
		await _wait(0.05)
	if mtype != "normal":
		_burst(to, 3, 8.0)


func _swing() -> void:
	var a0 := -PI * 0.75 if face > 0.0 else -PI * 0.25
	var a1 := PI * 0.25 if face > 0.0 else -PI * 1.25
	_stroke({"kind": "arc", "a": to, "r": 10.0, "a0": a0, "a1": a1, "color": c_hi, "life": 0.3, "width": 2.0})
	_stroke({"kind": "arc", "a": to, "r": 8.0, "a0": a0, "a1": a1, "color": c_mid, "life": 0.3, "width": 1.0})
	await _wait(0.1)
	_hit(to)
	_impact_star(to, 1.0)
	_burst(to, 3, 8.0)
	_shake(1.0)


func _spin() -> void:
	var c := body_center(src)
	for i in _n(6):
		var ang := TAU * float(i) / 6.0
		var s := _part(c + Vector2(cos(ang), sin(ang)) * 10.0)
		var t := s.create_tween()
		t.tween_method(func(k: float) -> void:
			s.position = (c + Vector2(cos(ang + k * TAU), sin(ang + k * TAU) * 0.5) * 10.0).round(), 0.0, 1.0, 0.35)
		t.tween_callback(s.queue_free)
	await _wait(0.2)
	_hit(to)
	_impact_star(to, 1.1)
	_burst(to, 4, 9.0)
	_shake(1.0)


func _vine() -> void:
	for k in 2:
		var mid := from.lerp(to, 0.5) + Vector2(0, -10.0 if k == 0 else 6.0)
		var pts := PackedVector2Array()
		for i in 9:
			var u := float(i) / 8.0
			pts.append(((1.0 - u) * (1.0 - u) * from + 2.0 * (1.0 - u) * u * mid + u * u * to).round())
		_stroke({"kind": "poly", "pts": pts, "color": c_mid, "life": 0.3, "width": 2.0})
		_stroke({"kind": "poly", "pts": pts, "color": c_hi, "life": 0.3, "width": 1.0})
		await _wait(0.12)
		_hit(to)
		_impact_star(to, 0.8)
		_shake(1.0)
	_burst(to, 3, 8.0)


# ------------------------------------------------------------------ estilos a distancia

func _projectile(part: String, count: int) -> void:
	var d := from.distance_to(to)
	var dur := clampf(d / 170.0, 0.12, 0.45)
	var shots := _n(count) if count > 1 else 1
	for i in shots:
		var a := from + Vector2(0, randf_range(-2, 2)) * float(mini(i, 1))
		var b := to + Vector2(randf_range(-3, 3), randf_range(-3, 3)) * float(mini(i, 1))
		_travel(a, b, dur, part, 0.0)
		# estela
		for k in 2:
			_travel(a, a.lerp(b, 0.4 + k * 0.2), dur * (0.4 + k * 0.2), "orb_s").modulate.a = 0.7
		await _wait(dur)
		_hit(b)
		_burst(b, 4 if count == 1 else 2, 9.0 if count == 1 else 6.0)
		if count == 1:
			_impact_star(b, 0.8)
		_shake(0.5 if count > 1 else 1.0)
		if i < shots - 1:
			await _wait(0.04)


func _beam() -> void:
	var grow := 0.1
	_line(from, to, c_dark, 0.45, 5.0, grow)
	_line(from, to, c_mid, 0.45, 3.0, grow)
	_line(from, to, c_hi, 0.45, 1.0, grow)
	_flash_part(from, "orb_l", 0.4)
	for i in _n(4):
		var p := from.lerp(to, randf_range(0.2, 0.9))
		_travel(p, p + Vector2(0, randf_range(-6, 6)), 0.3, "orb_s")
	await _wait(grow)
	_hit(to)
	_impact_star(to, 1.2)
	_burst(to, 5, 10.0)
	_shake(1.0)


func _spray() -> void:
	var n := _n(10)
	var dur := clampf(from.distance_to(to) / 150.0, 0.18, 0.4)
	for i in n:
		var b := to + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		_travel(from, b, dur, "", randf_range(-3.0, 4.0))
		await _wait(0.035)
		if i == 3:
			_hit(to)
			_shake(0.5)
	await _wait(dur * 0.6)
	_burst(to, 4, 9.0)


func _zigzag(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([a.round()])
	var steps := maxi(3, int(a.distance_to(b) / 7.0))
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		pts.append((p + Vector2(randf_range(-4, 4), 0)).round())
	pts.append(b.round())
	return pts


func _bolt() -> void:
	var top := Vector2(to.x + randf_range(-6, 6), maxf(2.0, to.y - 46.0))
	for k in 3:
		var pts := _zigzag(top, to)
		_stroke({"kind": "poly", "pts": pts, "color": c_dark, "life": 0.14, "width": 3.0})
		_stroke({"kind": "poly", "pts": pts, "color": c_mid, "life": 0.14, "width": 2.0})
		_stroke({"kind": "poly", "pts": pts, "color": c_hi, "life": 0.14, "width": 1.0})
		if k == 0:
			_hit(to)
			_impact_star(to, 1.1)
			_shake(1.0)
		await _wait(0.09)
	_burst(to, 5, 10.0, "spark")


func _rain() -> void:
	var n := _n(8)
	for i in n:
		var x := to.x + randf_range(-12, 12)
		var land := Vector2(x, randf_range(to.y - 2, ground - 3))
		_travel(Vector2(x + 6.0 * -face, maxf(2.0, to.y - 44.0)), land, 0.28)
		if i == 1:
			await _wait(0.28)
			_hit(to)
			_impact_star(to, 0.9)
			_shake(1.0)
		else:
			await _wait(0.06)
	await _wait(0.2)
	_burst(Vector2(to.x, ground - 3), 3, 8.0, "dust")


func _rise() -> void:
	var n := _n(4)
	for i in n:
		var x := to.x + (float(i) - (n - 1) / 2.0) * 6.0
		var s := _part(Vector2(x, ground + 2))
		var t := s.create_tween()
		t.tween_property(s, "position:y", ground - randf_range(8, 16), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.18)
		t.tween_property(s, "modulate:a", 0.0, 0.12)
		t.tween_callback(s.queue_free)
		if i == 0:
			_hit(to)
			_shake(1.0)
		await _wait(0.05)
	_burst(Vector2(to.x, ground - 2), 3, 8.0, "dust")


func _quake() -> void:
	var x0 := src.position.x
	var steps := maxi(3, int(absf(to.x - x0) / 9.0))
	for i in steps + 1:
		var x := lerpf(x0, to.x, float(i) / steps)
		_travel(Vector2(x, ground - 2), Vector2(x, ground - 6), 0.25, "dust", 0.0)
		if i % 2 == 0:
			_shake(1.5)
		await _wait(0.04)
	_hit(to)
	_impact_star(to, 1.0)
	_burst(Vector2(to.x, ground - 3), 4, 9.0, "rock" if mtype in ["ground", "rock"] else "dust")


func _wave() -> void:
	var x0 := from.x
	var steps := maxi(4, int(absf(to.x - x0) / 6.0))
	for i in steps + 1:
		var x := lerpf(x0, to.x, float(i) / steps)
		var crest := Vector2(x, ground - 10.0 - 3.0 * sin(float(i) * 0.9))
		# lomo de la ola: medio círculo de arriba (en Godot, de PI a TAU)
		_stroke({"kind": "arc", "a": Vector2(x, ground), "r": 10.0, "a0": PI, "a1": TAU, "color": c_dark, "life": 0.3, "width": 3.0})
		_stroke({"kind": "arc", "a": Vector2(x, ground), "r": 9.0, "a0": PI, "a1": TAU, "color": c_mid, "life": 0.3, "width": 2.0})
		_stroke({"kind": "arc", "a": Vector2(x, ground - 1.0), "r": 10.0, "a0": PI * 1.2, "a1": PI * 1.8, "color": c_hi, "life": 0.3, "width": 1.0})
		_travel(crest, crest + Vector2(face * 5.0, -5.0), 0.3)
		await _wait(0.03)
	_hit(to)
	_impact_star(to, 1.0)
	_burst(to, 5, 10.0)
	_shake(1.0)


func _wind() -> void:
	var n := _n(6)
	var dur := clampf(from.distance_to(to) / 140.0, 0.2, 0.45)
	for i in n:
		var s := _part(from, "swirl" if i % 2 == 0 else "")
		var ph := randf() * TAU
		var a := from
		var b := to + Vector2(randf_range(-4, 4), randf_range(-5, 5))
		var t := s.create_tween()
		t.tween_method(func(k: float) -> void:
			s.position = (a.lerp(b, k) + Vector2(0, sin(ph + k * TAU * 1.5) * 4.0)).round(), 0.0, 1.0, dur)
		t.tween_property(s, "modulate:a", 0.0, 0.1)
		t.tween_callback(s.queue_free)
		await _wait(0.05)
		if i == 2:
			_hit(to)
	_line(from + Vector2(0, -3), to + Vector2(0, -3), c_hi, 0.2, 1.0, 0.15)
	await _wait(dur * 0.5)
	_burst(to, 3, 8.0)


func _sound() -> void:
	var d := from.distance_to(to)
	var dir := (to - from).normalized() if d > 0.0 else Vector2(face, 0)
	var ang := dir.angle()
	for k in 3:
		_stroke({"kind": "arc", "a": from, "r": 4.0 + k * 3.0, "a0": ang - 0.7, "a1": ang + 0.7, "color": c_hi, "life": 0.2, "width": 1.0})
		var s := _part(from, "note" if String(info["part"]) == "note" else String(info["part"]))
		var t := s.create_tween()
		t.tween_property(s, "position", to + Vector2(0, -4 + k * 4), clampf(d / 160.0, 0.15, 0.4))
		t.tween_property(s, "modulate:a", 0.0, 0.12)
		t.tween_callback(s.queue_free)
		await _wait(0.09)
	_hit(to)
	_ring(to, 3.0, 12.0, c_hi, 0.3)
	_shake(0.5)


func _psychic() -> void:
	var dark := mtype in ["ghost", "dark"]
	for k in 3:
		_ring(to, 16.0 - k * 2.0, 2.0, c_hi if k % 2 == 0 else c_mid, 0.3)
		await _wait(0.07)
	if dark:
		for i in _n(4):
			var ang := TAU * i / 4.0
			_travel(to + Vector2(cos(ang), sin(ang)) * 12.0, to, 0.25, "wisp" if mtype == "ghost" else "crescent")
		await _wait(0.2)
	_hit(to)
	_impact_star(to, 1.0)
	_burst(to, 4, 9.0)
	_shake(0.5)


func _drain() -> void:
	_hit(to)
	_burst(to, 3, 7.0)
	await _wait(0.12)
	var back := body_center(src)
	for i in _n(5):
		_travel(to + Vector2(randf_range(-4, 4), randf_range(-4, 4)), back + Vector2(randf_range(-3, 3), randf_range(-4, 2)), 0.4, "orb_m" if i % 2 == 0 else "orb_s", randf_range(4, 10))
		await _wait(0.06)
	await _wait(0.3)
	_ring(back, 3.0, 10.0, c_hi, 0.3)
	_burst(back, 3, 7.0, "orb_s")


func _explosion() -> void:
	var c := body_center(src)
	_ring(c, 2.0, 26.0 * (0.6 if small else 1.0), c_hi, 0.35)
	_ring(c, 2.0, 18.0 * (0.6 if small else 1.0), c_mid, 0.35)
	_burst(c, 12, 22.0, "", 0.45)
	_burst(c, 6, 14.0, "dust", 0.45)
	_shake(3.0)
	_hit(to)
	await _wait(0.1)
	_impact_star(to, 1.3)


## Se hunde (Excavar, Buceo, Golpe Fantasma) y sale bajo el objetivo.
func _vanish() -> void:
	var spr := src.sprite
	var t := spr.create_tween()
	t.tween_property(spr, "modulate:a", 0.0, 0.15)
	_burst(Vector2(src.position.x, src.position.y - 2), 3, 7.0, "dust" if mtype != "ghost" else "wisp")
	await _wait(0.3)
	_rise_at(to.x)
	_hit(to)
	_impact_star(to, 1.1)
	_shake(1.0)
	await _wait(0.15)
	var t2 := spr.create_tween()
	t2.tween_property(spr, "modulate:a", 1.0, 0.15)


func _rise_at(x: float) -> void:
	for i in 3:
		_travel(Vector2(x + (i - 1) * 5.0, ground), Vector2(x + (i - 1) * 7.0, ground - 10.0), 0.25, "dust" if mtype != "ghost" else "wisp")


## Sube fuera de la vista (Vuelo, Bote) y cae en picada sobre el objetivo.
func _dive_bomb() -> void:
	var spr := src.sprite
	var base := spr.position
	var t := spr.create_tween()
	t.tween_property(spr, "position:y", base.y - 30.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(spr, "modulate:a", 0.0, 0.18)
	await _wait(0.22)
	var top := Vector2(to.x - face * 14.0, maxf(2.0, to.y - 40.0))
	_line(top, to, c_hi, 0.22, 1.0, 0.12)
	_travel(top, to, 0.12, String(info["part"]))
	await _wait(0.12)
	_hit(to)
	_impact_star(to, 1.2)
	_burst(to, 4, 9.0)
	_shake(1.5)
	await _wait(0.15)
	var t2 := spr.create_tween()
	t2.tween_property(spr, "position:y", base.y, 0.01)
	t2.tween_property(spr, "modulate:a", 1.0, 0.15)


# ------------------------------------------------------------------ estado (casa, futuros)

func _aura(heal: bool) -> void:
	var c := body_center(src)
	_ring(c, 3.0, 12.0, c_hi, 0.35)
	for i in _n(6):
		var p := c + Vector2(randf_range(-8, 8), randf_range(2, 8))
		var part := "orb_s" if heal else ""
		_travel(p, p + Vector2(0, -12), 0.5, part)
		await _wait(0.06)
	if heal:
		var sp := _part(c + Vector2(0, -6), "star", "grass")
		var tt := sp.create_tween()
		tt.tween_property(sp, "position:y", sp.position.y - 6, 0.4)
		tt.tween_property(sp, "modulate:a", 0.0, 0.1)
		tt.tween_callback(sp.queue_free)
	_hit(c)


func _status() -> void:
	_travel(from, to, 0.2, String(info["part"]))
	await _wait(0.2)
	_hit(to)
	_ring(to, 2.0, 10.0, c_mid, 0.3)
	_burst(to, 4, 8.0)


func _shield() -> void:
	var bb: Array = src.meta["anims"][src.resolve("Idle")]["bbox"]
	var r := Rect2(src.position + Vector2(float(bb[0]) - 3.0, float(bb[1]) - 3.0), Vector2(float(bb[2]) + 6.0, float(bb[3]) + 4.0))
	_stroke({"kind": "rect", "rect": r.grow(-0.0), "color": c_hi, "life": 0.5})
	_stroke({"kind": "rect", "rect": r.grow(1.0), "color": c_mid, "life": 0.5})
	_burst(body_center(src), 4, 10.0, "orb_s")
	await _wait(0.2)
	_hit(to)


func _field() -> void:
	var span := 40.0 if small else 90.0
	for i in _n(10):
		var x := src.position.x + randf_range(-span, span)
		_travel(Vector2(x, maxf(2.0, src.position.y - 50.0)), Vector2(x - 6.0, src.position.y - 2.0), 0.6)
		await _wait(0.05)
	_hit(to)
