class_name ToyBall
extends Node2D
## Pelota de juguete en casa. Rebota con física simple; se arrastra y se lanza con el
## mouse (el impulso es la velocidad del cursor al soltar). Las mascotas juguetonas la
## persiguen y la patean (ver PetBrain). Si nadie la toca un rato, desaparece sola.

## La lanzaste tú (para que las mascotas juguetonas salgan detrás).
signal thrown

const TEX := preload("res://assets/ui/toy_ball.png")
const GRAVITY := 420.0
const BOUNCE := 0.55
const ROLL_FRICTION := 90.0
const IDLE_LIFE := 45.0
const MAX_THROW := 260.0

var home: HomeArea
var vel := Vector2.ZERO
## La lanzó el usuario y todavía nadie la pateó: el primero que la alcance gana amistad.
var fresh_throw := false

var _sprite: Sprite2D
var _idle := 0.0
var _pressing := false
var _grab := Vector2.ZERO
var _last_cursor := Vector2.ZERO
var _cursor_vel := Vector2.ZERO
var _spin := 0.0


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.offset = Vector2(0, -3)
	add_child(_sprite)
	z_index = 5
	Passthrough.register(self)


func get_click_rect() -> Rect2:
	return Rect2(global_position + Vector2(-5, -8), Vector2(10, 10))


func on_ground() -> bool:
	return position.y >= home.ground_y - 0.5


func is_resting() -> bool:
	return on_ground() and absf(vel.x) < 8.0


## Impulso (desde una mascota que la patea o desde el usuario).
func kick(v: Vector2, by_user := false) -> void:
	vel = v
	_idle = 0.0
	fresh_throw = by_user
	if position.y >= home.ground_y:
		position.y = home.ground_y - 0.5
	if by_user:
		thrown.emit()


func _process(delta: float) -> void:
	var cursor := Passthrough.mouse_in_viewport()
	if _pressing:
		_cursor_vel = _cursor_vel.lerp((cursor - _last_cursor) / maxf(delta, 0.001), 0.5)
		_last_cursor = cursor
		position = home.clamp_drag(cursor + _grab).round()
		_idle = 0.0
		home.desk.keep_awake()
		return
	if not is_resting() or not on_ground():
		_step(delta)
		home.desk.keep_awake()
	else:
		vel = Vector2.ZERO
		_idle += delta
		if _idle > IDLE_LIFE:
			_vanish()


func _step(delta: float) -> void:
	vel.y += GRAVITY * delta
	position += vel * delta
	_spin += vel.x * delta * 0.25
	_sprite.flip_h = int(_spin) % 2 == 1  # "rueda" sin rotar el pixel art
	if position.x < home.x_min - 16.0 or position.x > home.x_max + 6.0:
		position.x = clampf(position.x, home.x_min - 16.0, home.x_max + 6.0)
		vel.x = -vel.x * 0.7
	if position.y >= home.ground_y:
		position.y = home.ground_y
		if vel.y > 60.0:
			vel.y = -vel.y * BOUNCE
			Fx.dust(home, position)
		else:
			vel.y = 0.0
			vel.x = move_toward(vel.x, 0.0, ROLL_FRICTION * delta)
	position = Vector2(position.x, minf(position.y, home.ground_y))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Passthrough.hovered() == self:
			_pressing = true
			_last_cursor = Passthrough.mouse_in_viewport()
			_cursor_vel = Vector2.ZERO
			_grab = position - _last_cursor
			Passthrough.capture_count += 1
			get_viewport().set_input_as_handled()
		elif not event.pressed and _pressing:
			_pressing = false
			Passthrough.capture_count = maxi(0, Passthrough.capture_count - 1)
			# un clic sin arrastrar la tira hacia arriba
			var v := _cursor_vel if _cursor_vel.length() > 30.0 else Vector2(randf_range(-70.0, 70.0), -170.0)
			kick(v.limit_length(MAX_THROW), true)


func _vanish() -> void:
	set_process(false)
	Passthrough.unregister(self)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	t.tween_callback(queue_free)
