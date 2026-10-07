class_name ClimbWindow
extends Window
## Ventanita transparente que lleva a un Pokémon por el borde de la pantalla.
## Sube y baja por la pared izquierda o derecha del monitor, con paradas opcionales.
## Mismo patrón que FlightWindow: siempre deja pasar el mouse, oculta cuando nadie escala.

signal finished(landing_screen: Vector2i)

const MIN_LOGICAL := 64
## Velocidad de escalada en px lógicos/s (lento para que se aprecie).
const SPEED := 30.0

var actor: PokemonActor
var desk: DesktopWindow
var px_scale := 2
var logical := Vector2i(MIN_LOGICAL, MIN_LOGICAL)
var feet := Vector2(32, 52)
## "left" o "right": de qué borde escala.
var wall := "left"
var _points: PackedVector2Array = []
var _pauses := {}
var _seg := 0
var _seg_t := 0.0
var _hold := 0.0
var _time := 0.0


func _init(scale_px: int) -> void:
	px_scale = scale_px
	title = "Taskbar Pokémon - escala"
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
	set_process(false)


func _resize(l: Vector2i) -> void:
	logical = l
	content_scale_size = logical
	size = logical * px_scale
	feet = Vector2(logical.x / 2.0, logical.y - 12.0).round()
	if actor:
		actor.position = feet


## Inicia la escalada. `start` es la posición inicial en coordenadas de pantalla (pies).
## `waypoints` son los puntos siguientes en pantalla. `pauses`: índice → segundos quieto ahí.
func climb(species: String, start: Vector2, waypoints: PackedVector2Array, scale_px: int,
		which_wall: String, pauses := {}) -> void:
	px_scale = scale_px
	wall = which_wall
	var m := PokemonActor.load_meta(species)
	var info: Dictionary = m["anims"].get(m["alias"].get("Walk", "Walk"), m["anims"]["Idle"])
	var need := maxi(int(info["fw"]), int(info["fh"])) + 16
	var side := maxi(MIN_LOGICAL, int(ceil(need / 16.0)) * 16)
	_resize(Vector2i(side, side))
	actor.species = species
	actor.modulate.a = 1.0
	_points = PackedVector2Array([start]) + waypoints
	_pauses = pauses
	_seg = 0
	_seg_t = 0.0
	_hold = 0.0
	_time = 0.0
	_move_to(start)
	visible = true
	set_process(true)
	if Game.native:
		Game.native.set_click_through(get_window_id(), true)
		Game.native.hide_from_taskbar(get_window_id())
	# Cara hacia el interior de la pantalla (E si escala borde izq, W si escala borde der).
	actor.play_anim("Hop", "E" if wall == "left" else "W")


func abort() -> void:
	if not visible:
		return
	var land := _points[_points.size() - 1] if not _points.is_empty() else Vector2(position)
	_end(land)


func _process(delta: float) -> void:
	if _seg >= _points.size() - 1:
		_end(_points[_points.size() - 1])
		return
	_time += delta
	if desk:
		desk.keep_ambient()
	if _hold > 0.0:
		_hold -= delta
		actor.play_anim("Idle", actor.dir)
		return
	var a := _points[_seg]
	var b := _points[_seg + 1]
	var seg_len := maxf(1.0, a.distance_to(b))
	_seg_t += SPEED * px_scale * delta / seg_len
	if _seg_t >= 1.0:
		_seg += 1
		_seg_t = 0.0
		_hold = float(_pauses.get(_seg, 0.0))
		if _hold <= 0.0 and _seg < _points.size() - 1:
			if not actor.sprite.is_playing():
				actor.play_anim("Hop", actor.dir, true)
		return
	var p := a.lerp(b, _seg_t)
	if not actor.sprite.is_playing():
		actor.play_anim("Hop", actor.dir, true)
	_move_to(p)


func _move_to(screen_feet: Vector2) -> void:
	position = Vector2i((screen_feet - feet * px_scale).round())


func _end(land: Vector2) -> void:
	set_process(false)
	visible = false
	finished.emit(Vector2i(land.round()))
