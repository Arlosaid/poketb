class_name PokemonActor
extends Node2D
## Un Pokémon visible en la franja: sprite PMD + sombra suave.
## El origen del nodo es el punto de suelo (donde va la sombra).
##
## Las animaciones se piden por nombre lógico ("Walk", "Sleep", "Faint"...) y
## `play_anim` aplica las alternativas que dejó el importador en meta.json.

signal clicked(actor: PokemonActor, button: int)
signal anim_finished(anim: String)

const SPECIES_DIR := "res://pokemon/species/"
## Ancho de la sombra (px lógicos) según ShadowSize de AnimData (0, 1, 2).
const SHADOW_W := [10, 14, 20]

## SpriteFrames armados en memoria (los más recientes; ver FRAMES_CACHE_MAX).
const FRAMES_CACHE_MAX := 40
const PORTRAIT_SIZE := 40

static var _meta_cache := {}
static var _shadow_cache := {}
static var _frames_cache := {}
static var _portrait_cache := {}

@export var species := "charmander":
	set(v):
		species = v
		if is_inside_tree():
			_load_species()
## Si es true, se registra en Passthrough y recibe clics.
@export var interactive := true

const DIRS: Array[String] = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]

var dir := "E"
var anim := ""
var meta: Dictionary

var sprite: AnimatedSprite2D
var shadow: Sprite2D

## Altura sobre el suelo (px). La sombra se queda en el suelo mientras está en el aire.
var air := 0.0:
	set(v):
		air = v
		if shadow:
			_update_shadow()

var _shadow_track: Array = []
var _shadow_dir := 0


func _ready() -> void:
	shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.centered = true
	add_child(shadow)
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = true
	sprite.animation_finished.connect(_on_sprite_finished)
	sprite.frame_changed.connect(_update_shadow)
	add_child(sprite)
	_load_species()
	if interactive:
		Passthrough.register(self)


func _load_species() -> void:
	meta = load_meta(species)
	sprite.sprite_frames = frames_for(species)
	shadow.texture = _shadow_texture(int(meta.get("shadow_size", 1)))
	anim = ""
	play_anim("Idle")


static func load_meta(sp: String) -> Dictionary:
	if not _meta_cache.has(sp):
		var path := SPECIES_DIR + sp + "/meta.json"
		_meta_cache[sp] = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return _meta_cache[sp]


## SpriteFrames de una especie, armado desde su hoja empacada (tools/pack_sprites.py):
## cada cuadro es un AtlasTexture recortado cuyo `margin` le devuelve el tamaño del cuadro PMD.
static func frames_for(sp: String) -> SpriteFrames:
	if _frames_cache.has(sp):
		var cached: SpriteFrames = _frames_cache[sp]
		_frames_cache.erase(sp)  # al final: es el más reciente
		_frames_cache[sp] = cached
		return cached
	var m := load_meta(sp)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var sheet: Texture2D = load(SPECIES_DIR + sp + "/sheet.png")
	var cells: Array = m["cells"]
	var atlases := {}
	for an in m["anims"]:
		var info: Dictionary = m["anims"][an]
		var fw := float(info["fw"])
		var fh := float(info["fh"])
		var durations: Array = info["durations"]
		for r in int(info["dirs"]):
			var key := StringName("%s_%s" % [an, DIRS[r]])
			frames.add_animation(key)
			frames.set_animation_speed(key, 60.0)  # duraciones en ticks de 60 fps
			frames.set_animation_loop(key, bool(info["loop"]))
			var row: Array = info["cells"][r]
			for c in row.size():
				var ci := int(row[c])
				if not atlases.has(ci):
					var cell: Array = cells[ci]
					var at := AtlasTexture.new()
					at.atlas = sheet
					at.region = Rect2(cell[0], cell[1], cell[2], cell[3])
					at.margin = Rect2(cell[4], cell[5], fw - float(cell[2]), fh - float(cell[3]))
					atlases[ci] = at
				frames.add_frame(key, atlases[ci], float(durations[c]))
	_frames_cache[sp] = frames
	while _frames_cache.size() > FRAMES_CACHE_MAX:
		_frames_cache.erase(_frames_cache.keys()[0])
	return frames


## Retrato de 40x40 de la primera emoción de `emotions` que tenga la especie (o null).
static func portrait(sp: String, emotions: Array = ["Normal"]) -> Texture2D:
	var ports: Dictionary = load_meta(sp).get("portraits", {})
	for e in emotions + ["Normal"]:
		if not ports.has(e):
			continue
		var key := "%s/%s" % [sp, e]
		if not _portrait_cache.has(key):
			var at := AtlasTexture.new()
			at.atlas = load(SPECIES_DIR + sp + "/portraits.png")
			at.region = Rect2(int(ports[e]) * PORTRAIT_SIZE, 0, PORTRAIT_SIZE, PORTRAIT_SIZE)
			_portrait_cache[key] = at
		return _portrait_cache[key]
	return null


