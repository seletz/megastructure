// Height-graded exponential fog and the post chain (exposure tone map, film
// grain, vignette), ported from the end of main() in docs/megastructure-chasm.html.
// Requires hash.gdshaderinc to be included first.

group_uniforms fog;
// Linear values like the prototype, so no source_color conversion.
// Light bleeds down from far above, nothing comes up from below.
uniform vec3 fog_color_down = vec3(0.004, 0.004, 0.006);
uniform vec3 fog_color_up = vec3(0.075, 0.085, 0.105);
// Ray direction y range over which the fog blends from down to up.
uniform float fog_gradient_lo : hint_range(-1.0, 1.0, 0.01) = -0.35;
uniform float fog_gradient_hi : hint_range(-1.0, 1.0, 0.01) = 0.7;
uniform float fog_density : hint_range(0.0, 0.05, 0.0001) = 0.0032;

group_uniforms post;
uniform float exposure : hint_range(0.0, 8.0, 0.01) = 1.7;
// Off by default, unlike the prototype's 0.04: the grain is hashed per render
// pixel, and at rendering/scaling_3d/scale=0.5 each speck covers a 2x2 block
// of screen pixels that flickers at grain_fps, which reads as snow rather than
// film grain. The knob stays for full-resolution renders and presets.
uniform float grain_amount : hint_range(0.0, 0.5, 0.001) = 0.0;
uniform float grain_fps : hint_range(1.0, 120.0, 1.0) = 24.0;
uniform float vignette : hint_range(0.0, 2.0, 0.01) = 0.3;
group_uniforms;

// Fog colour seen along world ray direction rd.
vec3 post_fog_color(vec3 rd) {
	return mix(fog_color_down, fog_color_up, smoothstep(fog_gradient_lo, fog_gradient_hi, rd.y));
}

// Blends col towards the fog for a surface t units along ray rd.
vec3 post_apply_fog(vec3 col, vec3 rd, float t) {
	return mix(col, post_fog_color(rd), 1.0 - exp(-fog_density * t));
}

// Tone map, grain and vignette for the pixel at frag_coord.
// The prototype ends with a 1/2.2 gamma pow; Godot expects linear output and
// applies its own sRGB conversion, so it is deliberately left out here.
vec3 post_process(vec3 col, vec2 frag_coord, vec2 resolution, float time) {
	col = 1.0 - exp(-col * exposure);
	float g = hash3(ivec3(ivec2(frag_coord), int(time * grain_fps)), 60u) - 0.5;
	col += g * grain_amount;
	vec2 uv = (frag_coord * 2.0 - resolution) / resolution.y;
	col *= 1.0 - vignette * dot(uv * 0.6, uv * 0.6);
	return max(col, 0.0);
}
