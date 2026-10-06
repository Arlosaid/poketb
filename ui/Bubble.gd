class_name Bubble
extends PanelContainer
## Globo de texto delgado sobre la cabeza de un Pokémon (una línea, sin retrato ni
## botones). No es clicable: nunca bloquea el mouse. Aparece con un "pop" y se va solo.
## Para emociones sin texto se usa Emote (más chico todavía).

const TAIL := preload("res://assets/ui/text_tail.png")
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

var target: PokemonActor
var _tail_pos := Vector2.ZERO
var _life := 0.0
## Desplazamiento animado del "pop" de entrada (px lógicos hacia abajo).
var _pop := 3.0


## Muestra un globo con `text` (uno por actor: reemplaza al anterior). La duración
## depende del largo del texto si no se indica.
static func say(hud: Control, actor: PokemonActor, text: String, life := -1.0) -> Bubble:
	var prev := actor.attached(&"bubble")
	if prev:
		prev.close()
	# un solo cartel a la vez sobre la cabeza
	for k in [&"emote", &"card"]:
		var other := actor.attached(k)
		if other:
			other.queue_free()
	var b := Bubble.new()
	b.target = actor
	b._life = life if life > 0.0 else clampf(1.6 + text.length() * 0.07, 2.0, 4.5)
	b.theme_type_variation = &"TextBubble"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(b)
	var l := Label.new()
	l.text = text
	b.add_child(l)
	b.reset_size()
	b._place()
	actor.set_meta(&"bubble", b)
	b.modulate.a = 0.0
	var t := b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "_pop", 0.0, 0.18)
	t.parallel().tween_property(b, "modulate:a", 1.0, 0.12)
	return b


static func portrait_for(species: String, emotion: String) -> Texture2D:
	return PokemonActor.portrait(species, PORTRAIT_FALLBACK.get(emotion, [emotion, "Normal"]))


func _place() -> void:
	if not is_instance_valid(target):
		return
	var head: Vector2 = target.global_position + target.head_point()
	var vp := get_viewport_rect().size
	var x := clampf(head.x - size.x / 2.0, 2.0, vp.x - size.x - 3.0)
	# 8 px de aire sobre la cabeza (deja ver los corazones)
	var y := maxf(1.0, head.y - size.y - 8.0)
	position = Vector2(x, y + _pop).round()
	var tp := Vector2(clampf(head.x - position.x - 2.0, 3.0, size.x - 8.0), size.y - 2.0).round()
	if tp != _tail_pos:
		_tail_pos = tp
		queue_redraw()


func _draw() -> void:
	# La cola se dibuja aquí (como hijo de un Container se estiraría).
	draw_texture(TAIL, _tail_pos)


func _process(delta: float) -> void:
	_place()
	_life -= delta
	if _life <= 0.0:
		close()


func close() -> void:
	set_process(false)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(queue_free)