static func has_portrait(sp: String, emotion: String) -> bool:
	return load_meta(sp).get("portraits", {}).has(emotion)


## Nombre real de la animación tras aplicar alternativas.
func resolve(logical: String) -> String:
	return meta["alias"].get(logical, logical if meta["anims"].has(logical) else "Idle")


func has_real(logical: String) -> bool:
	return meta["alias"].get(logical, "") == logical


func play_anim(logical: String, new_dir := "", restart := false) -> void:
	if new_dir != "":
		dir = new_dir
	var real := resolve(logical)
	var info: Dictionary = meta["anims"][real]
	var d := dir if int(info["dirs"]) == 8 else "S"
	var key := StringName("%s_%s" % [real, d])
	if key == sprite.animation and sprite.is_playing() and not restart:
		anim = logical
		return
	anim = logical
	var g: Array = info["ground"]
	sprite.position = -Vector2(g[0], g[1])
	sprite.play(key)
	if restart:
		sprite.frame = 0
	_shadow_track = info.get("shadow", [])
	_shadow_dir = DIRS.find(d) if int(info["dirs"]) == 8 else 0
	_update_shadow()


## Duración en segundos de una animación (sin bucle).
func anim_length(logical: String) -> float:
	return float(meta["anims"][resolve(logical)]["length_ticks"]) / 60.0


## Segundo en el que cae el golpe (HitFrame) de una animación de ataque.
func hit_time(logical: String) -> float:
	var info: Dictionary = meta["anims"][resolve(logical)]
	var hit := int(info["hit"])
	if hit < 0:
		return anim_length(logical) * 0.5
	var frames := sprite.sprite_frames
	var key := sprite.animation
	var t := 0.0
	for i in mini(hit, frames.get_frame_count(key)):
		t += frames.get_frame_duration(key, i)
	return t / 60.0


func face_towards(x: float) -> void:
	var nd := "E" if x >= global_position.x else "W"
	if nd != dir:
		play_anim(anim, nd)


## Globo, emoción o ficha que cuelga de este actor (uno de cada tipo), o null.
func attached(key: StringName) -> Node:
	if not has_meta(key):
		return null
	var n: Variant = get_meta(key)
	if is_instance_valid(n):
		return n
	remove_meta(key)
	return null


## Rect clicable en coordenadas del viewport (usa el bbox de Idle, estable entre cuadros).
func get_click_rect() -> Rect2:
	var bb: Array = meta["anims"][resolve("Idle")]["bbox"]
	var r := Rect2(bb[0], bb[1], bb[2], bb[3])
	return get_global_transform_with_canvas() * r


## Punto sobre la cabeza (para burbujas, corazones, "Zzz"), en coordenadas locales.
func head_point() -> Vector2:
	var bb: Array = meta["anims"][resolve("Idle")]["bbox"]
	return Vector2(0, float(bb[1]))


## La sombra sigue al marcador de PMD en las animaciones que se desplazan.
func _update_shadow() -> void:
	var base := Vector2(0, air)
	if _shadow_track.is_empty():
		shadow.position = base
		return
	var row: Array = _shadow_track[mini(_shadow_dir, _shadow_track.size() - 1)]
	var off: Array = row[mini(sprite.frame, row.size() - 1)]
	shadow.position = base + Vector2(off[0], off[1])


func _on_sprite_finished() -> void:
	anim_finished.emit(anim)


func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed:
		if Passthrough.hovered() == self:
			clicked.emit(self, event.button_index)
			get_viewport().set_input_as_handled()


## Sombra pixel art: elipse dura en INK con 35% de alfa (sin bordes difusos).
static func _shadow_texture(size_idx: int) -> Texture2D:
	size_idx = clampi(size_idx, 0, 2)
	if _shadow_cache.has(size_idx):
		return _shadow_cache[size_idx]
	var w: int = SHADOW_W[size_idx]
	var h: int = maxi(3, w / 3)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c := Palette.a(Palette.INK, 0.35)
	var rx := w / 2.0
	var ry := h / 2.0
	for y in h:
		for x in w:
			var dx := (x + 0.5 - rx) / rx
			var dy := (y + 0.5 - ry) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_shadow_cache[size_idx] = tex
	return tex
