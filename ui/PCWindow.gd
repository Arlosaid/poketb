class_name PCWindow
extends Window
## La PC: ventana nativa pequeña (transitoria de la principal, así que no aparece en la
## barra de tareas) con marco propio. Pestañas: Equipo (los que pelean + cajas + detalle),
## Mascotas (las que viven en casa + cajas + detalle), Entrenar
## (vitaminas, movimientos, objetos), Mochila (fusionar y equipar), Árbol del entrenador,
## Bayas y Créditos. Las monedas se ven siempre arriba.

const LOGICAL := Vector2i(504, 262)
const FLAVORS: Array[String] = ["spicy", "dry", "sweet", "bitter", "sour"]
const STAT_ES := {"atk": "Ata", "def": "Def", "spa": "AtEsp", "spd": "DefEsp", "spe": "Vel"}

var px_scale := 2
var selected_uid := 0

var _pages := {}
var _tab_buttons := {}
## Pestañas de Pokémon: id → {"zone": "team"|"pets", "cells", "grid", "detail"}.
var _mon_pages := {}
## Ficha de la pestaña de Pokémon que se ve.
var _detail: VBoxContainer
var _berry_list: VBoxContainer
var _gold: Label
var _train: TrainPage
var _bag: BagPage
var _tree: TreePage
var _current := "pokemon"
var _drag_from := Vector2i.ZERO
var _drag_win := Vector2i.ZERO
var _dragging := false


func _init(scale_px: int) -> void:
	px_scale = scale_px
	title = "PC Pokémon"
	borderless = true
	transparent = true
	transparent_bg = true
	unresizable = true
	# sin always_on_top: al ser transitoria de la principal (que sí lo es) queda encima igual
	transient = true
	wrap_controls = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	content_scale_size = LOGICAL
	size = LOGICAL * px_scale
	theme = UiTheme.theme()


func _ready() -> void:
	var root := PanelContainer.new()
	root.size = Vector2(LOGICAL)
	add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	root.add_child(v)

	# barra de título (arrastrable)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	bar.gui_input.connect(_on_title_input)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(bar)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/pokeball_8.png")
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bar.add_child(icon)
	var t := Label.new()
	t.text = "PC"
	bar.add_child(t)
	var coin := TextureRect.new()
	coin.texture = Progression.coin_icon()
	coin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bar.add_child(coin)
	_gold = Label.new()
	_gold.add_theme_color_override("font_color", Palette.BARK)
	_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_gold)
	var group := ButtonGroup.new()
	for id in ["pokemon", "mascotas", "entrenar", "mochila", "arbol", "bayas", "creditos"]:
		var b := Button.new()
		b.text = {"pokemon": "Equipo", "mascotas": "Mascotas", "entrenar": "Entrenar", "mochila": "Mochila", "arbol": "Árbol", "bayas": "Bayas", "creditos": "Créditos"}[id]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(show_tab.bind(id))
		bar.add_child(b)
		_tab_buttons[id] = b
	var close_b := Button.new()
	close_b.text = "×"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	bar.add_child(close_b)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_pages["pokemon"] = _build_pokemon_page("pokemon", "team")
	_pages["mascotas"] = _build_pokemon_page("mascotas", "pets")
	_train = TrainPage.new()
	_train.pick.connect(_select)
	_pages["entrenar"] = _train
	_bag = BagPage.new()
	_bag.pick.connect(_select)
	_pages["mochila"] = _bag
	_tree = TreePage.new()
	_pages["arbol"] = _tree
	_pages["bayas"] = _build_berries_page()
	_pages["creditos"] = _build_credits_page()
	for k in _pages:
		var p: Control = _pages[k]
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		body.add_child(p)

	Game.roster.changed.connect(refresh)
	Game.roster.berries_changed.connect(_fill_berries)
	Game.roster.wallet_changed.connect(_on_wallet)
	close_requested.connect(close)
	show_tab("pokemon")
	refresh()


func close() -> void:
	queue_free()


