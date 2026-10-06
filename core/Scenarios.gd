class_name Scenarios
extends Node
## Escenarios automatizados para validar el acabado visual: colocan cosas, fuerzan
## la hora, sacan capturas del viewport (Game.shot) y cierran el juego.
## Uso: godot --path . -- --scenario=<nombre>

var main: Node


func run(m: Node, scenario_name: String) -> void:
	main = m
	Game.forced_idle = 0.0  # resultados deterministas: el usuario "está activo"
	await get_tree().process_frame
	match scenario_name:
		"still":
			await _still()
		"gallery":
			await _gallery()
		"pet":
			await _pet()
		"battle":
			await _battle()
		"showcase":
			await _showcase()
		"save_write":
			await _save_write()
		"save_load":
			await _save_load()
		_:
			push_error("Escenario desconocido: " + scenario_name)
	Game.quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _still() -> void:
	Game.set_mode(Game.MODE_REST)
	await _wait(0.5)
	var a: PokemonActor = main.home.actor_for(Game.roster.companion)
	var b: PetBrain = main.home.brain_for(Game.roster.companion)
	a.position.x = 100
	b.force_state(PetBrain.State.IDLE, 1e9)
	a.play_anim("Idle", "S")
	await _wait(1.0)
	await Game.shot("p1_still")
	await _wait(20.0)


func _gallery() -> void:
	var roster: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/pokemon_roster.json"))["species"]
	var actors: Array[PokemonActor] = []
	for i in roster.size():
		var a := PokemonActor.new()
		a.species = roster[i]["name"]
		a.interactive = false
		main.world.add_child(a)
		a.position = Vector2(18 + i * 32, main.desk.ground_y())
		actors.append(a)
	for anim in ["Idle", "Walk", "Attack", "Hurt", "Sleep", "Faint", "Eat", "Sit"]:
		for a in actors:
			a.play_anim(anim, "S" if anim in ["Idle", "Sleep", "Eat", "Sit"] else "E", true)
		await _wait(actors[0].hit_time(anim) if anim == "Attack" else 0.3)
		await Game.shot("p2_anim_" + anim.to_lower())
	for a in actors:
		a.queue_free()

	# Panel de pelea en cada bioma y fase del día.
	var bs: BattleStrip = main.battle
	var hero := PokemonActor.new()
	hero.species = "charmander"
	hero.interactive = false
	bs.stage.add_child(hero)
	var foe := PokemonActor.new()
	foe.species = "pidgey"
	foe.interactive = false
	bs.stage.add_child(foe)
	for biome in ["pradera", "bosque"]:
		bs.layout(BattleWindow.LOGICAL, biome, bs.px_scale)
		hero.position = Vector2(70, bs.ground_y())
		foe.position = Vector2(bs.inner.size.x - 90, bs.ground_y())
		hero.play_anim("Walk", "E")
		foe.play_anim("Idle", "W")
		for hour in [6.5, 12.0, 18.5, 23.0]:
			Game.clock.forced_hour = hour
			bs.backdrop.refresh()
			hero.modulate = DayNight.sprite_tint(hour)
			foe.modulate = hero.modulate
			for i in 20:
				bs.backdrop.scroll(1.0)
				await get_tree().process_frame
			await Game.shot("p2_strip_%s_%02d" % [biome, int(hour)])
	Game.clock.forced_hour = -1.0
	bs.layout(BattleWindow.LOGICAL, "pradera", bs.px_scale)

	# Prueba del tema de UI: panel crema, diálogo oscuro, corazones y bayas.
	var p := PanelContainer.new()
	p.position = Vector2(12, 20)
	main.hud.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var l := Label.new()
	l.text = "Charmander  Nv. 16  Firme"
	v.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 1)
	v.add_child(h)
	for i in 5:
		var t := TextureRect.new()
		t.texture = load("res://assets/ui/heart.png" if i < 3 else "res://assets/ui/heart_empty.png")
		h.add_child(t)
	var berries: Texture2D = load("res://assets/ui/berries.png")
	var hb := HBoxContainer.new()
	v.add_child(hb)
	for i in 6:
		var at := AtlasTexture.new()
		at.atlas = berries
		at.region = Rect2(i * 12, 0, 12, 12)
		var t := TextureRect.new()
		t.texture = at
		hb.add_child(t)
	var b := Button.new()
	b.text = "Dar baya"
	v.add_child(b)
	var d := PanelContainer.new()
	d.theme_type_variation = &"DialogPanel"
	d.position = Vector2(170, 40)
	main.hud.add_child(d)
	var dl := Label.new()
	dl.theme_type_variation = &"DialogLabel"
	dl.text = "¡Charmander usó Ascuas! ¡Es muy eficaz!"
	d.add_child(dl)
	await _wait(0.3)
	await Game.shot("p2_ui")


