class_name TreePage
extends VBoxContainer
## Árbol del entrenador: mejoras para todo el equipo pagadas con monedas, en cuatro ramas.
## Los nodos piden niveles de otros nodos (se ve en el detalle). Se elige uno y se mejora.

var selected := "fuerza"

var _cols: HBoxContainer
var _info: VBoxContainer
var _buttons := {}


func _init() -> void:
	add_theme_constant_override("separation", 3)
	_cols = Widgets.hbox(3)
	_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_cols)
	var panel := Widgets.slot_panel()
	panel.custom_minimum_size = Vector2(0, 56)
	add_child(panel)
	_info = Widgets.vbox(1)
	panel.add_child(_info)


func refresh() -> void:
	Widgets.clear(_cols)
	_buttons.clear()
	var group := ButtonGroup.new()
	var r := Game.roster
	for br in Progression.branches():
		var col := Widgets.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cols.add_child(col)
		var band := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.by_name(br["color"])
		sb.set_content_margin_all(1)
		band.add_theme_stylebox_override("panel", sb)
		var head := Widgets.label(br["name_es"], Palette.INK)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		band.add_child(head)
		col.add_child(band)
		for n in Progression.nodes():
			if n["branch"] != br["id"]:
				continue
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lv := r.skill_level(n["id"])
			var st := r.skill_state(n["id"])
			var tail := "MÁX" if st == "max" else ("—" if st == "locked" else "%d/%d" % [lv, int(n["max"])])
			b.text = "%s  %s" % [n["name_es"], tail]
			if st == "locked":
				for k in ["font_color", "font_hover_color", "font_pressed_color"]:
					b.add_theme_color_override(k, Palette.OAK)
			elif st == "max":
				for k in ["font_color", "font_hover_color", "font_pressed_color"]:
					b.add_theme_color_override(k, Palette.FOREST)
			b.button_pressed = n["id"] == selected
			b.pressed.connect(_select.bind(n["id"]))
			col.add_child(b)
			_buttons[n["id"]] = b
	_fill_info()


func _select(id: String) -> void:
	selected = id
	_fill_info()


func _value_text(n: Dictionary, lv: int) -> String:
	var v := float(n["per_level"]) * lv
	var num := ("%.1f" % v).trim_suffix(".0")
	return "+%s" % num if n["effect"] == "pets" else "+%s%%" % num


func _fill_info() -> void:
	Widgets.clear(_info)
	var n := Progression.node(selected)
	if n.is_empty():
		return
	var r := Game.roster
	var lv := r.skill_level(selected)
	var st := r.skill_state(selected)
	var top := Widgets.hbox(4)
	_info.add_child(top)
	var left := Widgets.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(left)
	left.add_child(Widgets.label("%s  Nv. %d/%d" % [n["name_es"], lv, int(n["max"])], Palette.BARK))
	left.add_child(Widgets.wrapped(n["desc_es"], Palette.INK, 300))
	var eff := "Ahora: %s" % _value_text(n, lv)
	if st != "max":
		eff += "  →  %s" % _value_text(n, lv + 1)
	left.add_child(Widgets.label(eff, Palette.FOREST))
	var buy := Widgets.buy_button(Progression.node_cost(selected, lv) if st != "max" else 0, st)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(func() -> void:
		if r.buy_skill(selected):
			refresh())
	top.add_child(buy)
	if st == "locked":
		var need: PackedStringArray = []
		for q in n["requires"]:
			if r.skill_level(q["id"]) < int(q["level"]):
				need.append("%s Nv. %d" % [Progression.node(q["id"])["name_es"], int(q["level"])])
		left.add_child(Widgets.label("Requiere: " + ", ".join(need), Palette.EMBER))
