class_name Fx
extends RefCounted
## Efectos pequeños y sutiles ("juice"). Todos se auto-destruyen.
## `parent` es un Node2D en las mismas coordenadas que los actores.

const HEART := preload("res://assets/ui/heart.png")
const Z_SMALL := preload("res://assets/ui/z_small.png")
const Z_BIG := preload("res://assets/ui/z_big.png")
const DUST := preload("res://assets/ui/dust.png")
const SPARKLE := preload("res://assets/ui/sparkle.png")


static func _sprite(parent: Node, tex: Texture2D, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.z_index = 10
	parent.add_child(s)
	return s


## Corazones que suben al acariciar.
static func hearts(parent: Node, pos: Vector2, count := 3) -> void:
	for i in count:
		var s := _sprite(parent, HEART, pos + Vector2((i - (count - 1) / 2.0) * 7.0, 0))
		s.modulate.a = 0.0
		var t := s.create_tween()
		t.tween_interval(i * 0.12)
		t.tween_property(s, "modulate:a", 1.0, 0.1)
		t.parallel().tween_property(s, "position", s.position + Vector2(randf_range(-2, 2), -8), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(s, "modulate:a", 0.0, 0.25)
		t.tween_callback(s.queue_free)


## Una "z" que sube y crece (llamar periódicamente mientras duerme).
static func zzz(parent: Node, pos: Vector2) -> void:
	var s := _sprite(parent, Z_SMALL, pos)
	s.modulate.a = 0.0
	var t := s.create_tween()
	t.tween_property(s, "modulate:a", 1.0, 0.2)
	t.parallel().tween_property(s, "position", pos + Vector2(3, -6), 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void: s.texture = Z_BIG)
	t.tween_property(s, "position", pos + Vector2(6, -12), 0.8).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(s, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.tween_callback(s.queue_free)


## Polvo al aterrizar.
static func dust(parent: Node, pos: Vector2) -> void:
	var s := _sprite(parent, DUST, pos + Vector2(0, -1))
	s.hframes = 3
	s.z_index = 0
	var t := s.create_tween()
	for f in 3:
		t.tween_callback(func() -> void: s.frame = f)
		t.tween_interval(0.09)
	t.tween_callback(s.queue_free)


## Ícono de ánimo (enojo, sudor) que asoma un momento sobre la cabeza.
static func pop_icon(parent: Node, pos: Vector2, tex: Texture2D, hold := 1.2) -> void:
	var s := _sprite(parent, tex, pos + Vector2(0, 2))
	s.modulate.a = 0.0
	var t := s.create_tween()
	t.tween_property(s, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(s, "position", pos, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(hold)
	t.tween_property(s, "modulate:a", 0.0, 0.25)
	t.tween_callback(s.queue_free)


## Destellos (subida de nivel, evolución, captura).
static func sparkles(parent: Node, pos: Vector2, radius := 10.0, count := 5) -> void:
	for i in count:
		var a := TAU * i / count + randf() * 0.4
		var s := _sprite(parent, SPARKLE, pos)
		s.modulate.a = 0.0
		var t := s.create_tween()
		t.tween_interval(i * 0.05)
		t.tween_property(s, "modulate:a", 1.0, 0.08)
		t.parallel().tween_property(s, "position", pos + Vector2(cos(a), sin(a)) * radius, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(s, "modulate:a", 0.0, 0.2)
		t.tween_callback(s.queue_free)


## Texto flotante (números de daño, "+EXP"): sube 6 px con easing y se desvanece.
static func float_text(parent: Node, pos: Vector2, text: String, color: Color, outline: Color = Palette.INK) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.font())
	l.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	# sombra dura de 1 px (un contorno en fuente pixel se ve sucio)
	l.add_theme_color_override("font_shadow_color", outline)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.z_index = 20
	parent.add_child(l)
	l.reset_size()
	l.position = (pos - Vector2(l.size.x / 2.0, l.size.y)).round()
	var t := l.create_tween()
	t.tween_property(l, "position:y", l.position.y - 6.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.35)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)
