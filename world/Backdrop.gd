class_name Backdrop
extends Node2D
## Fondo del panel de pelea: cielo (shader según la hora) + capas de parallax del
## bioma (data/biomes/<id>.json) + partículas ambientales. Todo en px lógicos.

var biome: Dictionary
var size := Vector2i(376, 56)
## Distancia recorrida (px lógicos de la capa principal).
var distance := 0.0

var _sky: ColorRect
var _sky_mat: ShaderMaterial
var _layer_mat: ShaderMaterial
var _layers: Array[Sprite2D] = []
var _speeds: PackedFloat32Array = []
var _drifts: PackedFloat32Array = []
var _ambient: Ambient
var _time := 0.0
var _hour_timer := 0.0


func setup(biome_id: String, area: Vector2i, px_scale: int) -> void:
	size = area
	biome = JSON.parse_string(FileAccess.get_file_as_string("res://data/biomes/%s.json" % biome_id))
	for c in get_children():
		c.queue_free()
	_layers.clear()
	_speeds.clear()
	_drifts.clear()

	_sky = ColorRect.new()
	_sky.size = Vector2(size)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://world/sky.gdshader")
	_sky_mat.set_shader_parameter("size", Vector2(size))
	_sky.material = _sky_mat
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sky)

	_layer_mat = DayNight.new_layer_material(px_scale)
	var h: int = biome["height"]
	for L in biome["layers"]:
		var s := Sprite2D.new()
		s.texture = load("res://assets/bg/%s/%s.png" % [biome["id"], L["name"]])
		s.centered = false
		s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		s.region_enabled = true
		s.region_rect = Rect2(0, 0, size.x, h)
		s.position = Vector2(0, size.y - h)
		s.material = _layer_mat
		# El primer plano va por encima de los Pokémon (z 2); el resto, detrás.
		s.z_index = 2 if L["name"] == "front" else 0
		add_child(s)
		_layers.append(s)
		_speeds.append(float(L["speed"]))
		_drifts.append(float(L.get("drift", 0.0)))

	_ambient = Ambient.new()
	_ambient.area = size
	_ambient.material = _layer_mat
	_ambient.z_index = 1
	add_child(_ambient)
	_apply_hour()
	scroll(0.0)


## Altura (en coordenadas locales) donde pisan los Pokémon.
func ground_y() -> float:
	return size.y - int(biome["height"]) + int(biome["ground_y"])


func scroll(dx: float) -> void:
	distance += dx
	_ambient.scroll(dx)
	for i in _layers.size():
		var off := distance * _speeds[i] + _time * _drifts[i]
		_layers[i].region_rect.position.x = floorf(off)


func _process(delta: float) -> void:
	_time += delta
	if _drifts.size() > 0:
		scroll(0.0)
	_hour_timer -= delta
	if _hour_timer <= 0.0:
		_hour_timer = 5.0
		_apply_hour()
	elif Game.clock.is_night():
		_sky_mat.set_shader_parameter("time_s", _time)


func _apply_hour() -> void:
	var hour := Game.clock.hour()
	DayNight.apply_sky(_sky_mat, hour, _time)
	DayNight.apply_layer(_layer_mat, hour)
	var p := DayNight.phases_at(hour)
	var dominant: StringName = p["b"] if p["blend"] > 0.5 else p["a"]
	_ambient.kind = biome["particles"]["night" if dominant == &"night" else "day"]


## Fuerza la hora (para capturas y depuración) y refresca al instante.
func refresh() -> void:
	_hour_timer = 0.0
	_apply_hour()
