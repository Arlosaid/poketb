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
		"growth":
			await _growth()
		"moves":
			await _moves()
		"types":
			await _types()
		"hold":
			# no hace nada: para pruebas externas (probe.ps1, barra de tareas) hasta --autoquit
			await _wait(3600.0)
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


const GALLERY_SPECIES := [
	"charmander", "bulbasaur", "squirtle", "pikachu", "pidgey", "gengar", "onix", "snorlax", "dragonite",
	"mewtwo", "lugia", "rayquaza", "lucario", "garchomp", "zoroark", "greninja", "decidueye", "corviknight",
	"dragapult", "sprigatito", "koraidon", "pecharunt",
]


func _gallery() -> void:
	# una muestra de especies (las 1025 no caben en la franja)
	var roster: Array = []
	for n in GALLERY_SPECIES:
		roster.append({"name": n})
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
	for sp in ["pidgey", "oddish", "caterpie", "rattata"]:
		r.add(PokemonInstance.create(sp, 4))
	await _wait(3.0)
	await Game.shot("p3_home")
	for u in main.home.home_uids():
		var m: PokemonInstance = r.get_member(u)
		print("[pet] %s: %s (%s) «%s»" % [m.species, Personality.trait_name(m), m.characteristic_key(), Personality.characteristic_text(m)])

	var cid := r.companion
	var a: PokemonActor = main.home.actor_for(cid)
	var b: PetBrain = main.home.brain_for(cid)
	_hold_all(1e9)
	a.position.x = 120
	await _wait(0.3)
	# Caricia: corazones y, si tiene hambre, el globito de la baya.
	r.get_member(cid).fullness = 10.0
	b.pet()
	await _wait(0.45)
	await Game.shot("p8_pet")
	await _wait(2.5)
	r.get_member(cid).fullness = 80.0

	# Clic derecho: barrita de acciones (sin PC) y menú compacto de bayas.
	b.force_state(PetBrain.State.IDLE, 1e9)
	b.open_actions()
	await _wait(0.3)
	await Game.shot("p8_actions")
	b.open_berries()
	await _wait(0.3)
	await Game.shot("p8_berry_menu")
	b._close_popups()

	# Ficha compacta.
	b.show_card()
	await _wait(0.3)
	await Game.shot("p8_card")
	await _wait(0.3)

	# Una baya que le guste (globo de texto delgado) y otra que no.
	var picked := _pet_with_preferences()
	if not picked.is_empty():
		var mon: PokemonInstance = picked["mon"]
		var pb: PetBrain = main.home.brain_for(mon.uid)
		var pa: PokemonActor = main.home.actor_for(mon.uid)
		pb.force_state(PetBrain.State.IDLE, 1e9)
		pa.position.x = 260
		r.add_berry(picked["like"])
		r.add_berry(picked["hate"])
		pb.feed(picked["like"])
		await _wait(2.3)
		await Game.shot("p8_feed_like")
		await _wait(3.0)
		pb.feed(picked["hate"])
		await _wait(2.3)
		await Game.shot("p8_feed_hate")
		await _wait(3.0)

	# Cosquillas y rascar.
	_hold_all(1e9)
	b.tickle()
	await _wait(0.35)
	await Game.shot("p8_tickle")
	await _wait(2.0)
	b.rub()
	await _wait(0.35)
	await Game.shot("p8_rub")
	await _wait(2.0)

	# Herido: los mimos curan un poco.
	var cm: PokemonInstance = r.get_member(cid)
	cm.hp = maxi(1, cm.max_hp() / 4)
	b.force_state(PetBrain.State.LAY, 1e9)
	b.pet()
	await _wait(0.4)
	await Game.shot("p8_cuddle_heal")
	cm.hp = cm.max_hp()
	await _wait(2.0)

	# Todos los globitos de emoción, uno por mascota.
	_hold_all(1e9)
	var icons := ["heart", "note", "exclaim", "question", "dots", "anger", "sweat", "zzz", "star", "berry", "ball"]
	var uids: Array = main.home.home_uids()
	for i in uids.size():
		var ea: PokemonActor = main.home.actor_for(uids[i])
		ea.position.x = 40 + i * 40
		Emote.show_on(main.home, ea, icons[i % icons.size()], 3.0)
	await _wait(0.4)
	await Game.shot("p8_emotes")
	for i in uids.size():
		Emote.show_on(main.home, main.home.actor_for(uids[i]), icons[(i + uids.size()) % icons.size()], 3.0)
	await _wait(0.4)
	await Game.shot("p8_emotes2")
	await _wait(2.5)

	# Pelota: la tiras y los juguetones la persiguen.
	_hold_all(0.0)
	a.position.x = 150
	main.home.throw_ball_from(a)
	b.start_chase()
	for u in uids:
		if u != cid:
			main.home.brain_for(u).start_chase()
	await _wait(1.6)
	await Game.shot("p8_ball")
	await _wait(2.5)
	await Game.shot("p8_ball2")
	await _wait(3.0)

	# Vida social: dos mascotas se saludan.
	_hold_all(1e9)
	var b2: PetBrain = main.home.brain_for(uids[1])
	b2.actor.position.x = 200
	a.position.x = 150
	b.social_start("greet", b2)
	b2.social_invite("greet", b)
	await _wait(2.6)
	await Game.shot("p8_social")
	await _wait(2.0)

	# Lanzarlo: da una voltereta al caer.
	_hold_all(1e9)
	a.position = Vector2(100, 40)
	b._vx = 200.0
	b._vy = -100.0
	b.force_state(PetBrain.State.FALL)
	await _wait(1.2)
	await Game.shot("p8_tumble")
	await _wait(2.0)

	# Recordatorio de pausa y ánimo al descansar.
	_hold_all(1e9)
	Passthrough.fake_mouse = Vector2(300, 60)
	main.home.suggest_break()
	await _wait(3.2)
	await Game.shot("p8_break")
	await _wait(2.0)
	main.home.break_taken()
	await _wait(0.6)
	await Game.shot("p8_cheer")
	print("[pet] ánimo: +%d%% EXP (contento: %s)" % [int(r.cheer_exp_pct(cm)), str(cm.is_cheerful())])
	Passthrough.fake_mouse = Vector2.INF
	await _wait(3.0)

	# Viendo un video: se sientan a mirar contigo.
	_hold_all(0.0)
	main.home.sense.app_changed.emit("video")
	await _wait(1.0)
	await Game.shot("p8_watch")
	main.home.sense.app_changed.emit("")

	# Vuelo por la pantalla (la ventanita de vuelo se captura aparte).
	var flier: PetBrain = null
	for u in uids:
		if Personality.can_fly(r.get_member(u).species):
			flier = main.home.brain_for(u)
	if flier:
		main.home.force_flight(flier)
		await _wait(2.5)
		await Game.shot_window(main.home.flight, "p8_flight")
		print("[pet] vuelo: ventana en ", main.home.flight.position)
		main.home.abort_flight()
		await _wait(1.5)

	# De noche y con la PC inactiva: todos se acurrucan.
	Game.clock.forced_hour = 23.0
	Game.forced_idle = 400.0
	_hold_all(0.0)
	await _wait(2.5)
	await Game.shot("p3_sleep")
	Game.forced_idle = 0.0
	Game.clock.forced_hour = -1.0


