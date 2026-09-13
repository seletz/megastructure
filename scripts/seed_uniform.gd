class_name SeedUniform
extends Node
## Keeps the seed uniform of a ShaderMaterial in sync with WorldState.seed.

const UNIFORM := "seed"

## MeshInstance3D whose active surface material declares the seed uniform.
@export var material_source: NodePath

var _material: ShaderMaterial


func _ready() -> void:
	var mesh := get_node_or_null(material_source) as MeshInstance3D
	if mesh != null:
		_material = mesh.get_active_material(0) as ShaderMaterial
	if _material == null:
		push_warning("SeedUniform: no ShaderMaterial found at %s" % material_source)
		return
	WorldState.seed_changed.connect(_apply)
	_apply(WorldState.seed)


func _apply(seed: int) -> void:
	_material.set_shader_parameter(UNIFORM, seed)
