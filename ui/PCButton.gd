class_name PCButton
extends Control
## Botón siempre visible para abrir la PC: una Poké Ball sobre el camino. Al pasar el
## cursor da un saltito y muestra "PC". Se registra en Passthrough para ser clicable.

signal pressed

const BALL := preload("res://assets/ui/pokeball_16.png")
const SIZE := Vector2(16, 16)

var _hover := false


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	Passthrough.register(self)


func get_click_rect() -> Rect2:
	return Rect2(get_global_transform().origin, SIZE)


func _process(_delta: float) -> void:
	var h := Passthrough.hovered() == self
	if h != _hover:
		_hover = h
		queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and is_visible_in_tree() and Passthrough.hovered() == self:
		get_viewport().set_input_as_handled()
		pressed.emit()


func _draw() -> void:
	var lift := Vector2(0, -2) if _hover else Vector2.ZERO
	# sombra en el suelo
	draw_rect(Rect2(3, 15, 10, 1), Palette.a(Palette.INK, 0.35))
	draw_texture(BALL, lift)
	if _hover:
		var f := UiTheme.font()
		var t := "PC"
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE).x
		var pos := Vector2(round((SIZE.x - w) / 2.0), -5)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(f, pos + o, t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE, Palette.INK)
		draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE, Palette.PAPER)
