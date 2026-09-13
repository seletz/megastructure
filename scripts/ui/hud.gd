class_name Hud
extends CanvasLayer
## Top-left overlay with frame timing, camera pose and seed, plus screenshots.
##
## F1 toggles the overlay. F12 saves the current frame, without the overlay and
## the other layers in `hidden_during_capture`, to
## user://screenshots/<seed>_<yyyymmdd-hhmmss>.png at the window resolution.
## Yaw and pitch are shown in the HTML prototype's convention (see
## FreeFlyCamera), so they can be pasted into `state.yaw` / `state.pitch`.

const SCREENSHOT_DIR := "user://screenshots"

## FreeFlyCamera whose pose is displayed.
@export var camera: NodePath
## CanvasLayers hidden, together with the HUD, for the captured frame.
@export var hidden_during_capture: Array[NodePath] = []

@onready var _label: Label = $Label

var _camera: FreeFlyCamera
var _capturing := false


func _ready() -> void:
	_camera = get_node_or_null(camera) as FreeFlyCamera
	if _camera == null:
		push_warning("Hud: no FreeFlyCamera found at %s" % camera)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F12:
		get_viewport().set_input_as_handled()
		capture_screenshot()


func _process(delta: float) -> void:
	if not visible:
		return
	var lines := PackedStringArray([
		"FPS    %d" % Engine.get_frames_per_second(),
		"frame  %.2f ms" % (delta * 1000.0),
	])
	if _camera != null:
		var pos := _camera.global_position
		lines.append("pos    %.1f, %.1f, %.1f" % [pos.x, pos.y, pos.z])
		lines.append("yaw    %.2f  pitch %.2f" % [_camera.yaw, _camera.pitch])
	lines.append("seed   %d" % WorldState.seed)
	_label.text = "\n".join(lines)


## Saves the next rendered frame without the HUD and the layers in
## `hidden_during_capture`, prints and returns its absolute path.
## Returns an empty string on failure or while another capture is pending.
func capture_screenshot() -> String:
	if _capturing:
		return ""
	_capturing = true
	var layers: Array[CanvasLayer] = [self]
	for path in hidden_during_capture:
		var layer := get_node_or_null(path) as CanvasLayer
		if layer != null:
			layers.append(layer)
	var was_visible: Array[bool] = []
	for layer in layers:
		was_visible.append(layer.visible)
		layer.visible = false

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()

	for i in layers.size():
		layers[i].visible = was_visible[i]
	_capturing = false

	var path := ProjectSettings.globalize_path(screenshot_path(WorldState.seed))
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error == OK:
		error = image.save_png(path)
	if error != OK:
		push_error("Hud: could not save screenshot to %s: %s" % [path, error_string(error)])
		return ""
	print("Screenshot saved: %s" % path)
	return path


## user:// path for a screenshot of `world_seed` taken now.
static func screenshot_path(world_seed: int) -> String:
	var now := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [
		now.year, now.month, now.day, now.hour, now.minute, now.second,
	]
	return "%s/%d_%s.png" % [SCREENSHOT_DIR, world_seed, stamp]
