class_name OfflineSummary
extends PanelContainer
## Resumen breve de lo que pasó mientras el juego estuvo cerrado.

const LIFE := 30.0

var _life := LIFE


static func show_in(hud: Control, s: Dictionary, companion_species: String) -> OfflineSummary:
	var p := OfflineSummary.new()
	hud.add_child(p)
	p._build(s, companion_species)
	return p


static func duration_text(sec: float) -> String:
	var m := int(sec / 60.0)
	if m < 60:
		return "%d min" % maxi(1, m)
	return "%d h %02d min" % [m / 60, m % 60]


func _build(s: Dictionary, companion: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	add_child(row)
	if companion != "":
		var fr := PanelContainer.new()
		fr.theme_type_variation = &"Slot"
		fr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(fr)
		var tr := TextureRect.new()
		tr.texture = Bubble.portrait_for(companion, "Happy")
		tr.custom_minimum_size = Vector2(40, 40)
		fr.add_child(tr)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	row.add_child(v)
	var title := Label.new()
	title.text = "Mientras no estabas (%s%s)" % [duration_text(s["seconds"]), ", máx. 8 h" if s.get("capped", false) else ""]
	v.add_child(title)
	# Compacto: cabe en la franja (máx. 3 renglones además del título).
	var lines: PackedStringArray = []
	var evos: PackedStringArray = []
	var ups := 0
	var best := {}
	for m in s["mons"]:
		if m["evolved_to"] != "":
			evos.append(m["evolved_to"])
		if int(m["to_level"]) > int(m["from_level"]):
			ups += 1
			if best.is_empty() or int(m["to_level"]) - int(m["from_level"]) > int(best["to_level"]) - int(best["from_level"]):
				best = m
	var bt := 0
	for b in s["berries"]:
		bt += int(s["berries"][b])
	var it := 0
	for k in s.get("items", {}):
		it += int(s["items"][k])
	var first := "Ganaron %d combates" % int(s["wins"]) if int(s["wins"]) > 0 else "Descansaron tranquilos en casa"
	var gold := int(s.get("gold", 0))
	lines.append(first + (" y juntaron %d monedas." % gold if gold > 0 else "."))
	var found: PackedStringArray = []
	if bt > 0:
		found.append("%d baya%s" % [bt, "" if bt == 1 else "s"])
	if it > 0:
		found.append("%d objeto%s" % [it, "" if it == 1 else "s"])
	if not found.is_empty():
		lines.append("Encontraron " + " y ".join(found) + ".")
	if not evos.is_empty():
		var shown := evos.slice(0, 2)
		lines.append(("¡Nueva evolución: %s!" if evos.size() == 1 else "¡Nuevas evoluciones: %s!") % (" y ".join(shown) + (" (+%d)" % (evos.size() - 2) if evos.size() > 2 else "")))
	elif not best.is_empty():
		lines.append("%s: Nv. %d → %d%s" % [best["name"], best["from_level"], best["to_level"], (" (y %d más subieron)" % (ups - 1)) if ups > 1 else ""])
	if lines.size() < 4 and s["mons"].any(func(m): return m["hungry"]):
		lines.append("Alguien tiene hambre… ¡dale una baya!")
	for t in lines:
		var l := Label.new()
		l.text = t
		l.add_theme_color_override("font_color", Palette.BARK)
		v.add_child(l)
	var ok := Button.new()
	ok.text = "¡Genial!"
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_vertical = Control.SIZE_SHRINK_END
	ok.pressed.connect(close)
	row.add_child(ok)
	Passthrough.register(self)
	reset_size()
	position = Vector2(12, maxf(1.0, get_viewport_rect().size.y - size.y - 30.0)).round()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


func get_click_rect() -> Rect2:
	return get_global_rect()


func _process(delta: float) -> void:
	if Passthrough.hovered() == self:
		return
	_life -= delta
	if _life <= 0.0:
		close()


func close() -> void:
	set_process(false)
	Passthrough.unregister(self)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)
