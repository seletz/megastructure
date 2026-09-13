class_name ParamRegistry
extends RefCounted
## Tweakable parameters: shader uniforms discovered at runtime, plus script
## parameters registered by nodes.
##
## Walks Shader.get_shader_uniform_list(), so every uniform a shader or its
## includes declares shows up without a hand-maintained list. Uniforms are
## bucketed by their group_uniforms block; ranges come from hint_range and fall
## back to a span around the default where a uniform has no hint.
##
## Defaults come from the material override, then the rendering server, then
## the uniform's initializer in the shader source (the headless dummy renderer
## reports no defaults).
##
## Script parameters are values a node owns instead of a material. A source
## registers a group of them as a Dictionary with a setter, or lets the
## registry read a Resource's @export fields:
##     registry.add_script_params("viewer", {
##         "radius": {"value": 3, "min": 1, "max": 6, "step": 1, "default": 3},
##     }, func(name: String, value: Variant) -> void: set(name, value))
##     registry.add_object_exports(grammar, func(name: String, value: Variant) -> void:
##         grammar.set(name, value))
## The kind follows the type of "default"; get_value and set_value go through
## the Dictionary and the setter, never the material.

enum Kind { FLOAT, INT, BOOL, VEC2, COLOR }

const UNGROUPED := "general"
## Uniforms owned by other systems or not meant to be tweaked by hand.
const IGNORED: Array[String] = ["seed"]

const _UNIFORM_PATTERN := "uniform\\s+(?:lowp\\s+|mediump\\s+|highp\\s+)?\\w+\\s+(\\w+)\\s*(?::[^=;]*)?=\\s*([^;]+);"
const _INCLUDE_PATTERN := "#include\\s+\"([^\"]+)\""


class Param:
	extends RefCounted
	var name: String
	var label: String
	var kind: Kind
	var min_value: float
	var max_value: float
	var step: float
	var default_value: Variant


class Group:
	extends RefCounted
	var name: String
	var params: Array[Param] = []


var material: ShaderMaterial
var groups: Array[Group] = []

## Script param name -> {value, min, max, step, default}.
var _script_params := {}
## Script param name -> Callable(name: String, value: Variant).
var _script_setters := {}


static func from_material(target: ShaderMaterial) -> ParamRegistry:
	var registry := ParamRegistry.new()
	registry.material = target
	if target != null and target.shader != null:
		registry._discover(target.shader)
	return registry


func param_count() -> int:
	var count := 0
	for group in groups:
		count += group.params.size()
	return count


func get_value(param: Param) -> Variant:
	if _script_params.has(param.name):
		return (_script_params[param.name] as Dictionary)["value"]
	var value: Variant = material.get_shader_parameter(param.name)
	return param.default_value if value == null else value


func set_value(param: Param, value: Variant) -> void:
	if _script_params.has(param.name):
		(_script_params[param.name] as Dictionary)["value"] = value
		(_script_setters[param.name] as Callable).call(param.name, value)
		return
	material.set_shader_parameter(param.name, value)


func is_script_param(param: Param) -> bool:
	return _script_params.has(param.name)


## Adds a group of script parameters. `params` maps each name to a Dictionary
## with "value" and "default" (float, int or bool) and optionally "min",
## "max" and "step"; `setter` is called with (name, value) on every change.
## The Dictionaries are kept, so "value" always holds the current value.
func add_script_params(group_name: String, params: Dictionary, setter: Callable) -> void:
	var group := Group.new()
	group.name = group_name
	for param_name: String in params:
		var entry: Dictionary = params[param_name]
		var param := Param.new()
		param.name = param_name
		param.label = param_name.replace("_", " ")
		param.default_value = entry["default"]
		match typeof(param.default_value):
			TYPE_FLOAT:
				param.kind = Kind.FLOAT
			TYPE_INT:
				param.kind = Kind.INT
			TYPE_BOOL:
				param.kind = Kind.BOOL
			_:
				push_warning("ParamRegistry: script param %s has an unsupported type" % param_name)
				continue
		if entry.has("min") and entry.has("max"):
			param.min_value = float(entry["min"])
			param.max_value = float(entry["max"])
			param.step = float(entry.get("step", 0.0))
		else:
			_fallback_range(param)
		_normalize_step(param)
		if not entry.has("value"):
			entry["value"] = param.default_value
		_script_params[param_name] = entry
		_script_setters[param_name] = setter
		group.params.append(param)
	if not group.params.is_empty():
		groups.append(group)


