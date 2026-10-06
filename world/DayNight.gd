class_name DayNight
extends RefCounted
## Traduce la hora (Game.clock) a parámetros visuales: dos fases a mezclar (a → b con
## `blend`), colores del cielo, sol/luna y la LUT de paleta para las capas.
## Los datos viven en data/daynight.json.

const ORDER: Array[StringName] = [&"day", &"dawn", &"dusk", &"night"]  # filas de la LUT

static var _data: Dictionary
static var _lut: ImageTexture


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/daynight.json"))
	return _data


static func lut_texture() -> Texture2D:
	if _lut:
		return _lut
	var names := Palette.NAMES
	var img := Image.create(32, ORDER.size(), false, Image.FORMAT_RGB8)
	for row in ORDER.size():
		var remap: Dictionary = data()["phases"][ORDER[row]]["remap"]
		for i in 32:
			img.set_pixel(i, row, Palette.by_name(remap.get(names[i], names[i])))
	_lut = ImageTexture.create_from_image(img)
	return _lut


static func palette_vec3() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in Palette.ALL:
		out.append(Vector3(c.r, c.g, c.b))
	return out


## {a: StringName, b: StringName, blend: float} para la hora dada.
static func phases_at(hour: float) -> Dictionary:
	var ph: Dictionary = data()["phases"]
	var bh: float = data()["blend_h"]
	# fases ordenadas por hora de inicio
	var list: Array = []
	for k in ph:
		list.append([float(ph[k]["start"]), StringName(k)])
	list.sort_custom(func(x, y): return x[0] < y[0])
	var cur: StringName = list[-1][1]
	var next_start := 24.0 + float(list[0][0])
	var next: StringName = list[0][1]
	for i in list.size():
		if hour >= list[i][0]:
			cur = list[i][1]
			var j := (i + 1) % list.size()
			next = list[j][1]
			next_start = float(list[j][0]) + (24.0 if j == 0 else 0.0)
	var h := hour if hour >= float(ph[cur]["start"]) else hour + 24.0
	var to_next := next_start - h
	if to_next < bh:
		return {"a": cur, "b": next, "blend": 1.0 - to_next / bh}
	return {"a": cur, "b": cur, "blend": 0.0}


static func row_of(phase: StringName) -> int:
	return ORDER.find(phase)


## Configura el material del cielo para una hora.
static func apply_sky(mat: ShaderMaterial, hour: float, t: float) -> void:
	var p := phases_at(hour)
	var pa: Dictionary = data()["phases"][p["a"]]
	var pb: Dictionary = data()["phases"][p["b"]]
	mat.set_shader_parameter("stops_a", _stops(pa["sky"]))
	mat.set_shader_parameter("stops_b", _stops(pb["sky"]))
	mat.set_shader_parameter("blend", p["blend"])
	# el astro dominante es el de la fase más "presente"
	var dom: Dictionary = pb if p["blend"] > 0.5 else pa
	mat.set_shader_parameter("sun_kind", float(dom["sun"]["kind"]))
	mat.set_shader_parameter("sun_core", _v3(dom["sun"]["core"]))
	mat.set_shader_parameter("sun_rim", _v3(dom["sun"]["rim"]))
	mat.set_shader_parameter("star_amount", lerpf(float(pa["stars"]), float(pb["stars"]), p["blend"]))
	mat.set_shader_parameter("star_a", _v3("mist"))
	mat.set_shader_parameter("star_b", _v3("honey"))
	mat.set_shader_parameter("time_s", t)
	mat.set_shader_parameter("sun_pos", _sun_pos(hour, int(dom["sun"]["kind"]) == 1))


## Configura un material de capa (palette_lut) para una hora.
static func apply_layer(mat: ShaderMaterial, hour: float) -> void:
	var p := phases_at(hour)
	mat.set_shader_parameter("row_a", row_of(p["a"]))
	mat.set_shader_parameter("row_b", row_of(p["b"]))
	mat.set_shader_parameter("blend", p["blend"])


static func new_layer_material(px_scale: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://world/palette_lut.gdshader")
	m.set_shader_parameter("lut", lut_texture())
	m.set_shader_parameter("pal", palette_vec3())
	m.set_shader_parameter("px_scale", float(px_scale))
	return m


## Tinte suave para los sprites de Pokémon (no son de nuestra paleta) según la fase.
static func sprite_tint(hour: float) -> Color:
	var tints := {&"day": Color(1, 1, 1), &"dawn": Color(1.0, 0.94, 0.97), &"dusk": Color(1.0, 0.92, 0.86), &"night": Color(0.72, 0.76, 0.95)}
	var p := phases_at(hour)
	return (tints[p["a"]] as Color).lerp(tints[p["b"]], p["blend"])


static func _stops(names: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in names:
		out.append(_v3(n))
	return out


static func _v3(n: String) -> Vector3:
	var c := Palette.by_name(n)
	return Vector3(c.r, c.g, c.b)


## Arco del sol (6→20 h) o de la luna (20→6 h) de izquierda a derecha.
static func _sun_pos(hour: float, moon: bool) -> Vector2:
	var f: float
	if moon:
		var h := hour if hour >= 20.0 else hour + 24.0
		f = clampf((h - 20.0) / 10.0, 0.0, 1.0)
	else:
		f = clampf((hour - 5.5) / 15.0, 0.0, 1.0)
	var y := 0.62 - sin(f * PI) * 0.48
	return Vector2(0.08 + f * 0.84, y)
