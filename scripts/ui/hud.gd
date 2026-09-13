class_name Hud
extends CanvasLayer
## Top-left overlay with frame timing, camera pose and seed, plus screenshots.
##
## The overlay is shown on start. H (or F1) hides it and leaves a small dimmed
## hint in the corner saying how to bring it back. P (or F12) saves the current
## frame, without the HUD and the other layers in `hidden_during_capture`, to
## user://screenshots/<seed>_<yyyymmdd-hhmmss>.png at the window resolution.
## Both keys follow the UiKeys rule, so they are ignored while typing.
## Yaw and pitch are shown in the HTML prototype's convention (see
## FreeFlyCamera), so they can be pasted into `state.yaw` / `state.pitch`.

signal screenshot_saved(path: String)

const SCREENSHOT_DIR := "user://screenshots"
const TOGGLE_KEYS: Array[Key] = [KEY_H, KEY_F1]
const SCREENSHOT_KEYS: Array[Key] = [KEY_P, KEY_F12]
const CONTROLS_HINT := "Tab panel  H HUD  P screenshot  R new seed  Esc mouse  WASD QE move  Shift fast  wheel speed"

## FreeFlyCamera whose pose is displayed.
@export var camera: NodePath
## CanvasLayers hidden, together with the HUD, for the captured frame.
@export var hidden_during_capture: Array[NodePath] = []

@onready var _label: Label = $Label
@onready var _hint: Label = $Hint

var _camera: FreeFlyCamera
var _capturing := false


func _ready() -> void:
	_camera = get_node_or_null(camera) as FreeFlyCamera
	if _camera == null:
		push_warning("Hud: no FreeFlyCamera found at %s" % camera)
	set_overlay_shown(true)


func _unhandled_input(event: InputEvent) -> void:
	if UiKeys.is_shortcut(event, TOGGLE_KEYS):
		if UiKeys.text_field_focused(get_viewport()):
			return
		set_overlay_shown(not is_overlay_shown())
		get_viewport().set_input_as_handled()
	elif UiKeys.is_shortcut(event, SCREENSHOT_KEYS):
		if UiKeys.text_field_focused(get_viewport()):
			return
		get_viewport().set_input_as_handled()
		capture_screenshot()


## Shows the full overlay, or only the dimmed corner hint when `shown` is false.
func set_overlay_shown(shown: bool) -> void:
	_label.visible = shown
	_hint.visible = not shown


func is_overlay_shown() -> bool:
	return _label.visible


func _process(delta: float) -> void:
	if not _label.visible:
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
	lines.append(CONTROLS_HINT)
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
	var image := await grab_frame(get_viewport(), layers)
	_capturing = false

	var path := ProjectSettings.globalize_path(screenshot_path(WorldState.seed))
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error == OK:
		error = image.save_png(path)
	if error != OK:
		push_error("Hud: could not save screenshot to %s: %s" % [path, error_string(error)])
		return ""
	print("Screenshot saved: %s" % path)
	screenshot_saved.emit(path)
	return path


## Returns the next frame `viewport` draws with `layers` hidden, and restores
## their visibility afterwards. Also used by the shot tool.
static func grab_frame(viewport: Viewport, layers: Array[CanvasLayer]) -> Image:
	var was_visible: Array[bool] = []
	for layer in layers:
		was_visible.append(layer.visible)
		layer.visible = false

	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()

	for i in layers.size():
		layers[i].visible = was_visible[i]
	return image


## user:// path for a screenshot of `world_seed` taken now.
static func screenshot_path(world_seed: int) -> String:
	var now := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [
		now.year, now.month, now.day, now.hour, now.minute, now.second,
	]
	return "%s/%d_%s.png" % [SCREENSHOT_DIR, world_seed, stamp]