func show_tab(id: String) -> void:
	_current = id
	for k in _pages:
		_pages[k].visible = (k == id)
	_tab_buttons[id].button_pressed = true
	if _mon_pages.has(id) and is_inside_tree():
		# al cambiar de pestaña, la ficha muestra a alguien de esa fila
		var row: Array = Game.roster.team if _mon_pages[id]["zone"] == "team" else Game.roster.pets
		if not row.is_empty() and selected_uid not in row:
			selected_uid = row[0]
		refresh()
	else:
		_refresh_current()


func _on_wallet() -> void:
	_gold.text = "%d" % Game.roster.gold
	_refresh_current()


## Solo se reconstruye la pestaña que se ve (las demás se arman al abrirlas).
func _refresh_current() -> void:
	if not is_inside_tree() or _gold == null:
		return
	_gold.text = "%d" % Game.roster.gold
	_train.uid = selected_uid
	_bag.uid = selected_uid
	match _current:
		"entrenar":
			_train.refresh()
		"mochila":
			_bag.refresh()
		"arbol":
			_tree.refresh()


# ------------------------------------------------------------------ Pokémon

## Página de Pokémon: arriba la fila de la zona (`team`: los que pelean; `pets`: las
## mascotas, que viven en casa y no pelean), abajo las cajas y a la derecha la ficha.
func _build_pokemon_page(id: String, zone: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 1)
	h.add_child(left)
	if zone == "team":
		left.add_child(_caption("Equipo: pelean en la ruta"))
	else:
		left.add_child(_caption("Mascotas: viven en casa, no pelean"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	left.add_child(row)
	var cells: Array[MonCell] = []
	for i in (Roster.TEAM_MAX if zone == "team" else Roster.PETS_MAX):
		var c := MonCell.new(zone, i)
		c.picked.connect(_select)
		c.dropped.connect(_on_drop)
		row.add_child(c)
		cells.append(c)
	left.add_child(_caption("Cajas (arrastra para mover)"))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(6 * 45, 92)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	sc.add_child(grid)

	var dp := PanelContainer.new()
	dp.theme_type_variation = &"Slot"
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(dp)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 1)
	dp.add_child(detail)
	_mon_pages[id] = {"zone": zone, "cells": cells, "grid": grid, "detail": detail}
	return h


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.WOOD)
	return l


func refresh() -> void:
	if not is_inside_tree():
		return
	var r := Game.roster
	if selected_uid == 0 or r.get_member(selected_uid) == null:
		selected_uid = r.companion
	# Solo se arma la pestaña de Pokémon que se ve.
	if _mon_pages.has(_current):
		var pg: Dictionary = _mon_pages[_current]
		var top: Array[PokemonInstance] = r.team_members() if pg["zone"] == "team" else r.pet_members()
		var cells: Array = pg["cells"]
		for i in cells.size():
			var cell: MonCell = cells[i]
			cell.show_mon(top[i] if i < top.size() else null)
			cell.selected = cell.uid == selected_uid and selected_uid != 0
		var grid: GridContainer = pg["grid"]
		for c in grid.get_children():
			c.queue_free()
		var box := r.box_members()
		box.sort_custom(func(a: PokemonInstance, b: PokemonInstance) -> bool: return a.uid < b.uid)
		var n := maxi(12, int(ceil((box.size() + 1) / 6.0)) * 6)
		for i in n:
			var c := MonCell.new("box", i)
			c.picked.connect(_select)
			c.dropped.connect(_on_drop)
			c.show_mon(box[i] if i < box.size() else null)
			c.selected = c.uid == selected_uid and selected_uid != 0
			grid.add_child(c)
		_detail = pg["detail"]
		_fill_detail()
	_refresh_current()


func _select(uid: int) -> void:
	selected_uid = uid
	refresh()


func _on_drop(data: Dictionary, target: MonCell) -> void:
	var r := Game.roster
	var uid := int(data["uid"])
	selected_uid = uid
	if target.zone == "box":
		if uid in r.team:
			var team: Array[int] = r.team.duplicate()
			team.erase(uid)
			r.set_team(team)
		elif r.is_pet(uid):
			r.toggle_pet(uid)
		return
	var cap := Roster.TEAM_MAX if target.zone == "team" else Roster.PETS_MAX
	var list: Array[int] = (r.team if target.zone == "team" else r.pets).duplicate()
	var cur := list.find(uid)
	if cur >= 0:
		# reordenar dentro de la misma fila
		list.remove_at(cur)
		list.insert(mini(target.index, list.size()), uid)
	elif target.uid != 0:
		# reemplaza al que estaba en esa casilla (que va a la caja)
		list[list.find(target.uid)] = uid
	elif list.size() < cap:
		list.append(uid)
	if target.zone == "team":
		r.set_team(list)
	else:
		r.set_pets(list)


