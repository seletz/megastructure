// Chasm distance field, ported from facade()/map() in docs/megastructure-chasm.html.
// Requires sdf.gdshaderinc and hash.gdshaderinc to be included first.
//
// Hash salts match the prototype's call sites so both agree for the same seed.
// Material ids: 0 concrete, 1 metal, 2 lit opening (emissive).

const int CHASM_MAT_CONCRETE = 0;
const int CHASM_MAT_METAL = 1;
const int CHASM_MAT_LIT = 2;

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

group_uniforms chasm.openings;
// Openings sit one per cell of opening_cell_width by stratum_height.
uniform float opening_cell_width : hint_range(1.0, 100.0, 0.1) = 8.0;
uniform float opening_width : hint_range(0.0, 100.0, 0.05) = 5.2;
uniform float opening_height : hint_range(0.0, 30.0, 0.05) = 3.4;
uniform float opening_depth : hint_range(0.0, 50.0, 0.1) = 7.0;
uniform float opening_presence : hint_range(0.0, 1.0, 0.01) = 0.5;
// Present openings whose hash exceeds 1 - opening_lit_fraction are lit.
uniform float opening_lit_fraction : hint_range(0.0, 1.0, 0.005) = 0.045;

group_uniforms chasm.pillars;
// At most one pillar per cell of pillar_cell along x.
uniform float pillar_cell : hint_range(20.0, 1000.0, 1.0) = 110.0;
uniform float pillar_probability : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float pillar_radius_min : hint_range(0.5, 50.0, 0.1) = 4.0;
uniform float pillar_radius_max : hint_range(0.5, 50.0, 0.1) = 12.0;
// Rings sit at every deck level (deck_spacing) and stick out this far.
uniform float ring_extra_radius : hint_range(0.0, 20.0, 0.1) = 2.5;
uniform float ring_height : hint_range(0.0, 10.0, 0.05) = 1.6;
group_uniforms;

// Profile of a feature running along x: centred at v across its height,
// attached to the wall plane and protruding by depth into the void.
float chasm_profile(float v, float zz, float height, float depth) {
	return sdBox2(vec2(v, zz - depth * 0.5), vec2(height * 0.5, depth * 0.5));
}

// Wall mass of a facade whose wall plane lies zz in front of the point,
// punched by the opening of the point's opening cell when that one is open;
// ol is the point's offset from the opening cell centre. The hole reaches
// opening_depth behind the wall plane; the subtracted box extends as far in
// front of it, where it cuts only void, so rays aimed at the mouth enter the
// hole instead of converging on a zero distance at the coplanar front face.
// Subtraction only removes material and a point inside the box is nearest
// to solid outside it, so this stays a lower bound on the punched wall.
float chasm_wall(vec2 ol, bool has_opening, float zz) {
	if (!has_opening) {
		return zz;
	}
	vec3 half_size = vec3(opening_width * 0.5, opening_height * 0.5, opening_depth);
	return max(zz, -sdBox(vec3(ol, zz), half_size));
}

