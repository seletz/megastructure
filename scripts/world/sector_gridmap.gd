class_name SectorGridMap
extends GridMap
## One solved sector placed as a GridMap: every cell of a solver result
## becomes a `set_cell_item` with the tile's prototype mesh and yaw.
##
##     var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
##     var mesh_library := SectorGridMap.build_mesh_library(library)
##     var grid := SectorGridMap.new()
##     grid.mesh_library = mesh_library
##     add_child(grid)
##     grid.place(library, Vector3i(-1, 1, -1), result.cells)   # result of SectorJobs.solve_sector
##
## Cells are 2 m (`WalkableGraph.CELL_SIZE`) and centred, so cell (i, j, k)
## of sector s is the box from `s * 48 + (i, j, k) * 2` to two metres
## further, the mesh origin at its centre. The node itself sits at the
## sector's corner, `sector * 48` m, and a result cell
## `x + n * (y + n * z)` goes to GridMap cell (x, y, z).
##
## The MeshLibrary has one item per prototype with a mesh, item id =
## prototype index; the air prototype (no mesh) has none and its cells stay
## empty. Each item's collision is one `ConcavePolygonShape3D` generated from
## its mesh with `Mesh.create_trimesh_shape`, so the capsule walks on exactly
## the geometry it sees. With `family_colours` each item's mesh is a copy
## with a `StandardMaterial3D` in the contact sheet's family colour.
##
## Orientation: a tile turned r quarter turns about +y uses
## `Basis(Vector3.UP, r * PI / 2)` (the turn `TileLibrary` expands sockets
## with: +x goes to -z), and GridMap stores that basis as one of its 24
## orthogonal indices. For yaw turns the indices are
##
##     quarter turns  0   1   2   3
##     orientation    0  16  10  22
##
## (`YAW_ORIENTATIONS`, taken from `get_orthogonal_index_from_basis` and
## pinned by `mise run gridmap-check`, which places an asymmetric mesh at
## each and checks where its geometry and collision end up).

## GridMap orientation index of 0..3 quarter turns about +y.
const YAW_ORIENTATIONS: Array[int] = [0, 16, 10, 22]

## Sector whose cells this map holds.
var sector := Vector3i.ZERO
## Cells set by the last `place`, air excluded.
var placed_cells := 0


func _init() -> void:
	cell_size = Vector3.ONE * WalkableGraph.CELL_SIZE
	cell_center_x = true
	cell_center_y = true
	cell_center_z = true


## A MeshLibrary with one item per prototype of `library`'s tiles that has a
## mesh, id = prototype index, named after the prototype, with a trimesh
## collision shape from the mesh. With `family_colours` the meshes are copies
## coloured by family (the originals are never changed).
static func build_mesh_library(library: TileLibrary, family_colours := true) -> MeshLibrary:
	var mesh_library := MeshLibrary.new()
	var done := {}
	for tile in library.tiles:
		if done.has(tile.prototype_index):
			continue
		done[tile.prototype_index] = true
		var prototype := tile.prototype
		if prototype.mesh == null:
			continue
		var id := tile.prototype_index
		var mesh := prototype.mesh
		if family_colours:
			mesh = coloured_mesh(mesh, family_colour(prototype.family))
		mesh_library.create_item(id)
		mesh_library.set_item_name(id, prototype.name)
		mesh_library.set_item_mesh(id, mesh)
		mesh_library.set_item_shapes(id, [prototype.mesh.create_trimesh_shape(), Transform3D.IDENTITY])
	return mesh_library


## The GridMap orientation index of `quarter_turns` about +y.
static func yaw_orientation(quarter_turns: int) -> int:
	return YAW_ORIENTATIONS[posmod(quarter_turns, 4)]


## Colour of a tile family, as the contact sheet draws it.
static func family_colour(family: int) -> Color:
	if family < 0 or family >= TileContactSheet.FAMILY_COLOURS.size():
		return TileContactSheet.FREE_COLOUR
	return TileContactSheet.FAMILY_COLOURS[family]


## A copy of `mesh` whose every surface uses one opaque material of `colour`.
static func coloured_mesh(mesh: Mesh, colour: Color) -> Mesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	var copy := mesh.duplicate() as Mesh
	if copy is PrimitiveMesh:
		(copy as PrimitiveMesh).material = material
	elif copy is ArrayMesh:
		for surface in (copy as ArrayMesh).get_surface_count():
			(copy as ArrayMesh).surface_set_material(surface, material)
	return copy


## World position of the corner of `sector_cell`, in metres.
static func sector_origin(sector_cell: Vector3i, cells_per_sector: int) -> Vector3:
	return Vector3(sector_cell) * cells_per_sector * WalkableGraph.CELL_SIZE


## World position of the centre of local cell `cell` of `sector_cell`.
static func cell_centre(sector_cell: Vector3i, cell: Vector3i, cells_per_sector: int) -> Vector3:
	return sector_origin(sector_cell, cells_per_sector) + (Vector3(cell) + Vector3.ONE * 0.5) * WalkableGraph.CELL_SIZE


## Clears the map, moves it to the corner of `sector_cell` and sets one item
## per non-air cell of `cells` (a result of `cells_per_sector`³ tile indices
## of `library`), turned by the tile's rotation. Returns the cells set.
func place(library: TileLibrary, sector_cell: Vector3i, cells: PackedInt32Array) -> int:
	clear()
	sector = sector_cell
	var n := roundi(pow(cells.size(), 1.0 / 3.0))
	position = sector_origin(sector_cell, n)
	placed_cells = 0
	var i := 0
	for z in n:
		for y in n:
			for x in n:
				var tile := library.tiles[cells[i]]
				i += 1
				if tile.prototype.mesh == null or mesh_library == null or mesh_library.get_item_mesh(tile.prototype_index) == null:
					continue
				set_cell_item(Vector3i(x, y, z), tile.prototype_index, yaw_orientation(tile.rotation))
				placed_cells += 1
	return placed_cells
