class_name ParamRegistry
extends RefCounted
## Shader parameters of a ShaderMaterial, discovered at runtime.
##
## Walks Shader.get_shader_uniform_list(), so every uniform a shader or its
## includes declares shows up without a hand-maintained list. Uniforms are
## bucketed by their group_uniforms block; ranges come from hint_range and fall
## back to a span around the default where a uniform has no hint.
##
## Defaults come from the material override, then the rendering server, then
## the uniform's initializer in the shader source (the headless dummy renderer
## reports no defaults).

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
	var value: Variant = material.get_shader_parameter(param.name)
	return param.default_value if value == null else value


func set_value(param: Param, value: Variant) -> void:
	material.set_shader_parameter(param.name, value)


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
	if param.kind == Kind.INT:
		param.step = maxf(roundf(param.step), 1.0)
	elif param.step <= 0.0:
		param.step = _nice_step(param.max_value - param.min_value)
	return param


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