func _fill_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var p := Game.roster.get_member(selected_uid)
	if p == null:
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	_detail.add_child(top)
	var fr := PanelContainer.new()
	fr.theme_type_variation = &"Slot"
	top.add_child(fr)
	var tr := TextureRect.new()
	var emo := "Happy" if p.friendship >= 150 else ("Worried" if p.is_grumpy() else "Normal")
	tr.texture = PokemonActor.portrait(p.species, [emo])
	tr.custom_minimum_size = Vector2(40, 40)
	fr.add_child(tr)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	top.add_child(nv)
	nv.add_child(_text(p.display_name()))
	nv.add_child(_text("Nv. %d" % p.level, Palette.WOOD))
	nv.add_child(_text("/".join(p.types().map(func(t): return SpeciesDB.type_es(t))), Palette.WOOD))
	nv.add_child(_hearts(p.friendship))

	var nat := SpeciesDB.nature(p.nature)
	var nat_txt: String = nat["name_es"]
	if nat["increased"] != null:
		nat_txt += " (+%s −%s)" % [STAT_ES[nat["increased"]], STAT_ES[nat["decreased"]]]
	_detail.add_child(_text("Naturaleza: " + nat_txt, Palette.BARK))
	if p.ability() != "":
		var ab := _wrap("Habilidad: %s. %s" % [p.ability_es(), SpeciesDB.ability(p.ability())["desc_es"]], Palette.BARK)
		_detail.add_child(ab)
	_detail.add_child(_bar_row("PS", p.hp_frac(), false, "%d/%d" % [p.hp, p.max_hp()]))
	_detail.add_child(_bar_row("Saciedad", p.fullness / 100.0, false))
	_detail.add_child(_bar_row("Energía", p.energy / 100.0, true))
	_detail.add_child(_text("Sabores:", Palette.BARK))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	_detail.add_child(fl)
	for f in FLAVORS:
		var k: String = p.known_flavors.get(f, "")
		var mark: String = {"likes": "♥", "hates": "×", "neutral": "·"}.get(k, "?")
		var col: Color = {"likes": Palette.EMBER, "hates": Palette.DUSK, "neutral": Palette.OAK}.get(k, Palette.TAN)
		fl.add_child(_text("%s %s" % [SpeciesDB.flavor_es(f), mark], col))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 2)
	_detail.add_child(btns)
	var cb := Button.new()
	cb.text = "★ Compañero" if p.uid == Game.roster.companion else "Compañero"
	cb.disabled = p.uid == Game.roster.companion
	cb.focus_mode = Control.FOCUS_NONE
	cb.pressed.connect(func() -> void: Game.roster.set_companion(p.uid))
	btns.add_child(cb)
	# Dónde vive: en el equipo (pelea), de mascota (en casa) o en la caja. Solo uno a la vez.
	var r := Game.roster
	var in_team := p.uid in r.team
	var is_pet := r.is_pet(p.uid)
	if not in_team:
		var tb := Button.new()
		tb.text = "Al equipo"
		tb.tooltip_text = "Pelea en la ruta. Máximo %d." % Roster.TEAM_MAX
		tb.disabled = r.team.size() >= Roster.TEAM_MAX
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func() -> void:
			var team: Array[int] = r.team.duplicate()
			team.append(p.uid)
			r.set_team(team))
		btns.add_child(tb)
	if not is_pet:
		var pb := Button.new()
		pb.text = "A mascotas"
		pb.tooltip_text = "Sale del equipo, vive en casa y no pelea. Máximo %d." % Roster.PETS_MAX
		pb.disabled = r.pets_full()
		pb.focus_mode = Control.FOCUS_NONE
		pb.pressed.connect(r.toggle_pet.bind(p.uid))
		btns.add_child(pb)
	if in_team or is_pet:
		var xb := Button.new()
		xb.text = "A la caja"
		xb.focus_mode = Control.FOCUS_NONE
		xb.pressed.connect(func() -> void:
			if is_pet:
				r.toggle_pet(p.uid)
			else:
				var team: Array[int] = r.team.duplicate()
				team.erase(p.uid)
				r.set_team(team))
		btns.add_child(xb)


