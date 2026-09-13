class_name PresetStore
extends RefCounted
## Named snapshots of every registry parameter, the world seed and the camera
## pose, stored as JSON files in a presets directory:
##     user://presets/<name>.json     one preset
##     user://presets/last.json       {"name": <last loaded or saved preset>}
##
## A preset file looks like
##     {"version": 1, "seed": 1,
##      "camera": {"position": [x, y, z], "yaw": 0.9, "pitch": -0.28},
##      "params": {"fog_density": 0.02, "light_dir": [x, y], "tint": [r, g, b, a]}}
## Floats are written as their shortest round-trip decimal. Godot's JSON and
## String.to_float parsing can be off by many ulps, so numbers are read back
## from the text with an exact search (see _parse_float) and round-trip bitwise.
## Params missing from a file fall back to their registry defaults.
##
## The built-in "Prototype defaults" preset is made from the registry defaults,
## the default seed and the camera pose the scene starts with; it is read-only.

const BUILTIN_NAME := "Prototype defaults"
const DEFAULT_DIRECTORY := "user://presets"
const FORMAT_VERSION := 1
const _LAST_FILE := "last"
const _EXTENSION := ".json"
## JSON strings (skipped) or number tokens (captured) in file text.
const _TOKEN_PATTERN := "\"(?:[^\"\\\\]|\\\\.)*\"|(-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)"
## Bit-pattern distance searched around Godot's parse; its error stays far below.
const _FLOAT_SEARCH_WINDOW := 1 << 16


class Preset:
	extends RefCounted
	var name: String
	var seed: int = WorldState.DEFAULT_SEED
	var camera_position := Vector3.ZERO
	var camera_yaw := 0.0
	var camera_pitch := 0.0
	## Uniform name -> value typed as the registry param (float, int, bool, Vector2, Color).
	var params := {}


var registry: ParamRegistry
var directory: String

var _default_position: Vector3
var _default_yaw: float
var _default_pitch: float


## Builds a store for a registry. The camera's current pose becomes the pose of
## the built-in preset, so create the store before applying any preset.
static func create(target: ParamRegistry, camera: FreeFlyCamera, dir := DEFAULT_DIRECTORY) -> PresetStore:
	var store := PresetStore.new()
	store.registry = target
	store.directory = dir
	if camera != null:
		store._default_position = camera.position
		store._default_yaw = camera.yaw
		store._default_pitch = camera.pitch
	return store


static func is_builtin(preset_name: String) -> bool:
	return preset_name == BUILTIN_NAME


## Returns an error message for an unusable preset name, or "" when it is fine.
static func validate_name(preset_name: String) -> String:
	if preset_name.strip_edges() != preset_name or preset_name.is_empty():
		return "name must not be empty or padded with spaces"
	if is_builtin(preset_name):
		return "\"%s\" is built in and read-only" % BUILTIN_NAME
	if preset_name == _LAST_FILE:
		return "\"%s\" is reserved" % _LAST_FILE
	if not preset_name.is_valid_filename() or preset_name.begins_with("."):
		return "name contains characters not allowed in file names"
	return ""


## The built-in preset first, then saved presets sorted by name.
func list_names() -> PackedStringArray:
	var names := PackedStringArray()
	var files := DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	for file in files:
		if file.ends_with(_EXTENSION):
			var preset_name := file.trim_suffix(_EXTENSION)
			if validate_name(preset_name).is_empty():
				names.append(preset_name)
	names.sort()
	names.insert(0, BUILTIN_NAME)
	return names


func has_preset(preset_name: String) -> bool:
	return is_builtin(preset_name) or FileAccess.file_exists(_path(preset_name))


func defaults() -> Preset:
	var preset := Preset.new()
	preset.name = BUILTIN_NAME
	preset.seed = WorldState.DEFAULT_SEED
	preset.camera_position = _default_position
	preset.camera_yaw = _default_yaw
	preset.camera_pitch = _default_pitch
	for group in registry.groups:
		for param in group.params:
			preset.params[param.name] = param.default_value
	return preset


## Snapshots the material, WorldState and camera under a name.
func capture(preset_name: String, camera: FreeFlyCamera) -> Preset:
	var preset := Preset.new()
	preset.name = preset_name
	preset.seed = WorldState.seed
	if camera != null:
		preset.camera_position = camera.position
		preset.camera_yaw = camera.yaw
		preset.camera_pitch = camera.pitch
	for group in registry.groups:
		for param in group.params:
			preset.params[param.name] = registry.get_value(param)
	return preset


