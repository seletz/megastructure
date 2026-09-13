extends SceneTree
## Verifies the HUD screenshot on the main scene: the file lands under
## user://screenshots named after the seed, has the window resolution, and the
## HUD and tweak panel are hidden for the captured frame and restored after, and
## the H/F1 and P keys work but are ignored while a text field has focus.
## Needs a rendering device, so it runs windowed: `mise run screenshot-check`.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const SETTLE_FRAMES := 8
const TEST_SEED := 4242

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	var hud := main.get_node("Hud") as Hud
	var panel := main.get_node("TweakPanel") as CanvasLayer
	_expect(hud != null, "main scene contains the Hud")
	WorldState.seed = TEST_SEED
	for i in SETTLE_FRAMES:
		await process_frame

	# [layers hidden, window size] as seen right before the captured frame draws.
	var frame_state := [false, Vector2i.ZERO]
	var watch := func() -> void:
		frame_state[0] = not hud.visible and not panel.visible
		frame_state[1] = DisplayServer.window_get_size()
	RenderingServer.frame_pre_draw.connect(watch, CONNECT_ONE_SHOT)

	var path := await hud.capture_screenshot()
	_expect(path != "", "capture returns a path")
	_expect(frame_state[0], "HUD and tweak panel are hidden for the captured frame")
	_expect(hud.visible and panel.visible, "HUD and tweak panel are restored afterwards")
	_expect(path.get_file().begins_with("%d_" % TEST_SEED), "file name starts with the seed")
	_expect(path.begins_with(ProjectSettings.globalize_path(Hud.SCREENSHOT_DIR)), "file is in user://screenshots")
	_expect(FileAccess.file_exists(path), "screenshot file exists")
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	_expect(image != null and image.get_size() == frame_state[1],
		"screenshot has the window resolution")

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	await _check_keys(hud, main.get_node("TweakPanel") as TweakPanel)

	WorldState.seed = WorldState.DEFAULT_SEED
	main.queue_free()
	await process_frame
	print("screenshot check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


## H/F1 toggle the overlay and leave the corner hint, P takes a screenshot, and
## both are ignored while a text field has focus.
func _check_keys(hud: Hud, panel: TweakPanel) -> void:
	var hint := hud.get_node("Hint") as Label
	_expect(hud.is_overlay_shown() and not hint.visible, "HUD is shown on start, hint hidden")
	_press(KEY_H)
	_expect(not hud.is_overlay_shown() and hint.visible and hud.visible,
		"H hides the HUD and leaves the corner hint")
	_press(KEY_F1)
	_expect(hud.is_overlay_shown() and not hint.visible, "F1 shows the HUD again")

	var saved := await _press_and_wait_for_screenshot(hud, KEY_P)
	_expect(saved != "" and FileAccess.file_exists(saved), "P saves a screenshot")
	_expect(saved.get_file().begins_with("%d_" % TEST_SEED), "P screenshot is named after the seed")
	_expect(hud.visible and hud.is_overlay_shown(), "HUD is restored after the P screenshot")
	if saved != "" and FileAccess.file_exists(saved):
		DirAccess.remove_absolute(saved)

	var seed_controls := panel.find_children("*", "SeedControl", true, false)
	var fields := seed_controls[0].find_children("*", "LineEdit", true, false) if not seed_controls.is_empty() else []
	_expect(not fields.is_empty(), "tweak panel has the seed text field")
	if fields.is_empty():
		return
	var field := fields[0] as LineEdit
	_press(KEY_TAB)
	field.grab_focus()
	_expect(field.has_focus(), "the text field takes focus")
	_press(KEY_H)
	_expect(hud.is_overlay_shown(), "H is ignored while a text field has focus")
	saved = await _press_and_wait_for_screenshot(hud, KEY_P)
	_expect(saved == "", "P is ignored while a text field has focus")
	field.release_focus()
	_press(KEY_TAB)


## Presses `keycode` and returns the path of the screenshot it saved, or an
## empty string when none was saved within a few frames.
func _press_and_wait_for_screenshot(hud: Hud, keycode: Key) -> String:
	var saved := [""]
	var on_saved := func(p: String) -> void: saved[0] = p
	hud.screenshot_saved.connect(on_saved)
	_press(keycode)
	for i in SETTLE_FRAMES:
		await process_frame
		if saved[0] != "":
			break
	hud.screenshot_saved.disconnect(on_saved)
	return saved[0]


func _press(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	root.push_input(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	root.push_input(key)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
