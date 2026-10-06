class_name PcSense
extends Node
## "Sentidos" de las mascotas sobre lo que pasa en la PC. Todo es local y barato:
## se consulta cada pocos segundos (nunca por cuadro).
##
## Privacidad (ver docs/decisiones.md): solo se lee el NOMBRE del ejecutable de la ventana
## activa y se traduce a una categoría de data/apps.json. Nunca se leen títulos,
## teclas ni contenido, y nada de esto se guarda ni se escribe en el log.

signal app_changed(category: String)
## Volviste tras estar `away` segundos sin tocar teclado ni mouse.
signal user_returned(away: float)
## Llevas mucho rato seguido: el compañero propone una pausa.
signal break_suggested
## Tomaste la pausa que te propuso (el equipo se anima).
signal break_taken
signal late_night
signal battery_low(percent: int)
signal battery_charging

const POLL := 3.0
const POWER_POLL := 60.0
const AWAY_FOR_GREETING := 300.0
## Inactividad que corta la racha de trabajo aunque no sea una pausa completa.
const ACTIVE_IDLE_MAX := 120.0

var category := ""
var _apps: Dictionary
var _by_exe := {}
var _timer := 0.0
var _power_timer := 5.0
var _max_idle := 0.0
var _streak := 0.0
var _suggested_at := -1e9
var _waiting_break := false
var _late_night_day := -1
var _battery_warned := false
var _was_charging := true


func _ready() -> void:
	_apps = JSON.parse_string(FileAccess.get_file_as_string("res://data/apps.json"))
	for cat in _apps["categories"]:
		for exe in _apps["categories"][cat]:
			_by_exe[String(exe).to_lower()] = cat


func reaction(cat: String) -> Dictionary:
	return _apps["reactions"].get(cat, {})


func wellbeing() -> Dictionary:
	return _apps["wellbeing"]


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = POLL
	if Game.scenario != "":
		return  # los escenarios disparan las señales a mano
	_poll_idle(POLL)
	_poll_app()
	_power_timer -= POLL
	if _power_timer <= 0.0:
		_power_timer = POWER_POLL
		_poll_power()


func _poll_app() -> void:
	if not Game.settings.get("app_react", true) or Game.native == null or not Game.native.has_method("get_foreground_app"):
		if category != "":
			category = ""
			app_changed.emit("")
		return
	var exe: String = Game.native.get_foreground_app()
	if exe == "":
		return  # este mismo juego o desconocido: no cambia nada
	var cat: String = _by_exe.get(exe, "other")
	if cat != category:
		category = cat
		app_changed.emit(cat)


func _poll_idle(step: float) -> void:
	var idle := Game.user_idle_seconds()
	var wb := wellbeing()
	if idle < 5.0 and _max_idle >= AWAY_FOR_GREETING:
		user_returned.emit(_max_idle)
	if idle < 5.0 and _waiting_break and _max_idle >= float(wb["break_minutes"]) * 60.0:
		_waiting_break = false
		break_taken.emit()
	_max_idle = idle if idle >= 5.0 else 0.0
	if not Game.settings.get("wellbeing", true):
		_streak = 0.0
		return
	# racha de uso continuo (se corta con una pausa de break_minutes)
	if idle >= float(wb["break_minutes"]) * 60.0:
		_streak = 0.0
	elif idle < ACTIVE_IDLE_MAX:
		_streak += step
	var now := Time.get_ticks_msec() / 1000.0
	if _streak >= float(wb["work_minutes"]) * 60.0 and now - _suggested_at >= float(wb["remind_again_minutes"]) * 60.0:
		_suggested_at = now
		_waiting_break = true
		break_suggested.emit()
	# trasnochando: una vez por noche
	var t := Time.get_datetime_dict_from_system()
	var h := int(t["hour"])
	if idle < 30.0 and h >= int(wb["late_night_from"]) and h < int(wb["late_night_to"]) and _late_night_day != int(t["day"]):
		_late_night_day = int(t["day"])
		late_night.emit()


func _poll_power() -> void:
	if Game.native == null or not Game.native.has_method("get_power_status"):
		return
	var ps: Dictionary = Game.native.get_power_status()
	if not ps.get("has_battery", false):
		return
	var pct := int(ps.get("percent", -1))
	var charging := bool(ps.get("charging", false))
	if pct >= 0 and pct <= int(wellbeing()["battery_low"]) and not charging and not _battery_warned:
		_battery_warned = true
		battery_low.emit(pct)
	if charging and not _was_charging:
		if _battery_warned:
			battery_charging.emit()
		_battery_warned = false
	_was_charging = charging
