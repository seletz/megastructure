extends SceneTree
## Validates a tileset beyond its format: dead sockets, directions with an
## empty allowed set, tiles unreachable from air and solid, symmetric sockets
## whose mesh face is not mirror-symmetric, and a placement histogram of 100
## runs on a 6³ grid. Prints every finding and exits 1 when any check fails.
##
##     godot --headless --path . --script res://scripts/tools/tiles_check.gd -- res://tests/fixtures/tilesets/fixture_tileset.tres
##
## Options after the path: `--runs N` (100), `--grid N` (6), `--max-restarts N`
## (8), `--max-contradiction-rate R` (0.5), `--seed N` (0). With
## `-- --self-test` it instead checks the tool itself: the fixture tileset
## must pass, the dead socket fixture must fail with exactly the expected
## categories, the placement must repeat for a seed and fail a low rate
## threshold, and four meshes built here must pass, fail or be skipped by the
## symmetry check. Run with `mise run tiles-check <tileset>` or
## `mise run tiles-check-fixtures`. The checks and the placement are described
## in docs/algorithms/socket-adjacency.md.

const FIXTURE := "res://tests/fixtures/tilesets/fixture_tileset.tres"
const DEAD_SOCKET_FIXTURE := "res://tests/fixtures/tilesets/dead_socket_tileset.tres"

## Failure categories, in the order the checks run.
const DEAD_SOCKET := "dead socket"
const EMPTY_DIRECTION := "empty direction"
const UNREACHABLE := "unreachable"
const FALSE_SYMMETRY := "false symmetry"
const NEVER_PLACED := "never placed"
const CONTRADICTIONS := "contradictions"
const INVALID := "invalid tileset"

## Categories the dead socket fixture must fail with, and nothing else.
const DEAD_SOCKET_EXPECTED: Array[String] = [DEAD_SOCKET, EMPTY_DIRECTION, UNREACHABLE, NEVER_PLACED]

const DEFAULT_RUNS := 100
const DEFAULT_GRID := 6
const DEFAULT_MAX_RESTARTS := 8
const DEFAULT_MAX_CONTRADICTION_RATE := 0.5

## Half the width of the slab around a face plane whose vertices form the
## face profile, in metres.
const SLAB := 0.01
## Distance within which a mirrored profile vertex matches an original one.
const TOLERANCE := 0.001

## Hash salts of the placement: attempt seed, cell order, tile choice.
const SEED_SALT := 8701
const ORDER_SALT := 8702
const CHOICE_SALT := 8703

## Grid step of each face index, +x, -x, +y, -y, +z, -z.
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## Findings of one tileset.
class Report:
	extends RefCounted
	## "category: message" lines in the order found.
	var failures: Array[String] = []
	## Category -> number of failures.
	var categories := {}
	var warnings: Array[String] = []

	func fail(category: String, message: String) -> void:
		failures.append("%s: %s" % [category, message])
		categories[category] = int(categories.get(category, 0)) + 1

	func warn(message: String) -> void:
		warnings.append(message)


## Outcome of the placement runs.
class Placement:
	extends RefCounted
	## Per tile index, cells holding it over all completed runs.
	var counts := PackedInt64Array()
	var runs := 0
	var attempts := 0
	var contradictions := 0
	## Runs that hit a contradiction on every attempt.
	var failed_runs := 0

	func contradiction_rate() -> float:
		return float(contradictions) / attempts if attempts > 0 else 0.0


## Options of one check.
class Options:
	extends RefCounted
	var runs := DEFAULT_RUNS
	var grid := DEFAULT_GRID
	var max_restarts := DEFAULT_MAX_RESTARTS
	var max_contradiction_rate := DEFAULT_MAX_CONTRADICTION_RATE
	var seed := 0


var _failures := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "--self-test" in args:
		quit(_self_test())
		return
	var options := Options.new()
	var path := ""
	var i := 0
	while i < args.size():
		var arg := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		match arg:
			"--runs":
				options.runs = value.to_int()
			"--grid":
				options.grid = value.to_int()
			"--max-restarts":
				options.max_restarts = value.to_int()
			"--max-contradiction-rate":
				options.max_contradiction_rate = value.to_float()
			"--seed":
				options.seed = value.to_int()
			_:
				if arg.begins_with("--") or not path.is_empty():
					printerr("tiles check: unexpected argument %s" % arg)
					quit(1)
					return
				path = arg
				i += 1
				continue
		i += 2
	if path.is_empty() or options.runs < 1 or options.grid < 1 or options.max_restarts < 0:
		printerr("tiles check: usage: <tileset.tres> [--runs N] [--grid N] [--max-restarts N] [--max-contradiction-rate R] [--seed N]")
		quit(1)
		return
	var report := check(_resource_path(path), options, "")
	print("tiles check: %s" % ("ok" if report.failures.is_empty() else "%d failure(s)" % report.failures.size()))
	quit(0 if report.failures.is_empty() else 1)


