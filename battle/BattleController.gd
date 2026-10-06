class_name BattleController
extends Node
## Lógica y puesta en escena del modo pelea dentro del BattleStrip.
## El equipo camina (el fondo hace parallax), aparecen salvajes y se pelea por turnos
## con fórmulas canon. Las secuencias son corrutinas; `_epoch` las cancela si cambias
## de modo a mitad de una pelea.

signal fighters_changed
## Momentos clave (para escenarios de prueba y futuros sonidos): encounter, hit,
## throw, shake, caught, escaped, levelup, evolving, evolved, victory, faint, wipe, cleared.
signal event(kind: String)

enum State { IDLE, WALK, BATTLE, RESTING }

## Alto (en la ventana) donde van las fichas de nombre/PS, bajo la cajita de diálogo.
const CHIP_Y := 25.0
const LEAD_X := 96.0
const FOLLOW_GAP := 24.0
const MAX_VISIBLE := 4
const SCROLL_SPEED := 18.0
const WILD_SPEED := 70.0
const FOE_GAP := 50.0
const FLASH := preload("res://pokemon/flash.gdshader")
const BALL := preload("res://assets/ui/pokeball_8.png")

var strip: BattleStrip
var desk: DesktopWindow
var log_box: BattleLog
var route: Dictionary
var rng := RandomNumberGenerator.new()
var state := State.IDLE
var progress := 0
var cleared := false
var biome := ""

var fighters: Array[PokemonInstance] = []
var actors := {}             # uid → PokemonActor
var wild: PokemonInstance
var wild_actor: PokemonActor
var is_boss := false

var our_chip: InfoChip
var foe_chip: InfoChip
var progress_bar: RouteProgress
## Poké Ball sobre el camino que abre la PC.
var pc_button: PCButton
var _wipe_rect: ColorRect

var _walk_timer := 0.0
var _epoch := 0
var _tint_timer := 0.0
var _rest_timer := 0.0
var _shake_tween: Tween


func setup(s: BattleStrip, d: DesktopWindow, route_id := "ruta_1") -> void:
	strip = s
	desk = d
	rng.randomize()
	load_route(route_id)
	log_box = BattleLog.new()
	log_box.name = "BattleLog"
	strip.add_child(log_box)
	our_chip = InfoChip.new(false, true)
	foe_chip = InfoChip.new(true, false)
	progress_bar = RouteProgress.new()
	_wipe_rect = ColorRect.new()
	_wipe_rect.color = Palette.a(Palette.CREAM, 0.0)
	_wipe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [our_chip, foe_chip, _wipe_rect]:
		strip.inner.add_child(c)
	strip.add_child(progress_bar)
	pc_button = PCButton.new()
	strip.add_child(pc_button)
	relayout()


## Cambia de ruta (data/routes/<id>.json). El avance vuelve a cero.
func load_route(route_id: String) -> bool:
	var path := "res://data/routes/%s.json" % route_id
	if not FileAccess.file_exists(path):
		return false
	route = JSON.parse_string(FileAccess.get_file_as_string(path))
	progress = 0
	cleared = false
	return true


## Nivel de un salvaje de la tabla: sigue el avance de la ruta, pero nunca por debajo
## del nivel en el que esa especie existe (una evolución no aparece a nivel 3).
static func wild_level(r: Dictionary, prog: int, entry_species: String, rand: RandomNumberGenerator) -> int:
	var lr: Array = r["level_range"]
	var f := float(prog) / float(r["encounters_to_boss"])
	var lvl := int(round(lerpf(lr[0], lr[1], f))) + rand.randi_range(-1, 1)
	for t in ["day", "night"]:
		for e in r[t]:
			if e["species"] == entry_species:
				lvl = maxi(lvl, int(e.get("min_level", 2)))
				break
	return clampi(lvl, 2, 100)


