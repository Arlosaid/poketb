class_name GameClock
extends RefCounted
## Tiempo de juego: respeta la pausa y la velocidad de depuración (x10).
## También da la hora "real" del día para el cielo, que en debug se puede forzar.

signal time_of_day_changed(phase: StringName)

var paused := false
## Multiplicador de depuración. Se aplica con Engine.time_scale, así que el delta
## que llega a step() ya viene acelerado.
var speed := 1.0:
	set(v):
		speed = v
		Engine.time_scale = v
## Si es >= 0, sustituye a la hora real (0..24). Solo para depuración.
var forced_hour := -1.0
## Segundos de juego acumulados en esta sesión.
var elapsed := 0.0

var _phase: StringName = &""


## Delta de juego a partir del delta del frame.
func step(real_delta: float) -> float:
	var d := 0.0 if paused else real_delta
	elapsed += d
	var p := phase()
	if p != _phase:
		_phase = p
		time_of_day_changed.emit(p)
	return d


## Hora del día en 0..24 (con decimales).
func hour() -> float:
	if forced_hour >= 0.0:
		return forced_hour
	var t := Time.get_time_dict_from_system()
	return t.hour + t.minute / 60.0 + t.second / 3600.0


## &"dawn" 5–8, &"day" 8–17, &"dusk" 17–20, &"night" 20–5.
func phase() -> StringName:
	var h := hour()
	if h >= 5.0 and h < 8.0:
		return &"dawn"
	if h >= 8.0 and h < 17.0:
		return &"day"
	if h >= 17.0 and h < 20.0:
		return &"dusk"
	return &"night"


func is_night() -> bool:
	return phase() == &"night"
