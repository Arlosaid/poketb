class_name HpBar
extends Control
## Barra pixel art (PS o EXP): borde INK, fondo BARK y relleno según la fracción.
## El valor mostrado se anima hacia el real con easing.

var frac := 1.0:
	set(v):
		frac = clampf(v, 0.0, 1.0)
		_animate()
var exp_style := false
var shown := 1.0
var _tween: Tween


func _init(w := 28, h := 4, is_exp := false) -> void:
	custom_minimum_size = Vector2(w, h)
	size = custom_minimum_size
	exp_style = is_exp
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_instant(v: float) -> void:
	frac = v
	if _tween:
		_tween.kill()
	shown = frac
	queue_redraw()


func _animate() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(v: float) -> void:
		shown = v
		queue_redraw(), shown, frac, 0.35)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Palette.INK)
	var inner := r.grow(-1)
	draw_rect(inner, Palette.BARK)
	var w := int(round(inner.size.x * shown))
	if w > 0:
		var c := Palette.SKY if exp_style else Palette.hp_color(shown)
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), c)
		# brillo de 1 px arriba
		if inner.size.y >= 2:
			draw_rect(Rect2(inner.position, Vector2(w, 1)), Palette.HAZE if exp_style else _hi(c))


func _hi(c: Color) -> Color:
	if c == Palette.MINT:
		return Palette.PAPER
	if c == Palette.AMBER:
		return Palette.HONEY
	return Palette.FLAME