## Recoloca la HUD interna (llamar tras BattleStrip.layout).
func relayout() -> void:
	if our_chip == null:
		return
	var w := strip.inner.size.x
	# Debajo de la cajita de diálogo (arriba): fichas en las esquinas, ruta al centro bajo ellas.
	our_chip.position = Vector2(4, CHIP_Y)
	foe_chip.position = Vector2(w - 4 - foe_chip.size.x, CHIP_Y)
	progress_bar.position = Vector2(round((strip.size.x - progress_bar.size.x) / 2.0), CHIP_Y + 17.0)
	_wipe_rect.size = strip.inner.size
	pc_button.position = Vector2(w - PCButton.SIZE.x - 3, strip.ground_y() - PCButton.SIZE.y + 1).round()
	log_box.area_width = strip.size.x
	var b := _section_biome()
	if b != biome or strip.backdrop.biome.get("id", "") != b:
		biome = b
		strip.backdrop.setup(biome, Vector2i(strip.inner.size), strip.px_scale)
	for u in actors:
		actors[u].position.y = strip.ground_y()
	if wild_actor:
		wild_actor.position.y = strip.ground_y()
	progress_bar.frac = float(progress) / float(route["encounters_to_boss"])
	progress_bar.cleared = cleared


func fighting_uids() -> Array:
	return fighters.map(func(p: PokemonInstance) -> int: return p.uid)


# ------------------------------------------------------------------ ciclo

func _process(delta: float) -> void:
	if Game.mode != Game.MODE_BATTLE:
		if state != State.IDLE:
			_stop_all()
		return
	if Game.clock.paused:
		return
	if state == State.IDLE:
		_start_route()
	_tint_timer -= delta
	if _tint_timer <= 0.0:
		_tint_timer = 5.0
		_apply_tint()
	match state:
		State.WALK:
			strip.backdrop.scroll(SCROLL_SPEED * delta)
			desk.keep_ambient()
			_walk_timer -= Game.dt
			if _walk_timer <= 0.0:
				_encounter(_epoch)
		State.RESTING:
			_rest_timer -= delta
			if _rest_timer <= 0.0:
				_rest_timer = 2.0
				if _ready_to_return():
					_start_route()
		State.BATTLE:
			desk.keep_awake()


func _start_route() -> void:
	_rebuild_fighters(false)
	if fighters.is_empty():
		_enter_resting("Tu equipo descansa en casa…")
		return
	state = State.WALK
	_walk_timer = rng.randf_range(route["walk_seconds"][0], route["walk_seconds"][1])
	_formation(true)


func _stop_all() -> void:
	_epoch += 1
	state = State.IDLE
	log_box.clear()
	our_chip.appear(false)
	foe_chip.appear(false)
	_remove_wild()
	for u in actors.keys():
		_free_actor(u)
	fighters.clear()
	fighters_changed.emit()


func _enter_resting(msg: String) -> void:
	state = State.RESTING
	_rest_timer = 2.0
	log_box.say(msg, 2.5)


## ¿Alguien del equipo ya descansó lo suficiente para volver a la ruta?
func _ready_to_return() -> bool:
	for p in Game.roster.team_members():
		if not p.is_fainted() and p.energy >= Roster.ENERGY_TO_RETURN and p.hp_frac() >= 0.5:
			return true
	return false


## Decide quién pelea. Los que no pueden (debilitados o cansados) vuelven a casa.
func _rebuild_fighters(emit := true) -> void:
	var want: Array[PokemonInstance] = []
	for p in Game.roster.team_members():
		if Game.roster.can_fight(p):
			want.append(p)
	for u in actors.keys():
		if not want.any(func(p: PokemonInstance) -> bool: return p.uid == u):
			_walk_out(u)
	fighters = want
	for i in fighters.size():
		var p := fighters[i]
		if not actors.has(p.uid) and i < MAX_VISIBLE:
			var a := _spawn_actor(p.species, Vector2(-16.0 - i * FOLLOW_GAP, strip.ground_y()))
			actors[p.uid] = a
	if emit:
		fighters_changed.emit()
	else:
		fighters_changed.emit.call_deferred()


func _spawn_actor(sp: String, pos: Vector2) -> PokemonActor:
	var a := PokemonActor.new()
	a.species = sp
	a.interactive = false
	strip.stage.add_child(a)
	a.position = pos
	var m := ShaderMaterial.new()
	m.shader = FLASH
	a.sprite.material = m
	a.modulate = DayNight.sprite_tint(Game.clock.hour())
	return a


func _free_actor(u: int) -> void:
	if actors.has(u):
		actors[u].queue_free()
		actors.erase(u)


