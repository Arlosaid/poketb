class_name DesktopWindow
extends Node
## Coloca la ventana principal como una franja justo encima de la barra de tareas,
## con el ancho de la pantalla y escala entera. Por defecto queda por delante de las
## demás ventanas (opción "Siempre al frente" de la bandeja); como las zonas vacías
## dejan pasar el mouse y se esconde con apps a pantalla completa, no estorba.
## También gestiona los FPS para gastar poco.

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
## Otras ventanas del juego (propiedad de la principal): sin botón propio en la barra.
var extra_windows: Array[Window] = []

var _last_geom := Rect2i()
var _active_until := 0.0
var _ambient_until := 0.0
var _maint_timer := 0.0


func _ready() -> void:
	var win := get_tree().root
	win.title = "Taskbar Pokémon"
	win.transparent_bg = true
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	_relayout(true)
	Game.settings_changed.connect(_apply_topmost)
	_apply_topmost()
	# Al volver al juego (botón de la barra de tareas, Alt-Tab), el panel sube con él.
	win.focus_entered.connect(raise_extra_windows)
	_maintain()


## Mascotas siempre al frente (opción). Godot no deja usar always_on_top en las
## ventanas transitorias (pelea), así que esas se suben a mano con raise_extra_windows.
func _apply_topmost() -> void:
	var on: bool = Game.settings.get("topmost", true)
	var win := get_tree().root
	if win.always_on_top != on:
		win.always_on_top = on
		if not on:
			# Quitar el "siempre al frente" del panel: al recrear su ventana nativa
			# (ocultar y mostrar) vuelve a ser una ventana normal propiedad de la principal.
			for w in extra_windows:
				if is_instance_valid(w) and w.visible:
					w.hide()
					w.show()
	raise_extra_windows()


## Sube las otras ventanas visibles del juego (panel de pelea) por delante de las demás
## apps, sin robar el foco. Una ventana propiedad de una topmost NO es topmost por sí
## sola: al crearla (cada vez que se muestra) queda en la capa normal y cualquier app
## la tapa, y el botón de la barra no la recupera. Por eso se reafirma como la principal.
func raise_extra_windows() -> void:
	var native: Object = Game.native
	if native == null or fullscreen_app or not Game.settings.get("topmost", true):
		return
	for w in extra_windows:
		if is_instance_valid(w) and w.visible:
			native.reassert_topmost(w.get_window_id())


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
	# Nadie mirando (pantalla completa, mascotas escondidas o 5 min sin tocar la PC):
	# lo mínimo, aunque haya un combate (como ya pasaba con pantalla completa).
	if fullscreen_app or Game.pets_hidden() or Game.user_idle_seconds() >= PetBrain.USER_IDLE_SLEEP:
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


## Mantenimiento periódico (barato): geometría, botón de la barra de tareas, pantalla completa.
func _maintain() -> void:
	_relayout(false)
	var native: Object = Game.native
	if native == null:
		return
	# Clic sin activar (no roba el foco), pero el botón de la barra la trae al frente.
	if native.has_method("no_activate_on_click"):
		native.no_activate_on_click(get_tree().root.get_window_id())
	# Otra app "siempre al frente" puede taparnos: lo reafirmamos sin robar el foco.
	if Game.settings.get("topmost", true) and not fullscreen_app:
		native.reassert_topmost(get_tree().root.get_window_id())
	raise_extra_windows()
	for w in extra_windows:
		if is_instance_valid(w) and w.visible:
			native.hide_from_taskbar(w.get_window_id())
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