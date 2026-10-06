extends Node2D
## Escena raíz. Arma los sistemas y conecta las señales entre ellos.

## Fracción del ancho lógico que ocupa el panel de pelea (a la derecha).
const BATTLE_WIDTH_FRAC := 0.40
const BATTLE_HEIGHT := 64

var desk: DesktopWindow
var tray: Tray
var world: Node2D
var hud: Control
var battle: BattleStrip
var walker: PokemonActor

var _walk_target := 0.0
var _wait := 0.0


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

	desk.fullscreen_app_changed.connect(_on_fullscreen_app)
	desk.geometry_changed.connect(_on_geometry)
	_on_geometry(desk.logical_size)

	if Game.scenario != "":
		var sc := Scenarios.new()
		sc.name = "Scenarios"
		add_child(sc)
		sc.run(self, Game.scenario)
		return

	walker = PokemonActor.new()
	walker.species = "charmander"
	world.add_child(walker)
	walker.position = Vector2(120, desk.ground_y())
	walker.clicked.connect(_on_actor_clicked)
	_pick_target()


func _on_geometry(logical: Vector2i) -> void:
	hud.size = logical
	var w := int(round(logical.x * BATTLE_WIDTH_FRAC))
	var rect := Rect2i(logical.x - w - 2, logical.y - BATTLE_HEIGHT, w, BATTLE_HEIGHT)
	battle.layout(rect, "pradera", desk.scale)


func _process(_delta: float) -> void:
	if walker == null:
		return
	var d := Game.dt
	if _wait > 0.0:
		_wait -= d
		if _wait <= 0.0:
			_pick_target()
		return
	var dx := _walk_target - walker.position.x
	var speed := 22.0
	if absf(dx) < 1.0:
		walker.play_anim("Idle")
		_wait = randf_range(1.5, 4.0)
		return
	walker.play_anim("Walk", "E" if dx > 0.0 else "W")
	walker.position.x += signf(dx) * minf(absf(dx), speed * d)
	walker.position = walker.position.round()
	desk.keep_awake()


func _pick_target() -> void:
	_walk_target = randf_range(40.0, desk.logical_size.x * 0.5)


func _on_actor_clicked(actor: PokemonActor, button: int) -> void:
	print("[Main] clic en ", actor.species, " botón ", button)
	actor.play_anim("Joy", "S", true)
	_wait = actor.anim_length("Joy") + 0.4
	desk.keep_awake()


func _on_fullscreen_app(active: bool) -> void:
	world.visible = not active
	hud.visible = not active