## Runs every check on the tileset at `path` and prints the findings, each
## line prefixed with `indent` plus two spaces.
func check(path: String, options: Options, indent: String) -> Report:
	var report := Report.new()
	var tileset: TileSet3D = null
	if ResourceLoader.exists(path):
		tileset = load(path) as TileSet3D
	if tileset == null:
		report.fail(INVALID, "%s is not a TileSet3D" % path)
		_print_report(report, indent)
		return report
	var library := TileLibrary.build(tileset)
	for error in library.errors:
		report.fail(INVALID, error)
	print("%s  %s: %d prototypes, %d tiles" % [indent, path, tileset.prototypes.size(), library.tile_count()])
	if library.errors.is_empty():
		check_dead_sockets(library, report)
		check_empty_directions(library, report)
		check_reachability(tileset, library, report)
		check_symmetry(tileset, report)
		var placement := place(library, options)
		print_histogram(library, placement, indent)
		check_placement(library, placement, options, report)
	_print_report(report, indent)
	return report


## A socket on face d is dead when no tile shows its partner on face d ^ 1.
## Exclusions are ignored here; `check_empty_directions` sees them.
func check_dead_sockets(library: TileLibrary, report: Report) -> void:
	for dir in TilePrototype.FACE_COUNT:
		var shown := {}
		for tile in library.tiles:
			shown[tile.keys[dir ^ 1]] = true
		# Socket string -> labels of the tiles showing it on `dir`, in tile order.
		var dead := {}
		for tile in library.tiles:
			var socket := TilePrototype.parse_socket(tile.sockets[dir], dir)
			if not shown.has(TileLibrary.partner_key(socket)):
				dead.get_or_add(tile.sockets[dir], PackedStringArray()).append(tile.label())
		for text: String in dead:
			report.fail(DEAD_SOCKET, "%s \"%s\" on %s has no %s partner \"%s\"" % [
				TilePrototype.FACE_NAMES[dir], text, ", ".join(dead[text]),
				TilePrototype.FACE_NAMES[dir ^ 1], partner_text(TilePrototype.parse_socket(text, dir)),
			])


## Every tile needs at least one allowed neighbour in every direction.
func check_empty_directions(library: TileLibrary, report: Report) -> void:
	for tile in library.tiles:
		for dir in TilePrototype.FACE_COUNT:
			if _is_zero(library.allowed(dir, tile.index)):
				report.fail(EMPTY_DIRECTION, "%s allows no tile on %s" % [tile.label(), TilePrototype.FACE_NAMES[dir]])


## Breadth-first search over the adjacency graph from every rotation of the
## air and solid tiles; a tile it never reaches cannot grow out of them.
func check_reachability(tileset: TileSet3D, library: TileLibrary, report: Report) -> void:
	var reached := PackedByteArray()
	reached.resize(library.tile_count())
	reached.fill(0)
	var queue := PackedInt32Array()
	for tile in library.tiles:
		if tile.prototype.name == tileset.air_name or tile.prototype.name == tileset.solid_name:
			reached[tile.index] = 1
			queue.append(tile.index)
	var head := 0
	while head < queue.size():
		var a := queue[head]
		head += 1
		for b in library.tile_count():
			if reached[b] == 1:
				continue
			for dir in TilePrototype.FACE_COUNT:
				if library.is_allowed(dir, a, b):
					reached[b] = 1
					queue.append(b)
					break
	for tile in library.tiles:
		if reached[tile.index] == 0:
			report.fail(UNREACHABLE, "%s is not reachable from %s or %s" % [tile.label(), tileset.air_name, tileset.solid_name])


