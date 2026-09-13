// Chasm distance field, ported from facade()/map() in docs/megastructure-chasm.html.
// Requires sdf.gdshaderinc and hash.gdshaderinc to be included first.
//
// Hash salts match the prototype's call sites so both agree for the same seed.
// Material ids: 0 concrete, 1 metal.

const int CHASM_MAT_CONCRETE = 0;
const int CHASM_MAT_METAL = 1;

group_uniforms chasm;
uniform float chasm_half_width : hint_range(20.0, 400.0, 1.0) = 140.0;
uniform float stratum_height : hint_range(1.0, 30.0, 0.1) = 6.0;

group_uniforms chasm.ledges;
uniform float ledge_depth : hint_range(0.0, 10.0, 0.01) = 1.2;
uniform float ledge_height : hint_range(0.0, 5.0, 0.01) = 0.44;

group_uniforms chasm.decks;
uniform float deck_spacing : hint_range(5.0, 200.0, 0.5) = 30.0;
uniform float deck_depth : hint_range(0.0, 30.0, 0.1) = 4.4;
uniform float deck_height : hint_range(0.0, 10.0, 0.05) = 1.4;

group_uniforms chasm.buttresses;
uniform float buttress_spacing : hint_range(5.0, 200.0, 0.5) = 40.0;
uniform float buttress_width : hint_range(0.0, 30.0, 0.1) = 3.6;
uniform float buttress_depth : hint_range(0.0, 40.0, 0.1) = 10.0;
uniform float buttress_removal : hint_range(0.0, 1.0, 0.01) = 0.25;
// Removal decisions are made per cell of this size (x along the wall, y vertical).
uniform vec2 buttress_removal_cell = vec2(40.0, 120.0);

group_uniforms chasm.terraces;
uniform float terrace_cell : hint_range(10.0, 400.0, 1.0) = 60.0;
uniform float terrace_probability : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float terrace_depth_min : hint_range(0.0, 100.0, 0.5) = 6.0;
uniform float terrace_depth_max : hint_range(0.0, 100.0, 0.5) = 20.0;
group_uniforms;

// Profile of a feature running along x: centred at v across its height,
// attached to the wall plane and protruding by depth into the void.
float chasm_profile(float v, float zz, float height, float depth) {
	return sdBox2(vec2(v, zz - depth * 0.5), vec2(height * 0.5, depth * 0.5));
}

// Wall mass, ledges, decks and (unremoved) buttresses of a facade whose wall
// plane lies zz in front of the point. fy, ky and bx are the point's offsets
// from the nearest ledge, deck and buttress centre.
float chasm_features(float fy, float ky, float bx, float zz) {
	float d = zz;
	d = min(d, chasm_profile(fy, zz, ledge_height, ledge_depth));
	d = min(d, chasm_profile(ky, zz, deck_height, deck_depth));
	d = min(d, chasm_profile(bx, zz, buttress_width, buttress_depth));
	return d;
}

// Recess depth of one terrace cell, 0 where the cell is not recessed.
float chasm_terrace_recess(ivec2 cell, int side) {
	ivec3 tc = ivec3(cell, side);
	if (hash3(tc, 3u) < terrace_probability) {
		return mix(terrace_depth_min, terrace_depth_max, hash3(tc, 5u));
	}
	return 0.0;
}

// Lower bound on the distance to geometry owned by other terrace cells, seen
// from local offset tl inside a cell recessed by rec. A neighbour's geometry
// lies within its own footprint and within its unremoved features, so the
// larger of both distances bounds it. Recessing only moves geometry deeper,
// so neighbours recessed at least as far are covered by the cell's own
// field. The three neighbours towards the nearest corner get their actual
// recess; every other cell is at least half a cell away and is assumed
// un-recessed.
float chasm_terrace_border(float z, float fy, float ky, float bx, ivec2 cell, vec2 tl, float rec, int side) {
	float half_cell = terrace_cell * 0.5;
	ivec2 s = ivec2(tl.x < 0.0 ? -1 : 1, tl.y < 0.0 ? -1 : 1);
	vec2 lateral = half_cell - abs(tl);
	ivec2 cells[3] = ivec2[3](cell + ivec2(s.x, 0), cell + ivec2(0, s.y), cell + s);
	float distances[3] = float[3](lateral.x, lateral.y, length(lateral));

	float bound = max(chasm_features(fy, ky, bx, chasm_half_width - z), half_cell);
	for (int i = 0; i < 3; i++) {
		float rec_n = chasm_terrace_recess(cells[i], side);
		if (rec_n < rec) {
			float zz_n = (chasm_half_width + rec_n) - z;
			bound = min(bound, max(chasm_features(fy, ky, bx, zz_n), distances[i]));
		}
	}
	return bound;
}

