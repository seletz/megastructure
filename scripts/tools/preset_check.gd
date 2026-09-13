extends SceneTree
## Verifies presets round-trip exactly on the main scene: modifies every
## registry param, the seed and the camera pose, saves through the tweak panel,
## resets to the prototype defaults, reloads the preset (through a fresh store
## reading the file back from disk) and compares every value bitwise.
## Uses a scratch presets directory, so real presets are left alone.
## Run headless with `mise run preset-check`.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const CHECK_DIRECTORY := "user://preset_check"
const PRESET_NAME := "round trip"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clear_directory()
	_check_names()
	_check_float_text()

	var main := MAIN_SCENE.instantiate()
	var panel := main.get_node("TweakPanel") as TweakPanel
	panel.preset_directory = CHECK_DIRECTORY
	root.add_child(main)
	var camera := main.get_node("Camera") as FreeFlyCamera
	var registry := panel.registry
	_expect(registry != null and registry.param_count() > 0, "the panel discovered params")
	_expect(panel.presets.last_used_name() == PresetStore.BUILTIN_NAME, "without last.json the built-in preset is last used")

	var defaults := panel.presets.defaults()
	_expect(defaults.seed == WorldState.DEFAULT_SEED, "built-in preset uses the default seed")
	_expect(_same(defaults.camera_position, camera.position), "built-in preset uses the scene camera position")

	# Values chosen to be awkward: non-representable decimals, above-int32 seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20
	for group in registry.groups:
		for param in group.params:
			registry.set_value(param, _modified(param, rng))
	WorldState.seed = 0xFEEDBEEF
	camera.set_pose(Vector3(12.345678, -0.1, 1e-7), 1.0 / 3.0, -0.2718281828)

	var expected := panel.presets.capture(PRESET_NAME, camera)
	_expect(panel.save_preset(PRESET_NAME), "save preset")
	_expect(FileAccess.file_exists(CHECK_DIRECTORY.path_join(PRESET_NAME + ".json")), "preset file written")
	_expect(not panel.save_preset(PresetStore.BUILTIN_NAME), "saving over the built-in is refused")
	_expect(not panel.delete_preset(PresetStore.BUILTIN_NAME), "deleting the built-in is refused")
	_expect(PRESET_NAME in panel.presets.list_names(), "saved preset is listed")

	_expect(panel.load_preset(PresetStore.BUILTIN_NAME), "load built-in preset")
	_compare(panel, camera, defaults, "after loading defaults")
	_expect(WorldState.seed == WorldState.DEFAULT_SEED, "defaults restore seed 1")

	# A fresh store reads everything back from disk.
	var fresh := PresetStore.create(registry, null, CHECK_DIRECTORY)
	var loaded := fresh.load_preset(PRESET_NAME)
	_expect(loaded != null, "fresh store reads the preset file")
	if loaded != null:
		_compare_presets(registry, expected, loaded, "file contents")

	_expect(panel.load_preset(PRESET_NAME), "load saved preset")
	_compare(panel, camera, expected, "after loading the saved preset")
	_expect(panel.presets.last_used_name() == PRESET_NAME, "last used preset recorded")
	main.queue_free()
	await process_frame

	# Restart: a new scene restores the last used preset on start.
	WorldState.seed = WorldState.DEFAULT_SEED
	main = MAIN_SCENE.instantiate()
	panel = main.get_node("TweakPanel") as TweakPanel
	panel.preset_directory = CHECK_DIRECTORY
	root.add_child(main)
	camera = main.get_node("Camera") as FreeFlyCamera
	_compare(panel, camera, expected, "after restart")

	_expect(panel.delete_preset(PRESET_NAME), "delete preset")
	_expect(not panel.presets.has_preset(PRESET_NAME), "deleted preset is gone")
	_expect(panel.presets.last_used_name() == PresetStore.BUILTIN_NAME, "deleting the last used preset falls back to the built-in")

	main.queue_free()
	WorldState.seed = WorldState.DEFAULT_SEED
	await process_frame
	_clear_directory()
	print("preset check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_names() -> void:
	for bad: String in ["", " padded", "a/b", "last", PresetStore.BUILTIN_NAME, ".hidden"]:
		_expect(not PresetStore.validate_name(bad).is_empty(), "name %s is rejected" % JSON.stringify(bad))
	for good: String in ["night fog", "v2-wide_angle"]:
		_expect(PresetStore.validate_name(good).is_empty(), "name %s is accepted" % JSON.stringify(good))


## Stored float text must read back as the identical double across magnitudes.
func _check_float_text() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var values: Array[float] = [0.0, -0.0, 1.0, -2.5, 0.1, 1.0 / 3.0, 5e-324, 1.7976931348623157e308, 4294967295.0]
	for i in 5000:
		values.append((rng.randf_range(-1.0, 1.0) + rng.randf() * 1e-9) * pow(10.0, rng.randi_range(-30, 30)))
	var path := CHECK_DIRECTORY.path_join("floats.json")
	DirAccess.make_dir_recursive_absolute(CHECK_DIRECTORY)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"values": values}, "", false, true))
	file.close()
	var data: Variant = PresetStore._read_json(path)
	DirAccess.remove_absolute(path)
	var tokens: Array = (data as Dictionary)["values"] if data is Dictionary else []
	var mismatches := 0
	for i in values.size():
		if i >= tokens.size() or not _same(PresetStore._parse_float(tokens[i]), values[i]):
			mismatches += 1
	_expect(mismatches == 0, "%d floats read back bitwise from JSON text (%d mismatches)" % [values.size(), mismatches])


