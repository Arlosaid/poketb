class_name SaveManager
extends Node
## Guardado automático en user://save.json: cada minuto y al cerrar.
## Escritura atómica (archivo temporal + renombrar) para no corromper nunca la partida.

const FILE := "save.json"
## Los escenarios de prueba usan su propio archivo y nunca tocan la partida real.
const SCENARIO_FILE := "scenario_save.json"
const VERSION := 1
const AUTOSAVE_EVERY := 60.0

var combat: BattleController
## Si es true, no se guarda al cerrar (para el escenario que prepara un guardado viejo).
var skip_quit_save := false
## Posición guardada de la ventana de pelea (null = la de por defecto).
var saved_battle_pos: Variant = null
var battle_window: Window
var _timer := 0.0


func setup(c: BattleController) -> void:
	combat = c


func _process(delta: float) -> void:
	_timer += delta / maxf(1.0, Engine.time_scale)  # siempre cada 60 s reales
	if _timer >= AUTOSAVE_EVERY:
		_timer = 0.0
		save()


func _file() -> String:
	return SCENARIO_FILE if Game.scenario != "" else FILE


func _battle_pos_json() -> Variant:
	if is_instance_valid(battle_window):
		return [battle_window.position.x, battle_window.position.y]
	if saved_battle_pos is Vector2i:
		return [saved_battle_pos.x, saved_battle_pos.y]
	return null


## `age`: segundos a restar a la marca de tiempo (solo para probar el progreso offline).
func save(age := 0.0) -> void:
	var data := {
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system() - age,
		"mode": String(Game.mode),
		"roster": Game.roster.to_dict(),
		"route": {"id": combat.route.get("id", "ruta_1"), "progress": combat.progress, "cleared": combat.cleared},
		"ui": {"battle_pos": _battle_pos_json()},
	}
	var tmp := _file() + ".tmp"
	var f := FileAccess.open("user://" + tmp, FileAccess.WRITE)
	if f == null:
		push_error("No se pudo escribir el guardado: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir.file_exists(_file()):
		dir.remove(_file())
	var err := dir.rename(tmp, _file())
	if err != OK:
		push_error("No se pudo completar el guardado (%d)" % err)


## Carga la partida si existe. Devuelve los segundos que pasaron desde el último guardado
## (-1 si no había partida).
func load_game() -> float:
	# Solo el juego normal y el escenario que prueba la carga leen un guardado.
	if Game.scenario != "" and not Game.scenario.begins_with("save_load"):
		return -1.0
	var path := "user://" + _file()
	if not FileAccess.file_exists(path):
		return -1.0
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", 0)) != VERSION:
		push_warning("Guardado ilegible o de otra versión; se empieza de nuevo.")
		return -1.0
	Game.roster.from_dict(d["roster"])
	var r: Dictionary = d.get("route", {})
	combat.progress = int(r.get("progress", 0))
	combat.cleared = bool(r.get("cleared", false))
	Game.mode = StringName(d.get("mode", "battle"))
	var bp = d.get("ui", {}).get("battle_pos")
	if bp is Array and bp.size() == 2:
		saved_battle_pos = Vector2i(int(bp[0]), int(bp[1]))
	return maxf(0.0, Time.get_unix_time_from_system() - float(d.get("saved_at", 0.0)))