## Sale caminando por la izquierda del panel (hacia casa).
func _walk_out(u: int) -> void:
	var a: PokemonActor = actors.get(u)
	actors.erase(u)
	if a == null:
		return
	a.play_anim("Walk", "W")
	var t := a.create_tween()
	t.tween_property(a, "position:x", -30.0, maxf(0.3, (a.position.x + 30.0) / 40.0))
	t.tween_callback(a.queue_free)


## Coloca (o lleva caminando) al equipo en fila detrás del líder.
func _formation(walking: bool, lead_x := LEAD_X) -> void:
	var i := 0
	for p in fighters:
		var a: PokemonActor = actors.get(p.uid)
		if a == null:
			continue
		var x := lead_x - i * FOLLOW_GAP
		a.play_anim("Walk" if walking or absf(a.position.x - x) > 1.0 else "Idle", "E")
		var t := a.create_tween().set_trans(Tween.TRANS_SINE)
		t.tween_property(a, "position:x", x, clampf(absf(a.position.x - x) / 40.0, 0.05, 2.5))
		if not walking:
			t.tween_callback(a.play_anim.bind("Idle", "E"))
		i += 1


func _lead() -> PokemonInstance:
	for p in fighters:
		if not p.is_fainted():
			return p
	return null


func _apply_tint() -> void:
	var c := DayNight.sprite_tint(Game.clock.hour())
	for a in actors.values() + ([wild_actor] if wild_actor else []):
		a.modulate = Color(c, a.modulate.a)


func _section_biome() -> String:
	var f := float(progress) / float(route["encounters_to_boss"])
	var b: String = route["sections"][0]["biome"]
	for s in route["sections"]:
		if f >= float(s["from"]):
			b = s["biome"]
	return b


# ------------------------------------------------------------------ encuentro

func _alive(e: int) -> bool:
	return e == _epoch and is_inside_tree()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _encounter(e: int) -> void:
	state = State.BATTLE
	is_boss = progress >= int(route["encounters_to_boss"])
	var sp: String
	var lvl: int
	if is_boss:
		sp = route["boss"]["species"]
		lvl = int(route["boss"]["level"])
	else:
		var table: Array = route["night" if Game.clock.is_night() else "day"]
		sp = BattleMath.pick_weighted(table, "species", rng)
		lvl = wild_level(route, progress, sp, rng)
	wild = PokemonInstance.create(sp, lvl, rng)
	wild.wild = true
	var w := strip.inner.size.x
	wild_actor = _spawn_actor(sp, Vector2(w + 24.0, strip.ground_y()))
	var foe_x := LEAD_X + FOE_GAP
	wild_actor.play_anim("Walk", "W")
	# El fondo sigue avanzando mientras el salvaje se acerca.
	var dist := wild_actor.position.x - foe_x
	var t := wild_actor.create_tween()
	t.tween_property(wild_actor, "position:x", foe_x, dist / WILD_SPEED)
	if is_boss:
		log_box.say(route["boss"]["title_es"], 2.0)
	else:
		log_box.say("¡Un %s salvaje!" % wild.display_name(), 1.2)
	var elapsed := 0.0
	while elapsed < dist / WILD_SPEED:
		await get_tree().process_frame
		if not _alive(e):
			return
		var d := get_process_delta_time()
		elapsed += d
		strip.backdrop.scroll(SCROLL_SPEED * d)
	if not _alive(e):
		return
	wild_actor.play_anim("Idle", "W")
	for u in actors:
		actors[u].play_anim("Idle", "E")
	_formation(false)
	var lead := _lead()
	if lead == null:
		await _wipe(e)
		return
	our_chip.bind(lead)
	foe_chip.bind(wild, is_boss)
	relayout()
	our_chip.appear(true)
	foe_chip.appear(true)
	event.emit("boss" if is_boss else "encounter")
	await _wait(0.6)
	await _fight(e)


func _fight(e: int) -> void:
	while _alive(e):
		var lead := _lead()
		if lead == null:
			await _wipe(e)
			return
		var order: Array = [lead, wild]
		var ls := lead.stat("spe")
		var ws := wild.stat("spe")
		if ws > ls or (ws == ls and rng.randf() < 0.5):
			order = [wild, lead]
		for att in order:
			if not _alive(e):
				return
			var def: PokemonInstance = wild if att == lead else lead
			if att == lead and _should_throw():
				var caught := await _throw_ball(e, lead)
				if not _alive(e):
					return
				if caught:
					await _victory(e, true)
					return
				continue
			await _attack(e, att, def)
			if not _alive(e):
				return
			if def.is_fainted():
				if def == wild:
					await _victory(e, false)
					return
				await _our_faint(e, def)
				break
		await _wait(0.35)


