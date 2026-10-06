class_name Tray
extends Node
## Ícono en la bandeja del sistema con su menú nativo.

signal open_pc_requested
signal credits_requested
signal debug_action(id: int)

enum { ID_PC, ID_BATTLE, ID_REST, ID_PAUSE, ID_CREDITS, ID_QUIT, ID_HIDE, ID_TOPMOST, ID_FLIGHTS, ID_APPS, ID_WELLBEING }
## Minutos que se esconden las mascotas con "Esconder mascotas".
const HIDE_MINUTES := 30.0
enum { DBG_SPEED, DBG_LEVELS, DBG_EVOLVE, DBG_NIGHT, DBG_BOSS, DBG_SHOT }

var indicator: StatusIndicator
var menu: PopupMenu
var debug_menu: PopupMenu


func _ready() -> void:
	menu = PopupMenu.new()
	menu.name = "TrayMenu"
	menu.prefer_native_menu = true
	add_child(menu)
	menu.add_item("Abrir PC / Equipo", ID_PC)
	menu.add_separator()
	menu.add_radio_check_item("Modo pelea", ID_BATTLE)
	menu.add_radio_check_item("Modo descanso", ID_REST)
	menu.add_check_item("Pausar", ID_PAUSE)
	menu.add_separator()
	menu.add_check_item("Esconder mascotas 30 min", ID_HIDE)
	menu.add_check_item("Siempre al frente", ID_TOPMOST)
	menu.add_check_item("Vuelos por la pantalla", ID_FLIGHTS)
	menu.add_check_item("Reaccionar a mis apps", ID_APPS)
	menu.add_check_item("Recordar pausas", ID_WELLBEING)
	menu.add_separator()
	menu.add_item("Créditos", ID_CREDITS)
	if Game.debug:
		debug_menu = PopupMenu.new()
		debug_menu.name = "DebugMenu"
		debug_menu.prefer_native_menu = true
		menu.add_child(debug_menu)
		debug_menu.add_check_item("Tiempo x10", DBG_SPEED)
		debug_menu.add_item("+5 niveles al equipo", DBG_LEVELS)
		debug_menu.add_item("Forzar evolución", DBG_EVOLVE)
		debug_menu.add_check_item("Forzar noche", DBG_NIGHT)
		debug_menu.add_item("Invocar al jefe", DBG_BOSS)
		debug_menu.add_item("Captura de pantalla", DBG_SHOT)
		debug_menu.id_pressed.connect(_on_debug)
		menu.add_submenu_node_item("Debug", debug_menu)
	menu.add_separator()
	menu.add_item("Salir", ID_QUIT)
	menu.id_pressed.connect(_on_id)

	indicator = StatusIndicator.new()
	indicator.name = "StatusIndicator"
	indicator.icon = load("res://assets/ui/icon.png")
	indicator.tooltip = "Taskbar Pokémon"
	add_child(indicator)
	indicator.menu = indicator.get_path_to(menu)

	Game.mode_changed.connect(func(_m: StringName) -> void: _sync())
	Game.pause_changed.connect(func(_p: bool) -> void: _sync())
	Game.settings_changed.connect(_sync)
	Game.pets_hidden_changed.connect(func(_h: bool) -> void: _sync())
	_sync()


func _sync() -> void:
	menu.set_item_checked(menu.get_item_index(ID_BATTLE), Game.mode == Game.MODE_BATTLE)
	menu.set_item_checked(menu.get_item_index(ID_REST), Game.mode == Game.MODE_REST)
	menu.set_item_checked(menu.get_item_index(ID_PAUSE), Game.clock.paused)
	menu.set_item_checked(menu.get_item_index(ID_HIDE), Game.pets_hidden())
	for pair in [[ID_TOPMOST, "topmost"], [ID_FLIGHTS, "flights"], [ID_APPS, "app_react"], [ID_WELLBEING, "wellbeing"]]:
		menu.set_item_checked(menu.get_item_index(pair[0]), bool(Game.settings.get(pair[1], true)))
	if debug_menu:
		debug_menu.set_item_checked(debug_menu.get_item_index(DBG_SPEED), Game.clock.speed > 1.0)
		debug_menu.set_item_checked(debug_menu.get_item_index(DBG_NIGHT), Game.clock.forced_hour >= 0.0)


func _on_id(id: int) -> void:
	match id:
		ID_PC:
			open_pc_requested.emit()
		ID_BATTLE:
			Game.set_mode(Game.MODE_BATTLE)
		ID_REST:
			Game.set_mode(Game.MODE_REST)
		ID_PAUSE:
			Game.toggle_pause()
		ID_CREDITS:
			credits_requested.emit()
		ID_HIDE:
			Game.hide_pets(0.0 if Game.pets_hidden() else HIDE_MINUTES)
		ID_TOPMOST:
			Game.set_setting("topmost", not Game.settings.get("topmost", true))
		ID_FLIGHTS:
			Game.set_setting("flights", not Game.settings.get("flights", true))
		ID_APPS:
			Game.set_setting("app_react", not Game.settings.get("app_react", true))
		ID_WELLBEING:
			Game.set_setting("wellbeing", not Game.settings.get("wellbeing", true))
		ID_QUIT:
			Game.quit()


func _on_debug(id: int) -> void:
	match id:
		DBG_SPEED:
			Game.clock.speed = 1.0 if Game.clock.speed > 1.0 else 10.0
		DBG_NIGHT:
			Game.clock.forced_hour = -1.0 if Game.clock.forced_hour >= 0.0 else 22.0
	_sync()
	debug_action.emit(id)
