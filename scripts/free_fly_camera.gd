class_name FreeFlyCamera
extends Camera3D
## Free-fly camera mirroring the HTML prototype controls.
##
## Right mouse drag (or a captured mouse, toggled with Esc) looks around.
## WASD moves in the camera's forward/right plane, Q/E moves down/up along
## world Y, Shift is a fast multiplier and the mouse wheel scales the base speed.

const PITCH_LIMIT := 1.5
const WHEEL_STEP := 1.15
const MIN_SPEED_SCALE := 0.05
const MAX_SPEED_SCALE := 50.0

@export var speed := 5.0
@export var fast_speed := 18.0
@export var mouse_sensitivity := 0.003
@export var yaw := 0.9
@export var pitch := -0.28

var speed_scale := 1.0


func _ready() -> void:
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var dragging := motion.button_mask & MOUSE_BUTTON_MASK_RIGHT != 0
		if captured or dragging:
			yaw -= motion.relative.x * mouse_sensitivity
			pitch = clampf(pitch - motion.relative.y * mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
			_apply_rotation()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed_scale = minf(speed_scale * WHEEL_STEP, MAX_SPEED_SCALE)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed_scale = maxf(speed_scale / WHEEL_STEP, MIN_SPEED_SCALE)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_toggle_mouse_capture()


func _process(delta: float) -> void:
	var direction := Vector3.ZERO
	var basis := global_transform.basis
	if Input.is_physical_key_pressed(KEY_W):
		direction -= basis.z
	if Input.is_physical_key_pressed(KEY_S):
		direction += basis.z
	if Input.is_physical_key_pressed(KEY_D):
		direction += basis.x
	if Input.is_physical_key_pressed(KEY_A):
		direction -= basis.x
	if Input.is_physical_key_pressed(KEY_E):
		direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		direction -= Vector3.UP
	if direction == Vector3.ZERO:
		return
	var base_speed := fast_speed if Input.is_key_pressed(KEY_SHIFT) else speed
	global_position += direction.normalized() * base_speed * speed_scale * delta


func _apply_rotation() -> void:
	rotation = Vector3(pitch, yaw, 0.0)


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
