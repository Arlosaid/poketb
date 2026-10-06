class_name MonPicker
extends HBoxContainer
## Cabecera para elegir a qué Pokémon se entrena o equipa: "<  retrato  Nombre Nv.  >".
## Recorre primero el equipo y luego las cajas.

signal picked(uid: int)

var uid := 0
var _portrait: TextureRect
var _name: Label
var _sub: Label


func _init() -> void:
	add_theme_constant_override("separation", 3)
	add_child(_arrow("<", -1))
	var fr := PanelContainer.new()
	fr.theme_type_variation = &"Slot"
	add_child(fr)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(40, 40)
	fr.add_child(_portrait)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.custom_minimum_size = Vector2(96, 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(v)
	_name = Label.new()
	v.add_child(_name)
	_sub = Label.new()
	_sub.add_theme_color_override("font_color", Palette.WOOD)
	v.add_child(_sub)
	add_child(_arrow(">", 1))


func _arrow(t: String, dir: int) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_step.bind(dir))
	return b


## Todos los uids en orden: equipo, mascotas y luego cajas.
static func order() -> Array[int]:
	var r := Game.roster
	var out: Array[int] = r.team.duplicate()
	out.append_array(r.pets)
	var rest: Array[int] = []
	for u in r.members:
		if u not in out:
			rest.append(u)
	rest.sort()
	out.append_array(rest)
	return out


func _step(dir: int) -> void:
	var ids := order()
	if ids.is_empty():
		return
	var i := ids.find(uid)
	picked.emit(ids[posmod(i + dir, ids.size())])


func show_mon(p: PokemonInstance) -> void:
	uid = p.uid if p else 0
	if p == null:
		_portrait.texture = null
		_name.text = ""
		_sub.text = ""
		return
	_portrait.texture = PokemonActor.portrait(p.species)
	_name.text = p.display_name()
	_sub.text = "Nv. %d · %s" % [p.level, "/".join(p.types().map(func(t): return SpeciesDB.type_es(t)))]
