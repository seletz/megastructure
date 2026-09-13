shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, fog_disabled;

#include "res://shaders/include/sdf.gdshaderinc"
#include "res://shaders/include/raymarch.gdshaderinc"
#include "res://shaders/include/hash.gdshaderinc"
#include "res://shaders/include/chasm.gdshaderinc"
#include "res://shaders/include/post.gdshaderinc"

group_uniforms marching;
uniform int max_steps : hint_range(1, 1024) = 180;
uniform float max_distance : hint_range(10.0, 5000.0, 1.0) = 1400.0;
uniform float step_scale : hint_range(0.1, 1.0, 0.01) = 0.8;
// Hit threshold per unit of distance travelled (never below one unit).
uniform float hit_epsilon : hint_range(0.0001, 0.05, 0.0001) = 0.002;
// Absolute offset for the normal gradient; scaling it with distance smears
// normals across ledges and terrace borders.
uniform float normal_epsilon : hint_range(0.0005, 0.1, 0.0005) = 0.004;
group_uniforms debug;
// Debug views skip lighting, fog and post processing but still write DEPTH.
uniform int debug_view : hint_enum("Shaded", "Steps", "Depth", "Normals", "Material") = 0;
group_uniforms;

// World distance; mat receives the material id of the closest surface
// (CHASM_MAT_CONCRETE, CHASM_MAT_METAL or CHASM_MAT_LIT).
float map(vec3 p, out int mat) {
	return chasm_map(p, mat);
}

float map_distance(vec3 p) {
	int mat;
	return map(p, mat);
}

#include "res://shaders/include/surface.gdshaderinc"
#include "res://shaders/include/lighting.gdshaderinc"

// Tetrahedron-sampled gradient; falls back to facing the ray where it vanishes.
vec3 calc_normal(vec3 p, float t, vec3 rd) {
	float h = normal_epsilon;
	const vec2 k = vec2(1.0, -1.0);
	vec3 g = k.xyy * map_distance(p + k.xyy * h) +
		k.yyx * map_distance(p + k.yyx * h) +
		k.yxy * map_distance(p + k.yxy * h) +
		k.xxx * map_distance(p + k.xxx * h);
	float len = length(g);
	return len > 1e-8 ? g / len : -rd;
}

// Blue-green-yellow-red ramp for x in 0..1.
vec3 debug_heat(float x) {
	const vec3 c0 = vec3(0.0, 0.1, 0.9);
	const vec3 c1 = vec3(0.0, 0.8, 0.2);
	const vec3 c2 = vec3(1.0, 0.9, 0.0);
	const vec3 c3 = vec3(1.0, 0.05, 0.0);
	float s = clamp(x, 0.0, 1.0) * 3.0;
	if (s < 1.0) {
		return mix(c0, c1, s);
	}
	if (s < 2.0) {
		return mix(c1, c2, s - 1.0);
	}
	return mix(c2, c3, s - 2.0);
}

vec3 debug_material_color(int mat) {
	if (mat == CHASM_MAT_METAL) {
		return vec3(0.15, 0.35, 0.9);
	}
	if (mat == CHASM_MAT_LIT) {
		return vec3(1.0, 0.5, 0.05);
	}
	return vec3(0.5);
}

void vertex() {
	// The QuadMesh is 2x2, so VERTEX.xy already spans NDC; pin it to the near plane.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = ray_direction_world(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);

	// Start at the near plane so a hit never lands on the camera itself.
	float t = near_plane_distance(INV_PROJECTION_MATRIX);
	int mat = CHASM_MAT_CONCRETE;
	// A camera inside a solid first marches out of it, like clipping through a mesh.
	bool inside = map_distance(ro + rd * t) < 0.0;
	bool hit = false;
	int steps = 0;
	for (int i = 0; i < max_steps; i++) {
		steps = i + 1;
		float d = map(ro + rd * t, mat);
		float eps = hit_epsilon * max(t, 1.0);
		if (inside) {
			if (d > eps) {
				inside = false;
			} else {
				t += max(-d, eps);
			}
		} else {
			if (d < eps) {
				hit = true;
				break;
			}
			t += d * step_scale;
		}
		if (t > max_distance) {
			break;
		}
	}

	vec3 p = ro + rd * t;
	// Misses sit on the far plane (reversed-Z).
	DEPTH = hit ? depth_from_world(p, PROJECTION_MATRIX, VIEW_MATRIX) : 0.0;

	if (debug_view != 0) {
		// Flat debug colours, no fog or post processing.
		vec3 col = vec3(0.0);
		if (debug_view == 1) {
			col = debug_heat(float(steps) / float(max_steps));
		} else if (!hit) {
			// Depth shows misses at the far end; normals and materials leave them black.
			col = vec3(debug_view == 2 ? 1.0 : 0.0);
		} else if (debug_view == 2) {
			col = vec3(clamp(t / max_distance, 0.0, 1.0));
		} else if (debug_view == 3) {
			col = calc_normal(p, t, rd) * 0.5 + 0.5;
		} else {
			col = debug_material_color(mat);
		}
		ALBEDO = col;
	} else {
		vec3 col;
		if (hit) {
			vec3 n = calc_normal(p, t, rd);
			float occ = surface_ao(p, n);
			col = lighting_shade(p, n, ro, surface_albedo(p, mat), occ, mat);
			col = post_apply_fog(col, rd, t);
		} else {
			// Misses show the fog itself.
			col = post_fog_color(rd);
		}
		ALBEDO = post_process(col, FRAGCOORD.xy, VIEWPORT_SIZE, TIME);
	}
}