func _actor_of(p: PokemonInstance) -> PokemonActor:
	return wild_actor if p == wild else actors.get(p.uid)


func _attack(e: int, att: PokemonInstance, def: PokemonInstance) -> void:
	var aa := _actor_of(att)
	var da := _actor_of(def)
	if aa == null or da == null:
		return
	var move := BattleMath.choose_move(att, def, rng)
	var affection := not att.wild and att.friendship >= BattleMath.AFFECTION_FRIENDSHIP
	var r := BattleMath.attack(att, def, move, rng, affection)
	var md := SpeciesDB.move(move)
	var face := "W" if att.wild else "E"
	# cuerpo y efecto propios de cada movimiento (data/move_fx.json)
	var anim := MoveFx.body_anim(move)
	log_box.say("¡%s usó %s!" % [_name(att), md["name_es"]], 1.0)
	aa.play_anim(anim, face, true)
	await _wait(aa.hit_time(anim))
	if not _alive(e):
		return
	var fx := MoveFx.create(strip.stage, aa, MoveFx.body_center(da), move, da)
	fx.miss = r["miss"]
	fx.shake = _stage_shake
	fx.start()
	await fx.wait_impact()
	if not _alive(e):
		return
	if r["miss"]:
		log_box.say("¡Pero falló!", 0.9)
	else:
		var dmg: int = r["damage"]
		var endured := false
		if not def.wild and def.friendship >= BattleMath.AFFECTION_FRIENDSHIP and dmg >= def.hp and def.hp > 1 and rng.randf() < BattleMath.AFFECTION_ENDURE_CHANCE:
			dmg = def.hp - 1
			endured = true
		def.hp = maxi(0, def.hp - dmg)
		if r["eff"] > 0.0:
			_hit_fx(da, dmg, r["crit"])
			event.emit("hit")
		(foe_chip if def.wild else our_chip).refresh()
		if r["eff"] == 0.0:
			log_box.say("No afecta a %s…" % _name(def), 1.0)
		elif r["eff"] > 1.0:
			log_box.say("¡Es muy eficaz!", 0.9)
		elif r["eff"] < 1.0:
			log_box.say("No es muy eficaz…", 0.9)
		if r["affection_crit"]:
			log_box.say("¡%s dio un golpe crítico para no decepcionarte!" % _name(att), 1.4)
		elif r["crit"]:
			log_box.say("¡Un golpe crítico!", 0.9)
		if endured:
			log_box.say("¡%s aguantó para no decepcionarte!" % _name(def), 1.6)
	await _wait(maxf(0.2, aa.anim_length(anim) - aa.hit_time(anim)))
	if not _alive(e):
		return
	aa.play_anim("Idle", face)
	if not def.is_fainted():
		da.play_anim("Idle", "E" if att.wild else "W")


func _name(p: PokemonInstance) -> String:
	return ("%s salvaje" % p.display_name()) if p.wild and not is_boss else p.display_name()


## Golpe: animación Hurt, destello, sacudida de 2 px y número flotante.
func _hit_fx(da: PokemonActor, dmg: int, crit: bool) -> void:
	da.play_anim("Hurt", da.dir, true)
	_flash(da, 0.6, 0.08)
	var base := da.sprite.position
	var t := da.create_tween()
	for i in 3:
		t.tween_property(da.sprite, "position:x", base.x + (2.0 if i % 2 == 0 else -2.0), 0.04)
	t.tween_property(da.sprite, "position:x", base.x, 0.04)
	Fx.float_text(strip.stage, da.position + da.head_point(), str(dmg), Palette.HONEY if crit else Palette.PAPER, Palette.INK)
	_stage_shake(1.0)



## Sacudida del escenario de `px` píxeles enteros (la usan los golpes y MoveFx).
func _stage_shake(px: float) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	var amp := maxf(1.0, roundf(px))
	_shake_tween = strip.stage.create_tween()
	_shake_tween.tween_property(strip.stage, "position:y", amp, 0.04)
	if amp > 1.0:
		_shake_tween.tween_property(strip.stage, "position:y", -amp + 1.0, 0.05)
	_shake_tween.tween_property(strip.stage, "position:y", 0.0, 0.06)


