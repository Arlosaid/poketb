class_name FlightWindow
extends Window
## Ventanita transparente que lleva a un Pokémon de paseo por toda la pantalla.
## Siempre deja pasar el mouse (nunca estorba ni recibe clics) y está oculta cuando
## nadie vuela, así que no gasta nada. Se mueve la ventana entera (sin reescalar el
## pixel art), y el actor queda en píxeles enteros dentro de ella.
##
## Estilos (Personality.flight_style): "bird" (planea con vaivén), "bug" (aleteo nervioso),
## "dragon" (rápido, curvas amplias) y "float" (fantasmas y levitadores: lento y a la deriva).

signal finished(landing_screen: Vector2i)

## Tamaño lógico mínimo de la ventana; crece para los Pokémon grandes.
const MIN_LOGICAL := 64
## Velocidad de crucero (px lógicos/s) y vaivén (amplitud px, frecuencia) por estilo.
const STYLES := {
	"bird": {"speed": 70.0, "amp": 6.0, "freq": 3.0},
	"bug": {"speed": 48.0, "amp": 3.0, "freq": 9.0},
	"dragon": {"speed": 85.0, "amp": 4.0, "freq": 2.0},
	"float": {"speed": 30.0, "amp": 5.0, "freq": 1.2},
}

var actor: PokemonActor
var desk: DesktopWindow
var px_scale := 2
var logical := Vector2i(MIN_LOGICAL, MIN_LOGICAL)
## Pies del actor dentro de la ventana.
var feet := Vector2(32, 52)
var style := "bird"
var _points: PackedVector2Array = []
var _pauses := {}
var _seg := 0
var _seg_t := 0.0
var _time := 0.0
var _hold := 0.0


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
	_resize(logical)
	actor = PokemonActor.new()
	actor.interactive = false
	actor.position = feet
	add_child(actor)


func _ready() -> void:
	transient = true  # propiedad de la principal: sin botón propio y queda encima con ella
	set_process(false)


func _resize(l: Vector2i) -> void:
	logical = l
	content_scale_size = logical
	size = logical * px_scale
	feet = Vector2(logical.x / 2.0, logical.y - 12.0).round()
	if actor:
		actor.position = feet


## Despega desde `start` (pantalla, en los pies del Pokémon), recorre `waypoints`
## (pantalla) y aterriza en el último. `pauses`: índice de punto → segundos flotando ahí.
func fly(species: String, start: Vector2, waypoints: PackedVector2Array, scale_px: int,
		flight_style := "bird", pauses := {}) -> void:
	px_scale = scale_px
	style = flight_style if STYLES.has(flight_style) else "bird"
	# la ventana alcanza para el cuadro más grande de su animación de vuelo
	var m := PokemonActor.load_meta(species)
	var info: Dictionary = m["anims"].get(m["alias"].get(_anim_name(), "Walk"), m["anims"]["Idle"])
	var need := maxi(int(info["fw"]), int(info["fh"])) + 16
	var side := maxi(MIN_LOGICAL, int(ceil(need / 16.0)) * 16)
	_resize(Vector2i(side, side))
	actor.species = species
	actor.shadow.visible = false
	actor.modulate.a = 0.85 if style == "float" else 1.0
	_points = PackedVector2Array([start]) + waypoints
	_pauses = pauses
	_seg = 0
	_seg_t = 0.0
	_time = 0.0
	_hold = 0.0
	_move_to(start)
	visible = true
	set_process(true)
	# Siempre transparente al mouse y sin botón en la barra (seguridad: nunca estorba).
	if Game.native:
		Game.native.set_click_through(get_window_id(), true)
		Game.native.hide_from_taskbar(get_window_id())
	_face(1)


## Animación lógica del vuelo según el estilo.
func _anim_name() -> String:
	return "Float" if style == "float" else "Flap"


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
	var st: Dictionary = STYLES[style]
	_time += delta
	if desk:
		desk.keep_awake()
	if _hold > 0.0:
		# flotando en el sitio: solo el vaivén
		_hold -= delta
		var p0 := _points[_seg]
		_move_to(p0 + Vector2(0, sin(_time * float(st["freq"])) * float(st["amp"]) * px_scale))
		return
	var a := _points[_seg]
	var b := _points[_seg + 1]
	var seg_len := maxf(1.0, a.distance_to(b))
	_seg_t += float(st["speed"]) * px_scale * delta / seg_len
	if _seg_t >= 1.0:
		_seg += 1
		_seg_t = 0.0
		_hold = float(_pauses.get(_seg, 0.0))
		if _hold > 0.0:
			actor.play_anim("Flap" if style != "float" else "Float", actor.dir)
		elif _seg < _points.size() - 1:
			_face(_seg + 1)
		return
	var p := a.lerp(b, _seg_t)
	# vaivén suave en el crucero (no al despegar ni al aterrizar)
	if _seg > 0 and _seg < _points.size() - 2:
		var amp := float(st["amp"]) * px_scale * sin(_seg_t * PI)
		p.y += sin(_time * float(st["freq"])) * amp
		if style == "bug":
			p.x += cos(_time * float(st["freq"]) * 0.7) * amp * 0.6
	_move_to(p)


func _face(i: int) -> void:
	var d := _points[i] - _points[maxi(0, i - 1)]
	actor.play_anim(_anim_name(), "E" if d.x >= 0.0 else "W")


func _move_to(screen_feet: Vector2) -> void:
	position = Vector2i((screen_feet - feet * px_scale).round())


func _end(land: Vector2) -> void:
	set_process(false)
	visible = false
	finished.emit(Vector2i(land.round()))