## Every horizontal `Ns` socket of a prototype must have a mirror-symmetric
## face profile in its mesh. Rotations turn the profile with the socket, so
## the unrotated prototype decides.
func check_symmetry(tileset: TileSet3D, report: Report) -> void:
	for prototype in tileset.prototypes:
		if prototype.mesh == null:
			continue
		var symmetric_faces: Array[int] = []
		for face in TilePrototype.FACE_COUNT:
			var socket := prototype.socket(face)
			if not socket.vertical and socket.symmetric:
				symmetric_faces.append(face)
		if symmetric_faces.is_empty():
			continue
		var vertices := mesh_vertices(prototype.mesh)
		if vertices.is_empty():
			report.warn("prototype \"%s\": %s has no vertex data, symmetry not checked" % [prototype.name, prototype.mesh.get_class()])
			continue
		for face in symmetric_faces:
			var unmatched := asymmetric_vertices(vertices, face)
			if not unmatched.is_empty():
				report.fail(FALSE_SYMMETRY, "prototype \"%s\": %s \"%s\" but %d face profile point(s), first %s, have no mirror image" % [
					prototype.name, TilePrototype.FACE_NAMES[face], prototype.sockets[face], unmatched.size(), unmatched[0],
				])


## Every vertex of every surface; a `PrimitiveMesh` generates its arrays.
static func mesh_vertices(mesh: Mesh) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	if mesh is PrimitiveMesh:
		var arrays := (mesh as PrimitiveMesh).get_mesh_arrays()
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
		return vertices
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
	return vertices


## The profile points (tangent, y) of the vertices within SLAB of the face
## plane whose mirror (-tangent, y) matches no profile point within
## TOLERANCE; empty when the profile is mirror-symmetric. The tangent is z on ±x faces
## and x on ±z faces, both measured from the cell centre.
static func asymmetric_vertices(vertices: PackedVector3Array, face: int) -> PackedVector2Array:
	var axis := 0 if face <= TilePrototype.FACE_NEG_X else 2
	var tangent := 2 if axis == 0 else 0
	var plane := WalkableGraph.CELL_SIZE / 2.0 * (1.0 if face % 2 == 0 else -1.0)
	var profile: Array[Vector2] = []
	var buckets := {}
	var unmatched := PackedVector2Array()
	for vertex in vertices:
		if absf(vertex[axis] - plane) > SLAB:
			continue
		var point := Vector2(vertex[tangent], vertex.y)
		profile.append(point)
		buckets.get_or_add(_bucket(point), []).append(point)
	for point in profile:
		var mirrored := Vector2(-point.x, point.y)
		var cell := _bucket(mirrored)
		var found := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for other: Vector2 in buckets.get(cell + Vector2i(dx, dy), []):
					if other.distance_to(mirrored) <= TOLERANCE:
						found = true
		if not found:
			unmatched.append(point)
	return unmatched


## The socket string that matches `socket` on the opposite face.
static func partner_text(socket: TilePrototype.Socket) -> String:
	var partner := TileLibrary.rotate_socket(socket, 0)
	if not socket.vertical and not socket.symmetric:
		partner.flipped = not socket.flipped
	return str(partner)


## Fills a grid of `options.grid`³ cells `options.runs` times with no boundary
## constraints. Each attempt visits the cells in hashed order; a cell with
## more than one tile left picks one by weight with a hashed draw, then AC-3
## propagation over the bitsets narrows the neighbours. An empty domain is a
## contradiction: the run restarts with the next attempt seed, at most
## `options.max_restarts` times.
func place(library: TileLibrary, options: Options) -> Placement:
	var placement := Placement.new()
	var n := library.tile_count()
	var words := library.word_count
	placement.counts.resize(n)
	placement.counts.fill(0)
	placement.runs = options.runs
	var allowed: Array[PackedInt64Array] = []
	for dir in TilePrototype.FACE_COUNT:
		for tile in n:
			allowed.append(library.allowed(dir, tile))
	var full := PackedInt64Array()
	full.resize(words)
	full.fill(0)
	for tile in n:
		full[tile >> 6] |= 1 << (tile & 63)
	var size := options.grid
	var cells := size * size * size

	for run in options.runs:
		var solved := PackedInt32Array()
		for attempt in options.max_restarts + 1:
			placement.attempts += 1
			var seed := Hash.hash3_u(options.seed, Vector3i(run, attempt, 0), SEED_SALT)
			solved = _attempt(library, allowed, full, size, seed)
			if solved.size() == cells:
				break
			placement.contradictions += 1
		if solved.size() != cells:
			placement.failed_runs += 1
			continue
		for tile in solved:
			placement.counts[tile] += 1
	return placement


