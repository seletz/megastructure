// Shared integer hash. Must stay bit-identical with scripts/hash.gd and the
// hash3() in the HTML prototypes; docs/hash_vectors.md holds reference values.
//
// All arithmetic is 32-bit unsigned. Cells are integer lattice coordinates
// (floor() the position first), salt separates independent decisions made on
// the same cell.

uniform uint seed = 0u;

// PCG-style permutation of one 32-bit word.
uint hash_pcg(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

uint hash3_u(ivec3 cell, uint salt) {
	uvec3 c = uvec3(cell);
	uint h = hash_pcg(seed ^ hash_pcg(salt));
	h = hash_pcg(h ^ c.x);
	h = hash_pcg(h ^ c.y);
	h = hash_pcg(h ^ c.z);
	return h;
}

// 0..1 (exclusive). Uses the top 24 bits so the value is exact in float32.
float hash3(ivec3 cell, uint salt) {
	return float(hash3_u(cell, salt) >> 8u) / 16777216.0;
}

float hash2(ivec2 cell, uint salt) {
	return hash3(ivec3(cell, 0), salt);
}

float hash1(int cell, uint salt) {
	return hash3(ivec3(cell, 0, 0), salt);
}
