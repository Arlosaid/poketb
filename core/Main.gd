extends Node2D
## Escena raíz. Arma los sistemas y conecta las señales entre ellos.
## (Fase 1: ventana, bandeja y un Charmander paseando).

var desk: DesktopWindow
var tray: Tray
var world: Node2D
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
	desk.fullscreen_app_changed.connect(_on_fullscreen_app)

	walker = PokemonActor.new()
	walker.species = "charmander"
	world.add_child(walker)
	walker.position = Vector2(120, desk.ground_y())
	walker.clicked.connect(_on_actor_clicked)
	_pick_target()
	if Game.scenario == "still":
		# Validación del clic a través: Charmander quieto en x lógica 100.
		walker.position.x = 100
		walker.play_anim("Idle", "S")
		_wait = 1e9
		await get_tree().create_timer(2.0).timeout
		Game.shot("p1_still")


func _process(_delta: float) -> void:
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
	Passthrough.disabled = false
