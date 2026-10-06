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
## Estado de clic a través por ventana (id de ventana → bool).
var _through := {}
var _hover: Node = null
## Mientras se arrastra algo, la ventana no suelta el mouse.
var capture_count := 0
## Si es true, nunca se activa el clic a través (por ejemplo, sin la extensión).
var disabled := false
## Si es finito, sustituye a la posición real del cursor (escenarios automatizados).
var fake_mouse := Vector2.INF


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


## Posición del cursor en coordenadas del viewport de la ventana `win` (la principal
## por defecto), aunque la ventana no reciba eventos.
func mouse_in_viewport(win: Window = null) -> Vector2:
	var root := get_tree().root
	if win == null:
		win = root
	if win == root and fake_mouse.is_finite():
		return fake_mouse
	var local := Vector2(DisplayServer.mouse_get_position() - win.position)
	return win.get_final_transform().affine_inverse() * local


func _process(_delta: float) -> void:
	_hover = null
	var windows := {get_tree().root: true}
	# Recorremos al revés: lo último registrado suele estar encima.
	for i in range(_nodes.size() - 1, -1, -1):
		var n := _nodes[i]
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		var w := n.get_window()
		if not w.visible:
			continue
		windows[w] = true
		if _hover != null:
			continue
		var r: Rect2 = n.get_click_rect()
		if r.grow(MARGIN).has_point(mouse_in_viewport(w)):
			_hover = n
	var hover_win: Window = _hover.get_window() if _hover != null else null
	for w: Window in windows:
		_set_click_through(w, hover_win != w and capture_count == 0 and not disabled)


func _set_click_through(w: Window, enabled: bool) -> void:
	var id := w.get_window_id()
	if Game.native == null or _through.get(id, false) == enabled:
		return
	_through[id] = enabled
	Game.native.set_click_through(id, enabled)


func is_click_through() -> bool:
	return _through.get(get_tree().root.get_window_id(), false)
