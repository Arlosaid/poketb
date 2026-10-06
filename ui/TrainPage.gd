class_name TrainPage
extends VBoxContainer
## Entrenar: para el Pokémon elegido, vitaminas (suben un stat, cuestan monedas), movimientos
## (elegir los 4 activos y subir su maestría) y los dos objetos que lleva.

signal pick(uid: int)

var uid := 0

var _picker: MonPicker
var _vit: VBoxContainer
var _moves: VBoxContainer
var _held: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 3)
	_picker = MonPicker.new()
	_picker.picked.connect(func(u: int) -> void: pick.emit(u))
	add_child(_picker)
	var cols := Widgets.hbox(5)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
	_vit = _column(cols, 186, false)
	_moves = _column(cols, 164, true)
	_held = _column(cols, 92, false)


func _column(parent: Control, width: int, scroll: bool) -> VBoxContainer:
	var panel := Widgets.slot_panel()
	panel.custom_minimum_size = Vector2(width, 0)
	parent.add_child(panel)
	var v := Widgets.vbox(1)
	if scroll:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(sc)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
	else:
		panel.add_child(v)
	return v


func refresh() -> void:
	var p := Game.roster.get_member(uid)
	_picker.show_mon(p)
	Widgets.clear(_vit)
	Widgets.clear(_moves)
	Widgets.clear(_held)
	if p == null:
		return
	_fill_vitamins(p)
	_fill_moves(p)
	_fill_held(p)


func _fill_vitamins(p: PokemonInstance) -> void:
	_vit.add_child(Widgets.label("Vitaminas (+%d%% c/u)" % int(Progression.vitamin_cfg()["pct_per_dose"]), Palette.WOOD))
	var max_doses := int(Progression.vitamin_cfg()["max"])
	for stat in Progression.vitamin_stats():
		var vd: Dictionary = Progression.vitamins()[stat]
		var row := Widgets.hbox(3)
		var ic := TextureRect.new()
		ic.texture = Progression.vitamin_icon(stat)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(ic)
		var nm := Widgets.label(vd["name_es"])
		nm.custom_minimum_size = Vector2(46, 0)
		row.add_child(nm)
		var val := Widgets.label("%s %d" % [vd["stat_es"], p.stat(stat)], Palette.WOOD)
		val.custom_minimum_size = Vector2(34, 0)
		row.add_child(val)
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(gap)
		row.add_child(Pips.new(max_doses, p.vitamin_doses(stat), Palette.by_name(vd["color"])))
		var st := Game.roster.vitamin_state(p, stat)
		var b := Widgets.buy_button(Progression.vitamin_cost(p, stat), st)
		b.custom_minimum_size = Vector2(36, 0)
		b.pressed.connect(func() -> void: Game.roster.buy_vitamin(p, stat))
		row.add_child(b)
		_vit.add_child(row)


func _fill_moves(p: PokemonInstance) -> void:
	_moves.add_child(Widgets.label("Movimientos  %d/%d" % [p.moves.size(), PokemonInstance.MAX_MOVES], Palette.WOOD))
	var avail := p.available_moves()
	avail.reverse()
	var mp := float(Progression.mastery_cfg()["pct_per_level"])
	var mmax := int(Progression.mastery_cfg()["max"])
	for m in avail:
		var md := SpeciesDB.move(m)
		var row := Widgets.hbox(3)
		var on: bool = m in p.moves
		var t := Button.new()
		t.text = "●" if on else "○"
		t.focus_mode = Control.FOCUS_NONE
		t.custom_minimum_size = Vector2(14, 0)
		t.disabled = (not on and p.moves.size() >= PokemonInstance.MAX_MOVES) or (on and p.moves.size() <= 1)
		t.pressed.connect(func() -> void: Game.roster.toggle_move(p, m))
		row.add_child(t)
		var nm := Widgets.label(md["name_es"], Palette.INK if on else Palette.WOOD)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(40, 0)
		row.add_child(nm)
		var pw := int(round(float(md["power"]) * (1.0 + p.mastery(m) * mp / 100.0)))
		row.add_child(Widgets.label("%d" % pw, Palette.BARK))
		row.add_child(Pips.new(mmax, p.mastery(m), Palette.EMBER))
		var b := Widgets.buy_button(Progression.mastery_cost(p, m), Game.roster.mastery_state(p, m))
		b.custom_minimum_size = Vector2(34, 0)
		b.pressed.connect(func() -> void: Game.roster.buy_mastery(p, m))
		row.add_child(b)
		_moves.add_child(row)


func _fill_held(p: PokemonInstance) -> void:
	_held.add_child(Widgets.label("Objetos", Palette.WOOD))
	for i in PokemonInstance.HELD_MAX:
		var key := p.held[i] if i < p.held.size() else ""
		var row := Widgets.hbox(3)
		var cell := ItemCell.new(key)
		if key != "":
			cell.pressed.connect(func() -> void: Game.roster.unequip(p, i))
		row.add_child(cell)
		var v := Widgets.vbox(0)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if key == "":
			v.add_child(Widgets.label("Vacío", Palette.OAK))
		else:
			v.add_child(Widgets.label(Progression.item_summary(key), Palette.FOREST))
			v.add_child(Widgets.label(Progression.tier_name(Progression.key_tier(key)), Progression.tier_color(Progression.key_tier(key)).darkened(0.25)))
		row.add_child(v)
		_held.add_child(row)
	_held.add_child(Widgets.wrapped("Toca uno para quitarlo. Se equipan desde la Mochila.", Palette.WOOD, 80))