## Adds one script param group per @export_group of `target` holding its
## float, int and bool @export fields, with ranges from @export_range. The
## current values become the defaults; `setter` is called with (name, value).
## Group names are prefixed with `prefix` when it is not empty.
func add_object_exports(target: Object, setter: Callable, prefix := "") -> void:
	var current := UNGROUPED
	var by_group := {}
	var order: Array[String] = []
	for property: Dictionary in target.get_property_list():
		var usage: int = property["usage"]
		var property_name: String = property["name"]
		if usage & PROPERTY_USAGE_GROUP:
			current = property_name if not property_name.is_empty() else UNGROUPED
			continue
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var type: int = property["type"]
		if type not in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
			continue
		var value: Variant = target.get(property_name)
		var entry := {"value": value, "default": value}
		var hint_parts: PackedStringArray = (property["hint_string"] as String).split(",")
		if property["hint"] == PROPERTY_HINT_RANGE and hint_parts.size() >= 2:
			entry["min"] = hint_parts[0].to_float()
			entry["max"] = hint_parts[1].to_float()
			if hint_parts.size() >= 3 and hint_parts[2].is_valid_float():
				entry["step"] = hint_parts[2].to_float()
		var group_name := current.to_lower() if prefix.is_empty() else "%s %s" % [prefix, current.to_lower()]
		if not by_group.has(group_name):
			by_group[group_name] = {}
			order.append(group_name)
		(by_group[group_name] as Dictionary)[property_name] = entry
	for group_name in order:
		add_script_params(group_name, by_group[group_name], setter)


func reset_group(group: Group) -> void:
	for param in group.params:
		set_value(param, param.default_value)


func _discover(shader: Shader) -> void:
	var source_defaults := _parse_source_defaults(shader.code, shader.resource_path, {})
	var by_name := {}
	var current := UNGROUPED
	for entry: Dictionary in shader.get_shader_uniform_list(true):
		var usage: int = entry["usage"]
		var uniform_name: String = entry["name"]
		if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
			current = uniform_name if not uniform_name.is_empty() else UNGROUPED
			continue
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if uniform_name in IGNORED or uniform_name.begins_with("_"):
			continue
		var param := _make_param(shader, entry, source_defaults)
		if param == null:
			continue
		if not by_name.has(current):
			var group := Group.new()
			group.name = current
			by_name[current] = group
			groups.append(group)
		(by_name[current] as Group).params.append(param)


func _make_param(shader: Shader, entry: Dictionary, source_defaults: Dictionary) -> Param:
	var param := Param.new()
	param.name = entry["name"]
	param.label = param.name.replace("_", " ")
	var type: int = entry["type"]
	match type:
		TYPE_FLOAT:
			param.kind = Kind.FLOAT
		TYPE_INT:
			param.kind = Kind.INT
		TYPE_BOOL:
			param.kind = Kind.BOOL
		TYPE_VECTOR2:
			param.kind = Kind.VEC2
		TYPE_COLOR:
			param.kind = Kind.COLOR
		_:
			return null

	var default_value: Variant = material.get_shader_parameter(param.name)
	if default_value == null:
		default_value = RenderingServer.shader_get_parameter_default(shader.get_rid(), param.name)
	if default_value == null:
		default_value = _convert_literal(source_defaults.get(param.name, ""), param.kind)
	param.default_value = default_value

	var hint: int = entry["hint"]
	var hint_parts: PackedStringArray = (entry["hint_string"] as String).split(",")
	var has_range := hint == PROPERTY_HINT_RANGE and hint_parts.size() >= 2
	# An int uniform without hint_range reports the full int32 span.
	if has_range and param.kind == Kind.INT and absf(hint_parts[1].to_float()) >= 2147483647.0:
		has_range = false
	if has_range:
		param.min_value = hint_parts[0].to_float()
		param.max_value = hint_parts[1].to_float()
		param.step = hint_parts[2].to_float() if hint_parts.size() >= 3 else 0.0
	else:
		_fallback_range(param)
	_normalize_step(param)
	return param


