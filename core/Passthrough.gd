extends Node
## Autoload: decide cada frame si la ventana principal deja pasar el mouse.
##
## Todo lo que deba ser clicable (Pokémon, paneles, botones) se registra con
## `Passthrough.register(node)` e implementa `get_click_rect() -> Rect2` en
## coordenadas del viewport (escala lógica). Si el cursor no está sobre ninguno,
## la ventana pasa a ser "transparente al mouse" (WS_EX_TRANSPARENT vía DesktopNative)
## y los clics llegan a las apps de abajo.
##
## Ver docs/decisiones.md: no se usa window_set_mouse_passthrough porque en
## Windows recorta también el render.

## Margen extra (px lógicos) alrededor de cada rect, para que no cueste atinar.
const MARGIN := 2.0

var _nodes: Array[Node] = []
var _click_through := false
var _hover: Node = null
## Mientras se arrastra algo, la ventana no suelta el mouse.
var capture_count := 0
## Si es true, nunca se activa el clic a través (por ejemplo, sin la extensión).
var disabled := false


func register(n: Node) -> void:
	if n not in _nodes:
		_nodes.append(n)
		n.tree_exiting.connect(unregister.bind(n), CONNECT_ONE_SHOT)


func unregister(n: Node) -> void:
	_nodes.erase(n)
	if _hover == n:
		_hover = null


## Nodo clicable bajo el cursor (o null).
func hovered() -> Node:
	return _hover


## Posición del cursor en coordenadas del viewport principal, aunque la ventana no reciba eventos.
func mouse_in_viewport() -> Vector2:
	var win := get_tree().root
	var local := Vector2(DisplayServer.mouse_get_position() - win.position)
	return win.get_final_transform().affine_inverse() * local


func _process(_delta: float) -> void:
	var p := mouse_in_viewport()
	_hover = null
	# Recorremos al revés: lo último registrado suele estar encima.
	for i in range(_nodes.size() - 1, -1, -1):
		var n := _nodes[i]
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		var r: Rect2 = n.get_click_rect()
		if r.grow(MARGIN).has_point(p):
			_hover = n
			break
	var want := _hover == null and capture_count == 0 and not disabled
	_set_click_through(want)


func _set_click_through(enabled: bool) -> void:
	if enabled == _click_through or Game.native == null:
		return
	_click_through = enabled
	Game.native.set_click_through(get_tree().root.get_window_id(), enabled)


func is_click_through() -> bool:
	return _click_through