## Prints each tile's placement count with its share of all placed cells,
## then the attempts and contradiction rate.
func print_histogram(library: TileLibrary, placement: Placement, indent: String) -> void:
	var total := 0
	for count in placement.counts:
		total += count
	print("%s  placement: %d runs, %d attempts, %d contradictions (rate %.3f), %d failed runs" % [
		indent, placement.runs, placement.attempts, placement.contradictions, placement.contradiction_rate(), placement.failed_runs,
	])
	for tile in library.tiles:
		var count := placement.counts[tile.index]
		var share := float(count) / total if total > 0 else 0.0
		print("%s    %3d %-14s %8d  %5.1f%%  %s" % [indent, tile.index, tile.label(), count, share * 100.0, "#".repeat(roundi(share * 40.0))])


func check_placement(library: TileLibrary, placement: Placement, options: Options, report: Report) -> void:
	for tile in library.tiles:
		if placement.counts[tile.index] == 0:
			report.fail(NEVER_PLACED, "%s never placed in %d runs" % [tile.label(), placement.runs])
	if placement.contradiction_rate() > options.max_contradiction_rate:
		report.fail(CONTRADICTIONS, "rate %.3f above %.3f (%d of %d attempts)" % [
			placement.contradiction_rate(), options.max_contradiction_rate, placement.contradictions, placement.attempts,
		])


## One attempt: the tile index of every cell in x, y, z order, or an empty
## array on a contradiction.
func _attempt(library: TileLibrary, allowed: Array[PackedInt64Array], full: PackedInt64Array, size: int, seed: int) -> PackedInt32Array:
	var n := library.tile_count()
	var words := library.word_count
	var cells := size * size * size
	var wave := PackedInt64Array()
	wave.resize(cells * words)
	for cell in cells:
		for w in words:
			wave[cell * words + w] = full[w]

	# Cells sorted by a 31-bit hash above the cell index, so ties keep index order.
	var order := PackedInt64Array()
	order.resize(cells)
	for cell in cells:
		order[cell] = (Hash.hash3_u(seed, _position(cell, size), ORDER_SALT) >> 1) << 32 | cell
	order.sort()

	for key in order:
		var cell := key & 0xFFFFFFFF
		var base := cell * words
		var total := 0.0
		var options := 0
		for tile in n:
			if (wave[base + (tile >> 6)] >> (tile & 63)) & 1 == 1:
				total += library.tiles[tile].weight
				options += 1
		if options == 1:
			continue
		var draw := Hash.hash3(seed, _position(cell, size), CHOICE_SALT) * total
		var chosen := -1
		for tile in n:
			if (wave[base + (tile >> 6)] >> (tile & 63)) & 1 == 1:
				chosen = tile
				draw -= library.tiles[tile].weight
				if draw < 0.0:
					break
		for w in words:
			wave[base + w] = 0
		wave[base + (chosen >> 6)] = 1 << (chosen & 63)
		if not _propagate(library, allowed, wave, size, cell):
			return PackedInt32Array()

	var result := PackedInt32Array()
	result.resize(cells)
	for cell in cells:
		for tile in n:
			if (wave[cell * words + (tile >> 6)] >> (tile & 63)) & 1 == 1:
				result[cell] = tile
				break
	return result


## AC-3 from `start`: each changed cell ANDs the union of its tiles' allowed
## sets into each neighbour and queues the neighbours that shrank. False when
## a domain becomes empty.
func _propagate(library: TileLibrary, allowed: Array[PackedInt64Array], wave: PackedInt64Array, size: int, start: int) -> bool:
	var n := library.tile_count()
	var words := library.word_count
	var stack := PackedInt32Array([start])
	var mask := PackedInt64Array()
	mask.resize(words)
	while not stack.is_empty():
		var cell := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var position := _position(cell, size)
		var base := cell * words
		for dir in TilePrototype.FACE_COUNT:
			var next := position + STEPS[dir]
			if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= size or next.y >= size or next.z >= size:
				continue
			mask.fill(0)
			for tile in n:
				if (wave[base + (tile >> 6)] >> (tile & 63)) & 1 == 1:
					var tile_allowed := allowed[dir * n + tile]
					for w in words:
						mask[w] |= tile_allowed[w]
			var neighbour := (next.x * size + next.y) * size + next.z
			var changed := false
			var empty := true
			for w in words:
				var old := wave[neighbour * words + w]
				var narrowed := old & mask[w]
				if narrowed != old:
					wave[neighbour * words + w] = narrowed
					changed = true
				if narrowed != 0:
					empty = false
			if empty:
				return false
			if changed:
				stack.append(neighbour)
	return true


