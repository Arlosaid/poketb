class_name DesktopWindow
extends Node
## Coloca la ventana principal como una franja justo encima de la barra de tareas,
## con el ancho de la pantalla y escala entera. También mantiene la ventana fuera de
## la barra de tareas, siempre al frente, y gestiona los FPS para gastar poco.

signal geometry_changed(logical_size: Vector2i)
signal fullscreen_app_changed(active: bool)

## Alto lógico de la franja (px antes de escalar). Deja aire para burbujas y saltos.
const LOGICAL_HEIGHT := 96
const FPS_ACTIVE := 30
## Movimiento tranquilo (paseos, caminata de la ruta): suficiente para 1 px por cuadro.
const FPS_AMBIENT := 20
const FPS_IDLE := 10
const FPS_HIDDEN := 5
## Segundos que se mantienen los FPS altos tras la última petición de actividad.
const ACTIVE_HOLD := 1.0

var scale := 2
var logical_size := Vector2i(960, LOGICAL_HEIGHT)
var fullscreen_app := false

var _last_geom := Rect2i()
var _active_until := 0.0
var _ambient_until := 0.0
var _maint_timer := 0.0


func _ready() -> void:
	var win := get_tree().root
	win.transparent_bg = true
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	_relayout(true)
	_maintain()


## Pide FPS altos durante un momento (combates, interacción, arrastrar).
func keep_awake() -> void:
	_active_until = Time.get_ticks_msec() / 1000.0 + ACTIVE_HOLD


## Pide FPS intermedios (paseos y caminata por la ruta).
func keep_ambient() -> void:
	_ambient_until = Time.get_ticks_msec() / 1000.0 + ACTIVE_HOLD


## Y lógica del suelo: justo encima del borde de la barra de tareas, con 2 px
## de margen para que la sombra (que sobresale bajo los pies) no se corte.
func ground_y() -> float:
	return logical_size.y - 3


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var target := FPS_IDLE
	if fullscreen_app:
		target = FPS_HIDDEN
	elif now < _active_until:
		target = FPS_ACTIVE
	elif now < _ambient_until:
		target = FPS_AMBIENT
	if Engine.max_fps != target:
		Engine.max_fps = target
	_maint_timer -= delta
	if _maint_timer <= 0.0:
		_maint_timer = 2.0
		_maintain()


## Mantenimiento periódico (barato): geometría, barra de tareas, topmost, pantalla completa.
func _maintain() -> void:
	_relayout(false)
	var native: Object = Game.native
	if native == null:
		return
	var wid := get_tree().root.get_window_id()
	native.hide_from_taskbar(wid)
	native.reassert_topmost(wid)
	var fs: bool = native.is_fullscreen_app_active()
	if fs != fullscreen_app:
		fullscreen_app = fs
		fullscreen_app_changed.emit(fs)


func _relayout(force: bool) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var full := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var geom_key := Rect2i(usable.position, usable.size + full.size)
	if not force and geom_key == _last_geom:
		return
	_last_geom = geom_key

	if full.size.y <= 1080:
		scale = 2
	elif full.size.y <= 1600:
		scale = 3
	else:
		scale = 4
	var w_log := full.size.x / scale
	logical_size = Vector2i(w_log, LOGICAL_HEIGHT)
	var size := logical_size * scale
	# El suelo es el borde superior de la barra de tareas (si está abajo); si está
	# en otro borde u oculta automáticamente, usamos el borde inferior del área útil.
	var bottom := usable.end.y
	var pos := Vector2i(full.position.x + (full.size.x - size.x) / 2, bottom - size.y)

	var win := get_tree().root
	win.content_scale_size = logical_size
	win.size = size
	win.position = pos
	geometry_changed.emit(logical_size)
	print("[DesktopWindow] pantalla %s útil %s escala x%d ventana %s en %s" % [full, usable, scale, size, pos])
