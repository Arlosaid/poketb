extends Node2D
## Escena raíz. Arma los sistemas y conecta las señales entre ellos.

var desk: DesktopWindow
var tray: Tray
var world: Node2D
var home: HomeArea
var hud: Control
var battle_win: BattleWindow
var battle: BattleStrip
var combat: BattleController
var saver: SaveManager
var pc: PCWindow
## Poké Ball en la casa que abre la PC (también hay una en el panel de pelea).
var pc_button: PCButton

var _battle_placed := false
var _needs_timer := 0.0


func _ready() -> void:
	desk = DesktopWindow.new()
	desk.name = "DesktopWindow"
	add_child(desk)
	tray = Tray.new()
	tray.name = "Tray"
	add_child(tray)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	hud = Control.new()
	hud.name = "Hud"
	hud.theme = UiTheme.theme()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	pc_button = PCButton.new()
	pc_button.name = "PCButton"
	hud.add_child(pc_button)
	pc_button.pressed.connect(_open_pc)
	# La pelea vive en su propia ventana, que se arrastra a cualquier parte.
	battle_win = BattleWindow.new(desk.scale)
	battle_win.name = "BattleWindow"
	add_child(battle_win)
	battle = battle_win.strip
	battle.desk = desk
	battle.dropped.connect(_on_battle_dropped)
	desk.extra_windows.append(battle_win)
	Game.battle_window = battle_win
	combat = BattleController.new()
	combat.name = "BattleController"
	add_child(combat)
	combat.setup(battle, desk)
	saver = SaveManager.new()
	saver.name = "SaveManager"
	saver.battle_window = battle_win
	add_child(saver)
	saver.setup(combat)
	home = HomeArea.new()
	home.name = "Home"
	home.setup(desk, hud)
	world.add_child(home)

	desk.fullscreen_app_changed.connect(_on_fullscreen_app)
	Game.pets_hidden_changed.connect(func(_h: bool) -> void: _update_pet_visibility())
	desk.geometry_changed.connect(_on_geometry)
	Game.mode_changed.connect(_on_mode_changed)
	Game.roster.changed.connect(_sync_home)
	home.pc_requested.connect(_open_pc)
	combat.pc_button.pressed.connect(_open_pc)
	tray.open_pc_requested.connect(_open_pc)
	tray.debug_action.connect(_on_debug)
	tray.credits_requested.connect(func() -> void: _open_pc("creditos"))
	Game.roster.changed.connect(_on_roster_changed)
	combat.fighters_changed.connect(_sync_home)

	Game.roster.new_game()
	var away := saver.load_game()
	battle_win.place(saver.saved_battle_pos)
	_battle_placed = true
	_on_geometry(desk.logical_size)
	if away >= 120.0:
		_offline(away)

	if Game.scenario != "":
		var sc := Scenarios.new()
		sc.name = "Scenarios"
		add_child(sc)
		sc.run(self, Game.scenario)


func _process(_delta: float) -> void:
	# Necesidades: se aplican cada 0.5 s con el tiempo de juego acumulado.
	_needs_timer += Game.dt
	if _needs_timer >= 0.5:
		Game.roster.tick(_needs_timer, fighting_uids(), home.sleeping_uids())
		_needs_timer = 0.0


func _on_geometry(logical: Vector2i) -> void:
	hud.size = logical
	pc_button.position = Vector2(4, desk.ground_y() - PCButton.SIZE.y + 1).round()
	battle_win.rescale(desk.scale)
	if _battle_placed:
		battle_win.place(battle_win.position)
	combat.relayout()
	_apply_mode(false)


## Pokémon que están peleando ahora (los decide BattleController).
func fighting_uids() -> Array:
	return combat.fighting_uids()


func _sync_home() -> void:
	var fighting := fighting_uids()
	var uids := []
	for p in Game.roster.team_members():
		if p.uid not in fighting:
			uids.append(p.uid)
	var c := Game.roster.companion
	# El compañero siempre está visible: si no pelea, pasea por casa.
	if c != 0 and c not in fighting and c not in uids:
		uids.append(c)
	# Los que vuelven de pelear entran caminando desde el lado del panel.
	home.sync(uids, c, _panel_entry_x() if Game.mode == Game.MODE_BATTLE else -1.0)


func _on_mode_changed(_m: StringName) -> void:
	_apply_mode(true)


## Modo pelea: la ventana del panel se ve. Modo descanso: se oculta y las mascotas
## ocupan todo el ancho de la barra. La casa siempre usa todo el ancho.
func _apply_mode(_animate: bool) -> void:
	_update_battle_visibility()
	home.set_bounds(26.0, float(desk.logical_size.x - 10), desk.ground_y())
	_sync_home()


func _update_battle_visibility() -> void:
	var show := Game.mode == Game.MODE_BATTLE and not desk.fullscreen_app
	if battle_win.visible != show:
		battle_win.visible = show


## X (en la franja de casa) por donde entran caminando los que vuelven de pelear:
## la del panel, o el borde más cercano si el panel está fuera de esta pantalla.
func _panel_entry_x() -> float:
	var cx := battle_win.position.x + battle_win.size.x / 2.0 - get_tree().root.position.x
	return clampf(cx / desk.scale, home.x_min, home.x_max)


func _on_battle_dropped() -> void:
	saver.save()


func _on_debug(id: int) -> void:
	match id:
		Tray.DBG_LEVELS:
			combat.debug_levels(5)
		Tray.DBG_EVOLVE:
			combat.debug_evolve()
		Tray.DBG_BOSS:
			combat.debug_force_boss()
		Tray.DBG_SHOT:
			Game.shot("debug_%d" % Time.get_unix_time_from_system())
		Tray.DBG_NIGHT:
			battle.backdrop.refresh()


func _open_pc(tab := "pokemon") -> void:
	if is_instance_valid(pc):
		pc.show_tab(tab)
		pc.grab_focus()
		return
	pc = PCWindow.new(desk.scale)
	add_child(pc)
	# encima de la franja, centrada sobre la casa
	var win := get_tree().root
	if battle_win.visible:
		var bx := battle_win.position.x + battle_win.size.x / 2 - pc.size.x / 2
		pc.position = Vector2i(maxi(8, bx), maxi(8, battle_win.position.y - pc.size.y - 4))
	else:
		pc.position = Vector2i(win.position.x + (win.size.x - pc.size.x) / 2, win.position.y - pc.size.y - 4)
	pc.show_tab(tab)


func _on_roster_changed() -> void:
	# Cambios hechos en la PC: el equipo en ruta se actualiza al momento.
	if combat.state == BattleController.State.WALK:
		combat._rebuild_fighters()
		combat._formation(true)


## Progreso mientras el juego estuvo cerrado (tope 8 h) y su resumen.
func _offline(seconds: float) -> void:
	var s := OfflineSim.run(seconds, Game.mode == Game.MODE_BATTLE, combat)
	combat.relayout()
	await get_tree().create_timer(1.5).timeout
	var c := Game.roster.companion_member()
	OfflineSummary.show_in(hud, s, c.species if c else "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not saver.skip_quit_save:
		saver.save()


func _on_fullscreen_app(_active: bool) -> void:
	_update_pet_visibility()
	_update_battle_visibility()


## Las mascotas se esconden con una app a pantalla completa o con "Esconder mascotas".
func _update_pet_visibility() -> void:
	var hidden := desk.fullscreen_app or Game.pets_hidden()
	world.visible = not hidden
	hud.visible = not hidden
	home.set_hidden(hidden)
