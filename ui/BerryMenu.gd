class_name BerryMenu
extends PanelContainer
## Menú chiquito de bayas junto a un Pokémon. Al pasar el mouse muestra el nombre y
## el sabor; al hacer clic emite `chosen`. Se cierra solo si lo ignoras.

signal chosen(berry: String)

const BERRIES_TEX := preload("res://assets/ui/berries.png")
const LIFE := 6.0

var target: PokemonActor
var _info: Label
var _life := LIFE
var _index: Dictionary


static func open(hud: Control, actor: PokemonActor, inventory: Dictionary) -> BerryMenu:
	var m := BerryMenu.new()
	m.target = actor
	hud.add_child(m)
	m._build(inventory)
	return m


static func icon(berry: String) -> AtlasTexture:
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/berries_index.json"))
	var at := AtlasTexture.new()
	at.atlas = BERRIES_TEX
	at.region = Rect2(int(idx["index"].get(berry, 0)) * 12, 0, 12, 12)
	return at


func _build(inventory: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	_info = Label.new()
	_info.text = "Bayas"
	v.add_child(_info)
	if inventory.is_empty():
		var l := Label.new()
		l.text = "No tienes bayas.\nCaen al ganar combates."
		l.add_theme_color_override("font_color", Palette.WOOD)
		v.add_child(l)
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 1)
		grid.add_theme_constant_override("v_separation", 1)
		v.add_child(grid)
		var names := inventory.keys()
		names.sort()
		for b in names:
			var btn := Button.new()
			btn.icon = icon(b)
			btn.text = "%d" % int(inventory[b])
			btn.focus_mode = Control.FOCUS_NONE
			btn.mouse_entered.connect(_show_info.bind(b))
			btn.pressed.connect(func() -> void:
				chosen.emit(b)
				close())
			grid.add_child(btn)
	Passthrough.register(self)
	reset_size()
	_place()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _show_info(b: String) -> void:
	var d := SpeciesDB.berry(b)
	var f := SpeciesDB.dominant_flavor(b)
	_info.text = "%s · %s" % [d["name_es"], SpeciesDB.flavor_es(f) if f != "" else "Varios sabores"]


func get_click_rect() -> Rect2:
	return get_global_rect()


func _place() -> void:
	if not is_instance_valid(target):
		return
	var head := target.global_position + target.head_point()
	var vp := get_viewport_rect().size
	position = Vector2(clampf(head.x + 10.0, 2.0, vp.x - size.x - 3.0), maxf(1.0, head.y - size.y + 6.0)).round()


func _process(delta: float) -> void:
	_place()
	if Passthrough.hovered() == self:
		_life = LIFE * 0.5
		return
	_life -= delta
	if _life <= 0.0:
		close()


func close() -> void:
	set_process(false)
	Passthrough.unregister(self)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	t.tween_callback(queue_free)
