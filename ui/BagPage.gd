class_name BagPage
extends HBoxContainer
## Mochila: los objetos que no están equipados. 3 iguales del mismo nivel se fusionan en 1 del
## siguiente (Común → Poco común → Raro → Épico). Se equipan en el Pokémon elegido.

signal pick(uid: int)

var uid := 0
var selected := ""

var _grid: GridContainer
var _detail: VBoxContainer
var _picker: MonPicker


func _init() -> void:
	add_theme_constant_override("separation", 4)
	var left := Widgets.vbox(2)
	add_child(left)
	left.add_child(Widgets.label("Objetos", Palette.WOOD))
	var panel := Widgets.slot_panel()
	panel.custom_minimum_size = Vector2(7 * ItemCell.SIZE + 6 * 2 + 10, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	sc.add_child(_grid)

	var right := Widgets.vbox(3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var dp := Widgets.slot_panel()
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(dp)
	_detail = Widgets.vbox(2)
	dp.add_child(_detail)
	_picker = MonPicker.new()
	_picker.picked.connect(func(u: int) -> void: pick.emit(u))
	right.add_child(_picker)


## Orden estable: por objeto (como en data/items.json) y de mayor a menor nivel.
func _sorted_keys() -> Array:
	var ids: Array = Progression.item_defs().keys()
	var keys: Array = Game.roster.bag.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ia := ids.find(Progression.key_id(a))
		var ib := ids.find(Progression.key_id(b))
		if ia != ib:
			return ia < ib
		return Progression.key_tier(a) > Progression.key_tier(b))
	return keys


func refresh() -> void:
	var r := Game.roster
	_picker.show_mon(r.get_member(uid))
	if selected != "" and not r.bag.has(selected):
		selected = ""
	Widgets.clear(_grid)
	var keys := _sorted_keys()
	if selected == "" and not keys.is_empty():
		selected = keys[0]
	for k in keys:
		var c := ItemCell.new(k, int(r.bag[k]))
		c.selected = k == selected
		c.pressed.connect(func() -> void:
			selected = k
			refresh())
		_grid.add_child(c)
	# casillas vacías para que se vea la cuadrícula
	for i in maxi(0, 28 - keys.size()):
		_grid.add_child(ItemCell.new())
	_fill_detail()


func _fill_detail() -> void:
	Widgets.clear(_detail)
	var r := Game.roster
	if selected == "":
		_detail.add_child(Widgets.wrapped("La mochila está vacía. Los objetos caen al ganar combates (el jefe siempre suelta uno).", Palette.WOOD, 190))
		return
	var tier := Progression.key_tier(selected)
	var top := Widgets.hbox(4)
	top.add_child(ItemCell.new(selected))
	var nv := Widgets.vbox(0)
	nv.add_child(Widgets.label(Progression.item_name(selected)))
	nv.add_child(Widgets.label(Progression.tier_name(tier), Progression.tier_color(tier).darkened(0.25)))
	top.add_child(nv)
	_detail.add_child(top)
	_detail.add_child(Widgets.label(Progression.item_summary(selected), Palette.FOREST))
	_detail.add_child(Widgets.label("En la mochila: %d" % int(r.bag[selected]), Palette.WOOD))

	var need := Progression.merge_count()
	var mb := Button.new()
	mb.focus_mode = Control.FOCUS_NONE
	if tier >= Progression.max_tier():
		mb.text = "Nivel máximo"
		mb.disabled = true
	else:
		mb.text = "Fusionar %d → 1 %s" % [need, Progression.tier_name(tier + 1)]
		mb.disabled = not r.can_merge(selected)
	mb.pressed.connect(func() -> void: r.merge(selected))
	_detail.add_child(mb)
	var mall := Button.new()
	mall.focus_mode = Control.FOCUS_NONE
	mall.text = "Fusionar todo"
	var any := false
	for k in r.bag:
		if r.can_merge(k):
			any = true
	mall.disabled = not any
	mall.pressed.connect(func() -> void: r.merge_all())
	_detail.add_child(mall)

	var p := r.get_member(uid)
	if p:
		var eq := Button.new()
		eq.focus_mode = Control.FOCUS_NONE
		eq.text = "Equipar en %s" % p.display_name()
		var sel := selected
		eq.pressed.connect(func() -> void: r.equip(p, sel))
		_detail.add_child(eq)
		var held: PackedStringArray = []
		for k in p.held:
			held.append("%s %s" % [Progression.item_name(k), Progression.item_summary(k)])
		_detail.add_child(Widgets.wrapped("Lleva: " + (", ".join(held) if not held.is_empty() else "nada") + " (%d/%d)" % [p.held.size(), PokemonInstance.HELD_MAX], Palette.WOOD, 190))