## Deja a todas las mascotas quietas `sec` segundos (0 = que sigan con su vida).
func _hold_all(sec: float) -> void:
	for u in main.home.home_uids():
		main.home.brain_for(u).force_state(PetBrain.State.IDLE, sec)


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


## Progresión: monedas, árbol, vitaminas, movimientos y objetos (capturas p7_*).
func _growth() -> void:
	var r := Game.roster
	var ch: PokemonInstance = r.get_member(r.companion)
	ch.gain_exp(SpeciesDB.exp_for_level(ch.data()["growth_rate"], 14) - ch.xp)
	r.add(PokemonInstance.create("pidgey", 6))
	r.add_gold(2400)
	var hp0 := ch.max_hp()
	var atk0 := ch.stat("atk")
	for id in ["fuerza", "fuerza", "fuerza", "guardia", "punteria", "punteria", "botin", "siesta"]:
		print("[growth] compra ", id, ": ", r.buy_skill(id))
	for st in ["atk", "atk", "spe"]:
		r.buy_vitamin(ch, st)
	r.buy_mastery(ch, ch.moves[-1])
	r.buy_mastery(ch, ch.moves[-1])
	for k in ["muscle_band:0", "muscle_band:0", "muscle_band:0", "muscle_band:1", "scope_lens:0", "lucky_egg:2", "amulet_coin:3", "leftovers:0"]:
		r.add_item(k)
	r.equip(ch, "scope_lens:0")
	print("[growth] merge: ", r.merge("muscle_band:0"))
	print("[growth] PS %d → %d, Ata %d → %d, oro %d" % [hp0, ch.max_hp(), atk0, ch.stat("atk"), r.gold])
	# daño: el mismo ataque contra un salvaje, sin y con bonos
	var foe := PokemonInstance.create("rattata", 12)
	foe.wild = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var with_bonus := 0
	var without := 0
	var saved_uid := ch.uid
	for i in 200:
		with_bonus += BattleMath.attack(ch, foe, ch.moves[-1], rng)["damage"]
	ch.uid = 0
	rng.seed = 7
	for i in 200:
		without += BattleMath.attack(ch, foe, ch.moves[-1], rng)["damage"]
	ch.uid = saved_uid
	print("[growth] daño medio %.1f (con bonos) vs %.1f (sin)" % [with_bonus / 200.0, without / 200.0])
	# ida y vuelta del guardado con los datos nuevos
	var copy := Roster.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	var c2: PokemonInstance = copy.get_member(ch.uid)
	var same := copy.gold == r.gold and copy.skills == r.skills and copy.bag == r.bag \
		and c2.held == ch.held and c2.doses == ch.doses and c2.move_mastery == ch.move_mastery \
		and c2.max_hp() == ch.max_hp() and c2.stat("atk") == ch.stat("atk")
	print("[growth] guardado ida y vuelta: ", "OK" if same else "FALLA")
	main._open_pc("pokemon")
	await _wait(0.6)
	for tab in ["entrenar", "mochila", "arbol"]:
		main.pc.show_tab(tab)
		await _wait(0.4)
		await Game.shot_window(main.pc, "p7_pc_" + tab)
	main.pc.show_tab("pokemon")
	await _wait(0.4)
	await Game.shot_window(main.pc, "p7_pc_pokemon")
	await _wait(0.5)


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


