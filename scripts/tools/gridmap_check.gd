extends SceneTree
## Checks `SectorGridMap` on hand-built meshes and the placeholder tileset.
##
## Orientation: for 0..3 quarter turns about +y,
## `get_orthogonal_index_from_basis(Basis(Vector3.UP, r * PI / 2))` equals
## `SectorGridMap.YAW_ORIENTATIONS[r]` and the index turns back into that
## basis. An asymmetric mesh (a 0.8 × 2 × 0.4 m box in the +x, -z corner of
## the cell) placed at each orientation must have its geometry, read through
## `get_cell_item_basis`, and its collision, found by rays cast down through
## the map, at the hand-computed corner: +x-z, then -x-z, -x+z and +x+z,
## counter-clockwise seen from above as `TileLibrary` turns sockets; the
## mirrored corner must stay empty.
##
## Placeholder tileset: the MeshLibrary has one item per prototype with a
## mesh, named after it, each with one trimesh shape, and none for air. A
## 2³ result holding the four stair rotations under air is placed:
## every cell's item and orientation match its tile, air stays empty, and
## each stair's collision is high on the face `TileLibrary` gives its rock
## socket (`1s`, the stair's high end) and low on the opposite face.
##
##     godot --headless --path . --script res://scripts/tools/gridmap_check.gd
##
## Run with `mise run gridmap-check`.

const TILESET := "res://resources/tilesets/placeholder.tres"
## Centre of the asymmetric box of the unturned mesh, inside a 2 m cell.
const MARK_CENTRE := Vector3(0.6, 0.0, -0.8)
## Where that centre must be after 0..3 quarter turns, by hand.
const MARK_TURNED: Array[Vector3] = [
	Vector3(0.6, 0.0, -0.8), Vector3(-0.8, 0.0, -0.6),
	Vector3(-0.6, 0.0, 0.8), Vector3(0.8, 0.0, 0.6),
]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_indices()
	await _check_asymmetric_mesh()
	await _check_placeholder()
	print("gridmap check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_indices() -> void:
	var probe := GridMap.new()
	for r in 4:
		var basis := Basis(Vector3.UP, r * PI / 2.0)
		var index := probe.get_orthogonal_index_from_basis(basis)
		_expect(index == SectorGridMap.YAW_ORIENTATIONS[r] and SectorGridMap.yaw_orientation(r) == index,
			"%d quarter turn(s) is orientation %d (table %d)" % [r, index, SectorGridMap.YAW_ORIENTATIONS[r]])
		_expect(probe.get_basis_with_orthogonal_index(index).is_equal_approx(basis.orthonormalized()),
			"orientation %d turns back into the %d quarter turn basis" % [index, r])
	_expect(SectorGridMap.yaw_orientation(-1) == SectorGridMap.YAW_ORIENTATIONS[3] and SectorGridMap.yaw_orientation(5) == SectorGridMap.YAW_ORIENTATIONS[1],
		"yaw_orientation wraps quarter turns modulo 4")
	probe.free()


func _check_asymmetric_mesh() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 2.0, 0.4)
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i] += MARK_CENTRE
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	mesh_library.set_item_mesh(0, mesh)
	mesh_library.set_item_shapes(0, [mesh.create_trimesh_shape(), Transform3D.IDENTITY])

	var grid := SectorGridMap.new()
	grid.mesh_library = mesh_library
	root.add_child(grid)
	# Cells two apart along x, one per turn.
	for r in 4:
		grid.set_cell_item(Vector3i(2 * r, 0, 0), 0, SectorGridMap.yaw_orientation(r))
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	for r in 4:
		var cell := Vector3i(2 * r, 0, 0)
		var centre := grid.map_to_local(cell)
		var seen := grid.get_cell_item_basis(cell) * MARK_CENTRE
		_expect(seen.is_equal_approx(MARK_TURNED[r]),
			"%d quarter turn(s): mesh centre at %s, expected %s" % [r, seen, MARK_TURNED[r]])
		var hit := _ray_down(space, centre + MARK_TURNED[r])
		var mirrored := _ray_down(space, centre - MARK_TURNED[r])
		_expect(not hit.is_empty() and mirrored.is_empty(),
			"%d quarter turn(s): collision at %s and not at the mirrored corner" % [r, MARK_TURNED[r]])
	grid.queue_free()
	await process_frame


