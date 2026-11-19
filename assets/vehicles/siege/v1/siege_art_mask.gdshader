shader_type canvas_item;

// Source sheets stay unchanged; omit their detached reference figures/panels.
uniform vec4 exclude_0 = vec4(0.0);
uniform vec4 exclude_1 = vec4(0.0);
uniform vec4 exclude_2 = vec4(0.0);
uniform vec4 exclude_3 = vec4(0.0);

bool excluded(vec2 uv, vec4 rect) {
	return rect.z > rect.x && rect.w > rect.y
		&& uv.x >= rect.x && uv.y >= rect.y && uv.x < rect.z && uv.y < rect.w;
}

void fragment() {
	if (excluded(UV, exclude_0) || excluded(UV, exclude_1)
		|| excluded(UV, exclude_2) || excluded(UV, exclude_3)) {
		COLOR.a = 0.0;
	}
}