bool chasm_buttress_removed(ivec2 cell, int side) {
	return hash3(ivec3(cell, side), 7u) < buttress_removal;
}

// Lower bound on the lateral distance to buttress pieces kept by other removal
// cells, seen from local offset bl inside a removed cell. Cell borders need
// not fall between buttresses (with the defaults they run along every
// buttress centreline, so a neighbour may keep half of one right at the
// border). The three neighbours towards the nearest corner are checked;
// every other cell is at least half a cell away.
float chasm_buttress_neighbours(ivec2 cell, vec2 bl, int side) {
	vec2 half_cell = buttress_removal_cell * 0.5;
	ivec2 s = ivec2(bl.x < 0.0 ? -1 : 1, bl.y < 0.0 ? -1 : 1);
	vec2 lateral = half_cell - abs(bl);

	float bound = min(half_cell.x, half_cell.y);
	if (!chasm_buttress_removed(cell + ivec2(s.x, 0), side)) {
		bound = min(bound, lateral.x);
	}
	if (!chasm_buttress_removed(cell + ivec2(0, s.y), side)) {
		bound = min(bound, lateral.y);
	}
	if (!chasm_buttress_removed(cell + s, side)) {
		bound = min(bound, length(lateral));
	}
	return bound;
}

// One facade in local coordinates; zz is the distance in front of the wall
// plane (positive = void). side (+1 / -1) keeps the two facades' hashes apart.
float chasm_facade(vec3 p, int side, out int mat) {
	mat = CHASM_MAT_CONCRETE;
	float z = abs(p.z);

	// Terrace recess per coarse cell.
	vec2 tid = floor(p.xy / terrace_cell);
	float rec = chasm_terrace_recess(ivec2(tid), side);
	vec2 tl = p.xy - (tid + 0.5) * terrace_cell;
	float zz = (chasm_half_width + rec) - z;

	float fy = mod(p.y + stratum_height * 0.5, stratum_height) - stratum_height * 0.5;
	float ky = mod(p.y + deck_spacing * 0.5, deck_spacing) - deck_spacing * 0.5;
	float bx = mod(p.x + buttress_spacing * 0.5, buttress_spacing) - buttress_spacing * 0.5;

	// Wall mass.
	float d = zz;
	// Ledge per stratum.
	d = min(d, chasm_profile(fy, zz, ledge_height, ledge_depth));
	// Heavy deck.
	d = min(d, chasm_profile(ky, zz, deck_height, deck_depth));
	// Buttress.
	float but = chasm_profile(bx, zz, buttress_width, buttress_depth);
	vec2 bcell = floor(p.xy / buttress_removal_cell);
	if (chasm_buttress_removed(ivec2(bcell), side)) {
		// Removed: the buttress continues in the neighbour cells, so the
		// distance to those cells bounds it within the profile.
		vec2 bl = p.xy - (bcell + 0.5) * buttress_removal_cell;
		but = max(but, chasm_buttress_neighbours(ivec2(bcell), bl, side));
	}
	d = min(d, but);

	// Conservative near terrace borders: a less recessed neighbour carries its
	// wall and protrusions right up to the border.
	if (rec > 0.0) {
		d = min(d, max(chasm_terrace_border(z, fy, ky, bx, ivec2(tid), tl, rec, side), 0.03));
	}
	return d;
}

// Both facades, mirrored in z as the prototype does.
float chasm_facades(vec3 p, out int mat) {
	int mat_a;
	int mat_b;
	float d = chasm_facade(p, 1, mat_a);
	float d_b = chasm_facade(vec3(p.x, p.y, -p.z), -1, mat_b);
	mat = d_b < d ? mat_b : mat_a;
	return min(d, d_b);
}
