class_name PetCard
extends PanelContainer
## Ficha compacta de una mascota: nombre, nivel, rasgo, característica canon y cuatro
## barritas (saciedad, energía, diversión y amistad). No es clicable; se va sola.

const EMOTES := preload("res://assets/ui/emotes.png")
const LIFE := 6.0

var target: PokemonActor
var mon: PokemonInstance
var _life := LIFE


static func open(hud: Control, actor: PokemonActor, p: PokemonInstance) -> PetCard:
	for k in [&"card", &"emote", &"bubble"]:
		var prev := actor.attached(k)
		if prev:
			prev.queue_free()
	var c := PetCard.new()
	c.target = actor
	c.mon = p
	c.theme_type_variation = &"TextBubble"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(c)
	c._build()
	actor.set_meta(&"card", c)
	return c


func _build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var title := Label.new()
	title.text = "%s Nv.%d · %s" % [mon.display_name(), mon.level, Personality.trait_name(mon)]
	v.add_child(title)
	var ch := Label.new()
	ch.text = Personality.characteristic_text(mon)
	ch.add_theme_color_override("font_color", Palette.WOOD)
	v.add_child(ch)
	if mon.ability() != "":
		var ab := Label.new()
		ab.text = "Habilidad: " + mon.ability_es()
		ab.add_theme_color_override("font_color", Palette.WOOD)
		v.add_child(ab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	row.add_child(_meter("berry", mon.fullness / 100.0))
	row.add_child(_meter("zzz", mon.energy / 100.0))
	row.add_child(_meter("ball", mon.fun / 100.0))
	row.add_child(_meter("heart", mon.friendship / 255.0))
	reset_size()
	_place()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


## Ícono de 7x7 + barrita de 14x3 px.
func _meter(icon_name: String, frac: float) -> Control:
	var idx := Emote.icon_index(icon_name)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 1)
	var tr := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = EMOTES
	at.region = Rect2(idx * 7, 0, 7, 7)
	tr.texture = at
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	h.add_child(tr)
	var bar := MiniBar.new()
	bar.frac = clampf(frac, 0.0, 1.0)
	h.add_child(bar)
	return h


func _place() -> void:
	if not is_instance_valid(target):
		return
	var head := target.global_position + target.head_point()
	var vp := get_viewport_rect().size
	position = Vector2(clampf(head.x - size.x / 2.0, 2.0, vp.x - size.x - 3.0), maxf(1.0, head.y - size.y - 6.0)).round()


func _process(delta: float) -> void:
	_place()
	_life -= delta
	if _life <= 0.0:
		set_process(false)
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.15)
		t.tween_callback(queue_free)


## Barrita de 14x3: fondo arena, relleno según el nivel (menta, ámbar o rojo).
class MiniBar extends Control:
	var frac := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(16, 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(0, 2, 16, 4)
		draw_rect(r, Palette.WOOD)
		draw_rect(r.grow(-1), Palette.SAND)
		var w := roundf(14.0 * frac)
		if w > 0.0:
			draw_rect(Rect2(1, 3, w, 2), Palette.hp_color(frac))
