shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform float base_metallic = 0.0;
uniform float base_roughness = 0.8;
uniform float ground_height = 0.0;
uniform float source_floor = 0.0;
uniform float cloth_top = 1.5;

void vertex() {
	// Gather the hanging length while kneeling; keep the upper attachment fixed.
	// Presentation only: this never changes body or armor contact geometry.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float floor_y = ground_height + 0.06;
	if (source_floor < floor_y && world.y < cloth_top && cloth_top > floor_y) {
		float gather = (cloth_top - floor_y) / max(cloth_top - source_floor, 0.01);
		world.y = cloth_top + (world.y - cloth_top) * gather;
	}
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	ALBEDO = base_color.rgb * (texture(albedo_texture, UV).rgb * float(has_texture) + vec3(float(!has_texture)));
	METALLIC = base_metallic;
	ROUGHNESS = base_roughness;
}
