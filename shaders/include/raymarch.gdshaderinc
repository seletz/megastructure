// Ray setup and depth helpers for fullscreen ray-march passes.
// Godot 4.3+ uses reversed-Z: NDC z = 1 is the near plane, z = 0 the far plane.

// World-space direction of the ray through the pixel at screen_uv.
// Built in view space, where the unprojected near-plane point is already the
// offset from the camera, so precision does not degrade far from the origin.
vec3 ray_direction_world(vec2 screen_uv, mat4 inv_projection, mat4 inv_view) {
	vec2 ndc = screen_uv * 2.0 - 1.0;
	vec4 view = inv_projection * vec4(ndc, 1.0, 1.0);
	view.xyz /= view.w;
	return normalize(mat3(inv_view) * view.xyz);
}

// Distance from the camera to the near clip plane.
float near_plane_distance(mat4 inv_projection) {
	vec4 view = inv_projection * vec4(0.0, 0.0, 1.0, 1.0);
	return -view.z / view.w;
}

// Normalised device depth of a world-space point, as expected by DEPTH.
// Points on or behind the camera plane map to the far plane.
float depth_from_world(vec3 p, mat4 projection, mat4 view) {
	vec4 clip = projection * view * vec4(p, 1.0);
	if (clip.w <= 0.0) {
		return 0.0;
	}
	return clamp(clip.z / clip.w, 0.0, 1.0);
}
