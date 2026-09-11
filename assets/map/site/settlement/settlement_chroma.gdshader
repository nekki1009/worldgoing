shader_type canvas_item;

// Key the generated atlas at draw time; ordinary shapes and font texels stay intact.
void fragment() {
	vec3 source = texture(TEXTURE, UV).rgb;
	float spill = max(0.0, min(source.r, source.b) - source.g);
	float keyed = smoothstep(0.10, 0.60, spill);
	vec3 neutral_edge = vec3(min(COLOR.r, COLOR.g + 0.10), COLOR.g, min(COLOR.b, COLOR.g + 0.08));
	COLOR.rgb = mix(COLOR.rgb, neutral_edge, smoothstep(0.04, 0.25, spill));
	COLOR.a *= 1.0 - keyed;
}