func _modified(param: ParamRegistry.Param, rng: RandomNumberGenerator) -> Variant:
	match param.kind:
		ParamRegistry.Kind.FLOAT:
			return rng.randf_range(param.min_value, param.max_value) + 1e-9
		ParamRegistry.Kind.INT:
			return int(param.default_value) + 1
		ParamRegistry.Kind.BOOL:
			return not bool(param.default_value)
		ParamRegistry.Kind.VEC2:
			return Vector2(rng.randf(), -rng.randf()) * 7.3
		ParamRegistry.Kind.COLOR:
			return Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
	return null


## Compares the live material, WorldState and camera against a preset.
func _compare(panel: TweakPanel, camera: FreeFlyCamera, expected: PresetStore.Preset, context: String) -> void:
	var live := panel.presets.capture(expected.name, camera)
	_compare_presets(panel.registry, expected, live, context)


func _compare_presets(registry: ParamRegistry, expected: PresetStore.Preset, actual: PresetStore.Preset, context: String) -> void:
	var mismatches: Array[String] = []
	for group in registry.groups:
		for param in group.params:
			var want: Variant = expected.params[param.name]
			var got: Variant = actual.params.get(param.name)
			if not _same(want, got):
				mismatches.append("%s: %s != %s" % [param.name, var_to_str(got), var_to_str(want)])
	if expected.seed != actual.seed:
		mismatches.append("seed: %d != %d" % [actual.seed, expected.seed])
	if not _same(expected.camera_position, actual.camera_position):
		mismatches.append("camera position: %s != %s" % [actual.camera_position, expected.camera_position])
	if not _same(expected.camera_yaw, actual.camera_yaw) or not _same(expected.camera_pitch, actual.camera_pitch):
		mismatches.append("camera yaw/pitch: %s != %s" % [[actual.camera_yaw, actual.camera_pitch], [expected.camera_yaw, expected.camera_pitch]])
	for mismatch in mismatches:
		printerr("        %s" % mismatch)
	_expect(mismatches.is_empty(), "%s: %d params, seed and camera match bitwise" % [context, registry.param_count()])


## Bitwise equality, including the Variant type.
static func _same(a: Variant, b: Variant) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)


func _clear_directory() -> void:
	if not DirAccess.dir_exists_absolute(CHECK_DIRECTORY):
		return
	for file in DirAccess.get_files_at(CHECK_DIRECTORY):
		DirAccess.remove_absolute(CHECK_DIRECTORY.path_join(file))
	DirAccess.remove_absolute(CHECK_DIRECTORY)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
