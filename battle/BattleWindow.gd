class_name BattleWindow
extends Window
## Ventana propia del panel de pelea: pequeña, transparente, sin bordes, sin botón
## propio en la barra y sin robar el foco. Se arrastra desde el camino a cualquier punto de
## cualquier pantalla (ver BattleStrip). Contiene la escena y el cuadro de diálogo.

## Tamaño lógico (px antes de escalar).
const LOGICAL := Vector2i(216, 96)

var strip: BattleStrip
var px_scale := 2


func _init(scale_px: int) -> void:
	px_scale = scale_px
	title = "Taskbar Pokémon - pelea"
	borderless = true
	transparent = true
	transparent_bg = true
	unresizable = true
	unfocusable = true
	wrap_controls = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	content_scale_size = LOGICAL
	size = LOGICAL * px_scale
	theme = UiTheme.theme()
	strip = BattleStrip.new()
	strip.name = "BattleStrip"
	add_child(strip)


func _ready() -> void:
	transient = true  # propiedad de la principal: sin botón propio y sube con ella
	strip.layout(LOGICAL, "pradera", px_scale)


## Posición por defecto: abajo a la derecha, sobre la barra de tareas.
func default_position() -> Vector2i:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	return Vector2i(usable.end.x - size.x - 24, usable.end.y - size.y)


## Coloca la ventana en `pos` si todavía cae dentro de alguna pantalla; si no, en la
## posición por defecto (por ejemplo, si se desconectó el monitor donde estaba).
func place(pos: Variant) -> void:
	if pos is Vector2i:
		var center: Vector2i = pos + size / 2
		for s in DisplayServer.get_screen_count():
			var r := Rect2i(DisplayServer.screen_get_position(s), DisplayServer.screen_get_size(s))
			if r.has_point(center):
				position = pos
				return
	position = default_position()


## Cambia la escala entera (si cambió la resolución) conservando el centro de la ventana.
func rescale(scale_px: int) -> void:
	if scale_px == px_scale:
		return
	var center := position + size / 2
	px_scale = scale_px
	strip.px_scale = scale_px
	size = LOGICAL * px_scale
	position = center - size / 2
	strip.layout(LOGICAL, strip.backdrop.biome.get("id", "pradera"), px_scale)