func _check_placeholder() -> void:
	var library := TileLibrary.build(load(TILESET) as TileSet3D)
	_expect(library.errors.is_empty(), "placeholder library builds")
	if not library.errors.is_empty():
		return
	var mesh_library := SectorGridMap.build_mesh_library(library)
	var tileset := load(TILESET) as TileSet3D
	var items := 0
	for index in tileset.prototypes.size():
		var prototype := tileset.prototypes[index]
		if prototype.mesh == null:
			_expect(index not in mesh_library.get_item_list(), "%s has no item" % prototype.name)
			continue
		items += 1
		_expect(mesh_library.get_item_name(index) == prototype.name and mesh_library.get_item_mesh(index) != null
			and mesh_library.get_item_shapes(index).size() == 2 and mesh_library.get_item_shapes(index)[0] is ConcavePolygonShape3D,
			"item %d is %s with a mesh and one trimesh shape" % [index, prototype.name])
	_expect(mesh_library.get_item_list().size() == items, "%d items, one per prototype with a mesh" % items)

	# A 2³ result: the four stair rotations on the bottom layer, air above.
	var stairs: Array[int] = []
	for tile in library.tiles:
		if tile.prototype.family == EdgeRasteriser.TileFamily.STAIR:
			stairs.append(tile.index)
	_expect(stairs.size() == 4, "placeholder has four stair rotations")
	if stairs.size() != 4:
		return
	var air := library.air_tile
	var cells := PackedInt32Array([stairs[0], stairs[1], air, air, stairs[2], stairs[3], air, air])
	var grid := SectorGridMap.new()
	grid.mesh_library = mesh_library
	root.add_child(grid)
	var placed := grid.place(library, Vector3i(1, -1, 0), cells)
	_expect(placed == 4 and grid.position == Vector3(4.0, -4.0, 0.0), "place sets 4 cells at the corner of a 4 m sector (%d at %s)" % [placed, grid.position])
	for i in cells.size():
		var cell := Vector3i(i % 2, (i / 2) % 2, i / 4)
		var tile := library.tiles[cells[i]]
		if tile.prototype.mesh == null:
			_expect(grid.get_cell_item(cell) == GridMap.INVALID_CELL_ITEM, "air at %s stays empty" % cell)
		else:
			_expect(grid.get_cell_item(cell) == tile.prototype_index and grid.get_cell_item_orientation(cell) == SectorGridMap.yaw_orientation(tile.rotation),
				"%s at %s has item %d orientation %d" % [tile.label(), cell, tile.prototype_index, SectorGridMap.yaw_orientation(tile.rotation)])
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	for i in [0, 1, 4, 5]:
		var tile := library.tiles[cells[i]]
		var cell := Vector3i(i % 2, 0, i / 4)
		var high_face := TileLibrary.rotate_face(TilePrototype.FACE_POS_X, tile.rotation)
		_expect(tile.sockets[high_face] == "1s", "%s has its rock socket on %s" % [tile.label(), TilePrototype.FACE_NAMES[high_face]])
		var dir := Vector3(SolverSectorRun.STEPS[high_face])
		var centre := grid.to_global(grid.map_to_local(cell))
		var high := _ray_down(space, centre + dir * 0.8)
		var low := _ray_down(space, centre - dir * 0.8)
		var high_y: float = high.position.y - centre.y if not high.is_empty() else -INF
		var low_y: float = low.position.y - centre.y if not low.is_empty() else -INF
		_expect(high_y > 0.5 and low_y < -0.3,
			"%s: tread %.2f m on %s, %.2f m opposite" % [tile.label(), high_y, TilePrototype.FACE_NAMES[high_face], low_y])
	grid.queue_free()
	await process_frame


## The first hit of a ray from 1.5 m above `point` to 1.5 m below it.
func _ray_down(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.5, point + Vector3.DOWN * 1.5)
	return space.intersect_ray(query)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s" % message)

