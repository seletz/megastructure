extends SceneTree
## Regression test of the sector grammar. Prints the type histogram of the
## 9x9x9 sectors centred on the origin for seed 0 (in total and per layer),
## checks that `Skeleton.sector_type()` is total and deterministic, and
## compares the histogram with docs/skeleton_histogram_seed0.md.
## Run headless with `mise run skeleton-histogram`; pass `--update` to
## rewrite the reference file instead of comparing against it.

const REFERENCE_PATH := "res://docs/skeleton_histogram_seed0.md"
const SEED := 0
const RADIUS := 4
const RANDOM_CELLS := 2000
## Salt for picking the random test cells; outside the grammar's salt range.
const SALT_TEST_CELL := 900

var _failures := 0


func _init() -> void:
	var update := "--update" in OS.get_cmdline_user_args()
	var skeleton := Skeleton.new()

	var table := _histogram_table(skeleton)
	print("\n".join(table))

	_check_total(skeleton)
	_check_deterministic(skeleton)

	if update:
		_write_reference(table)
	else:
		_compare_reference(table)

	print("skeleton histogram: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


## Markdown table rows: one per layer y = -RADIUS..RADIUS, then the total.
func _histogram_table(skeleton: Skeleton) -> PackedStringArray:
	var type_count := Skeleton.TYPE_NAMES.size()
	var header := "| y |"
	var rule := "| ---: |"
	for type_name in Skeleton.TYPE_NAMES:
		header += " %s |" % type_name
		rule += " ---: |"
	var rows := PackedStringArray([header, rule])

	var total := PackedInt32Array()
	total.resize(type_count)
	for y in range(-RADIUS, RADIUS + 1):
		var layer := PackedInt32Array()
		layer.resize(type_count)
		for x in range(-RADIUS, RADIUS + 1):
			for z in range(-RADIUS, RADIUS + 1):
				var type := skeleton.sector_type(SEED, Vector3i(x, y, z))
				layer[type] += 1
				total[type] += 1
		rows.append(_row(str(y), layer))
	rows.append(_row("**all**", total))
	return rows


static func _row(label: String, counts: PackedInt32Array) -> String:
	var row := "| %s |" % label
	for count in counts:
		row += " %d |" % count
	return row


## Every cell gets one of the five types, including the int32 extremes and
## with a grammar whose parameters are out of range.
func _check_total(skeleton: Skeleton) -> void:
	var broken := SectorGrammar.new()
	broken.shaft_layers = 0
	broken.cavity_cell = 0
	broken.cavity_min_size = 9
	broken.cavity_max_size = 0
	broken.solid_wall_grid = 0
	broken.solid_wall_panel = 0
	broken.solid_floor_grid = 0
	broken.solid_floor_panel = 0
	broken.chasm_band = 0
	broken.chasm_band_height = 0
	broken.chasm_probability = 1.0
	broken.chasm_width = 100
	broken.chasm_min_height = 500
	broken.chasm_max_height = 0
	var skeletons: Array[Skeleton] = [skeleton, Skeleton.new(broken)]

	var cells := _random_cells()
	for extreme in [-2147483648, -1, 0, 2147483647]:
		cells.append(Vector3i(extreme, extreme, extreme))
	var bad := 0
	for s in skeletons:
		for cell in cells:
			var type: int = s.sector_type(SEED, cell)
			if type < 0 or type >= Skeleton.TYPE_NAMES.size():
				bad += 1
	_expect(bad == 0, "total: %d cells under two grammars, %d without a type" % [cells.size(), bad])


## Two evaluations agree, on the same instance and on a fresh one.
func _check_deterministic(skeleton: Skeleton) -> void:
	var fresh := Skeleton.new()
	var mismatches := 0
	for cell in _random_cells():
		var first := skeleton.sector_type(SEED, cell)
		if skeleton.sector_type(SEED, cell) != first or fresh.sector_type(SEED, cell) != first:
			mismatches += 1
	_expect(mismatches == 0, "deterministic: %d random cells, %d mismatches" % [RANDOM_CELLS, mismatches])


## RANDOM_CELLS cells spread over the whole int32 range, drawn from the hash.
static func _random_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for i in RANDOM_CELLS:
		var axis := func(a: int) -> int: return Hash.hash3_u(SEED, Vector3i(i, a, 0), SALT_TEST_CELL) - 0x80000000
		cells.append(Vector3i(axis.call(0), axis.call(1), axis.call(2)))
	return cells


func _compare_reference(table: PackedStringArray) -> void:
	if not FileAccess.file_exists(REFERENCE_PATH):
		_expect(false, "reference: %s missing, run: mise run skeleton-histogram --update" % REFERENCE_PATH)
		return
	var reference := PackedStringArray()
	for line in FileAccess.get_file_as_string(REFERENCE_PATH).split("\n"):
		if line.begins_with("|"):
			reference.append(line)
	var same := reference == table
	_expect(same, "reference: histogram matches %s" % REFERENCE_PATH.trim_prefix("res://"))
	if not same:
		printerr("  expected:\n    %s" % "\n    ".join(reference))


func _write_reference(table: PackedStringArray) -> void:
	var text := """---
tags:
  - skeleton
  - reference
status: current
---

# Skeleton Histogram, Seed 0

> [!summary]
> How many sectors of each type the skeleton produces in the 9 × 9 × 9
> sectors centred on the origin for seed 0, per horizontal layer and in
> total. `mise run skeleton-histogram` recomputes the table and fails if it
> differs, so a change to the grammar or its defaults that changes the world
> shows up here. After an intended change, regenerate this file with
> `mise run skeleton-histogram --update` and commit it.

Cells span x, y and z from -%d to %d with the default `SectorGrammar`.
Generated file: only the table rows are compared.

%s

## References

- [[sector-skeleton-and-walkable-graph]]: the grammar these counts come from.
- [[tools-and-tasks]]: the task and its script.
""" % [RADIUS, RADIUS, "\n".join(table)]
	var file := FileAccess.open(REFERENCE_PATH, FileAccess.WRITE)
	if file == null:
		_expect(false, "reference: cannot write %s" % REFERENCE_PATH)
		return
	file.store_string(text)
	file.close()
	print("  ok    wrote %s" % REFERENCE_PATH.trim_prefix("res://"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
