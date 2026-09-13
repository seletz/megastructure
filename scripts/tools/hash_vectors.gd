extends SceneTree
## Prints the reference vectors of the shared integer hash.
## Run with `mise run hash-vectors`; the output must match docs/hash_vectors.md.

const HashLib := preload("res://scripts/hash.gd")

const VECTORS := [
	[0, Vector3i(0, 0, 0), 0],
	[1, Vector3i(0, 0, 0), 0],
	[0, Vector3i(1, 2, 3), 0],
	[0, Vector3i(0, 0, 0), 7],
	[12345, Vector3i(-1, -2, -3), 31],
	[4294967295, Vector3i(2147483647, -2147483648, 0), 4294967295],
	[3735928559, Vector3i(17, -40, 255), 42],
	[2654435769, Vector3i(-100000, 7, 123456), 60],
]


func _init() -> void:
	print("| seed | cell | salt | u32 | value |")
	print("| ---: | :--- | ---: | ---: | ---: |")
	for v in VECTORS:
		var cell: Vector3i = v[1]
		var u := HashLib.hash3_u(v[0], cell, v[2])
		var f := HashLib.hash3(v[0], cell, v[2])
		print("| %d | (%d, %d, %d) | %d | %d | %.9f |" % [v[0], cell.x, cell.y, cell.z, v[2], u, f])
	quit()
