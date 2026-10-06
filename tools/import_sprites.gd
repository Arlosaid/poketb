extends SceneTree
## Importador de sprites PMD SpriteCollab → SpriteFrames de Godot.
##
## Lee assets/raw/spritecollab/sprite/XXXX/AnimData.xml y sus spritesheets y genera,
## por cada especie del roster:
##   pokemon/species/<name>/frames.res  SpriteFrames con animaciones "<Anim>_<Dir>"
##   pokemon/species/<name>/meta.json   tamaños, ancla de suelo, bbox, HitFrame, alias y retratos
## Las animaciones que faltan se resuelven con alternativas (ALTERNATIVES) y quedan
## registradas en tools/import_log.txt.
##
## Uso (primero hay que importar los PNG para que existan sus .import):
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/import_sprites.gd

const RAW := "res://assets/raw/spritecollab/"
const OUT := "res://pokemon/species/"
const LOG_PATH := "res://tools/import_log.txt"
## Orden de las filas en las hojas de PMD.
const DIRS: Array[String] = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
## Animaciones que importamos (si existen). El resto no se usa y no ocupa memoria.
const WANTED: Array[String] = [
	"Walk", "Idle", "Sleep", "EventSleep", "Wake", "Laying", "Sit", "Eat", "Hop", "Nod",
	"Pose", "LookUp", "Attack", "Strike", "Shoot", "Charge", "Swing", "Double", "Rotate",
	"Hurt", "Pain", "Faint", "Tumble", "FlapAround", "TailWhip", "Twirl",
]
## Animaciones lógicas que usa el juego → candidatas en orden de preferencia.
const ALTERNATIVES := {
	"Walk": ["Walk"],
	"Idle": ["Idle", "Walk"],
	"Sleep": ["Sleep", "EventSleep", "Laying", "Idle"],
	"Wake": ["Wake", "Idle"],
	"Laying": ["Laying", "Sleep"],
	"Sit": ["Sit", "Idle"],
	"Eat": ["Eat", "Nod", "Idle"],
	"Hop": ["Hop", "Walk"],
	"Nod": ["Nod", "Hop", "Idle"],
	"Pose": ["Pose", "Hop", "Idle"],
	"LookUp": ["LookUp", "Idle"],
	"Attack": ["Attack", "Strike", "Swing", "Shoot"],
	"Strike": ["Strike", "Attack"],
	"Shoot": ["Shoot", "Attack"],
	"Charge": ["Charge", "Idle"],
	"Hurt": ["Hurt", "Pain", "Idle"],
	"Faint": ["Faint", "Hurt"],
	"Joy": ["Hop", "Pose", "Nod", "Idle"],
}
const LOOPING: Array[String] = ["Walk", "Idle", "Sleep", "EventSleep", "Laying", "Sit", "Eat", "Charge", "FlapAround"]

var _log: PackedStringArray = []


func _initialize() -> void:
	var roster: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/pokemon_roster.json"))["species"]
	var ok := 0
	for sp in roster:
		if _import_species(int(sp["dex"]), String(sp["name"])):
			ok += 1
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	f.store_string("# Generado por tools/import_sprites.gd\n" + "\n".join(_log) + "\n")
	print("Importadas %d/%d especies. Log en %s" % [ok, roster.size(), LOG_PATH])
	quit(0 if ok == roster.size() else 1)


func _note(msg: String) -> void:
	_log.append(msg)
	print(msg)