func _pet() -> void:
	Game.set_mode(Game.MODE_REST)
	var r := Game.roster
	for sp in ["pidgey", "oddish", "caterpie"]:
		r.add(PokemonInstance.create(sp, 4))
	await _wait(3.0)
	await Game.shot("p3_home")

	var cid := r.companion
	var a: PokemonActor = main.home.actor_for(cid)
	var b: PetBrain = main.home.brain_for(cid)
	b.force_state(PetBrain.State.IDLE, 1e9)
	a.position.x = 120
	await _wait(0.3)
	b.pet()
	await _wait(0.45)
	await Game.shot("p3_pet")
	await _wait(2.0)

	b.open_berries()
	await _wait(0.3)
	await Game.shot("p3_berry_menu")

	# Una baya que le guste y otra que no, según la naturaleza (regla canon).
	var picked := _pet_with_preferences()
	if picked.is_empty():
		push_warning("Ningún Pokémon con gustos (todas las naturalezas neutras)")
	else:
		var mon: PokemonInstance = picked["mon"]
		var pb: PetBrain = main.home.brain_for(mon.uid)
		var pa: PokemonActor = main.home.actor_for(mon.uid)
		pb.force_state(PetBrain.State.IDLE, 1e9)
		pa.position.x = 260
		r.add_berry(picked["like"])
		r.add_berry(picked["hate"])
		print("[pet] ", mon.species, " ", mon.nature, " le gusta ", picked["like"], " odia ", picked["hate"])
		pb.feed(picked["like"])
		await _wait(0.8)
		await Game.shot("p3_eating")
		await _wait(1.5)
		await Game.shot("p3_feed_like")
		await _wait(3.0)
		pb.feed(picked["hate"])
		await _wait(2.3)
		await Game.shot("p3_feed_hate")
		await _wait(3.0)

	# Mira al cursor.
	b.force_state(PetBrain.State.IDLE, 1e9)
	Passthrough.fake_mouse = Vector2(a.position.x + 40, 30)
	await _wait(0.4)
	await Game.shot("p3_look_right")
	Passthrough.fake_mouse = Vector2(a.position.x - 30, 95)
	await _wait(0.4)
	await Game.shot("p3_look_downleft")

	# Arrastrar y soltar.
	Passthrough.fake_mouse = Vector2(a.position.x + 20, 40)
	b.force_state(PetBrain.State.DRAG)
	await _wait(0.3)
	await Game.shot("p3_drag")
	b.force_state(PetBrain.State.FALL)
	Passthrough.fake_mouse = Vector2.INF
	await _wait(0.42)
	await Game.shot("p3_land")
	await _wait(1.0)

	# De noche y con la PC inactiva: todos se acurrucan.
	Game.clock.forced_hour = 23.0
	Game.forced_idle = 400.0
	await _wait(2.5)
	await Game.shot("p3_sleep")
	Game.forced_idle = -1.0
	Game.clock.forced_hour = -1.0


## Busca un Pokémon de casa cuya naturaleza tenga gustos y elige bayas para probar.
func _pet_with_preferences() -> Dictionary:
	var by_flavor := {}
	for bname in SpeciesDB.berries():
		var f := SpeciesDB.dominant_flavor(bname)
		if f != "" and not by_flavor.has(f):
			by_flavor[f] = bname
	for u in main.home.home_uids():
		var mon: PokemonInstance = Game.roster.get_member(u)
		var n := SpeciesDB.nature(mon.nature)
		if n["likes_flavor"] != null and by_flavor.has(n["likes_flavor"]) and by_flavor.has(n["hates_flavor"]):
			return {"mon": mon, "like": by_flavor[n["likes_flavor"]], "hate": by_flavor[n["hates_flavor"]]}
	return {}