## Fase 9: un movimiento de cada estilo de animación (data/move_fx.json) en el panel de pelea.
## Saca p9_<estilo>_battle.png en el momento del golpe.
const MOVE_SAMPLES := [
	["tackle", "eevee"], ["fire-punch", "charmeleon"], ["double-kick", "hitmonlee"], ["body-slam", "snorlax"],
	["crunch", "mightyena"], ["slash", "scyther"], ["iron-tail", "pikachu"], ["rapid-spin", "blastoise"],
	["vine-whip", "bulbasaur"], ["shadow-ball", "gengar"], ["bullet-seed", "breloom"], ["hyper-beam", "dragonite"],
	["flamethrower", "charizard"], ["thunder", "raichu"], ["rock-slide", "golem"], ["stone-edge", "tyranitar"],
	["earthquake", "garchomp"], ["surf", "lapras"], ["gust", "pidgeot"], ["hyper-voice", "wigglytuff"],
	["psychic", "alakazam"], ["giga-drain", "venusaur"], ["explosion", "electrode"], ["dig", "dugtrio"],
	["fly", "pidgeot"], ["swords-dance", "scizor"], ["recover", "starmie"], ["toxic", "nidoking"],
	["protect", "blissey"], ["rain-dance", "kyogre"], ["ice-beam", "glaceon"], ["moonblast", "sylveon"],
]


func _moves() -> void:
	Game.set_mode(Game.MODE_BATTLE)
	await _wait(1.5)
	var bc: BattleController = main.combat
	bc.set_process(false)
	bc._stop_all()
	var stage: Node2D = bc.strip.stage
	var gy: float = bc.strip.ground_y()
	for sample in MOVE_SAMPLES:
		var mv: String = sample[0]
		var att := bc._spawn_actor(sample[1], Vector2(70, gy))
		var def := bc._spawn_actor("snorlax" if sample[1] != "snorlax" else "lapras", Vector2(170, gy))
		att.play_anim("Idle", "E")
		def.play_anim("Idle", "W")
		await _wait(0.4)
		var body := MoveFx.body_anim(mv)
		att.play_anim(body, "E", true)
		await _wait(att.hit_time(body))
		var fx := MoveFx.create(stage, att, MoveFx.body_center(def), mv, def)
		fx.shake = bc._stage_shake
		fx.start()
		await _wait(0.1)
		await Game.shot("p9_%s_a" % MoveFx.data(mv)["style"])
		await fx.wait_impact()
		def.play_anim("Hurt", "W", true)
		await _wait(0.06)
		await Game.shot("p9_%s" % MoveFx.data(mv)["style"])
		await _wait(0.9)
		att.queue_free()
		def.queue_free()
		await _wait(0.1)
	print("[moves] estilos probados: ", MOVE_SAMPLES.size())


