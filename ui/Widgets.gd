class_name Widgets
extends RefCounted
## Piezas pequeñas compartidas por las pestañas de la PC.


static func label(t: String, c: Color = Palette.INK) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", c)
	return l


static func wrapped(t: String, c: Color, width: float) -> Label:
	var l := label(t, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


## Botón de compra: ícono de moneda y costo. `state`: "ok", "poor" (sin monedas), "max", "locked".
static func buy_button(cost: int, state: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	match state:
		"max":
			b.text = "MÁX"
			b.disabled = true
		"locked":
			b.text = "—"
			b.disabled = true
		_:
			b.text = "%d" % cost
			b.icon = Progression.coin_icon()
			b.disabled = state != "ok"
	return b


static func hbox(sep := 3) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 1) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func slot_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"Slot"
	return p


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()
