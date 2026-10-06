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

static var _meta_cache := {}
static var _shadow_cache := {}

@export var species := "charmander":
	set(v):
		species = v
		if is_inside_tree():
			_load_species()
## Si es true, se registra en Passthrough y recibe clics.
@export var interactive := true

var dir := "E"
var anim := ""
var meta: Dictionary

var sprite: AnimatedSprite2D
var shadow: Sprite2D


func _ready() -> void:
	shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.centered = true
	add_child(shadow)
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = true
	sprite.animation_finished.connect(_on_sprite_finished)
	add_child(sprite)
	_load_species()
	if interactive:
		Passthrough.register(self)


func _load_species() -> void:
	meta = load_meta(species)
	sprite.sprite_frames = load(SPECIES_DIR + species + "/frames.res")
	shadow.texture = _shadow_texture(int(meta.get("shadow_size", 1)))
	anim = ""
	play_anim("Idle")


static func load_meta(sp: String) -> Dictionary:
	if not _meta_cache.has(sp):
		_meta_cache[sp] = JSON.parse_string(FileAccess.get_file_as_string(SPECIES_DIR + sp + "/meta.json"))
	return _meta_cache[sp]


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


## Rect clicable en coordenadas del viewport (usa el bbox de Idle, estable entre cuadros).
func get_click_rect() -> Rect2:
	var bb: Array = meta["anims"][resolve("Idle")]["bbox"]
	var r := Rect2(bb[0], bb[1], bb[2], bb[3])
	return get_global_transform_with_canvas() * r


## Punto sobre la cabeza (para burbujas, corazones, "Zzz"), en coordenadas locales.
func head_point() -> Vector2:
	var bb: Array = meta["anims"][resolve("Idle")]["bbox"]
	return Vector2(0, float(bb[1]))


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
