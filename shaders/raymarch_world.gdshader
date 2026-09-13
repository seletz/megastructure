shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, fog_disabled;

#include "res://shaders/include/sdf.gdshaderinc"
#include "res://shaders/include/raymarch.gdshaderinc"

uniform int max_steps = 180;
uniform float max_distance = 1400.0;
uniform float step_scale = 0.8;
uniform float hit_epsilon = 0.002;

uniform vec3 surface_color : source_color = vec3(0.55, 0.55, 0.6);
uniform vec3 fog_color : source_color = vec3(0.02, 0.02, 0.03);
uniform float fog_density = 0.004;

// Placeholder world: a sphere over a ground slab.
float map(vec3 p) {
	float sphere = sdSphere(p - vec3(20.0, -3.0, 10.0), 6.0);
	float ground = sdBox(p - vec3(0.0, -9.0, 0.0), vec3(1000.0, 1.0, 1000.0));
	return opUnion(sphere, ground);
}

// Tetrahedron-sampled gradient; falls back to facing the ray where it vanishes.
vec3 calc_normal(vec3 p, float t, vec3 rd) {
	float h = max(hit_epsilon * t, 1e-4);
	const vec2 k = vec2(1.0, -1.0);
	vec3 g = k.xyy * map(p + k.xyy * h) +
		k.yyx * map(p + k.yyx * h) +
		k.yxy * map(p + k.yxy * h) +
		k.xxx * map(p + k.xxx * h);
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
	// A camera inside a solid first marches out of it, like clipping through a mesh.
	bool inside = map(ro + rd * t) < 0.0;
	bool hit = false;
	for (int i = 0; i < max_steps; i++) {
		float d = map(ro + rd * t);
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
	vec3 col = surface_color * (0.08 + 0.92 * headlight);
	col = mix(col, fog_color, 1.0 - exp(-t * fog_density));

	ALBEDO = col;
	DEPTH = depth_from_world(p, PROJECTION_MATRIX, VIEW_MATRIX);
}
