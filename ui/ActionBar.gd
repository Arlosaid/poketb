class_name ActionBar
extends PanelContainer
## Barrita de acciones junto a un Pokémon (clic derecho): botones de ícono de 9x9.
## El nombre de la acción solo aparece al pasar el mouse. Se cierra sola si la ignoras.

signal chosen(id: String)

const ICONS := preload("res://assets/ui/actions.png")
## Índice de cada ícono en actions.png (ver tools/gen_ui.py: action_icons).
const ICON_INDEX := {"berry": 0, "ball": 1, "sleep": 2, "wake": 3, "card": 4}
const LIFE := 5.0

var target: PokemonActor
var _info: Label
var _life := LIFE


## `actions`: [[id, texto], ...] con id ∈ ICON_INDEX.
static func open(hud: Control, actor: PokemonActor, actions: Array) -> ActionBar:
	var m := ActionBar.new()
	m.target = actor
	m.theme_type_variation = &"TextBubble"
	hud.add_child(m)
	m._build(actions)
	return m


static func icon(id: String) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = ICONS
	at.region = Rect2(int(ICON_INDEX.get(id, 0)) * 9, 0, 9, 9)
	return at


func _build(actions: Array) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	add_child(v)
	_info = Label.new()
	_info.visible = false
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	v.add_child(row)
	for a in actions:
		var btn := Button.new()
		btn.theme_type_variation = &"Chip"
		btn.icon = icon(a[0])
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_entered.connect(_show_info.bind(a[1]))
		btn.mouse_exited.connect(_show_info.bind(""))
		btn.pressed.connect(func() -> void:
			chosen.emit(a[0])
			close())
		row.add_child(btn)
	Passthrough.register(self)
	reset_size()
	_place()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


func _show_info(text: String) -> void:
	_info.text = text
	_info.visible = text != ""
	reset_size()


func get_click_rect() -> Rect2:
	return get_global_rect()


func _place() -> void:
	if not is_instance_valid(target):
		close()
		return
	var head := target.global_position + target.head_point()
	var vp := get_viewport_rect().size
	# encima de la cabeza; el borde inferior se mantiene fijo aunque aparezca el nombre
	position = Vector2(clampf(head.x - size.x / 2.0, 2.0, vp.x - size.x - 3.0), maxf(1.0, head.y - size.y - 4.0)).round()


func _process(delta: float) -> void:
	_place()
	if Passthrough.hovered() == self:
		_life = LIFE * 0.6
		return
	_life -= delta
	if _life <= 0.0:
		close()


func close() -> void:
	if not is_processing():
		return
	set_process(false)
	Passthrough.unregister(self)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	t.tween_callback(queue_free)
