class_name WarpWindow
extends Window
## Ventanita transparente para la teletransportación psíquica por la pantalla.
## El Pokémon aparece en 2-4 posiciones aleatorias con efectos de sparkle y desaparece,
## luego vuelve a casa. Mismo patrón que FlightWindow: sin foco, sin icono de barra.

signal finished(landing_screen: Vector2i)

const MIN_LOGICAL := 64
## Duración de las transiciones de fade en segundos.
const FADE_IN := 0.25
const HOLD := 0.65
const FADE_OUT := 0.20
## Pausa entre posiciones mientras el Pokémon "viaja".
const TRAVEL := 0.12

var actor: PokemonActor
var desk: DesktopWindow
var px_scale := 2
var logical := Vector2i(MIN_LOGICAL, MIN_LOGICAL)
var feet := Vector2(32, 52)
var _positions: PackedVector2Array = []
var _return_screen: Vector2 = Vector2.ZERO
var _alive := true


func _init(scale_px: int) -> void:
	px_scale = scale_px
	title = "Taskbar Pokémon - teletransporte"
	borderless = true
	transparent = true
	transparent_bg = true
	unresizable = true
	unfocusable = true
	wrap_controls = false
	visible = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	_resize(logical)
	actor = PokemonActor.new()
	actor.interactive = false
	actor.shadow.visible = false
	actor.position = feet
	add_child(actor)


func _ready() -> void:
	transient = true


func _resize(l: Vector2i) -> void:
	logical = l
	content_scale_size = logical
	size = logical * px_scale
	feet = Vector2(logical.x / 2.0, logical.y - 12.0).round()
	if actor:
		actor.position = feet


## Inicia el teletransporte. `positions` son las posiciones en pantalla (pies del Pokémon)
## donde debe aparecer. `return_screen` es donde vuelve al terminar.
func warp(species: String, positions: PackedVector2Array, return_screen: Vector2,
		scale_px: int) -> void:
	_alive = true
	px_scale = scale_px
	_positions = positions
	_return_screen = return_screen
	var m := PokemonActor.load_meta(species)
	var info: Dictionary = m["anims"].get(m["alias"].get("Idle", "Idle"), m["anims"]["Idle"])
	var need := maxi(int(info["fw"]), int(info["fh"])) + 16
	var side := maxi(MIN_LOGICAL, int(ceil(need / 16.0)) * 16)
	_resize(Vector2i(side, side))
	actor.species = species
	actor.modulate.a = 0.0
	visible = true
	if Game.native:
		Game.native.set_click_through(get_window_id(), true)
		Game.native.hide_from_taskbar(get_window_id())
	_run.call_deferred()


func abort() -> void:
	_alive = false
	visible = false
	finished.emit(Vector2i(_return_screen.round()))


func _run() -> void:
	for pos in _positions:
		if not _alive:
			return
		_move_to(pos)
		actor.play_anim("Idle", ["S", "E", "W", "N"][randi() % 4])
		# Sparkle de aparición
		_spawn_sparks(4)
		# Fade in
		await _fade(0.0, 1.0, FADE_IN)
		if not _alive:
			return
		await _hold_frame(HOLD)
		if not _alive:
			return
		# Sparkle de desaparición
		_spawn_sparks(3)
		# Fade out
		await _fade(1.0, 0.0, FADE_OUT)
		if not _alive:
			return
		await _hold_frame(TRAVEL)
	visible = false
	_alive = false
	finished.emit(Vector2i(_return_screen.round()))


func _fade(from: float, to: float, dur: float) -> void:
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		if not _alive:
			return
		t += get_process_delta_time()
		actor.modulate.a = lerpf(from, to, minf(1.0, t / dur))
		if desk:
			desk.keep_ambient()


func _hold_frame(dur: float) -> void:
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		if not _alive:
			return
		t += get_process_delta_time()
		if desk:
			desk.keep_ambient()


func _spawn_sparks(n: int) -> void:
	for i in n:
		var s := Sprite2D.new()
		s.texture = MoveFx.part_tex("psychic", "star")
		var offset := Vector2(randf_range(-12, 12), randf_range(-18, 4))
		s.position = (feet + offset).round()
		add_child(s)
		var tw := s.create_tween()
		tw.tween_property(s, "position", s.position + Vector2(randf_range(-8, 8), randf_range(-14, -4)), 0.45)
		tw.parallel().tween_property(s, "modulate:a", 0.0, 0.45).set_delay(0.2)
		tw.tween_callback(s.queue_free)


func _move_to(screen_feet: Vector2) -> void:
	position = Vector2i((screen_feet - feet * px_scale).round())
