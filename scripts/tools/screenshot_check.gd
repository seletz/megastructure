extends SceneTree
## Verifies the HUD screenshot on the main scene: the file lands under
## user://screenshots named after the seed, has the window resolution, and the
## HUD and tweak panel are hidden for the captured frame and restored after.
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
	WorldState.seed = WorldState.DEFAULT_SEED
	main.queue_free()
	await process_frame
	print("screenshot check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