func _self_test() -> int:
	var options := Options.new()
	print("tiles check self-test")
	var fixture := check(FIXTURE, options, "  ")
	if not fixture.failures.is_empty():
		_fail("%s: expected no failures, got %d" % [FIXTURE, fixture.failures.size()])
	var broken := check(DEAD_SOCKET_FIXTURE, options, "  ")
	var categories: Array[String] = []
	for category: String in broken.categories:
		categories.append(category)
	if categories != DEAD_SOCKET_EXPECTED:
		_fail("%s: failure categories %s, expected %s" % [DEAD_SOCKET_FIXTURE, categories, DEAD_SOCKET_EXPECTED])
	_self_test_placement()
	_self_test_symmetry()
	print("tiles check self-test: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	return 0 if _failures == 0 else 1


## The placement is deterministic for a seed, differs for another seed, and
## a rate threshold below the dead socket fixture's rate fails.
func _self_test_placement() -> void:
	var library := TileLibrary.build(load(DEAD_SOCKET_FIXTURE) as TileSet3D)
	var options := Options.new()
	options.runs = 20
	var first := place(library, options)
	var again := place(library, options)
	if first.counts != again.counts or first.contradictions != again.contradictions:
		_fail("placement: two runs with seed 0 differ: %s and %s" % [first.counts, again.counts])
	options.seed = 1
	if place(library, options).counts == first.counts:
		_fail("placement: seeds 0 and 1 place the same tiles")
	options.max_contradiction_rate = first.contradiction_rate() / 2.0
	var report := Report.new()
	check_placement(library, first, options, report)
	if not report.categories.has(CONTRADICTIONS):
		_fail("placement: rate %.3f passed a threshold of %.3f" % [first.contradiction_rate(), options.max_contradiction_rate])
	print("  placement: deterministic per seed, threshold %.3f fails" % options.max_contradiction_rate)


## A centred `BoxMesh` and the same box as an `ArrayMesh` pass, the box
## shifted along z fails on +x and -x, and a mesh without surfaces is skipped
## with a warning.
func _self_test_symmetry() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 1)
	var shifted := PackedVector3Array()
	for vertex: Vector3 in box.get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
		shifted.append(vertex + Vector3(0, 0, 0.4))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = shifted
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var centred := ArrayMesh.new()
	centred.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())

	var cases := [
		[box, 0, 0], [centred, 0, 0], [array_mesh, 2, 0], [ArrayMesh.new(), 0, 1],
	]
	for case in cases:
		var tileset := TileSet3D.new()
		var prototype := TilePrototype.new()
		prototype.name = "probe"
		prototype.mesh = case[0]
		prototype.sockets = PackedStringArray(["0s", "0s", "0i", "0i", "0s", "0s"])
		tileset.prototypes.append(prototype)
		var report := Report.new()
		check_symmetry(tileset, report)
		if report.failures.size() != case[1] or report.warnings.size() != case[2]:
			_fail("symmetry of %s: %d failures %s, %d warnings, expected %d and %d" % [
				case[0], report.failures.size(), report.failures, report.warnings.size(), case[1], case[2],
			])
	print("  symmetry: %d meshes" % cases.size())


func _print_report(report: Report, indent: String) -> void:
	for warning in report.warnings:
		print("%s  warning: %s" % [indent, warning])
	for failure in report.failures:
		printerr("%s  FAIL  %s" % [indent, failure])


static func _bucket(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / TOLERANCE), roundi(point.y / TOLERANCE))


static func _position(cell: int, size: int) -> Vector3i:
	return Vector3i(cell / (size * size), (cell / size) % size, cell % size)


static func _is_zero(words: PackedInt64Array) -> bool:
	for word in words:
		if word != 0:
			return false
	return true


## A `res://` path as given, anything else taken relative to the project.
static func _resource_path(path: String) -> String:
	return path if path.contains("://") else "res://" + path.trim_prefix("./")


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  %s" % message)
