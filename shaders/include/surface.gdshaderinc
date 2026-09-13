// Surface materials and ambient occlusion, ported from main()/ao() in
// docs/megastructure-chasm.html. Requires hash.gdshaderinc and chasm.gdshaderinc
// to be included first, and a float map_distance(vec3 p) declared before this file.
//
// Grime salts match the prototype so both agree for the same seed.

group_uniforms surface;
// Linear values like the prototype, so no source_color conversion.
uniform vec3 concrete_albedo = vec3(0.50, 0.50, 0.48);
uniform vec3 metal_albedo = vec3(0.30, 0.31, 0.34);

group_uniforms surface.grime;
// World-space lattice frequencies of the fine and coarse grime cells.
uniform float grime_scale_fine : hint_range(0.01, 5.0, 0.01) = 0.7;
uniform float grime_scale_coarse : hint_range(0.01, 2.0, 0.01) = 0.12;
uniform float grime_fine : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float grime_coarse : hint_range(0.0, 1.0, 0.01) = 0.3;

group_uniforms surface.ao;
uniform int ao_taps : hint_range(1, 16) = 5;
// Tap i (1..ao_taps) samples at ao_start + ao_step * i / ao_taps along the normal.
uniform float ao_step : hint_range(0.0, 10.0, 0.01) = 1.6;
uniform float ao_start : hint_range(0.0, 5.0, 0.01) = 0.15;
uniform float ao_decay : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float ao_strength : hint_range(0.0, 4.0, 0.01) = 0.9;
group_uniforms;

float surface_grime(vec3 p) {
	return hash3(ivec3(floor(p * grime_scale_fine)), 50u) * grime_fine +
		hash3(ivec3(floor(p * grime_scale_coarse)), 51u) * grime_coarse;
}

// Albedo of concrete or metal; lit openings use the concrete branch like the prototype.
vec3 surface_albedo(vec3 p, int mat) {
	float grime = surface_grime(p);
	if (mat == CHASM_MAT_METAL) {
		return metal_albedo * (0.7 + 0.3 * grime);
	}
	return concrete_albedo * (0.55 + 0.45 * grime);
}

// 1 is fully open, 0 fully occluded.
float surface_ao(vec3 p, vec3 n) {
	float occ = 0.0;
	float sca = 1.0;
	for (int i = 1; i <= ao_taps; i++) {
		float h = ao_start + ao_step * float(i) / float(ao_taps);
		occ += (h - map_distance(p + n * h)) * sca;
		sca *= ao_decay;
	}
	return clamp(1.0 - ao_strength * occ, 0.0, 1.0);
}
