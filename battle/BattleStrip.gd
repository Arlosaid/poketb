class_name BattleStrip
extends Control
## Escena de pelea dentro de su ventana propia (BattleWindow): sin marco ni cielo,
## solo el camino con algo de decorado y los Pokémon que pelean. Solo el camino
## (para arrastrar la ventana) y los Pokémon son clicables; el resto deja pasar el mouse.

## Se emite al soltar la ventana tras arrastrarla.
signal dropped

## Alto (px lógicos) de la franja de camino que sirve de asa de arrastre.
const GRAB_H := 17.0

var inner: Control
var backdrop: Backdrop
## Contenedor de actores (coordenadas del área interior).
var stage: Node2D
var px_scale := 2
## Mientras se arrastra, la ventana sigue al cursor.
var dragging := false
var desk: DesktopWindow

var _grab := Vector2i.ZERO
var _cursor_set := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner = Control.new()
	inner.name = "Inner"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inner)
	backdrop = Backdrop.new()
	backdrop.name = "Backdrop"
	inner.add_child(backdrop)
	stage = Node2D.new()
	stage.name = "Stage"
	stage.y_sort_enabled = true
	stage.z_index = 1
	inner.add_child(stage)
	Passthrough.register(self)


## Asa de arrastre: la franja del camino (los Pokémon, registrados después, tienen prioridad).
func get_click_rect() -> Rect2:
	return Rect2(0.0, size.y - GRAB_H, size.x, GRAB_H)


func _input(event: InputEvent) -> void:
	var win := get_window()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not dragging and Passthrough.hovered() == self:
			dragging = true
			_grab = DisplayServer.mouse_get_position() - win.position
			Passthrough.capture_count += 1
			get_viewport().set_input_as_handled()
		elif not event.pressed and dragging:
			dragging = false
			Passthrough.capture_count -= 1
			dropped.emit()
	elif event is InputEventMouseMotion and dragging:
		var gp := DisplayServer.mouse_get_position()
		win.position = _clamp_to_screen(gp, gp - _grab, win.size)
		if desk:
			desk.keep_awake()


func _process(_delta: float) -> void:
	# Cursor de mover solo mientras el mouse está sobre el asa.
	var over := dragging or Passthrough.hovered() == self
	if over != _cursor_set:
		_cursor_set = over
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_DRAG if over else DisplayServer.CURSOR_ARROW)


## Mantiene la ventana dentro de la pantalla donde está el cursor (cualquier monitor).
static func _clamp_to_screen(cursor: Vector2i, pos: Vector2i, win_size: Vector2i) -> Vector2i:
	var screen := DisplayServer.get_screen_from_rect(Rect2i(cursor, Vector2i.ONE))
	var r := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	return Vector2i(
		clampi(pos.x, r.position.x, r.end.x - win_size.x),
		clampi(pos.y, r.position.y, r.end.y - win_size.y))


## Dimensiona la escena (px lógicos) y reconstruye el fondo.
func layout(logical: Vector2i, biome_id: String, scale_px: int) -> void:
	px_scale = scale_px
	size = Vector2(logical)
	inner.size = size
	backdrop.setup(biome_id, logical, px_scale)


func ground_y() -> float:
	return backdrop.ground_y()
