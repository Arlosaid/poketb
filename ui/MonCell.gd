class_name MonCell
extends PanelContainer
## Casilla de la PC con el retrato de un Pokémon. Se puede arrastrar y soltar
## (equipo ↔ mascotas ↔ cajas, y reordenar cada fila).

signal picked(uid: int)
signal dropped(data: Dictionary, target: MonCell)

const STAR := preload("res://assets/ui/sparkle.png")
## Marca de los que pasean por la casa como mascotas (el compañero ya lleva la estrella).
const HEART := preload("res://assets/ui/heart.png")

var uid := 0
var zone := "box"     # "team" | "pets" | "box"
var index := 0
var selected := false:
	set(v):
		selected = v
		queue_redraw()

var _portrait: TextureRect
var _lv: Label
var _hp: HpBar


func _init(z: String, i: int) -> void:
	zone = z
	index = i
	theme_type_variation = &"Slot"
	custom_minimum_size = Vector2(44, 44)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(40, 40)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_lv = Label.new()
	_lv.add_theme_color_override("font_color", Palette.PAPER)
	_lv.add_theme_color_override("font_shadow_color", Palette.INK)
	_lv.add_theme_constant_override("shadow_offset_x", 1)
	_lv.add_theme_constant_override("shadow_offset_y", 1)
	_lv.size_flags_vertical = Control.SIZE_SHRINK_END
	_lv.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lv)


func show_mon(p: PokemonInstance) -> void:
	uid = p.uid if p else 0
	_lv.visible = p != null
	if p == null:
		_portrait.texture = null
		tooltip_text = ""
		queue_redraw()
		return
	_portrait.texture = PokemonActor.portrait(p.species)
	_lv.text = "%d" % p.level
	_portrait.modulate = Color(1, 1, 1, 0.55) if p.is_fainted() else Color.WHITE
	queue_redraw()


func _draw() -> void:
	if uid != 0 and uid == Game.roster.companion:
		draw_texture(STAR, Vector2(size.x - 8, 2))
	elif uid != 0 and Game.roster.is_pet(uid):
		draw_texture(HEART, Vector2(size.x - 9, 2))
	if selected:
		var r := Rect2(Vector2.ZERO, size - Vector2(1, 1))
		draw_rect(r, Palette.FLAME, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and uid != 0:
		picked.emit(uid)


func _get_drag_data(_pos: Vector2) -> Variant:
	if uid == 0:
		return null
	var prev := TextureRect.new()
	prev.texture = _portrait.texture
	prev.modulate.a = 0.8
	set_drag_preview(prev)
	return {"uid": uid, "zone": zone, "index": index}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("uid")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	dropped.emit(data, self)
