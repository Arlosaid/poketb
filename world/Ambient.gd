class_name Ambient
extends Node2D
## Partículas ambientales sutiles, dibujadas como píxeles de la paleta:
##   pollen     motas que flotan de día
##   fireflies  luciérnagas que parpadean de noche
##   leaves     hojitas que caen en el bosque

const COUNT := {"pollen": 7, "fireflies": 9, "leaves": 5}

var area := Vector2i(376, 56)
var kind := "pollen":
	set(v):
		if v != kind:
			kind = v
			_spawn_all()

var _p: Array[Dictionary] = []
var _t := 0.0


func _ready() -> void:
	_spawn_all()


func _spawn_all() -> void:
	_p.clear()
	for i in COUNT.get(kind, 0):
		_p.append(_spawn(true))


func _spawn(anywhere: bool) -> Dictionary:
	var d := {
		"pos": Vector2(randf() * area.x, randf_range(area.y * 0.25, area.y * 0.85)),
		"vel": Vector2(randf_range(-2.0, 2.0), randf_range(-1.5, 0.5)),
		"phase": randf() * TAU,
	}
	if kind == "leaves":
		d["vel"] = Vector2(randf_range(-4.0, -1.0), randf_range(3.0, 5.0))
		if not anywhere:
			d["pos"].y = -2.0
	return d


## El paisaje se desplaza: las partículas se quedan atrás un poco (parallax medio).
func scroll(dx: float) -> void:
	for d in _p:
		d["pos"].x -= dx * 0.6


func _process(delta: float) -> void:
	_t += delta
	for i in _p.size():
		var d := _p[i]
		var wobble := Vector2(sin(_t * 0.9 + d["phase"]) * 3.0, cos(_t * 0.7 + d["phase"]) * 2.0)
		d["pos"] += (d["vel"] + wobble) * delta
		var p: Vector2 = d["pos"]
		if p.x < -4.0:
			d["pos"].x += area.x + 8.0
		elif p.x > area.x + 4.0:
			d["pos"].x -= area.x + 8.0
		if p.y < area.y * 0.1 or p.y > area.y - 4.0:
			_p[i] = _spawn(false)
			if kind != "leaves":
				_p[i]["pos"].y = area.y * 0.6
	queue_redraw()


func _draw() -> void:
	for d in _p:
		var p := (d["pos"] as Vector2).floor()
		match kind:
			"pollen":
				draw_rect(Rect2(p, Vector2.ONE), Palette.LIME if int(d["phase"] * 10.0) % 2 else Palette.HONEY)
			"fireflies":
				var on := sin(_t * 1.6 + d["phase"] * 3.0)
				if on > 0.2:
					draw_rect(Rect2(p, Vector2.ONE), Palette.HONEY)
					if on > 0.75:
						for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
							draw_rect(Rect2(p + o, Vector2.ONE), Palette.a(Palette.AMBER, 0.6))
			"leaves":
				var flip := sin(_t * 3.0 + d["phase"]) > 0.0
				draw_rect(Rect2(p, Vector2(2, 1) if flip else Vector2(1, 2)), Palette.GRASS if int(d["phase"] * 10.0) % 2 else Palette.SPROUT)
