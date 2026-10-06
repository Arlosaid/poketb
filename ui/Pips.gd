class_name Pips
extends Control
## Fila de cuadritos (llenos / vacíos) para niveles: dosis de vitaminas, maestría, etc.

const PIP := 3
const GAP := 1

var total := 5
var filled := 0
var color := Palette.AMBER


func _init(n_total: int, n_filled: int, c: Color) -> void:
	total = n_total
	filled = n_filled
	color = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(total * (PIP + GAP) - GAP, PIP + 2)


func _draw() -> void:
	for i in total:
		var r := Rect2(i * (PIP + GAP), 1, PIP, PIP)
		draw_rect(r, color if i < filled else Palette.TAN)