func _flash(a: PokemonActor, amount: float, dur: float) -> void:
	var m := a.sprite.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("amount", amount)
	var t := a.create_tween()
	t.tween_method(func(v: float) -> void: m.set_shader_parameter("amount", v), amount, 0.0, dur)


func _our_faint(e: int, p: PokemonInstance) -> void:
	var a := _actor_of(p)
	log_box.say("¡%s se debilitó!" % p.display_name(), 1.4)
	p.add_friendship(-1)
	if a:
		a.play_anim("Faint", "E", true)
		event.emit("faint")
		await _wait(a.anim_length("Faint") + 0.5)
	if not _alive(e):
		return
	_rebuild_fighters()  # el debilitado vuelve a casa caminando
	var next := _lead()
	if next:
		log_box.say("¡Adelante, %s!" % next.display_name(), 1.2)
		our_chip.bind(next)
		_formation(false)
		await _wait(0.8)


func _wipe(e: int) -> void:
	our_chip.appear(false)
	foe_chip.appear(false)
	log_box.say("Tu equipo está agotado… Vuelven a casa a descansar.", 2.5)
	event.emit("wipe")
	if wild_actor:
		wild_actor.play_anim("Walk", "E")
		var t := wild_actor.create_tween()
		t.tween_property(wild_actor, "position:x", strip.inner.size.x + 30.0, 1.5)
	await _wait(1.6)
	if not _alive(e):
		return
	_remove_wild()
	_rebuild_fighters()
	_enter_resting("Descansando en casa…")


func _remove_wild() -> void:
	if wild_actor:
		wild_actor.queue_free()
	wild_actor = null
	wild = null


func _victory(e: int, captured: bool) -> void:
	if not captured:
		log_box.say("¡%s se debilitó!" % _name(wild), 1.2)
		wild_actor.play_anim("Faint", "W", true)
		var t := wild_actor.create_tween()
		t.tween_interval(wild_actor.anim_length("Faint"))
		t.tween_property(wild_actor, "modulate:a", 0.0, 0.3)
		await _wait(wild_actor.anim_length("Faint") + 0.4)
		if not _alive(e):
			return
	foe_chip.appear(false)

	# EXP para todos los que pelean (como el Repartir EXP de Gen 6+).
	var evolving: Array[PokemonInstance] = []
	for p in fighters:
		if p.is_fainted():
			continue
		var gain := int(round(BattleMath.exp_gain(p.level, wild, is_boss) * Progression.exp_mult(p)))
		var ups := p.gain_exp(gain)
		var a: PokemonActor = actors.get(p.uid)
		if a and p == _lead():
			Fx.float_text(strip.stage, a.position + a.head_point(), "+%d EXP" % gain, Palette.HAZE, Palette.NIGHT)
		if not ups.is_empty():
			log_box.say("¡%s subió al Nv. %d!" % [p.display_name(), ups[-1]], 1.3)
			if a:
				Fx.sparkles(strip.stage, a.position + Vector2(0, -12))
			event.emit("levelup")
		p.wins += 1
		if p.wins % 5 == 0:
			p.add_friendship(1)
		if p.evolution_ready() != "":
			evolving.append(p)
	our_chip.refresh()
	event.emit("victory")
	await _wait(1.0)
	for p in evolving:
		if not _alive(e):
			return
		await evolve(e, p)

	# Monedas
	var coins := Progression.gold_for_win(wild, is_boss, route, fighters)
	Game.roster.add_gold(coins)
	var lead_a: PokemonActor = actors.get(_lead().uid) if _lead() else null
	if lead_a:
		Fx.float_text(strip.stage, lead_a.position + lead_a.head_point() + Vector2(0, -8), "+%d" % coins, Palette.HONEY, Palette.INK)

	# Botín: a veces una baya y, más raro, un objeto (el jefe siempre suelta uno).
	var drops: Dictionary = route["drops"]
	var luck := 1.0 + Game.roster.fx("drops") / 100.0
	if not captured and rng.randf() < float(drops["chance"]) * luck:
		var b := BattleMath.pick_weighted(drops["table"], "berry", rng)
		Game.roster.add_berry(b)
		log_box.say("¡Encontraste una %s!" % SpeciesDB.berry(b)["name_es"], 1.4)
	var idrops: Dictionary = route.get("item_drops", {})
	if not idrops.is_empty() and (is_boss or (not captured and rng.randf() < float(idrops["chance"]) * luck)):
		var key := Progression.roll_item(idrops, rng, is_boss)
		Game.roster.add_item(key)
		log_box.say("¡Encontraste %s (%s)!" % [Progression.item_name(key), Progression.tier_name(Progression.key_tier(key))], 1.6)
		event.emit("item")

	progress += 1
	if is_boss:
		if not cleared:
			log_box.say(route["cleared_es"], 3.0)
			event.emit("cleared")
		cleared = true
		progress = 0
		# siguiente ruta (si hay): más especies, más nivel y otro bioma
		var nxt = route.get("next")
		if nxt != null and load_route(String(nxt)):
			log_box.say("¡Llegaron a %s!" % route["name_es"], 2.4)
			event.emit("new_route")
	_remove_wild()
	our_chip.appear(false)
	await _wait(0.6)
	if not _alive(e):
		return
	var b2 := _section_biome()
	if b2 != biome:
		await _biome_transition(b2)
	relayout()
	_rebuild_fighters()
	if fighters.is_empty():
		_enter_resting("Tu equipo vuelve a casa a descansar…")
		return
	state = State.WALK
	_walk_timer = rng.randf_range(route["walk_seconds"][0], route["walk_seconds"][1])
	_formation(true)