// Ledges, decks and (unremoved) buttresses in front of the given wall mass
// distance; zz is the wall plane's distance in front of the point. fy, ky and
// bx are the point's offsets from the nearest ledge, deck and buttress centre.
// Features never reach behind the wall plane, so punching only the wall mass
// carves the same solid as punching everything.
float chasm_features(float fy, float ky, float bx, float wall, float zz) {
	float d = wall;
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
// larger of both distances bounds it.
//
// Recessing only moves geometry deeper, so neighbours recessed at least as
// far are covered by the cell's own field in front of its wall plane. Inside
// an opening (in_opening) the point is behind that plane, so more recessed
// neighbours are checked as well; an opening cell may straddle a terrace
// border.
//
// Opening cells do not depend on the terrace, so a neighbour punches the same
// opening (ol, has_opening) at its own depth. Bounding it as an unpunched wall would
// also be a lower bound, but one that reaches zero on the border plane right
// through the hole, where rays would stop on it.
//
// The three neighbours towards the nearest corner get their actual recess;
// every other cell is at least half a cell away and is assumed un-recessed
// and unpunched, which only adds material.
float chasm_terrace_border(float z, float fy, float ky, float bx, ivec2 cell, vec2 tl, vec2 ol, bool has_opening, float rec, bool in_opening, int side) {
	float half_cell = terrace_cell * 0.5;
	ivec2 s = ivec2(tl.x < 0.0 ? -1 : 1, tl.y < 0.0 ? -1 : 1);
	vec2 lateral = half_cell - abs(tl);
	ivec2 cells[3] = ivec2[3](cell + ivec2(s.x, 0), cell + ivec2(0, s.y), cell + s);
	float distances[3] = float[3](lateral.x, lateral.y, length(lateral));

	float zz_flat = chasm_half_width - z;
	float bound = max(chasm_features(fy, ky, bx, zz_flat, zz_flat), half_cell);
	for (int i = 0; i < 3; i++) {
		float rec_n = chasm_terrace_recess(cells[i], side);
		if (rec_n < rec || (in_opening && rec_n > rec)) {
			float zz_n = (chasm_half_width + rec_n) - z;
			float wall_n = chasm_wall(ol, has_opening, zz_n);
			bound = min(bound, max(chasm_features(fy, ky, bx, wall_n, zz_n), distances[i]));
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

	// Wall mass, punched by an opening per cell of opening_cell_width by
	// stratum_height.
	vec2 opening_cell = vec2(opening_cell_width, stratum_height);
	vec2 oid = floor(p.xy / opening_cell);
	vec2 ol = p.xy - (oid + 0.5) * opening_cell;
	float ho = hash3(ivec3(ivec2(oid), side), 11u);
	bool has_opening = ho >= 1.0 - opening_presence;
	float d = chasm_wall(ol, has_opening, zz);
	bool in_opening = d > zz;
	// A few lit openings; zz < -0.2 keeps the tint inside the hole.
	if (has_opening && ho > 1.0 - opening_lit_fraction && zz < -0.2) {
		mat = CHASM_MAT_LIT;
	}

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
	// wall and protrusions right up to the border, and inside an opening so
	// may a more recessed one.
	if (rec > 0.0 || in_opening) {
		d = min(d, max(chasm_terrace_border(z, fy, ky, bx, ivec2(tid), tl, ol, has_opening, rec, in_opening, side), 0.03));
	}
	return d;
}

// The pillar of one pillar cell with its deck rings, 1e5 where the cell has
// none. The hashed offsets keep the pillar at least 3 m inside its cell along
// x (so the rings stay inside with the defaults) and 20 m off the facades.
float chasm_pillar(vec3 p, int id) {
	ivec3 pc = ivec3(id, 0, 0);
	if (hash3(pc, 21u) >= pillar_probability) {
		return 1e5;
	}
	float r = mix(pillar_radius_min, pillar_radius_max, hash3(pc, 22u));
	float xo = (hash3(pc, 23u) - 0.5) * max(pillar_cell - 2.0 * r - 6.0, 0.0);
	float zo = (hash3(pc, 24u) - 0.5) * max(2.0 * chasm_half_width - 2.0 * r - 40.0, 0.0);
	vec2 q = vec2(p.x - (float(id) + 0.5) * pillar_cell - xo, p.z - zo);
	float pillar = length(q) - r;
	// Same deck phase as the facades, so rings line up with their decks.
	float ky = mod(p.y + deck_spacing * 0.5, deck_spacing) - deck_spacing * 0.5;
	float ring = max(length(q) - (r + ring_extra_radius), abs(ky) - ring_height * 0.5);
	return min(pillar, ring);
}

// Free-standing pillars in the void. The prototype only looks at the point's
// own cell; the cell towards the nearer border is checked too, since its
// pillar may stand closer than the one here. Cells further away lie beyond
// the far border, at least half a cell off.
float chasm_pillars(vec3 p, out int mat) {
	mat = CHASM_MAT_CONCRETE;
	float pid = floor(p.x / pillar_cell);
	float lx = p.x - (pid + 0.5) * pillar_cell;
	int id = int(pid);
	float d = pillar_cell * 0.5 + abs(lx);
	d = min(d, chasm_pillar(p, id));
	d = min(d, chasm_pillar(p, id + (lx < 0.0 ? -1 : 1)));
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

// The whole chasm: facades and pillars.
float chasm_map(vec3 p, out int mat) {
	int mat_f;
	int mat_p;
	float d = chasm_facades(p, mat_f);
	float d_p = chasm_pillars(p, mat_p);
	mat = d_p < d ? mat_p : mat_f;
	return min(d, d_p);
}
