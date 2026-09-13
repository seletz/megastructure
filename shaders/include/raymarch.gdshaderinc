// Ray setup and depth helpers for fullscreen ray-march passes.
// Godot 4.3+ uses reversed-Z: NDC z = 1 is the near plane, z = 0 the far plane.

// World-space direction of the ray through the pixel at screen_uv.
vec3 ray_direction_world(vec2 screen_uv, mat4 inv_projection, mat4 inv_view, vec3 origin) {
	vec2 ndc = screen_uv * 2.0 - 1.0;
	vec4 view = inv_projection * vec4(ndc, 1.0, 1.0);
	view.xyz /= view.w;
	vec3 world = (inv_view * vec4(view.xyz, 1.0)).xyz;
	return normalize(world - origin);
}

// Normalised device depth of a world-space point, as expected by DEPTH.
float depth_from_world(vec3 p, mat4 projection, mat4 view) {
	vec4 clip = projection * view * vec4(p, 1.0);
	return clip.z / clip.w;
}