## Cambio de bioma: un velo crema tapa el panel un instante.
func _biome_transition(b: String) -> void:
	var t := _wipe_rect.create_tween()
	t.tween_property(_wipe_rect, "color:a", 1.0, 0.3)
	await t.finished
	biome = b
	strip.backdrop.setup(biome, Vector2i(strip.inner.size), strip.px_scale)
	_apply_tint()
	var t2 := _wipe_rect.create_tween()
	t2.tween_property(_wipe_rect, "color:a", 0.0, 0.4)


# ------------------------------------------------------------------ captura

func _should_throw() -> bool:
	if is_boss or wild == null:
		return false
	var c: Dictionary = route["capture"]
	var r := Game.roster
	return wild.hp_frac() < float(c["hp_below"]) + r.fx("throw_hp") / 100.0 		and rng.randf() < float(c["chance_per_turn"]) + r.fx("throw_chance") / 100.0


## Lanza una Poké Ball con arco, la absorbe, sacude (1–3) y decide. Devuelve si atrapó.
func _throw_ball(e: int, thrower: PokemonInstance) -> bool:
	var ta: PokemonActor = actors.get(thrower.uid)
	log_box.say("¡Adelante, Poké Ball!", 1.0)
	var ball := Sprite2D.new()
	ball.texture = BALL
	ball.z_index = 5
	strip.stage.add_child(ball)
	var from := (ta.position if ta else Vector2(LEAD_X, strip.ground_y())) + Vector2(4, -18)
	var to := wild_actor.position + Vector2(0, -12)
	ball.position = from
	var t := ball.create_tween()
	t.tween_method(func(f: float) -> void:
		ball.position = from.lerp(to, f) + Vector2(0, -sin(f * PI) * 16.0), 0.0, 1.0, 0.5)
	event.emit("throw")
	await t.finished
	if not _alive(e):
		ball.queue_free()
		return false
	# el salvaje se vuelve luz y entra en la ball
	_flash(wild_actor, 1.0, 0.01)
	(wild_actor.sprite.material as ShaderMaterial).set_shader_parameter("amount", 1.0)
	var t2 := wild_actor.create_tween()
	t2.tween_property(wild_actor, "modulate:a", 0.0, 0.2)
	await _wait(0.25)
	var ground := Vector2(to.x, strip.ground_y() - 4)
	var t3 := ball.create_tween()
	t3.tween_property(ball, "position", ground, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await t3.finished
	var checks := BattleMath.capture_checks(wild, rng, 1.0 + Game.roster.fx("ball") / 100.0)
	for i in mini(checks, 3):
		await _wait(0.45)
		if not _alive(e):
			ball.queue_free()
			return false
		var s := ball.create_tween()
		for k in 4:
			s.tween_property(ball, "position:x", ground.x + (1.0 if k % 2 == 0 else -1.0), 0.06)
		s.tween_property(ball, "position:x", ground.x, 0.06)
		event.emit("shake")
	await _wait(0.5)
	if not _alive(e):
		ball.queue_free()
		return false
	if checks >= 4:
		Fx.sparkles(strip.stage, ball.position, 9.0, 6)
		log_box.say("¡Ya está! ¡Atrapaste a %s!" % wild.display_name(), 1.8)
		event.emit("caught")
		var mon := wild
		mon.wild = false
		var tb := ball.create_tween()
		tb.tween_interval(0.8)
		tb.tween_property(ball, "modulate:a", 0.0, 0.3)
		tb.tween_callback(ball.queue_free)
		await _wait(1.0)
		# EXP también al capturar (Gen 6+), y luego al equipo o a la PC
		for p in fighters:
			if not p.is_fainted():
				p.gain_exp(int(round(BattleMath.exp_gain(p.level, mon, false) * Progression.exp_mult(p))))
		Game.roster.add(mon)
		if Game.roster.team.has(mon.uid):
			log_box.say("%s se une a tu equipo." % mon.display_name(), 1.4)
		else:
			log_box.say("%s fue enviado a la PC." % mon.display_name(), 1.4)
		return true
	# se escapa
	ball.queue_free()
	wild_actor.modulate.a = 1.0
	_flash(wild_actor, 1.0, 0.3)
	log_box.say("¡Oh, no! ¡Se escapó!", 1.2)
	event.emit("escaped")
	await _wait(0.6)
	return false


# ------------------------------------------------------------------ evolución

## Secuencia de evolución: silueta blanca que alterna entre especies cada vez más
## rápido, destello y la nueva forma.
func evolve(e: int, p: PokemonInstance) -> void:
	var to := p.evolution_ready()
	var a: PokemonActor = actors.get(p.uid)
	if to == "" or a == null:
		return
	var from := p.species
	log_box.say("¿Eh? ¡%s está evolucionando!" % p.display_name(), 2.0)
	a.play_anim("Idle", "S")
	var m := a.sprite.material as ShaderMaterial
	var t := a.create_tween()
	t.tween_method(func(v: float) -> void: m.set_shader_parameter("amount", v), 0.0, 1.0, 0.6)
	await t.finished
	var period := 0.5
	for i in 7:
		if not _alive(e):
			return
		a.species = to if i % 2 == 0 else from
		a.play_anim("Idle", "S")
		m.set_shader_parameter("amount", 1.0)
		if i == 2:
			event.emit("evolving")
		await _wait(period)
		period *= 0.75
	if not _alive(e):
		return
	a.species = to
	a.play_anim("Idle", "S")
	m.set_shader_parameter("amount", 1.0)
	var old_name := p.display_name()
	p.evolve(to)
	Fx.sparkles(strip.stage, a.position + Vector2(0, -14), 14.0, 8)
	var t2 := a.create_tween()
	t2.tween_method(func(v: float) -> void: m.set_shader_parameter("amount", v), 1.0, 0.0, 0.5)
	log_box.say("¡%s evolucionó a %s!" % [old_name, p.display_name()], 2.4)
	event.emit("evolved")
	our_chip.refresh(true)
	Game.roster.changed.emit()
	await _wait(1.8)
	if _alive(e):
		a.play_anim("Joy", "S", true)
		await _wait(a.anim_length("Joy"))


# ------------------------------------------------------------------ depuración

func debug_force_boss() -> void:
	progress = int(route["encounters_to_boss"])
	relayout()


func debug_levels(n: int) -> void:
	for p in Game.roster.team_members():
		p.gain_exp(SpeciesDB.exp_for_level(p.data()["growth_rate"], mini(100, p.level + n)) - p.xp)
	our_chip.refresh(true)


func debug_evolve() -> void:
	for p in fighters:
		var evo = p.data()["evolution"]
		if evo != null and SpeciesDB.has_sprite(evo["to"]):
			if p.level < int(evo["level"]):
				p.gain_exp(SpeciesDB.exp_for_level(p.data()["growth_rate"], int(evo["level"])) - p.xp)
			if state == State.WALK:
				state = State.BATTLE
				await evolve(_epoch, p)
				if state == State.BATTLE:
					state = State.WALK
			return
