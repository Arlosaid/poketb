extends Node2D
## Escena raíz. Arma los sistemas y conecta las señales entre ellos.

## Fracción del ancho lógico que ocupa el panel de pelea (a la derecha).
const BATTLE_WIDTH_FRAC := 0.40
const BATTLE_HEIGHT := 64
## Margen entre la casa y el panel de pelea.
const HOME_GAP := 10.0

var desk: DesktopWindow
var tray: Tray
var world: Node2D
var home: HomeArea
var hud: Control
var battle: BattleStrip

var _battle_rect := Rect2i()
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
	battle = BattleStrip.new()
	battle.name = "BattleStrip"
	hud.add_child(battle)
	home = HomeArea.new()
	home.name = "Home"
	home.setup(desk, hud)
	world.add_child(home)

	desk.fullscreen_app_changed.connect(_on_fullscreen_app)
	desk.geometry_changed.connect(_on_geometry)
	Game.mode_changed.connect(_on_mode_changed)
	Game.roster.changed.connect(_sync_home)
	home.pc_requested.connect(_open_pc)
	tray.open_pc_requested.connect(_open_pc)

	Game.roster.new_game()
	_on_geometry(desk.logical_size)

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
	var w := int(round(logical.x * BATTLE_WIDTH_FRAC))
	_battle_rect = Rect2i(logical.x - w - 2, logical.y - BATTLE_HEIGHT, w, BATTLE_HEIGHT)
	battle.layout(_battle_rect, "pradera", desk.scale)
	_apply_mode(false)


## Pokémon que están peleando ahora (fase 4: los decide BattleController).
func fighting_uids() -> Array:
	if Game.mode != Game.MODE_BATTLE:
		return []
	var out := []
	for p in Game.roster.team_members():
		if Game.roster.can_fight(p):
			out.append(p.uid)
	return out


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
	home.sync(uids, c)


func _on_mode_changed(_m: StringName) -> void:
	_apply_mode(true)


## Modo pelea: panel visible y casa a su izquierda. Modo descanso: el panel se
## esconde bajando detrás del borde y la casa ocupa todo el ancho.
func _apply_mode(animate: bool) -> void:
	var resting := Game.mode == Game.MODE_REST
	var target_y := float(_battle_rect.position.y + (BATTLE_HEIGHT + 2 if resting else 0))
	if animate:
		var t := battle.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(battle, "position:y", target_y, 0.35)
	else:
		battle.position.y = target_y
	var right := float(desk.logical_size.x - 10) if resting else _battle_rect.position.x - HOME_GAP
	home.set_bounds(10.0, right, desk.ground_y())
	_sync_home()


func _open_pc() -> void:
	print("[Main] abrir PC (fase 5)")


func _on_fullscreen_app(active: bool) -> void:
	world.visible = not active
	hud.visible = not active
