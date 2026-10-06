class_name Scenarios
extends Node
## Escenarios automatizados para validar el acabado visual: colocan cosas, fuerzan
## la hora, sacan capturas del viewport (Game.shot) y cierran el juego.
## Uso: godot --path . -- --scenario=<nombre>

var main: Node


func run(m: Node, scenario_name: String) -> void:
	main = m
	await get_tree().process_frame
	match scenario_name:
		"still":
			await _still()
		"gallery":
			await _gallery()
		_:
			push_error("Escenario desconocido: " + scenario_name)
	Game.quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _still() -> void:
	var a := PokemonActor.new()
	a.species = "charmander"
	main.world.add_child(a)
	a.position = Vector2(100, main.desk.ground_y())
	a.play_anim("Idle", "S")
	await _wait(1.5)
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
		bs.layout(Rect2i(bs.position, bs.size), biome, bs.px_scale)
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
	bs.layout(Rect2i(bs.position, bs.size), "pradera", bs.px_scale)

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
