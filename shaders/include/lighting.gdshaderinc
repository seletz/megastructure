// Key light with soft shadows, sky and ground ambient, camera headlight and
// emissive openings, ported from main()/shadow() in docs/megastructure-chasm.html.
// Requires chasm.gdshaderinc to be included first, and a float map_distance(vec3 p)
// declared before this file.

group_uniforms lighting;
// Linear values like the prototype, so no source_color conversion.
// Direction towards the light; normalised before use.
uniform vec3 key_direction = vec3(0.25, 1.0, 0.15);
uniform vec3 key_color = vec3(0.9, 0.95, 1.0);
uniform float key_intensity : hint_range(0.0, 8.0, 0.01) = 1.3;
uniform vec3 sky_ambient = vec3(0.12, 0.14, 0.18);
uniform vec3 ground_ambient = vec3(0.02, 0.02, 0.025);

group_uniforms lighting.shadow;
uniform int shadow_steps : hint_range(1, 64) = 22;
// Penumbra sharpness: larger values give harder shadow edges.
uniform float shadow_softness : hint_range(0.1, 64.0, 0.1) = 10.0;
uniform float shadow_max_distance : hint_range(1.0, 1000.0, 1.0) = 160.0;

group_uniforms lighting.headlight;
uniform float headlight_power : hint_range(0.0, 200.0, 0.1) = 40.0;
uniform vec3 headlight_color = vec3(1.0, 0.9, 0.75);

group_uniforms lighting.emissive;
uniform vec3 emissive_color = vec3(1.0, 0.72, 0.42);
uniform float emissive_intensity : hint_range(0.0, 8.0, 0.01) = 1.8;
group_uniforms;

// 1 is fully lit, 0 fully shadowed.
float lighting_shadow(vec3 ro, vec3 rd) {
	float res = 1.0;
	float t = 0.6;
	for (int i = 0; i < shadow_steps; i++) {
		float h = map_distance(ro + rd * t);
		res = min(res, shadow_softness * h / t);
		t += clamp(h, 0.4, 12.0);
		if (res < 0.02 || t > shadow_max_distance) {
			break;
		}
	}
	return clamp(res, 0.0, 1.0);
}

// Lit colour of surface point p with normal n seen from camera ro.
vec3 lighting_shade(vec3 p, vec3 n, vec3 ro, vec3 alb, float occ, int mat) {
	vec3 l = normalize(key_direction);
	float sh = lighting_shadow(p + n * 0.3, l);

	float diff = max(dot(n, l), 0.0);
	vec3 key = key_color * diff * sh * key_intensity;
	vec3 sky = sky_ambient * (0.55 + 0.45 * n.y);
	vec3 ground = ground_ambient * (0.5 - 0.5 * n.y);

	vec3 lh = ro - p;
	float dl = length(lh);
	lh /= dl;
	float head = max(dot(n, lh), 0.0) * headlight_power / (1.0 + 0.1 * dl * dl);

	vec3 col = alb * (key + (sky + ground) * occ + head * headlight_color);
	col *= 0.5 + 0.5 * occ;
	if (mat == CHASM_MAT_LIT) {
		col += emissive_color * emissive_intensity;
	}
	return col;
}
