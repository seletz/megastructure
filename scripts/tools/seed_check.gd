extends SceneTree
## Verifies the seed control end to end on the main scene: parsing and
## clamping, the shader uniform following WorldState.seed, the panel field and
## R key, and that returning to a seed renders a byte-identical frame.
## Needs a rendering device, so it runs windowed: `mise run seed-check`.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QUAD_PATH := "Camera/RaymarchQuad"
const SETTLE_FRAMES := 8

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_parse()
	_check_clamp()

	var main := MAIN_SCENE.instantiate()
	var panel := main.get_node("TweakPanel") as TweakPanel
	# Saved presets would override the default seed this check starts from.
	panel.restore_last = false
	root.add_child(main)
	var quad := main.get_node(QUAD_PATH) as MeshInstance3D
	var material := quad.get_active_material(0) as ShaderMaterial
	var control := _find_seed_control(panel)
	_expect(control != null, "tweak panel contains a SeedControl")

	_expect(WorldState.seed == WorldState.DEFAULT_SEED, "starts at the default seed")
	_expect(_uniform(material) == WorldState.DEFAULT_SEED, "uniform starts at the default seed")
	var first := await _capture()

	WorldState.seed = 0xDEADBEEF
	_expect(_uniform(material) == 0xDEADBEEF, "uniform follows a seed above int32")
	WorldState.seed = 2
	_expect(_uniform(material) == 2, "uniform follows seed 2")
	var second := await _capture()
	_expect(first != second, "a different seed renders a different frame")

	WorldState.seed = WorldState.DEFAULT_SEED
	var again := await _capture()
	_expect(first == again, "the same seed renders a byte-identical frame")

	if control != null:
		var field := _find_child_of_type(control, "LineEdit") as LineEdit
		field.text = " 12345 "
		field.text_submitted.emit(field.text)
		_expect(WorldState.seed == 12345 and _uniform(material) == 12345, "submitting the field sets the seed")
		field.text = "nonsense"
		field.text_submitted.emit(field.text)
		_expect(WorldState.seed == 12345 and field.text == "12345", "invalid text reverts to the current seed")
		WorldState.seed = 7
		_expect(field.text == "7", "the field shows seeds set elsewhere")

		var before := WorldState.seed
		_press(KEY_R)
		_expect(WorldState.seed != before, "R picks a new seed when nothing has focus")
		_press(KEY_TAB)
		_expect(panel.is_open(), "Tab opens the panel")
		field.grab_focus()
		_expect(field.has_focus(), "the field takes focus")
		before = WorldState.seed
		_press(KEY_R)
		_expect(WorldState.seed == before, "R is ignored while the field has focus")
		field.release_focus()
		_press(KEY_TAB)

	WorldState.seed = WorldState.DEFAULT_SEED
	main.queue_free()
	await process_frame
	print("seed check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_parse() -> void:
	var cases := {
		"0": 0, "1": 1, " 42 ": 42, "0007": 7, "4294967295": 4294967295,
		"4294967296": 4294967295, "99999999999999999999999": 4294967295,
		"": -1, "-1": -1, "+5": -1, "1.5": -1, "abc": -1, "12a": -1,
	}
	for text: String in cases:
		var got := SeedControl.parse_seed(text)
		_expect(got == cases[text], "parse_seed(%s) == %d (got %d)" % [JSON.stringify(text), cases[text], got])


func _check_clamp() -> void:
	var emitted: Array[int] = []
	var record := func(value: int) -> void: emitted.append(value)
	WorldState.seed_changed.connect(record)
	WorldState.seed = -5
	_expect(WorldState.seed == 0, "negative seeds clamp to 0")
	WorldState.seed = 1 << 40
	_expect(WorldState.seed == WorldState.MAX_SEED, "large seeds clamp to MAX_SEED")
	WorldState.seed = WorldState.MAX_SEED
	WorldState.seed = WorldState.DEFAULT_SEED
	WorldState.seed_changed.disconnect(record)
	_expect(emitted == [0, WorldState.MAX_SEED, WorldState.DEFAULT_SEED], "seed_changed fires once per actual change")


func _capture() -> PackedByteArray:
	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().get_data()


func _uniform(material: ShaderMaterial) -> int:
	return int(material.get_shader_parameter("seed"))


func _press(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	root.push_input(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	root.push_input(key)


func _find_seed_control(node: Node) -> SeedControl:
	for child in node.find_children("*", "SeedControl", true, false):
		return child as SeedControl
	return null


func _find_child_of_type(node: Node, type: String) -> Node:
	var found := node.find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