func _text(t: String, c: Color = Palette.INK) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", c)
	return l


## Amistad en 5 corazones (cada uno ~51 puntos de 255).
func _hearts(f: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 1)
	var full := int(round(f / 51.0))
	for i in 5:
		var t := TextureRect.new()
		t.texture = load("res://assets/ui/heart.png" if i < full else "res://assets/ui/heart_empty.png")
		h.add_child(t)
	return h


func _bar_row(label: String, frac: float, exp_style: bool, value := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	var l := _text(label, Palette.BARK)
	l.custom_minimum_size = Vector2(44, 0)
	h.add_child(l)
	var b := HpBar.new(46, 5, exp_style)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_instant(frac)
	h.add_child(b)
	if value != "":
		h.add_child(_text(value, Palette.WOOD))
	return h


# ------------------------------------------------------------------ Bayas

func _build_berries_page() -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_berry_list = VBoxContainer.new()
	_berry_list.add_theme_constant_override("separation", 1)
	_berry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_berry_list)
	_fill_berries()
	return sc


func _fill_berries() -> void:
	if _berry_list == null:
		return
	for c in _berry_list.get_children():
		c.queue_free()
	var inv := Game.roster.berries
	if inv.is_empty():
		_berry_list.add_child(_text("No tienes bayas. Caen al ganar combates.", Palette.WOOD))
		return
	var names := inv.keys()
	names.sort()
	for b in names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var ic := TextureRect.new()
		ic.texture = BerryMenu.icon(b)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(ic)
		var d := SpeciesDB.berry(b)
		var f := SpeciesDB.dominant_flavor(b)
		row.add_child(_text("%s ×%d" % [d["name_es"], int(inv[b])]))
		var extra := SpeciesDB.flavor_es(f) if f != "" else "Varios sabores"
		if b == "oran":
			extra += " · cura 10 PS"
		elif b == "sitrus":
			extra += " · cura 1/4 de PS"
		row.add_child(_text("— " + extra, Palette.WOOD))
		_berry_list.add_child(row)


# ------------------------------------------------------------------ Créditos

func _build_credits_page() -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var cred: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_credits.json"))
	v.add_child(_wrap("Proyecto personal y no comercial. Pokémon es de Nintendo, Creatures Inc. y GAME FREAK inc.", Palette.WOOD))
	v.add_child(_text("Sprites y retratos: PMD SpriteCollab (%s)" % cred["license"]))
	var lines := PackedStringArray()
	for e in cred["species"]:
		if not SpeciesDB.has_sprite(e["name"]):
			continue
		var names := {}
		for k in ["sprite_authors", "portrait_authors"]:
			for a in e.get(k, []):
				var n: String = a["name"]
				names["usuario anónimo de Discord" if n.begins_with("<@") else n] = true
		lines.append("%s: %s" % [SpeciesDB.species(e["name"])["name_es"], ", ".join(names.keys())])
	# un solo Label: con ~1000 especies, un Label por línea tarda en armarse
	v.add_child(_wrap("
".join(lines), Palette.BARK))
	v.add_child(_text("Fuente: Ark Pixel Font, de TakWolf (OFL 1.1)"))
	v.add_child(_text("Datos: PokéAPI"))
	v.add_child(_wrap("Marcos, íconos, bayas, fondos y cielo: hechos para este proyecto.", Palette.BARK))
	return sc


func _wrap(t: String, c: Color) -> Label:
	var l := _text(t, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(LOGICAL.x - 24, 0)
	return l


# ------------------------------------------------------------------ mover la ventana

func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_from = DisplayServer.mouse_get_position()
		_drag_win = position
	elif event is InputEventMouseMotion and _dragging:
		position = _drag_win + (DisplayServer.mouse_get_position() - _drag_from)
