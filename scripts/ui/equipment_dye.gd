extends RefCounted
## Pure appearance/material policy; actual colours belong to Site item_records.
const SLOTS := ["helmet", "armor", "boots", "cape", "outfit"]
const PRESETS := {
	"blue": {"name": "靛藍／灰白", "colors": {"helmet": "396fbbff", "armor": "396fbbff", "boots": "26384eff", "cape": "305ca3ff", "outfit": "d8dce3ff"}},
	"red": {"name": "赭紅／米白", "colors": {"helmet": "b6433aff", "armor": "b6433aff", "boots": "49332fff", "cape": "96352fff", "outfit": "e3d5baff"}},
	"green": {"name": "松綠／亞麻", "colors": {"helmet": "39816bff", "armor": "39816bff", "boots": "293d34ff", "cape": "2c6855ff", "outfit": "d9d5bdff"}},
	"purple": {"name": "帝紫／淡金", "colors": {"helmet": "7b4ca8ff", "armor": "7850b2ff", "boots": "352d48ff", "cape": "52278eff", "outfit": "e4d6b3ff"}},
	"teal": {"name": "青碧／象牙", "colors": {"helmet": "318c97ff", "armor": "278894ff", "boots": "26494dff", "cape": "1c5e6bff", "outfit": "e5dcc4ff"}},
	"amber": {"name": "琥珀／炭黑", "colors": {"helmet": "c9a343ff", "armor": "c29338ff", "boots": "383129ff", "cape": "8f641fff", "outfit": "353b42ff"}},
	"orange": {"name": "橙銅／深藍", "colors": {"helmet": "c66a32ff", "armor": "ca7339ff", "boots": "423532ff", "cape": "915020ff", "outfit": "263952ff"}},
	"rose": {"name": "玫紅／暖白", "colors": {"helmet": "c34d83ff", "armor": "c7487cff", "boots": "4b2d3bff", "cape": "902752ff", "outfit": "eee1d4ff"}},
	"ivory": {"name": "象牙／酒紅", "colors": {"helmet": "e1d7baff", "armor": "d9d0b4ff", "boots": "413332ff", "cape": "702735ff", "outfit": "71353dff"}},
	"charcoal": {"name": "墨黑／赭金", "colors": {"helmet": "c6a158ff", "armor": "323940ff", "boots": "1c2328ff", "cape": "202733ff", "outfit": "c8a15cff"}},
	"slate": {"name": "石灰／海藍", "colors": {"helmet": "8397a0ff", "armor": "86959cff", "boots": "353f4aff", "cape": "315a79ff", "outfit": "d4dee1ff"}},
	"brown": {"name": "栗棕／苔綠", "colors": {"helmet": "986645ff", "armor": "825438ff", "boots": "392922ff", "cape": "6f4036ff", "outfit": "84966aff"}},
	"lime": {"name": "嫩綠／深紫", "colors": {"helmet": "a1b84fff", "armor": "8fae45ff", "boots": "394133ff", "cape": "527c36ff", "outfit": "67517dff"}},
	"cyan": {"name": "冰青／靛紫", "colors": {"helmet": "83ccdaff", "armor": "67bccdff", "boots": "294958ff", "cape": "347f9aff", "outfit": "424876ff"}},
	"lavender": {"name": "藤紫／墨綠", "colors": {"helmet": "c1acd8ff", "armor": "b095ceff", "boots": "37303fff", "cape": "81709eff", "outfit": "284b46ff"}},
	"navy": {"name": "午夜／霜白", "colors": {"helmet": "d8e5e5ff", "armor": "27334eff", "boots": "192332ff", "cape": "161f36ff", "outfit": "d8e5e5ff"}},
}
# Explicit source material allowlists, not the outline exclusion list. Hardware,
# soles, skin and bare metal cannot become dyeable merely because of a node prefix.
const MATERIALS := {
	"helmet": ["Worldgoing_Helmet_Leather_Dome", "ChineseGear_LeatherHelmet_Leather", "Helmet_Iron_01_Horsehair", "Helmet_Steel_01_Horsehair", "Worldgoing_Steel_Cord_Red", "ChineseGear_Horsehair0", "ChineseGear_Horsehair1", "ChineseGear_Horsehair2", "ChineseGear_Horsehair3", "ChineseGear_Horsehair4"],
	"armor": ["Worldgoing_LightLeather_Body", "Worldgoing_Leather_Body", "Worldgoing_Underwear_Fabric", "Worldgoing_Armor_Cloth", "ChineseGear_Leather", "Worldgoing_Chinese_Cloth_Dark", "Worldgoing_Chinese_Cord_Red", "Worldgoing_Mingguang_Cloth", "Worldgoing_Mingguang_Brocade", "WesternPlate_Padding"],
	"boots": ["Audit_AdventureBoot_Leather", "ChineseBoots_Chestnut", "Worldgoing_Leather_Dark", "Worldgoing_Mingguang_Boot_Cloth", "Worldgoing_Mingguang_Boot_Leather", "WesternPlate_Leather"],
	"cape": ["Worldgoing_Cape_Travel", "Worldgoing_Cape_Female", "ChineseCloak_Cape_Chinese_01_Collar", "ChineseCloak_Cape_Chinese_01_Main", "ChineseCloak_Cape_Chinese_01_Mantle"],
	"outfit": ["Worldgoing_Underwear_Main", "Worldgoing_Underwear_Fabric", "ChineseLining_Linen", "ChineseLining_Shorts"],
}
const PBR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float base_metallic = 0.0;
uniform float base_roughness = 0.8;
uniform float base_specular = 0.5;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap;
uniform bool has_orm = false;
void fragment() {
	ALBEDO = base_color.rgb;
	if (has_texture) { ALBEDO *= texture(albedo_texture, UV).rgb; }
	METALLIC = base_metallic;
	ROUGHNESS = base_roughness;
	SPECULAR = base_specular;
	if (has_normal) { NORMAL_MAP = texture(normal_texture, UV).rgb; NORMAL_MAP_DEPTH = normal_scale; }
	if (has_orm) { ROUGHNESS *= texture(orm_texture, UV).g; METALLIC *= texture(orm_texture, UV).b; }
}
"""
const UNIFORMS := """
uniform vec4 equipment_dye_color : source_color = vec4(1.0);
uniform float equipment_dye_reference = 1.0;
uniform bool equipment_dye_paint = false;
uniform bool equipment_dye_preserve_gold = false;
uniform vec3 equipment_dye_min = vec3(0.0);
uniform vec3 equipment_dye_size = vec3(1.0);
varying vec3 equipment_dye_position;
"""
const FRAGMENT := """
	float dye_weight = 1.0;
	if (equipment_dye_preserve_gold && ALBEDO.g > ALBEDO.r * 0.32 && ALBEDO.b < ALBEDO.g * 0.65) { dye_weight = 0.0; }
	if (equipment_dye_paint) {
		// A central painted panel; the rolled edges and surrounding iron stay bare.
		vec3 p = (equipment_dye_position - equipment_dye_min) / max(equipment_dye_size, vec3(0.0001));
		dye_weight = step(0.38, p.x) * step(p.x, 0.62) * step(0.12, p.y) * step(p.y, 0.91);
	}
	float dye_shade = clamp(max(max(ALBEDO.r, ALBEDO.g), ALBEDO.b) / max(equipment_dye_reference, 0.001), 0.08, 1.0);
	ALBEDO = mix(ALBEDO, equipment_dye_color.rgb * dye_shade, dye_weight);
	EMISSION = mix(EMISSION, vec3(0.0), dye_weight);
	if (equipment_dye_paint) { METALLIC = mix(METALLIC, 0.0, dye_weight); ROUGHNESS = mix(ROUGHNESS, 0.72, dye_weight); }
