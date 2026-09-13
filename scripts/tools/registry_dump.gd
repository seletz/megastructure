extends SceneTree
## Prints the shader parameters the tweak panel discovers on the main scene.
## Run with `mise run ui-params`.

const Registry := preload("res://scripts/ui/param_registry.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const QUAD_PATH := "Camera/RaymarchQuad"
const KIND_NAMES: Array[String] = ["float", "int", "bool", "vec2", "color"]


func _init() -> void:
	var main := MAIN_SCENE.instantiate()
	var quad := main.get_node(QUAD_PATH) as MeshInstance3D
	var material := quad.get_active_material(0) as ShaderMaterial
	var registry := Registry.from_material(material)
	print("%d groups, %d params" % [registry.groups.size(), registry.param_count()])
	for group in registry.groups:
		print("")
		print("[%s]" % group.name)
		for param in group.params:
			var range_text := ""
			if param.kind in [Registry.Kind.FLOAT, Registry.Kind.INT, Registry.Kind.VEC2]:
				range_text = "  %s..%s step %s" % [_num(param.min_value), _num(param.max_value), _num(param.step)]
			print("  %-26s %-5s default=%s%s" % [param.name, KIND_NAMES[param.kind], _value(param.default_value), range_text])
	main.free()
	quit()


static func _num(value: float) -> String:
	return String.num(value, 6)


static func _value(value: Variant) -> String:
	if value is float:
		return _num(value)
	if value is Vector2:
		var v := value as Vector2
		return "(%s, %s)" % [_num(v.x), _num(v.y)]
	if value is Color:
		var c := value as Color
		return "(%s, %s, %s)" % [_num(c.r), _num(c.g), _num(c.b)]
	return str(value)
