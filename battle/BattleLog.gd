class_name BattleLog
extends PanelContainer
## Cajita de diálogo (estilo Explorers) pegada al borde superior de la ventana de
## pelea, centrada. Muestra un mensaje a la vez (con salto de línea si es largo).

var _label: Label
var _queue: Array = []   # [[texto, segundos], ...]
var _busy := false
## Ancho de la ventana donde se centra la cajita (px lógicos).
var area_width := 216.0
const MAX_TEXT := 190.0


func _ready() -> void:
	theme_type_variation = &"DialogPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.theme_type_variation = &"DialogLabel"
	add_child(_label)
	modulate.a = 0.0


## Encola un mensaje. `hold`: segundos visible (se acorta si hay más en cola,
## para que el texto nunca se atrase respecto de la acción).
const MIN_SHOW := 0.55

var _elapsed := 0.0
var _hold := 0.0


func say(text: String, hold := 1.4) -> void:
	_queue.append([text, hold])
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.2)
		return
	_busy = true
	var item: Array = _queue.pop_front()
	_label.text = item[0]
	_hold = item[1]
	_elapsed = 0.0
	var font := _label.get_theme_font("font")
	var fs := _label.get_theme_font_size("font_size")
	var wide := font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > MAX_TEXT
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wide else TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size.x = MAX_TEXT if wide else 0.0
	reset_size()
	position = Vector2((area_width - size.x) / 2.0, 0.0).round()
	if modulate.a < 1.0:
		create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


func _process(delta: float) -> void:
	if not _busy:
		return
	_elapsed += delta
	if _elapsed >= _hold or (_elapsed >= MIN_SHOW and not _queue.is_empty()):
		_next()


func clear() -> void:
	_queue.clear()