## Pushes a preset to the material, WorldState and camera.
func apply(preset: Preset, camera: FreeFlyCamera) -> void:
	for group in registry.groups:
		for param in group.params:
			registry.set_value(param, preset.params.get(param.name, param.default_value))
	WorldState.seed = preset.seed
	if camera != null:
		camera.set_pose(preset.camera_position, preset.camera_yaw, preset.camera_pitch)


func save(preset: Preset) -> Error:
	if not validate_name(preset.name).is_empty():
		return ERR_INVALID_PARAMETER
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		return err
	return _write_json(_path(preset.name), to_dict(preset))


## Loads a preset by name; returns null when it is missing or unreadable.
func load_preset(preset_name: String) -> Preset:
	if is_builtin(preset_name):
		return defaults()
	if not validate_name(preset_name).is_empty():
		return null
	var data: Variant = _read_json(_path(preset_name))
	if not data is Dictionary:
		return null
	return from_dict(preset_name, data as Dictionary)


func delete(preset_name: String) -> Error:
	if not validate_name(preset_name).is_empty():
		return ERR_INVALID_PARAMETER
	var err := DirAccess.remove_absolute(_path(preset_name))
	if err == OK and last_used_name() == preset_name:
		DirAccess.remove_absolute(_path(_LAST_FILE))
	return err


## Name of the last loaded or saved preset if it still exists, else the built-in.
func last_used_name() -> String:
	var data: Variant = _read_json(_path(_LAST_FILE))
	if data is Dictionary:
		var preset_name: Variant = (data as Dictionary).get("name")
		if preset_name is String and has_preset(preset_name):
			return preset_name
	return BUILTIN_NAME


