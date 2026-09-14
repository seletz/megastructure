class_name Player
extends CharacterBody3D
## The walking capsule: WASD relative to the camera's yaw, Space jumps,
## Shift runs, gravity, and a step-up for stair treads and slab lips.
##
##     var player: Player = $Player
##     player.walking = true            # simulate and drive the camera
##     player.first_person = false      # camera behind and above the capsule
##     player.scripted_direction = Vector3(1, 0, 0)   # tools: walk +x without keys
##
## The body's origin is at the feet; its `CollisionShape3D` child holds the
## capsule, centred `capsule_height / 2` above them. While `walking`, the
## camera at `camera` (a FreeFlyCamera) is moved to the eye each frame, or
## `third_person_distance` behind it along the view direction, keeping the
## camera's own mouse look (its yaw and pitch), and its WASD flight is
## switched off; an optional `Body` child (the visible capsule) is hidden
## in first person. With `walking` false the body is frozen and the camera flies
## freely again.
##
## Stepping: CharacterBody3D slides along anything steeper than
## `floor_max_angle`, so a riser would stop it. When the body is on the floor
## and its horizontal motion this frame hits such a surface, it probes the
## same motion from `step_height` higher, `STEP_PROBE` metres further on;
## when that is free and a move down from there lands on a floor above the
## feet, the body is lifted by that rise before sliding. `floor_snap_length`
## keeps it on the floor walking down. The placeholder stair climbs 0.4 m per
## tread, but a flight ends 0.6 m below the landing slab (the top tread is
## flush with the cell top, the slab top 0.6 m above the cell bottom), so the
## default `step_height` is 0.65 m.
##
## Esc captures or releases the mouse; the event is marked handled so the
## camera does not toggle it back. Keys are ignored while a UI text field has
## focus (see UiKeys).

## Extra forward distance of the step probe beyond this frame's motion, so the
## rounded bottom of the capsule clears the edge it steps onto.
const STEP_PROBE := 0.15

## FreeFlyCamera that follows the body.
@export var camera: NodePath
@export var walk_speed := 4.0
@export var run_speed := 8.0
@export var jump_velocity := 4.5
@export var gravity := 9.8
## Highest ledge the body walks up without jumping, in metres.
@export var step_height := 0.65
@export var capsule_radius := 0.3:
	set(value):
		capsule_radius = value
		_apply_shape()
@export var capsule_height := 1.8:
	set(value):
		capsule_height = value
		_apply_shape()
## Camera height above the feet in first person, and the point the third
## person camera looks at.
@export var eye_height := 1.6
## First person at the eye, else third person behind it.
@export var first_person := true
@export var third_person_distance := 4.0
## Simulates and drives the camera; false freezes the body.
@export var walking := true:
	set(value):
		walking = value
		_apply_walking()

## When not zero, replaces the keys: the horizontal direction to walk in
## (normalised here), at `walk_speed`. For scripted walks.
var scripted_direction := Vector3.ZERO
## Ledges climbed by stepping since the body was created.
var steps_climbed := 0

var _camera: FreeFlyCamera
var _shape: CollisionShape3D


func _ready() -> void:
	_camera = get_node_or_null(camera) as FreeFlyCamera
	floor_snap_length = step_height
	floor_max_angle = deg_to_rad(46.0)
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "CollisionShape3D"
		add_child(_shape)
	_apply_shape()
	_apply_walking()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## Puts the feet at `feet` with no velocity.
func teleport(feet: Vector3) -> void:
	global_position = feet
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not walking:
		return
	var direction := _wanted_direction()
	var speed := run_speed if scripted_direction == Vector3.ZERO and Input.is_key_pressed(KEY_SHIFT) else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		if scripted_direction == Vector3.ZERO and _keys_active() and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta
	floor_snap_length = step_height
	_step_up(delta)
	move_and_slide()


func _process(_delta: float) -> void:
	if walking and _camera != null:
		_follow()


## The horizontal unit direction from the keys (relative to the camera's
## yaw) or `scripted_direction`.
func _wanted_direction() -> Vector3:
	if scripted_direction != Vector3.ZERO:
		return Vector3(scripted_direction.x, 0.0, scripted_direction.z).normalized()
	if not _keys_active():
		return Vector3.ZERO
	var yaw := _camera.yaw if _camera != null else 0.0
	# Prototype convention: yaw 0 looks toward +z.
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(-forward.z, 0.0, forward.x)
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction += forward
	if Input.is_physical_key_pressed(KEY_S):
		direction -= forward
	if Input.is_physical_key_pressed(KEY_D):
		direction += right
	if Input.is_physical_key_pressed(KEY_A):
		direction -= right
	return direction.normalized()


func _keys_active() -> bool:
	return is_inside_tree() and not UiKeys.text_field_focused(get_viewport())


## Lifts the body onto a ledge its horizontal motion runs into, if one within
## `step_height` has a floor on top and room above.
func _step_up(delta: float) -> void:
	if not is_on_floor() or step_height <= 0.0:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 1e-10:
		return
	var from := global_transform
	var hit := KinematicCollision3D.new()
	if not test_move(from, motion, hit) or hit.get_angle() <= floor_max_angle:
		return
	var up := Vector3.UP * step_height
	var lift := KinematicCollision3D.new()
	var raised := from
	if test_move(from, up, lift):
		raised = from.translated(lift.get_travel())
	else:
		raised = from.translated(up)
	var probe := motion + motion.normalized() * STEP_PROBE
	if test_move(raised, probe):
		return
	var ahead := raised.translated(probe)
	var down := KinematicCollision3D.new()
	if not test_move(ahead, from.origin - raised.origin, down) or down.get_angle() > floor_max_angle:
		return
	var rise := ahead.origin.y + down.get_travel().y - from.origin.y
	if rise <= 0.01 or rise > step_height:
		return
	global_position.y += rise
	steps_climbed += 1


func _follow() -> void:
	var eye := global_position + Vector3.UP * eye_height
	var forward := Vector3(cos(_camera.pitch) * sin(_camera.yaw), sin(_camera.pitch), cos(_camera.pitch) * cos(_camera.yaw))
	var at := eye if first_person else eye - forward * third_person_distance
	_camera.set_pose(at, _camera.yaw, _camera.pitch)
	var body := get_node_or_null("Body") as Node3D
	if body != null:
		body.visible = not first_person


func _apply_shape() -> void:
	if _shape == null:
		return
	var capsule := _shape.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		_shape.shape = capsule
	capsule.radius = capsule_radius
	capsule.height = capsule_height
	_shape.position = Vector3.UP * capsule_height * 0.5


func _apply_walking() -> void:
	if not is_inside_tree():
		return
	velocity = Vector3.ZERO
	if _shape != null:
		_shape.disabled = not walking
	if _camera != null:
		# The camera keeps its mouse look but stops flying while the body walks.
		_camera.set_process(not walking)
