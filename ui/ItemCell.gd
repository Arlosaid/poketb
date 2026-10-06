class_name ItemCell
extends Control
## Casilla de objeto: ícono 12x12 en un marco del color de su nivel (Común, Poco común, Raro,
## Épico) y la cantidad abajo a la derecha. Vacía si no tiene llave.

signal pressed

const SIZE := 20

var key := ""
var count := 0
var selected := false:
	set(v):
		selected = v
		queue_redraw()


func _init(item_key := "", n := 0) -> void:
	key = item_key
	count = n
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if key != "":
		tooltip_text = "%s (%s)\n%s" % [Progression.item_name(key), Progression.tier_name(Progression.key_tier(key)), Progression.item_summary(key)]


func _draw() -> void:
	var col := Palette.TAN if key == "" else Progression.tier_color(Progression.key_tier(key))
	draw_rect(Rect2(0, 0, SIZE, SIZE), col)
	draw_rect(Rect2(1, 1, SIZE - 2, SIZE - 2), Palette.PAPER if key == "" else Palette.CREAM)
	if key != "":
		draw_texture(Progression.item_icon(Progression.key_id(key)), Vector2(4, 4))
		if count > 1:
			var f := UiTheme.font()
			var t := "%d" % count
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE).x
			var pos := Vector2(SIZE - w - 1, SIZE - 2)
			draw_string(f, pos + Vector2(1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE, Palette.INK)
			draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE, Palette.PAPER)
	if selected:
		for r in [Rect2(0, 0, SIZE, 1), Rect2(0, SIZE - 1, SIZE, 1), Rect2(0, 0, 1, SIZE), Rect2(SIZE - 1, 0, 1, SIZE)]:
			draw_rect(r, Palette.FLAME)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
