class_name BattleStrip
extends Control
## Panel de pelea anclado a la derecha de la franja: marco de madera, fondo con
## parallax y los Pokémon que pelean. El panel en sí NO bloquea el mouse: solo los
## Pokémon y los botones registrados en Passthrough son clicables.

const FRAME := 4          # grosor del marco (px lógicos)
const SHADOW := 1

var frame: NinePatchRect
var inner: Control
var backdrop: Backdrop
## Contenedor de actores (coordenadas del área interior).
var stage: Node2D
var px_scale := 2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner = Control.new()
	inner.name = "Inner"
	inner.clip_contents = true
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
	frame = NinePatchRect.new()
	frame.name = "Frame"
	frame.texture = load("res://assets/ui/battle_frame.png")
	frame.patch_margin_left = FRAME
	frame.patch_margin_top = FRAME
	frame.patch_margin_right = FRAME + SHADOW
	frame.patch_margin_bottom = FRAME + SHADOW
	frame.draw_center = false
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)


## Coloca el panel (en px lógicos del viewport) y reconstruye el fondo.
func layout(rect: Rect2i, biome_id: String, scale_px: int) -> void:
	px_scale = scale_px
	position = rect.position
	size = rect.size
	frame.size = rect.size
	inner.position = Vector2(FRAME, FRAME)
	inner.size = Vector2(rect.size) - Vector2(FRAME * 2 + SHADOW, FRAME * 2 + SHADOW)
	backdrop.setup(biome_id, Vector2i(inner.size), px_scale)


func ground_y() -> float:
	return backdrop.ground_y()
