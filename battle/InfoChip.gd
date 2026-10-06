class_name InfoChip
extends Control
## Ficha compacta sobre el cielo del panel: "Nombre Nv.X", barra de PS y (para los
## nuestros) una barra fina de EXP. Texto PAPER con contorno INK para leerse sobre
## cualquier cielo.

var label: Label
var hp: HpBar
var xp: HpBar
var align_right := false
var mon: PokemonInstance


func _init(right := false, with_exp := true) -> void:
	align_right = right
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.add_theme_color_override("font_color", Palette.PAPER)
	label.add_theme_color_override("font_shadow_color", Palette.INK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	hp = HpBar.new(40, 4)
	add_child(hp)
	if with_exp:
		xp = HpBar.new(40, 3, true)
		add_child(xp)
	modulate.a = 0.0


func bind(p: PokemonInstance, boss := false) -> void:
	mon = p
	refresh(true)
	if boss:
		label.add_theme_color_override("font_color", Palette.HONEY)


func refresh(instant := false) -> void:
	if mon == null:
		return
	label.text = "%s Nv.%d" % [mon.display_name(), mon.level]
	label.reset_size()
	if instant:
		hp.set_instant(mon.hp_frac())
		if xp:
			xp.set_instant(mon.exp_frac())
	else:
		hp.frac = mon.hp_frac()
		if xp:
			xp.frac = mon.exp_frac()
	_layout()


func _layout() -> void:
	var w := maxf(label.size.x, hp.size.x)
	var x_label := (w - label.size.x) if align_right else 0.0
	var x_bar := (w - hp.size.x) if align_right else 0.0
	label.position = Vector2(x_label, -3)
	hp.position = Vector2(x_bar, 11)
	if xp:
		xp.position = Vector2(x_bar, 14)
	size = Vector2(w, 17)


func appear(on: bool) -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "modulate:a", 1.0 if on else 0.0, 0.2)
