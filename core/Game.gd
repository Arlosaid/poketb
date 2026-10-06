extends Node
## Autoload global: reloj, modo de juego, argumentos de línea de comandos y
## acceso a la extensión nativa. Los sistemas grandes viven en la escena Main.

signal mode_changed(mode: StringName)
signal pause_changed(paused: bool)

const MODE_BATTLE := &"battle"
const MODE_REST := &"rest"

var clock := GameClock.new()
var roster := Roster.new()
var mode: StringName = MODE_BATTLE
var debug := false
## Escenario automatizado para validar (pet, battle, gallery...). Vacío = juego normal.
var scenario := ""
## Singleton DesktopNative (GDExtension) o null si no está disponible.
var native: Object = null
## Delta de juego de este frame (0 en pausa, x10 en debug). Usarlo en vez del delta real.
var dt := 0.0
## Si es > 0, el juego se cierra solo tras estos segundos (para pruebas automáticas).
var autoquit := 0.0
## Si es >= 0, sustituye a la inactividad real del sistema (escenarios y depuración).
var forced_idle := -1.0
## Ventana del panel de pelea (para incluirla en las capturas de revisión).
var battle_window: Window = null


func _enter_tree() -> void:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	debug = OS.is_debug_build() and ("--debug" in args)
	for i in args.size():
		if args[i] == "--scenario" and i + 1 < args.size():
			scenario = args[i + 1]
		elif args[i].begins_with("--scenario="):
			scenario = args[i].get_slice("=", 1)
		elif args[i].begins_with("--autoquit="):
			autoquit = float(args[i].get_slice("=", 1))
	if Engine.has_singleton("DesktopNative"):
		native = Engine.get_singleton("DesktopNative")
	else:
		push_warning("DesktopNative no está cargado: no habrá clic a través ni ocultar de la barra de tareas.")


func _process(delta: float) -> void:
	dt = clock.step(delta)
	if autoquit > 0.0:
		autoquit -= delta
		if autoquit <= 0.0:
			quit()


## Segundos sin tocar teclado ni mouse en todo el sistema (GetLastInputInfo).
func user_idle_seconds() -> float:
	if forced_idle >= 0.0:
		return forced_idle
	return native.get_idle_seconds() if native else 0.0


func set_mode(m: StringName) -> void:
	if m == mode:
		return
	mode = m
	mode_changed.emit(m)


func toggle_pause() -> void:
	clock.paused = not clock.paused
	pause_changed.emit(clock.paused)


## Guarda una captura del viewport (fondo transparente) en res://shots/ para revisarla.
## No captura el escritorio: así nunca se guardan las ventanas privadas del usuario.
func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://shots/")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + shot_name + ".png")
	print("[shot] ", dir + shot_name + ".png")
	# La pelea vive en su propia ventana: va en un archivo aparte (<nombre>_battle.png).
	if is_instance_valid(battle_window) and battle_window.visible:
		battle_window.get_texture().get_image().save_png(dir + shot_name + "_battle.png")


## Captura de una ventana secundaria (por ejemplo, la PC).
func shot_window(win: Window, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := win.get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://shots/")
	img.save_png(dir + shot_name + ".png")
	print("[shot] ", dir + shot_name + ".png")


func quit() -> void:
	# El guardado se engancha a esta notificación (SaveManager, fase 5).
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()
