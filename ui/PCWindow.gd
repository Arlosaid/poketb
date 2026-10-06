class_name PCWindow
extends Window
## La PC: ventana nativa pequeña (transitoria de la principal, así que no aparece en la
## barra de tareas) con marco propio. Pestañas: Pokémon (equipo + cajas + detalle), Entrenar
## (vitaminas, movimientos, objetos), Mochila (fusionar y equipar), Árbol del entrenador,
## Bayas y Créditos. Las monedas se ven siempre arriba.

const LOGICAL := Vector2i(504, 262)
const FLAVORS: Array[String] = ["spicy", "dry", "sweet", "bitter", "sour"]
const STAT_ES := {"atk": "Ata", "def": "Def", "spa": "AtEsp", "spd": "DefEsp", "spe": "Vel"}

var px_scale := 2
var selected_uid := 0

var _pages := {}
var _tab_buttons := {}
var _team_cells: Array[MonCell] = []
var _box_grid: GridContainer
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
	for id in ["pokemon", "entrenar", "mochila", "arbol", "bayas", "creditos"]:
		var b := Button.new()
		b.text = {"pokemon": "Pokémon", "entrenar": "Entrenar", "mochila": "Mochila", "arbol": "Árbol", "bayas": "Bayas", "creditos": "Créditos"}[id]
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
	_pages["pokemon"] = _build_pokemon_page()
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

func _build_pokemon_page() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 1)
	h.add_child(left)
	left.add_child(_caption("Equipo"))
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 1)
	left.add_child(team_row)
	for i in Roster.TEAM_MAX:
		var c := MonCell.new("team", i)
		c.picked.connect(_select)
		c.dropped.connect(_on_drop)
		team_row.add_child(c)
		_team_cells.append(c)
	left.add_child(_caption("Cajas"))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(6 * 45, 92)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sc)
	_box_grid = GridContainer.new()
	_box_grid.columns = 6
	_box_grid.add_theme_constant_override("h_separation", 1)
	_box_grid.add_theme_constant_override("v_separation", 1)
	sc.add_child(_box_grid)

	var dp := PanelContainer.new()
	dp.theme_type_variation = &"Slot"
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(dp)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 1)
	dp.add_child(_detail)
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
	var team := r.team_members()
	for i in _team_cells.size():
		_team_cells[i].show_mon(team[i] if i < team.size() else null)
		_team_cells[i].selected = _team_cells[i].uid == selected_uid and selected_uid != 0
	for c in _box_grid.get_children():
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
		_box_grid.add_child(c)
	if selected_uid == 0 or r.get_member(selected_uid) == null:
		selected_uid = r.companion
	_fill_detail()
	_refresh_current()


func _select(uid: int) -> void:
	selected_uid = uid
	refresh()


func _on_drop(data: Dictionary, target: MonCell) -> void:
	var r := Game.roster
	var team: Array[int] = r.team.duplicate()
	var uid := int(data["uid"])
	if target.zone == "team":
		var cur := team.find(uid)
		if cur >= 0:
			# reordenar dentro del equipo
			team.remove_at(cur)
			team.insert(mini(target.index, team.size()), uid)
		elif target.uid != 0:
			# reemplaza al que estaba en esa casilla (que va a la caja)
			team[team.find(target.uid)] = uid
		elif team.size() < Roster.TEAM_MAX:
			team.append(uid)
	elif target.zone == "box" and uid in team and team.size() > 1:
		team.erase(uid)
	r.set_team(team)
	selected_uid = uid


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
	var in_team := p.uid in Game.roster.team
	var tb := Button.new()
	tb.text = "A la caja" if in_team else "Al equipo"
	tb.disabled = (in_team and Game.roster.team.size() <= 1) or (not in_team and Game.roster.team.size() >= Roster.TEAM_MAX)
	tb.focus_mode = Control.FOCUS_NONE
	tb.pressed.connect(func() -> void:
		var team: Array[int] = Game.roster.team.duplicate()
		if in_team:
			team.erase(p.uid)
		else:
			team.append(p.uid)
		Game.roster.set_team(team))
	btns.add_child(tb)
	# mascota: pasea por la casa (esté en el equipo o en las cajas)
	var is_pet := Game.roster.is_pet(p.uid)
	var pb := Button.new()
	pb.text = "♥ Mascota" if is_pet else "Mascota"
	pb.tooltip_text = "Se queda en casa y no pelea. Máximo %d a la vez." % Roster.PETS_MAX
	pb.disabled = not is_pet and Game.roster.pets_full()
	pb.focus_mode = Control.FOCUS_NONE
	pb.pressed.connect(Game.roster.toggle_pet.bind(p.uid))
	btns.add_child(pb)


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