func set_last_used(preset_name: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		return err
	return _write_json(_path(_LAST_FILE), {"name": preset_name})


func to_dict(preset: Preset) -> Dictionary:
	var params := {}
	for group in registry.groups:
		for param in group.params:
			var value: Variant = preset.params.get(param.name, param.default_value)
			params[param.name] = _encode(value, param.kind)
	var pos := preset.camera_position
	return {
		"version": FORMAT_VERSION,
		"seed": preset.seed,
		"camera": {"position": [pos.x, pos.y, pos.z], "yaw": preset.camera_yaw, "pitch": preset.camera_pitch},
		"params": params,
	}


func from_dict(preset_name: String, data: Dictionary) -> Preset:
	var preset := defaults()
	preset.name = preset_name
	var seed_value: Variant = _parse_int(data.get("seed"))
	if seed_value != null:
		preset.seed = clampi(seed_value, 0, WorldState.MAX_SEED)
	var camera: Variant = data.get("camera")
	if camera is Dictionary:
		var numbers := _numbers((camera as Dictionary).get("position"), 3)
		if numbers.size() == 3:
			preset.camera_position = Vector3(numbers[0], numbers[1], numbers[2])
		var yaw_value: Variant = _parse_float((camera as Dictionary).get("yaw"))
		if yaw_value != null:
			preset.camera_yaw = yaw_value
		var pitch_value: Variant = _parse_float((camera as Dictionary).get("pitch"))
		if pitch_value != null:
			preset.camera_pitch = pitch_value
	var params: Variant = data.get("params")
	if params is Dictionary:
		for group in registry.groups:
			for param in group.params:
				var decoded: Variant = _decode((params as Dictionary).get(param.name), param.kind)
				if decoded != null:
					preset.params[param.name] = decoded
	return preset


func _path(preset_name: String) -> String:
	return directory.path_join(preset_name + _EXTENSION)


static func _encode(value: Variant, kind: ParamRegistry.Kind) -> Variant:
	match kind:
		ParamRegistry.Kind.FLOAT:
			return float(value)
		ParamRegistry.Kind.INT:
			return int(value)
		ParamRegistry.Kind.BOOL:
			return bool(value)
		ParamRegistry.Kind.VEC2:
			var v := value as Vector2
			return [v.x, v.y]
		ParamRegistry.Kind.COLOR:
			var c := value as Color
			return [c.r, c.g, c.b, c.a]
	return null


## Converts a JSON value back to the param's type; null when it does not fit.
static func _decode(value: Variant, kind: ParamRegistry.Kind) -> Variant:
	match kind:
		ParamRegistry.Kind.FLOAT:
			return _parse_float(value)
		ParamRegistry.Kind.INT:
			return _parse_int(value)
		ParamRegistry.Kind.BOOL:
			if value is bool:
				return value
		ParamRegistry.Kind.VEC2:
			var numbers := _numbers(value, 2)
			if numbers.size() == 2:
				return Vector2(numbers[0], numbers[1])
		ParamRegistry.Kind.COLOR:
			var numbers := _numbers(value, 4)
			if numbers.size() == 3:
				return Color(numbers[0], numbers[1], numbers[2])
			if numbers.size() == 4:
				return Color(numbers[0], numbers[1], numbers[2], numbers[3])
	return null


## Numeric array elements of a JSON value, at most `limit`; empty when any is not a number.
static func _numbers(value: Variant, limit: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	if not value is Array or (value as Array).size() > limit:
		return result
	for item: Variant in value:
		var number: Variant = _parse_float(item)
		if number == null:
			return PackedFloat64Array()
		result.append(number)
	return result


## An integer from a number token; null for anything else.
static func _parse_int(token: Variant) -> Variant:
	if not token is String or not (token as String).is_valid_int():
		return null
	return (token as String).to_int()


## The double a number token denotes; null for anything else.
##
## Tokens this store wrote are the shortest decimal that round-trips, and that
## text grows monotonically with the value, so a binary search over the bit
## patterns near Godot's rough parse finds the exact double. Hand-written text
## that no double prints as falls back to Godot's parse.
static func _parse_float(token: Variant) -> Variant:
	if not token is String or not (token as String).is_valid_float():
		return null
	var text := token as String
	var guess := text.to_float()
	if not is_finite(guess) or _format_float(guess) == text:
		return guess
	var negative := text.begins_with("-")
	var magnitude := text.trim_prefix("-")
	var target := _decimal_key(magnitude)
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, absf(guess))
	var center := bytes.decode_s64(0)
	var low := maxi(center - _FLOAT_SEARCH_WINDOW, 0)
	var high := center + _FLOAT_SEARCH_WINDOW
	while low <= high:
		var mid := low + (high - low) / 2
		bytes.encode_s64(0, mid)
		var candidate := bytes.decode_double(0)
		var candidate_text := _format_float(candidate)
		if candidate_text == magnitude:
			return -candidate if negative else candidate
		if _compare_decimal(_decimal_key(candidate_text), target) < 0:
			low = mid + 1
		else:
			high = mid - 1
	return guess


static func _format_float(value: float) -> String:
	return JSON.stringify(value, "", false, true)


## [exponent, digits] for a non-negative decimal: value = 0.digits * 10^exponent,
## digits without leading or trailing zeros (empty for zero).
static func _decimal_key(text: String) -> Array:
	var mantissa := text
	var exponent := 0
	var e := text.findn("e")
	if e >= 0:
		mantissa = text.substr(0, e)
		exponent = text.substr(e + 1).to_int()
	var point := mantissa.find(".")
	var whole := mantissa if point < 0 else mantissa.substr(0, point)
	var digits := whole + ("" if point < 0 else mantissa.substr(point + 1))
	exponent += whole.length()
	var stripped := digits.lstrip("0")
	exponent -= digits.length() - stripped.length()
	return [exponent, stripped.rstrip("0")]


static func _compare_decimal(a: Array, b: Array) -> int:
	var a_digits: String = a[1]
	var b_digits: String = b[1]
	if a_digits.is_empty() or b_digits.is_empty():
		return signi(a_digits.length() - b_digits.length())
	if a[0] != b[0]:
		return signi(int(a[0]) - int(b[0]))
	var width := maxi(a_digits.length(), b_digits.length())
	a_digits = a_digits.rpad(width, "0")
	b_digits = b_digits.rpad(width, "0")
	if a_digits == b_digits:
		return 0
	return -1 if a_digits < b_digits else 1


static func _write_json(path: String, data: Variant) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", false, true))
	file.store_string("\n")
	return OK


## Parses a JSON file with every number turned into its token string, so
## callers can convert numbers exactly.
static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var quoted := ""
	var copied := 0
	for token in RegEx.create_from_string(_TOKEN_PATTERN).search_all(text):
		if token.get_start(1) < 0:
			continue
		quoted += text.substr(copied, token.get_start(1) - copied) + "\"" + token.get_string(1) + "\""
		copied = token.get_end(1)
	quoted += text.substr(copied)
	var json := JSON.new()
	if json.parse(quoted) != OK:
		return null
	return json.data