"""
static var _shaders := {}
static var _mask_shaders := {}

static func mask_material(source: Material, slot: String, group: int) -> Material:
	# Offline only: preserve clipping/ground deformation in the original shader.
	# Undyed geometry remains a black depth occluder, never hidden for a mask.
	if source is BaseMaterial3D:
		var black := source.duplicate() as BaseMaterial3D
		black.albedo_color = Color.BLACK
		black.emission_enabled = false
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return black
	assert(source is ShaderMaterial)
	var result := source.duplicate() as ShaderMaterial
	var source_code := source.shader.code as String
	var key := str(group) + slot + source_code
	if not _mask_shaders.has(key):
		var index := SLOTS.find(slot) - group * 3
		var color: String = ["vec3(1.0,0.0,0.0)", "vec3(0.0,1.0,0.0)", "vec3(0.0,0.0,1.0)"][index] if index >= 0 and index < 3 else "vec3(0.0)"
		var weight := "dye_weight" if "float dye_weight =" in source_code else "0.0"
		var regex := RegEx.new()
		assert(regex.compile("render_mode[^;]*;") == OK)
		var code := regex.sub(source_code, "render_mode unshaded, cull_disabled;", true)
		var start := code.find("void fragment()")
		var depth := 0
		for index_in_code in range(code.find("{", start), code.length()):
			if code[index_in_code] == "{": depth += 1
			elif code[index_in_code] == "}":
				depth -= 1
				if depth == 0:
					code = code.insert(index_in_code, "\n ALBEDO = " + color + " * " + weight + "; EMISSION = vec3(0.0);\n")
					break
		var shader := Shader.new()
		shader.code = code
		_mask_shaders[key] = shader
	result.shader = _mask_shaders[key]
	return result

static func valid_color(value: Variant) -> bool:
	return value is String and value.length() == 8 and value.is_valid_hex_number(false) and value.right(2).to_lower() == "ff"

static func valid_dyes(value: Variant, parts: Dictionary = {}, allow_reset: bool = false) -> bool:
	if not value is Dictionary or value.size() > SLOTS.size():
		return false
	for slot: Variant in value:
		if not slot is String or slot not in SLOTS or (not valid_color(value[slot]) and not (allow_reset and value[slot] == "")):
			return false
		if not parts.is_empty() and parts.get(slot, "none") == "none":
			return false
	return true

static func geometry_appearance(appearance: Dictionary) -> Dictionary:
	var result := appearance.duplicate(true)
	result.erase("equipment_dyes")
	return result

static func surface_slot(node_name: String, material_name: String) -> String:
	var slot := node_name.get_slice("_", 0).to_lower()
	if slot not in SLOTS:
		return ""
	if slot == "boots" and ("Sole" in node_name or "Heel" in node_name or "Buckle" in node_name):
		return ""
	if slot == "cape" and ("Lining" in node_name or "Trim" in node_name):
		return ""
	if material_name in MATERIALS[slot]:
		return slot
	if painted_panel(node_name, material_name):
		return slot
	return ""

static func painted_panel(node_name: String, material_name: String) -> bool:
	return material_name == "WesternPlate_ForgedIron" and node_name in ["Helmet_Western_Iron_01_Skull", "Armor_Western_Iron_01_Cuirass"]

static func material(source: Material, base_material: BaseMaterial3D, mesh: MeshInstance3D) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	var code := PBR_SHADER
	if source is ShaderMaterial:
		code = source.shader.code
		for parameter: Dictionary in source.shader.get_shader_uniform_list():
			var value: Variant = source.get_shader_parameter(parameter.name)
			if value != null:
				result.set_shader_parameter(parameter.name, value)
	else:
		result.set_shader_parameter("base_color", base_material.albedo_color)
		result.set_shader_parameter("base_metallic", base_material.metallic)
		result.set_shader_parameter("base_roughness", base_material.roughness)
		result.set_shader_parameter("base_specular", base_material.metallic_specular)
		result.set_shader_parameter("has_texture", base_material.albedo_texture != null)
		result.set_shader_parameter("albedo_texture", base_material.albedo_texture)
		result.set_shader_parameter("has_normal", base_material.normal_enabled and base_material.normal_texture != null)
		result.set_shader_parameter("normal_texture", base_material.normal_texture)
		result.set_shader_parameter("normal_scale", base_material.normal_scale)
		result.set_shader_parameter("has_orm", base_material.roughness_texture != null)
		result.set_shader_parameter("orm_texture", base_material.roughness_texture)
	if not _shaders.has(code):
		var patched := code.replace("shader_type spatial;", "shader_type spatial;\n" + UNIFORMS)
		if "void vertex() {" in patched:
			patched = patched.replace("void vertex() {", "void vertex() {\n equipment_dye_position = VERTEX;")
		else:
			patched += "\nvoid vertex() { equipment_dye_position = VERTEX; }\n"
		# The known equipment/ground shaders end their fragment before any added vertex.
		var start := patched.find("void fragment()")
		var depth := 0
		var end := -1
		for index in range(patched.find("{", start), patched.length()):
			if patched[index] == "{": depth += 1
			elif patched[index] == "}":
				depth -= 1
				if depth == 0:
					end = index
					break
		assert(start >= 0 and end >= 0, "Unsupported equipment shader")
		var shader := Shader.new()
		shader.code = patched.insert(end, FRAGMENT)
		_shaders[code] = shader
	result.shader = _shaders[code]
	# Linear reference removes the source hue, including dark leather, without a
	# red*blue multiply. Textured weave/normal detail and real lighting remain.
	var linear := base_material.albedo_color.srgb_to_linear()
	result.set_shader_parameter("equipment_dye_reference", maxf(maxf(linear.r, linear.g), linear.b))
	result.set_shader_parameter("equipment_dye_paint", painted_panel(str(mesh.name), base_material.resource_name))
	result.set_shader_parameter("equipment_dye_preserve_gold", str(mesh.name).begins_with("Cape_Chinese_") and base_material.albedo_texture != null)
	result.set_shader_parameter("equipment_dye_min", mesh.get_aabb().position)
	result.set_shader_parameter("equipment_dye_size", mesh.get_aabb().size)
	return result
