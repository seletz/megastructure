class_name Hash
## Shared integer hash. Must stay bit-identical with
## shaders/include/hash.gdshaderinc and the hash3() in the HTML prototypes;
## docs/hash_vectors.md holds reference values.
##
## GDScript ints are 64-bit, so every intermediate is masked to 32 bits and
## multiplication is split into 16-bit halves to stay clear of int64 overflow.

const MASK := 0xFFFFFFFF


static func _mul32(a: int, b: int) -> int:
	var lo := a * (b & 0xFFFF)
	var hi := (a * (b >> 16)) & 0xFFFF
	return (lo + (hi << 16)) & MASK


## PCG-style permutation of one 32-bit word.
static func pcg(v: int) -> int:
	var s := (_mul32(v & MASK, 747796405) + 2891336453) & MASK
	var w := _mul32((s >> ((s >> 28) + 4)) ^ s, 277803737)
	return (w >> 22) ^ w


static func hash3_u(seed: int, cell: Vector3i, salt: int) -> int:
	var h := pcg((seed & MASK) ^ pcg(salt & MASK))
	h = pcg(h ^ (cell.x & MASK))
	h = pcg(h ^ (cell.y & MASK))
	h = pcg(h ^ (cell.z & MASK))
	return h


## 0..1 (exclusive). Uses the top 24 bits so the value is exact in float32.
static func hash3(seed: int, cell: Vector3i, salt: int) -> float:
	return float(hash3_u(seed, cell, salt) >> 8) / 16777216.0


static func hash2(seed: int, cell: Vector2i, salt: int) -> float:
	return hash3(seed, Vector3i(cell.x, cell.y, 0), salt)


static func hash1(seed: int, cell: int, salt: int) -> float:
	return hash3(seed, Vector3i(cell, 0, 0), salt)
