shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, fog_disabled;

#include "res://shaders/include/sdf.gdshaderinc"
#include "res://shaders/include/raymarch.gdshaderinc"
#include "res://shaders/include/hash.gdshaderinc"
#include "res://shaders/include/chasm.gdshaderinc"

uniform int max_steps = 180;
uniform float max_distance = 1400.0;
uniform float step_scale = 0.8;
uniform float hit_epsilon = 0.002;
// Absolute offset for the normal gradient; scaling it with distance smears
// normals across ledges and terrace borders.
uniform float normal_epsilon = 0.004;

uniform vec3 surface_color : source_color = vec3(0.55, 0.55, 0.6);
uniform vec3 metal_color : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 fog_color : source_color = vec3(0.02, 0.02, 0.03);
uniform float fog_density = 0.004;

// World distance; mat receives the material id of the closest surface
// (CHASM_MAT_CONCRETE or CHASM_MAT_METAL).
float map(vec3 p, out int mat) {
	return chasm_facades(p, mat);
}

float map_distance(vec3 p) {
	int mat;
	return map(p, mat);
}

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
	for (int i = 0; i < max_steps; i++) {
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
	if (!hit) {
		discard;
	}

	vec3 p = ro + rd * t;
	vec3 n = calc_normal(p, t, rd);
	float headlight = max(dot(n, -rd), 0.0);
	vec3 albedo = mat == CHASM_MAT_METAL ? metal_color : surface_color;
	vec3 col = albedo * (0.08 + 0.92 * headlight);
	col = mix(col, fog_color, 1.0 - exp(-t * fog_density));

	ALBEDO = col;
	DEPTH = depth_from_world(p, PROJECTION_MATRIX, VIEW_MATRIX);
}
