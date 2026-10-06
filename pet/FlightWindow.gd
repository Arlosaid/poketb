class_name FlightWindow
extends Window
## Ventanita transparente que lleva a un Pokémon volador de paseo por la pantalla.
## Siempre deja pasar el mouse (nunca estorba ni recibe clics) y está oculta cuando
## nadie vuela, así que no gasta nada. Se mueve la ventana entera (sin reescalar el
## pixel art), y el actor queda en píxeles enteros dentro de ella.

signal finished(landing_screen: Vector2i)

const LOGICAL := Vector2i(64, 64)
## Pies del actor dentro de la ventana.
const FEET := Vector2(32, 52)
## Velocidad de crucero en px lógicos por segundo.
const SPEED := 55.0

var actor: PokemonActor
var desk: DesktopWindow
var px_scale := 2
var _points: PackedVector2Array = []
var _seg := 0
var _seg_t := 0.0
var _time := 0.0


func _init(scale_px: int) -> void:
	px_scale = scale_px
	title = "Taskbar Pokémon - vuelo"
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
	content_scale_size = LOGICAL
	size = LOGICAL * px_scale
	actor = PokemonActor.new()
	actor.interactive = false
	actor.position = FEET
	add_child(actor)


func _ready() -> void:
	transient = true  # propiedad de la principal: sin botón propio y queda encima con ella
	set_process(false)


## Despega desde `start` (pantalla, en los pies del Pokémon), recorre `waypoints`
## (pantalla) y aterriza en el último.
func fly(species: String, start: Vector2, waypoints: PackedVector2Array, scale_px: int) -> void:
	if scale_px != px_scale:
		px_scale = scale_px
		size = LOGICAL * px_scale
	actor.species = species
	actor.shadow.visible = false
	_points = PackedVector2Array([start]) + waypoints
	_seg = 0
	_seg_t = 0.0
	_time = 0.0
	_move_to(start)
	visible = true
	set_process(true)
	# Siempre transparente al mouse y sin botón en la barra (seguridad: nunca estorba).
	if Game.native:
		Game.native.set_click_through(get_window_id(), true)
		Game.native.hide_from_taskbar(get_window_id())
	_face(1)


## Cancela el vuelo y aterriza ya (pantalla completa, esconder mascotas, etc.).
func abort() -> void:
	if not visible:
		return
	var land := _points[_points.size() - 1] if not _points.is_empty() else Vector2(position)
	_end(land)


func _process(delta: float) -> void:
	if _seg >= _points.size() - 1:
		_end(_points[_points.size() - 1])
		return
	var a := _points[_seg]
	var b := _points[_seg + 1]
	var seg_len := maxf(1.0, a.distance_to(b))
	_seg_t += SPEED * px_scale * delta / seg_len
	_time += delta
	if _seg_t >= 1.0:
		_seg += 1
		_seg_t = 0.0
		if _seg < _points.size() - 1:
			_face(_seg + 1)
		return
	var p := a.lerp(b, _seg_t)
	# vaivén suave en el crucero (no al despegar ni al aterrizar)
	if _seg > 0 and _seg < _points.size() - 2:
		p.y += sin(_time * 3.0) * 6.0 * px_scale * sin(_seg_t * PI)
	_move_to(p)
	if desk:
		desk.keep_awake()


func _face(i: int) -> void:
	var d := _points[i] - _points[maxi(0, i - 1)]
	actor.play_anim("Walk", "E" if d.x >= 0.0 else "W")


func _move_to(screen_feet: Vector2) -> void:
	position = Vector2i((screen_feet - FEET * px_scale).round())


func _end(land: Vector2) -> void:
	set_process(false)
	visible = false
	finished.emit(Vector2i(land.round()))
