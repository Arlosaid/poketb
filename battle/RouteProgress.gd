class_name RouteProgress
extends Control
## Barrita de avance de la ruta: camino punteado, marca del equipo y Poké Ball del jefe.

const BALL := preload("res://assets/ui/pokeball_8.png")

var frac := 0.0:
	set(v):
		frac = clampf(v, 0.0, 1.0)
		queue_redraw()
var cleared := false:
	set(v):
		cleared = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(64, 8)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# pestaña de madera sobre el borde del marco
	draw_rect(Rect2(-3, -1, size.x + 5, size.y + 2), Palette.INK)
	draw_rect(Rect2(-2, 0, size.x + 3, size.y), Palette.WOOD)
	draw_rect(Rect2(-2, 0, size.x + 3, 1), Palette.OAK)
	var w := size.x - 10.0
	var y := 4.0
	# camino: puntos SAND con borde INK
	draw_rect(Rect2(0, y - 2, w, 4), Palette.INK)
	draw_rect(Rect2(1, y - 1, w - 2, 2), Palette.BARK)
	var filled := int(round((w - 2) * frac))
	if filled > 0:
		draw_rect(Rect2(1, y - 1, filled, 2), Palette.AMBER)
		draw_rect(Rect2(1, y - 1, filled, 1), Palette.HONEY)
	# marca del equipo
	var x := 1.0 + filled
	draw_rect(Rect2(x - 1, y - 2, 3, 5), Palette.INK)
	draw_rect(Rect2(x, y - 1, 1, 3), Palette.FLAME)
	# Poké Ball del jefe al final (se apaga cuando la ruta está despejada)
	draw_texture(BALL, Vector2(w - 1, 0), Color(1, 1, 1, 0.55) if cleared else Color.WHITE)