func _import_species(dex: int, name: String) -> bool:
	var sdir := RAW + "sprite/%04d/" % dex
	var xml_path := sdir + "AnimData.xml"
	if not FileAccess.file_exists(xml_path):
		_note("ERROR %s: falta %s" % [name, xml_path])
		return false
	var data := _parse_anim_data(xml_path)
	var defs: Dictionary = data["anims"]

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var meta := {
		"dex": dex, "name": name, "shadow_size": data["shadow_size"],
		"anims": {}, "alias": {}, "portraits": {},
	}

	for anim_name in WANTED:
		if not defs.has(anim_name):
			continue
		var d: Dictionary = defs[anim_name]
		var src_name: String = d.get("copy_of", anim_name)
		var src: Dictionary = defs.get(src_name, d)
		var tex_path := sdir + src_name + "-Anim.png"
		if not ResourceLoader.exists(tex_path):
			_note("WARN %s: falta %s" % [name, tex_path])
			continue
		var tex: Texture2D = load(tex_path)
		var fw: int = src["fw"]
		var fh: int = src["fh"]
		var durations: Array = src["durations"]
		var cols := tex.get_width() / fw
		var rows := tex.get_height() / fh
		if cols != durations.size():
			_note("WARN %s/%s: %d columnas vs %d duraciones" % [name, anim_name, cols, durations.size()])
		var n_frames := mini(cols, durations.size())
		var n_dirs := 8 if rows >= 8 else 1
		for r in n_dirs:
			var key := StringName("%s_%s" % [anim_name, DIRS[r]])
			frames.add_animation(key)
			frames.set_animation_speed(key, 60.0)  # duraciones en ticks de 60 fps
			frames.set_animation_loop(key, anim_name in LOOPING)
			for c in n_frames:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(c * fw, r * fh, fw, fh)
				frames.add_frame(key, at, float(durations[c]))

		var shadow_path := sdir + src_name + "-Shadow.png"
		var ground := _shadow_center(shadow_path, fw, fh)
		var bbox := _opaque_bbox(tex.get_image(), fw, fh, n_frames)
		var shadow_frames := _shadow_frames(shadow_path, fw, fh, n_frames, n_dirs, ground)
		meta["anims"][anim_name] = {
			"fw": fw, "fh": fh, "frames": n_frames, "dirs": n_dirs,
			"ground": [ground.x, ground.y],
			# bbox relativo al punto de suelo (origen del actor)
			"bbox": [bbox.position.x - fw / 2.0 - ground.x, bbox.position.y - fh / 2.0 - ground.y, bbox.size.x, bbox.size.y],
			"rush": src.get("rush", -1), "hit": src.get("hit", -1), "return": src.get("ret", -1),
			"length_ticks": _sum(durations.slice(0, n_frames)),
		}
		if not shadow_frames.is_empty():
			# desplazamiento de la sombra por [dir][cuadro] respecto a `ground` (embestidas, saltos)
			meta["anims"][anim_name]["shadow"] = shadow_frames

	# Resolver alias lógicos.
	for logical in ALTERNATIVES:
		var found := ""
		for cand in ALTERNATIVES[logical]:
			if meta["anims"].has(cand):
				found = cand
				break
		if found == "":
			_note("ERROR %s: sin animación para %s" % [name, logical])
			continue
		meta["alias"][logical] = found
		if found != logical:
			_note("alt %s: %s -> %s" % [name, logical, found])

	# Retratos.
	var pdir := RAW + "portrait/%04d/" % dex
	var da := DirAccess.open(pdir)
	if da:
		for fn in da.get_files():
			if fn.ends_with(".png"):
				meta["portraits"][fn.get_basename()] = pdir + fn
	if not meta["portraits"].has("Normal"):
		_note("WARN %s: sin retrato Normal" % name)

	DirAccess.make_dir_recursive_absolute(OUT + name)
	var err := ResourceSaver.save(frames, OUT + name + "/frames.res", ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		_note("ERROR %s: no se pudo guardar frames (%d)" % [name, err])
		return false
	var mf := FileAccess.open(OUT + name + "/meta.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta, "\t", true))
	print("ok %04d %s: %d anims, %d retratos" % [dex, name, meta["anims"].size(), meta["portraits"].size()])
	return true


func _sum(a: Array) -> int:
	var s := 0
	for v in a:
		s += int(v)
	return s


## Centro del marcador de sombra del primer cuadro (fila S), relativo al centro del cuadro.
func _shadow_center(path: String, fw: int, fh: int) -> Vector2:
	if not ResourceLoader.exists(path):
		return Vector2(0, fh * 0.25)
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var sum := Vector2.ZERO
	var n := 0
	for y in fh:
		for x in fw:
			if img.get_pixel(x, y).a > 0.5:
				sum += Vector2(x, y)
				n += 1
	if n == 0:
		return Vector2(0, fh * 0.25)
	var c := sum / n + Vector2(0.5, 0.5)
	return (c - Vector2(fw, fh) / 2.0).round()


## Desplazamiento del marcador de sombra por dirección y cuadro, relativo a `ground`.
## Devuelve [] si la sombra no se mueve nunca (lo normal en Idle/Walk).
func _shadow_frames(path: String, fw: int, fh: int, n_frames: int, n_dirs: int, ground: Vector2) -> Array:
	if not ResourceLoader.exists(path):
		return []
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var out := []
	var moves := false
	for r in n_dirs:
		var row := []
		for c in n_frames:
			var used := img.get_region(Rect2i(c * fw, r * fh, fw, fh)).get_used_rect()
			var off := Vector2.ZERO
			if used.size != Vector2i.ZERO:
				var center := Vector2(used.position) + Vector2(used.size) / 2.0
				off = (center - Vector2(fw, fh) / 2.0).round() - ground
			if off != Vector2.ZERO:
				moves = true
			row.append([off.x, off.y])
		out.append(row)
	return out if moves else []


## Unión de los píxeles opacos de todos los cuadros de la fila S.
func _opaque_bbox(img: Image, fw: int, fh: int, n_frames: int) -> Rect2:
	if img.is_compressed():
		img.decompress()
	var r := Rect2()
	var has := false
	for c in n_frames:
		var used := img.get_region(Rect2i(c * fw, 0, fw, fh)).get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var rr := Rect2(used)
		r = rr if not has else r.merge(rr)
		has = true
	return r if has else Rect2(0, 0, fw, fh)


func _parse_anim_data(path: String) -> Dictionary:
	var p := XMLParser.new()
	p.open(path)
	var anims := {}
	var shadow := 1
	var cur := {}
	var tag := ""
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				tag = p.get_node_name()
				if tag == "Anim":
					cur = {"durations": []}
			XMLParser.NODE_TEXT:
				var t := p.get_node_data().strip_edges()
				if t == "":
					continue
				match tag:
					"ShadowSize": shadow = int(t)
					"Name": cur["name"] = t
					"FrameWidth": cur["fw"] = int(t)
					"FrameHeight": cur["fh"] = int(t)
					"Duration": cur["durations"].append(int(t))
					"RushFrame": cur["rush"] = int(t)
					"HitFrame": cur["hit"] = int(t)
					"ReturnFrame": cur["ret"] = int(t)
					"CopyOf": cur["copy_of"] = t
			XMLParser.NODE_ELEMENT_END:
				if p.get_node_name() == "Anim" and cur.has("name"):
					anims[cur["name"]] = cur
				tag = ""
	return {"shadow_size": shadow, "anims": anims}