## Whole steps for ints, a step from the span where a param has none.
static func _normalize_step(param: Param) -> void:
	if param.kind == Kind.INT:
		param.step = maxf(roundf(param.step), 1.0)
	elif param.step <= 0.0:
		param.step = _nice_step(param.max_value - param.min_value)


## Span for uniforms without hint_range: zero to four times the default,
## mirrored for negative defaults.
func _fallback_range(param: Param) -> void:
	var magnitude := 1.0
	var negative := false
	match param.kind:
		Kind.FLOAT, Kind.INT:
			var scalar := float(param.default_value)
			magnitude = absf(scalar)
			negative = scalar < 0.0
		Kind.VEC2:
			var v := param.default_value as Vector2
			magnitude = maxf(absf(v.x), absf(v.y))
	if magnitude == 0.0:
		magnitude = 0.25
	param.min_value = -magnitude * 4.0 if negative else 0.0
	param.max_value = 0.0 if negative else magnitude * 4.0
	if param.kind == Kind.INT:
		param.step = 1.0
	else:
		param.step = 0.0


static func _nice_step(span: float) -> float:
	if span <= 0.0:
		return 0.001
	return pow(10.0, floorf(log(span / 1000.0) / log(10.0)))


## Maps uniform names to their initializer text, following #include lines.
static func _parse_source_defaults(code: String, path: String, visited: Dictionary) -> Dictionary:
	var result := {}
	if visited.has(path):
		return result
	visited[path] = true
	var include_re := RegEx.create_from_string(_INCLUDE_PATTERN)
	for include_match in include_re.search_all(code):
		var include_path := include_match.get_string(1)
		if not include_path.begins_with("res://"):
			include_path = path.get_base_dir().path_join(include_path)
		var include_file := FileAccess.open(include_path, FileAccess.READ)
		if include_file != null:
			result.merge(_parse_source_defaults(include_file.get_as_text(), include_path, visited))
	var uniform_re := RegEx.create_from_string(_UNIFORM_PATTERN)
	for uniform_match in uniform_re.search_all(code):
		result[uniform_match.get_string(1)] = uniform_match.get_string(2).strip_edges()
	return result


static func _convert_literal(text: String, kind: Kind) -> Variant:
	var numbers := PackedFloat64Array()
	var inner := text
	var open := text.find("(")
	if open >= 0:
		inner = text.substr(open + 1, text.rfind(")") - open - 1)
	for part in inner.split(",", false):
		numbers.append(part.strip_edges().trim_suffix("u").trim_suffix("f").to_float())
	if numbers.is_empty():
		numbers.append(0.0)
	match kind:
		Kind.FLOAT:
			return numbers[0]
		Kind.INT:
			return int(numbers[0])
		Kind.BOOL:
			return text.strip_edges() == "true"
		Kind.VEC2:
			return Vector2(numbers[0], numbers[1] if numbers.size() > 1 else numbers[0])
		Kind.COLOR:
			if numbers.size() < 3:
				return Color(numbers[0], numbers[0], numbers[0])
			return Color(numbers[0], numbers[1], numbers[2], numbers[3] if numbers.size() > 3 else 1.0)
	return null
