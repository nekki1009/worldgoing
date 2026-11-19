shader_type canvas_item;
render_mode unshaded;

// Render-only mask over the unchanged source sheet, in original sheet pixels.
// Up to four actual front-rail/front-superstructure polygons, sixteen vertices
// each. A one-screen-pixel transition uses derivatives; no person is baked here.
uniform vec2 sheet_size = vec2(1.0);
uniform int polygon_counts[4];
uniform vec2 polygon_points[64];
uniform bool foreground = false;

float polygon_distance(vec2 point, int polygon_index) {
	int count = polygon_counts[polygon_index];
	if (count < 3) { return 1000000.0; }
	int base = polygon_index * 16;
	float distance_squared = 1000000000000.0;
	bool inside = false;
	for (int i = 0; i < 16; i++) {
		if (i >= count) { break; }
		int j = i == 0 ? count - 1 : i - 1;
		vec2 a = polygon_points[base + i];
		vec2 b = polygon_points[base + j];
		vec2 segment = b - a;
		float t = clamp(dot(point - a, segment) / max(dot(segment, segment), 0.000001), 0.0, 1.0);
		vec2 nearest = a + segment * t;
		distance_squared = min(distance_squared, dot(point - nearest, point - nearest));
		if ((a.y > point.y) != (b.y > point.y)) {
			float crossing = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x;
			if (point.x < crossing) { inside = !inside; }
		}
	}
	return sqrt(distance_squared) * (inside ? -1.0 : 1.0);
}

void fragment() {
	vec2 point = UV * sheet_size;
	float distance_to_front = 1000000.0;
	for (int p = 0; p < 4; p++) {
		distance_to_front = min(distance_to_front, polygon_distance(point, p));
	}
	float one_screen_pixel = max(fwidth(distance_to_front), 0.000001);
	float front = 1.0 - smoothstep(-0.5 * one_screen_pixel, 0.5 * one_screen_pixel, distance_to_front);
	// CanvasItem fragment COLOR already contains sampled texture and modulation.
	// Do not sample/multiply the wood texture twice. Split alpha so that the two
	// layers recombine to the original alpha even across the one-pixel boundary.
	float source_alpha = COLOR.a;
	float front_alpha = source_alpha * front;
	COLOR.a = foreground ? front_alpha : max(0.0, source_alpha - front_alpha) / max(1.0 - front_alpha, 0.000001);
}
