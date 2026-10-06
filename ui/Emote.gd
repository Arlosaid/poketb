class_name Emote
extends Node2D
## Globito de emoción sobre la cabeza (estilo de los compañeros de HGSS): 11x13 px con un
## ícono de 7x7. No es clicable (nunca bloquea el mouse) y se va solo.
## Íconos: heart, note, exclaim, question, dots, anger, sweat, zzz, star, berry, ball.

const BUBBLE := preload("res://assets/ui/emote_bubble.png")
const SHEET := preload("res://assets/ui/emotes.png")

static var _index: Dictionary

var target: PokemonActor
var _icon: Sprite2D
var _life := 1.6
var _pop := 3.0


## Índice del ícono en emotes.png (-1 si no existe).
static func icon_index(icon: String) -> int:
	if _index.is_empty():
		_index = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/emotes_index.json"))["index"]
	return int(_index.get(icon, -1))


## Muestra el globo sobre `actor` (uno por actor: reemplaza al anterior).
static func show_on(parent: Node, actor: PokemonActor, icon: String, life := 1.6) -> Emote:
	var idx := icon_index(icon)
	if idx < 0 or actor.attached(&"bubble") or actor.attached(&"card"):
		return null  # ya hay un cartel sobre la cabeza
	var prev := actor.attached(&"emote")
	if prev:
		prev.queue_free()
	var e := Emote.new()
	e.target = actor
	e._life = life
	e.z_index = 30
	parent.add_child(e)
	e._build(idx)
	actor.set_meta(&"emote", e)
	return e


func _build(idx: int) -> void:
	var b := Sprite2D.new()
	b.texture = BUBBLE
	b.centered = false
	add_child(b)
	_icon = Sprite2D.new()
	_icon.texture = SHEET
	_icon.centered = false
	_icon.region_enabled = true
	_icon.region_rect = Rect2(idx * 7, 0, 7, 7)
	_icon.position = Vector2(2, 2)
	add_child(_icon)
	modulate.a = 0.0
	_place()
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_pop", 0.0, 0.18)
	t.parallel().tween_property(self, "modulate:a", 1.0, 0.1)


func _place() -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	# la punta de la cola (x=5, y=12 del globo) queda 2 px sobre la cabeza, un poco a la derecha
	var head := target.position + target.head_point()
	position = (head + Vector2(-1, -15 + _pop)).round()


func _process(delta: float) -> void:
	_place()
	_life -= delta
	if _life <= 0.0:
		set_process(false)
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.2)
		t.tween_callback(queue_free)
