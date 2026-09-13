// Signed distance primitives and operators shared by the ray-march shaders.

float sdSphere(vec3 p, float r) {
	return length(p) - r;
}

// Box centred at the origin with half extents b.
float sdBox(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// 2D rectangle centred at the origin with half extents b.
float sdBox2(vec2 p, vec2 b) {
	vec2 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float opUnion(float a, float b) {
	return min(a, b);
}
