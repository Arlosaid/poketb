class_name OfflineSim
extends RefCounted
## Progreso mientras el juego estuvo cerrado: simulación estadística por minutos
## (sin animaciones). Tope de 8 h. Da EXP, niveles, evoluciones, bayas y amistad;
## no captura y nunca llega al jefe (el jefe siempre se pelea en vivo).
## Los Pokémon pelean "con más calma" cuando no estás: eficiencia del 35%.

const MAX_SECONDS := 8.0 * 3600.0
const STEP := 60.0
const EFFICIENCY := 0.35
## Duración media de una pelea en vivo (s); se suma a la caminata media de la ruta.
const BATTLE_SECONDS := 14.0


## Devuelve un resumen: {seconds, wins, berries: {name: n}, mons: [{name, from_level, to_level, exp, evolved_to}]}
static func run(seconds: float, battle_mode: bool, combat: BattleController) -> Dictionary:
	var secs := minf(seconds, MAX_SECONDS)
	var roster := Game.roster
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var route := combat.route
	var summary := {"seconds": secs, "capped": seconds > MAX_SECONDS, "wins": 0, "berries": {}, "mons": []}
	var before := {}
	for p in roster.team_members():
		before[p.uid] = {"name": p.display_name(), "level": p.level, "xp": p.xp, "species": p.species}

	var ws: Array = route["walk_seconds"]
	var per_min := 60.0 / ((float(ws[0]) + float(ws[1])) / 2.0 + BATTLE_SECONDS)
	var acc := 0.0
	var t := 0.0
	while t < secs:
		var step := minf(STEP, secs - t)
		t += step
		var fighting := []
		if battle_mode:
			for p in roster.team_members():
				if roster.can_fight(p) and p.energy >= Roster.ENERGY_TO_FIGHT:
					fighting.append(p.uid)
		roster.tick(step, fighting, [])
		if fighting.is_empty():
			continue
		acc += per_min * EFFICIENCY * step / 60.0
		while acc >= 1.0:
			acc -= 1.0
			var lr: Array = route["level_range"]
			var f := float(combat.progress) / float(route["encounters_to_boss"])
			var lvl := clampi(int(round(lerpf(lr[0], lr[1], f))) + rng.randi_range(-1, 1), 2, 100)
			var table: Array = route["day"]
			var foe := PokemonInstance.create(BattleMath.pick_weighted(table, "species", rng), lvl, rng)
			summary["wins"] += 1
			combat.progress = mini(combat.progress + 1, int(route["encounters_to_boss"]))
			for u in fighting:
				var p: PokemonInstance = roster.get_member(u)
				p.gain_exp(BattleMath.exp_gain(p.level, foe, false))
				p.wins += 1
				if p.wins % 5 == 0:
					p.add_friendship(1)
				var to := p.evolution_ready()
				if to != "":
					p.evolve(to)
			if rng.randf() < float(route["drops"]["chance"]):
				var b := BattleMath.pick_weighted(route["drops"]["table"], "berry", rng)
				roster.add_berry(b)
				summary["berries"][b] = int(summary["berries"].get(b, 0)) + 1

	# El jefe siempre se pelea en vivo.
	combat.progress = mini(combat.progress, int(route["encounters_to_boss"]))
	for p in roster.team_members():
		if not before.has(p.uid):
			continue
		var b: Dictionary = before[p.uid]
		summary["mons"].append({
			"name": b["name"], "from_level": b["level"], "to_level": p.level,
			"exp": p.xp - int(b["xp"]),
			"evolved_to": p.display_name() if p.species != b["species"] else "",
			"hungry": p.fullness < 25.0,
		})
	return summary
