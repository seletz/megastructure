@tool
class_name TileSet3D
extends Resource
## The tile prototypes the fill solver places, with the names of its solid
## and air tiles. Named TileSet3D so it does not clash with Godot's 2D
## `TileSet`.
##
##     var tileset: TileSet3D = load("res://tests/fixtures/tilesets/fixture_tileset.tres")
##     var errors := tileset.validate()
##     if errors.is_empty():
##         print(tileset.find(tileset.solid_name).sockets)
##
## `validate` reports every structural problem as one string: duplicate or
## empty names, bad socket strings, weights, rotations and families, unknown
## solid, air and exclusion names, a missing mesh. With `require_families`
## it also requires one prototype per `EdgeRasteriser.TileFamily`. Socket
## matching, rotation expansion and the adjacency table are not done here.
## The format is in docs/code/tileset.md.

## Prototypes in authoring order; names are unique.
@export var prototypes: Array[TilePrototype] = []
## Name of the near-universal solid tile.
@export var solid_name := "solid"
## Name of the empty tile. It is the only prototype that may have no mesh.
@export var air_name := "air"


## The prototype with this name, or null.
func find(prototype_name: String) -> TilePrototype:
	for prototype in prototypes:
		if prototype != null and prototype.name == prototype_name:
			return prototype
	return null


## `EdgeRasteriser.TileFamily` values no prototype belongs to, ascending.
func missing_families() -> Array[int]:
	var present := {}
	for prototype in prototypes:
		if prototype != null:
			present[prototype.family] = true
	var missing: Array[int] = []
	for family in EdgeRasteriser.TileFamily.size():
		if not present.has(family):
			missing.append(family)
	return missing


## Every problem of the tileset, in prototype order and then tileset-wide;
## empty when it is valid.
func validate(require_families := false) -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for i in prototypes.size():
		var prototype := prototypes[i]
		if prototype == null:
			errors.append("prototype %d: null" % i)
			continue
		errors.append_array(prototype.validate())
		if not prototype.name.is_empty():
			if seen.has(prototype.name):
				errors.append("prototype \"%s\": name used more than once" % prototype.name)
			seen[prototype.name] = true
		if prototype.mesh == null and prototype.name != air_name:
			errors.append("prototype \"%s\": no mesh" % prototype.name)

	for prototype in prototypes:
		if prototype == null:
			continue
		for excluded in prototype.exclusions:
			if not seen.has(excluded):
				errors.append("prototype \"%s\": exclusion \"%s\" is not a prototype" % [prototype.name, excluded])

	if not seen.has(solid_name):
		errors.append("solid_name \"%s\" is not a prototype" % solid_name)
	if not seen.has(air_name):
		errors.append("air_name \"%s\" is not a prototype" % air_name)
	if solid_name == air_name:
		errors.append("solid_name and air_name are both \"%s\"" % solid_name)
	if require_families:
		for family in missing_families():
			errors.append("no prototype of family %s" % EdgeRasteriser.family_name(family))
	return errors
