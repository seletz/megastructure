extends SceneTree
## Drives the tweak panel of the skeleton viewer with mouse events and checks
## that every kind of script-backed widget reaches its setter: the bool
## checkboxes (click on the box, click on the label, a press whose release is
## lost), an int script param spin box, float and int grammar export spin
## boxes and a float grammar slider.
## Run headless with `mise run panel-check`.

const VIEWER_SCENE := preload("res://scenes/skeleton_viewer.tscn")
const SETTLE_FRAMES := 4

var _failures := 0
var _panel: TweakPanel


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := VIEWER_SCENE.instantiate()
	root.add_child(scene)
	var viewer := scene.get_node("SkeletonViewer") as SkeletonViewer
	_panel = scene.get_node("TweakPanel") as TweakPanel
	await _frames()
	_press_key(KEY_TAB)
	await _frames()
	_expect(_panel.is_open(), "Tab opens the panel")

	var stratum := viewer.show_stratum
	var check := _row_control("show stratum", "CheckBox") as CheckBox
	_expect(check != null, "show stratum row has a CheckBox")
	if check != null:
		await _click(_center(check))
		_expect(viewer.show_stratum == not stratum and check.button_pressed == viewer.show_stratum,
			"clicking the show stratum box runs the setter")
		await _click(_center(_row_label("show stratum")))
		_expect(viewer.show_stratum == stratum and check.button_pressed == stratum,
			"clicking the show stratum label toggles it back")

	var follow := viewer.follow_camera
	var follow_check := _row_control("follow camera", "CheckBox") as CheckBox
	if follow_check != null:
		await _click(_center(follow_check), false)
		_expect(viewer.follow_camera == not follow, "a press without release toggles follow camera")
		await _click(_center(follow_check))
		_expect(viewer.follow_camera == follow, "clicking follow camera again restores it")

	var radius := viewer.radius
	await _click(_spin_up(_row_control("radius", "SpinBox") as SpinBox))
	_expect(viewer.radius == radius + 1, "radius spin box (int script param) runs the setter: %d -> %d" % [radius, viewer.radius])

	var probability := viewer.grammar.shaft_probability
	await _click(_spin_up(_row_control("shaft probability", "SpinBox") as SpinBox))
	_expect(is_equal_approx(viewer.grammar.shaft_probability, probability + 0.01),
		"shaft probability spin box (float grammar export) runs the setter: %.2f -> %.2f" % [probability, viewer.grammar.shaft_probability])

	var grid := viewer.grammar.solid_wall_grid
	await _click(_spin_up(_row_control("solid wall grid", "SpinBox") as SpinBox))
	_expect(viewer.grammar.solid_wall_grid == grid + 1,
		"solid wall grid spin box (int grammar export) runs the setter: %d -> %d" % [grid, viewer.grammar.solid_wall_grid])

	var sector_size := viewer.grammar.sector_size
	var slider := _row_control("sector size", "HSlider") as HSlider
	if slider != null:
		var rect := slider.get_global_rect()
		await _click(Vector2(rect.position.x + rect.size.x * 0.1, rect.get_center().y))
	_expect(slider != null and not is_equal_approx(viewer.grammar.sector_size, sector_size),
		"sector size slider (float grammar export) runs the setter: %.1f -> %.1f" % [sector_size, viewer.grammar.sector_size])

	scene.queue_free()
	await process_frame
	print("panel check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _row_label(text: String) -> Label:
	for node in _panel.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == text and label.get_parent() is HBoxContainer:
			return label
	_expect(false, "panel has a row labelled %s" % text)
	return null


func _row_control(text: String, type: String) -> Control:
	var label := _row_label(text)
	if label == null:
		return null
	for node in label.get_parent().get_children():
		if node.is_class(type):
			return node as Control
	_expect(false, "row %s has a %s" % [text, type])
	return null


static func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center() if control != null else Vector2(-1, -1)


## Point on the up arrow of a spin box.
static func _spin_up(spin: SpinBox) -> Vector2:
	if spin == null:
		return Vector2(-1, -1)
	var rect := spin.get_global_rect()
	return Vector2(rect.end.x - 4.0, rect.position.y + 4.0)


## Left click at a viewport position; with `release` false the release is lost.
func _click(position: Vector2, release := true) -> void:
	for pressed in ([true, false] if release else [true]):
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		root.push_input(event, true)
		await process_frame
	await _frames()


func _press_key(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	root.push_input(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	root.push_input(key)


func _frames() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