## Fase 9: acciones propias de cada tipo, entrenar, combate de práctica y estilos de vuelo.
## Saca p9_type_<acción>.png, p9_train, p9_spar y p9_fly_<estilo>.png.
const TYPE_SAMPLES := [
	["charmander", "brasas"], ["squirtle", "fuente"], ["pikachu", "chispas"], ["bulbasaur", "hojas"],
	["sandshrew", "excavar"], ["abra", "teletransporte"], ["gastly", "atravesar"], ["spinarak", "colgar_de_seda"],
	["machop", "puñetazos"], ["snorunt", "nevada"], ["clefairy", "danza_feerica"], ["geodude", "rodar"],
	["pidgey", "revolotear"], ["dratini", "rugido"], ["koffing", "burbujas_toxicas"], ["magnemite", "pulirse"], ["eevee", "pose"], ["rhyhorn", "pisotón"], ["gyarados", "sacudirse"], ["umbreon", "sombra"],
]


func _types() -> void:
	Game.set_mode(Game.MODE_REST)
	await _wait(0.5)
	var home: HomeArea = main.home
	var r := Game.roster
	# de a 5 (más el compañero): el máximo de mascotas paseando es Roster.PETS_MAX
	var round_i := 0
	var brains: Array[PetBrain] = []
	for start in range(0, TYPE_SAMPLES.size(), 5):
		var chunk := TYPE_SAMPLES.slice(start, start + 5)
		var uids: Array[int] = []
		for sample in chunk:
			var p := PokemonInstance.create(sample[0], 20)
			r.add(p)
			uids.append(p.uid)
		r.pets = uids
		main._sync_home()
		await _wait(0.8)
		brains.clear()
		for i in chunk.size():
			var b := home.brain_for(uids[i])
			b.actor.position = Vector2(40 + i * 60, home.ground_y)
			b.force_state(PetBrain.State.IDLE, 1e9)
			brains.append(b)
		var comp := home.brain_for(r.companion)
		if comp:
			comp.actor.position.x = 380
			comp.force_state(PetBrain.State.IDLE, 1e9)
		await _wait(0.4)
		for i in chunk.size():
			var b := brains[i]
			for t in b.mon.types():
				for a in TypeAct.data()["types"].get(t, []):
					if a["id"] == chunk[i][1]:
						b.start_type_act(a, t)
		await _wait(1.2)
		await Game.shot("p9_types%d_a" % round_i)
		await _wait(1.2)
		await Game.shot("p9_types%d_b" % round_i)
		await _wait(5.0)
		round_i += 1
	# entrenar y combate de práctica (con los últimos)
	for b in brains:
		b.force_state(PetBrain.State.IDLE, 1e9)
	await _wait(0.5)
	brains[0].train("dragon-breath")
	await _wait(0.45)
	await Game.shot("p9_train")
	await _wait(1.5)
	brains[0].actor.position.x = 120
	brains[1].actor.position.x = 160
	home.run_spar(brains[0], brains[1])
	await _wait(0.9)
	await Game.shot("p9_spar")
	await _wait(6.0)
	# estilos de vuelo
	for pair in [["pidgeot", "bird"], ["butterfree", "bug"], ["haunter", "float"], ["dragonite", "dragon"]]:
		var f := PokemonInstance.create(pair[0], 40)
		r.add(f)
		r.pets = [f.uid]
		main._sync_home()
		await _wait(0.6)
		var fb := home.brain_for(f.uid)
		print("[types] %s vuela=%s estilo=%s" % [pair[0], Personality.can_fly(pair[0]), Personality.flight_style(pair[0])])
		home.force_flight(fb)
		await _wait(2.5)
		await Game.shot_window(home.flight, "p9_fly_" + pair[1])
		home.abort_flight()
		await _wait(0.5)
	print("[types] listo")