## Pelea acelerada: encuentros, golpes, captura, subida de nivel, evolución y jefe.
## Toma una captura la primera vez que ocurre cada momento clave.
func _battle() -> void:
	var r := Game.roster
	var ch: PokemonInstance = r.get_member(r.companion)
	# Charmander a un paso del Nv. 16 para ver la evolución.
	ch.gain_exp(SpeciesDB.exp_for_level(ch.data()["growth_rate"], 15) - ch.xp)
	ch.xp = SpeciesDB.exp_for_level(ch.data()["growth_rate"], 16) - 3
	ch.hp = ch.max_hp()
	ch.friendship = 210  # para ver los efectos de afecto
	var pg := PokemonInstance.create("pidgey", 4)
	r.add(pg)
	r.set_team([pg.uid, ch.uid])  # Pidgey lidera: peleas más largas → captura
	var bc: BattleController = main.combat
	bc.route["capture"]["chance_per_turn"] = 1.0
	bc.route["walk_seconds"] = [1.5, 2.0]
	var seen := {}
	bc.event.connect(func(kind: String) -> void:
		if seen.has(kind):
			return
		seen[kind] = true
		var delay: float = {"hit": 0.12, "shake": 0.05, "evolving": 0.1, "levelup": 0.15, "encounter": 0.1, "boss": 0.3, "caught": 0.3, "victory": 0.1}.get(kind, 0.2)
		await get_tree().create_timer(delay).timeout
		await Game.shot("p4_" + kind))
	Game.set_mode(Game.MODE_BATTLE)
	Game.clock.speed = 2.0
	await _wait(3.0)
	await Game.shot("p4_walk")
	var t := 0.0
	while t < 160.0 and not (seen.has("cleared") and seen.has("caught") and seen.has("evolved")):
		await _wait(1.0)
		t += 1.0 * Game.clock.speed
		if bc.progress >= 3 and not seen.has("boss") and seen.has("evolved") and seen.has("caught"):
			bc.debug_force_boss()
	Game.clock.speed = 1.0
	print("[battle] eventos vistos: ", seen.keys(), " progreso ", bc.progress, " equipo ", r.team_members().map(func(p): return "%s Nv%d PS%d/%d" % [p.species, p.level, p.hp, p.max_hp()]))
	await _wait(1.0)
	await Game.shot("p4_end")


## Paso 1: arma una partida con capturas y bayas, y la guarda "hace 3 horas".
func _save_write() -> void:
	var r := Game.roster
	r.add(PokemonInstance.create("pidgey", 5))
	var od := PokemonInstance.create("oddish", 4)
	r.add(od)
	r.add(PokemonInstance.create("hoothoot", 6))
	for i in 5:
		r.add(PokemonInstance.create(["rattata", "caterpie", "spinarak"][i % 3], 3 + i))
	r.get_member(r.companion).known_flavors = {"spicy": "likes", "dry": "hates"}
	r.add_berry("sitrus", 2)
	r.add_berry("figy", 1)
	main.saver.save(3.0 * 3600.0)
	main.saver.skip_quit_save = true
	print("[save] guardado de prueba con ", r.members.size(), " Pokémon")


## Paso 2: carga, calcula el progreso offline (3 h) y muestra la PC.
func _save_load() -> void:
	print("[save] cargado: ", Game.roster.members.size(), " Pokémon, equipo ", Game.roster.team.size())
	await _wait(2.5)
	await Game.shot("p5_offline")
	main._open_pc("pokemon")
	await _wait(0.6)
	await Game.shot_window(main.pc, "p5_pc_pokemon")
	main.pc._select(Game.roster.team[1])
	await _wait(0.3)
	await Game.shot_window(main.pc, "p5_pc_select")
	main.pc.show_tab("bayas")
	await _wait(0.3)
	await Game.shot_window(main.pc, "p5_pc_bayas")
	main.pc.show_tab("creditos")
	await _wait(0.3)
	await Game.shot_window(main.pc, "p5_pc_creditos")
	await _wait(8.0)  # margen para comprobar con tools/probe.ps1 que la PC no está en la barra


## Vista de conjunto: casa con mascotas + pelea, de día y de noche.
func _showcase() -> void:
	var r := Game.roster
	var ch: PokemonInstance = r.get_member(r.companion)
	ch.level = 9
	ch.hp = ch.max_hp()
	for sp in ["pidgey", "oddish", "caterpie", "rattata"]:
		var p := PokemonInstance.create(sp, 4)
		r.add(p)
	# Charmander pelea solo; los demás descansan en casa.
	var others: Array[int] = [ch.uid]
	for p in r.members.values():
		if p.uid != ch.uid:
			others.append(p.uid)
	r.set_team(others)
	for p in r.team_members():
		if p.uid != ch.uid:
			p.energy = 5.0  # cansados: se quedan en casa
	main.combat.route["walk_seconds"] = [2.0, 3.0]
	Game.set_mode(Game.MODE_BATTLE)
	for hour in [12.0, 21.5]:
		Game.clock.forced_hour = hour
		main.battle.backdrop.refresh()
		main.combat._apply_tint()
		var bc: BattleController = main.combat
		var got := [false]
		var cb := func(kind: String) -> void:
			if kind == "hit":
				got[0] = true
		bc.event.connect(cb)
		var t := 0.0
		while not got[0] and t < 30.0:
			await _wait(0.25)
			t += 0.25
		bc.event.disconnect(cb)
		await _wait(0.1)
		await Game.shot("p6_showcase_%02d" % int(hour))
		await _wait(4.0)
	Game.clock.forced_hour = -1.0
