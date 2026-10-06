class_name Bubble
extends PanelContainer
## Bocadillo sobre la cabeza de un Pokémon: retrato PMD (40x40) + texto opcional +
## botones de acción opcionales. Aparece con un pequeño "pop" y se va solo.

signal action(id: String)

const TAIL := preload("res://assets/ui/bubble_tail.png")
## Cadenas de respaldo de retratos (no todas las especies tienen todas las emociones).
const PORTRAIT_FALLBACK := {
	"Joyous": ["Joyous", "Inspired", "Happy", "Normal"],
	"Happy": ["Happy", "Joyous", "Normal"],
	"Sad": ["Sad", "Teary-Eyed", "Worried", "Normal"],
	"Angry": ["Angry", "Determined", "Sad", "Normal"],
	"Worried": ["Worried", "Sad", "Normal"],
	"Sigh": ["Sigh", "Worried", "Normal"],
	"Surprised": ["Surprised", "Stunned", "Normal"],
	"Determined": ["Determined", "Normal"],
	"Pain": ["Pain", "Worried", "Normal"],
	"Normal": ["Normal"],
}

var target: Node2D
var _tail_pos := Vector2.ZERO
var _life := 0.0
var _hovered_once := false
## Desplazamiento animado del "pop" de entrada (px lógicos hacia abajo).
var _pop := 4.0


## Crea y muestra un bocadillo. `actions`: [[id, texto], ...]
static func show_for(hud: Control, actor: PokemonActor, emotion: String, text := "", actions: Array = [], life := 3.5) -> Bubble:
	var b := Bubble.new()
	b.target = actor
	b._life = life
	hud.add_child(b)
	b._build(actor, emotion, text, actions)
	return b


static func portrait_texture(actor: PokemonActor, emotion: String) -> Texture2D:
	return portrait_for(actor.species, emotion)


static func portrait_for(species: String, emotion: String) -> Texture2D:
	var ports: Dictionary = PokemonActor.load_meta(species).get("portraits", {})
	for e in PORTRAIT_FALLBACK.get(emotion, [emotion, "Normal"]):
		if ports.has(e):
			return load(ports[e])
	return null


func _build(actor: PokemonActor, emotion: String, text: String, actions: Array) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Slot"
	row.add_child(frame)
	var tr := TextureRect.new()
	tr.texture = portrait_texture(actor, emotion)
	tr.custom_minimum_size = Vector2(40, 40)
	frame.add_child(tr)
	if text != "" or not actions.is_empty():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		if text != "":
			var l := Label.new()
			l.text = text
			col.add_child(l)
		if not actions.is_empty():
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 2)
			col.add_child(hb)
			for a in actions:
				var btn := Button.new()
				btn.text = a[1]
				btn.focus_mode = Control.FOCUS_NONE
				btn.pressed.connect(func() -> void: action.emit(a[0]))
				hb.add_child(btn)
	Passthrough.register(self)
	reset_size()
	_place()
	# pop: aparece desde 4 px abajo con alfa 0 → 1
	modulate.a = 0.0
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_pop", 0.0, 0.2)
	t.parallel().tween_property(self, "modulate:a", 1.0, 0.15)


func get_click_rect() -> Rect2:
	return get_global_rect()


func _place() -> void:
	if not is_instance_valid(target):
		return
	var head: Vector2 = target.global_position + (target as PokemonActor).head_point()
	var vp := get_viewport_rect().size
	var x := clampf(head.x - size.x / 2.0, 2.0, vp.x - size.x - 3.0)
	# 12 px de aire sobre la cabeza para que se vean los corazones
	var y := maxf(1.0, head.y - size.y - 12.0)
	position = Vector2(x, y + _pop).round()
	# la cola apunta a la cabeza aunque el bocadillo esté corrido por los bordes
	var tp := Vector2(clampf(head.x - position.x - 3.0, 6.0, size.x - 12.0), size.y - 2.0).round()
	if tp != _tail_pos:
		_tail_pos = tp
		queue_redraw()


func _draw() -> void:
	# La cola se dibuja aquí (como hijo de un Container se estiraría).
	draw_texture(TAIL, _tail_pos)


func _process(delta: float) -> void:
	_place()
	if Passthrough.hovered() == self:
		_hovered_once = true
		return  # mientras lo miras, no se va
	_life -= delta
	if _life <= 0.0:
		close()


func close() -> void:
	set_process(false)
	Passthrough.unregister(self)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(queue_free)
