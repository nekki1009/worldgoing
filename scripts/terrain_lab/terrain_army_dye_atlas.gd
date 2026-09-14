extends RefCounted
## Optional colour-only companions of exact published atlases. No pose/people owner.
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/dyes/v1"
const EXTRA_SOURCES := ["res://scripts/tools/bake_terrain_army_dyes.gd", "res://scripts/terrain_lab/terrain_army_dye_atlas.gd", "res://assets/characters/human/q35/combat/combat_cloth_ground.gdshader"]
const CACHE_BYTES := 192 * 1024 * 1024
const SHADER := """
shader_type canvas_item;
uniform sampler2D dye_map : filter_nearest, repeat_disable;
// The canonical LDR 2D atlas is already display-space. Do not linearize only
// the palette while leaving the sampled pixels in display-space.
instance uniform vec4 helmet_dye = vec4(0.0);
instance uniform vec4 armor_dye = vec4(0.0);
instance uniform vec4 boots_dye = vec4(0.0);
instance uniform vec4 cape_dye = vec4(0.0);
instance uniform vec4 outfit_dye = vec4(0.0);
void fragment() {
	vec4 original = COLOR; // Canvas fragment COLOR already contains the sampled texture.
	vec3 mask = texture(dye_map, UV).rgb;
	int slot = int(round(mask.r * 255.0));
	vec4 dye = vec4(0.0);
	if (slot == 1) { dye = helmet_dye; }
	else if (slot == 2) { dye = armor_dye; }
	else if (slot == 3) { dye = boots_dye; }
	else if (slot == 4) { dye = cape_dye; }
	else if (slot == 5) { dye = outfit_dye; }
	original.rgb = mix(original.rgb, dye.rgb * mask.g, dye.a * mask.b);
	COLOR = original;
}
"""
static var _entries := {}
static var _materials := {}
static var _material_refs := {}
static var _sources := {}
static var _shader: Shader
static var _bytes := 0

static func canvas_color(value: String) -> Vector4:
	var color := Color.from_string(value, Color.TRANSPARENT)
	# Per-instance Color values are linearized by the renderer; the existing
	# LDR canvas needs the same display-space values as its decoded PNG.
	return Vector4(color.r, color.g, color.b, color.a)

static func fingerprints() -> Dictionary:
	var result := Plan.fingerprints()
	for path: String in EXTRA_SOURCES:
		var hash := FileAccess.get_md5(path)
		if hash.length() != 32: return {}
		result[path] = hash
	return result

static func _key(appearance: Dictionary) -> String:
	var weapon := str(appearance.get("parts", {}).get("weapon", ""))
	return weapon if weapon in ["bow_01", "crossbow_01"] else "base"

static func entry(appearance: Dictionary) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(appearance): return {}
	var key := _key(appearance)
	if not _entries.has(key):
		_entries[key] = {}
		var path := ROOT + "/" + key + ".json"
		if not FileAccess.file_exists(path): return {}
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if _sources.is_empty(): _sources = fingerprints()
		if not manifest is Dictionary or manifest.get("schema_version") != 1 or manifest.get("complete") != true or manifest.get("source_fingerprints") != _sources or manifest.get("slots") != Dye.SLOTS:
			return {}
		var base_path := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json" if key == "base" else "res://assets/characters/terrain_lab_army/standard_soldier/ranged/v1/" + key + "/manifest.json"
		if manifest.get("source_manifest") != base_path or manifest.get("source_manifest_md5") != FileAccess.get_md5(base_path): return {}
		var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(base_path))
		if not base is Dictionary or manifest.get("appearance") != base.get("appearance") or manifest.get("frame_count") != base.get("frames", []).size(): return {}
		var mask_path := ROOT + "/" + key + ".png"
		if manifest.get("mask_path") != mask_path or manifest.get("mask_md5") != FileAccess.get_md5(mask_path): return {}
		_entries[key] = manifest
	var record: Dictionary = _entries[key]
	return record if record.get("appearance") == Dye.geometry_appearance(appearance) else {}

static func supports(appearance: Dictionary) -> bool:
	return appearance.get("equipment_dyes", {}).is_empty() or not entry(appearance).is_empty()

static func apply(sprite: Sprite2D, appearance: Dictionary) -> bool:
	if sprite.get_meta("equipment_dye_appearance", {}) == appearance: return true
	var colors: Dictionary = appearance.get("equipment_dyes", {})
	if colors.is_empty():
		sprite.material = null
		sprite.set_meta("equipment_dye_appearance", appearance.duplicate(true))
		return true
	var record := entry(appearance)
	if record.is_empty(): return false
	var key := _key(appearance)
	if not _materials.has(key) and _material_refs.has(key) and _material_refs[key].get_ref() != null:
		sprite.material = _material_refs[key].get_ref()
		for slot: String in Dye.SLOTS:
			sprite.set_instance_shader_parameter(slot + "_dye", canvas_color(colors[slot]) if colors.has(slot) else Vector4.ZERO)
		sprite.set_meta("equipment_dye_appearance", appearance.duplicate(true))
		return true
	if not _materials.has(key):
		var pixels := Image.load_from_file(record.mask_path)
		if pixels == null or pixels.get_width() != int(record.width) or pixels.get_height() != int(record.height): return false
		pixels.convert(Image.FORMAT_RGB8)
		var bytes := pixels.get_data().size()
		# A sprite keeps its material alive; cache eviction never blanks live users.
		if _bytes + bytes > CACHE_BYTES:
			_materials.clear()
			_bytes = 0
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter("dye_map", ImageTexture.create_from_image(pixels))
		_materials[key] = material
		_material_refs[key] = weakref(material)
		_bytes += bytes
	if sprite.material != _materials[key]: sprite.material = _materials[key]
	for slot: String in Dye.SLOTS:
		sprite.set_instance_shader_parameter(slot + "_dye", canvas_color(colors[slot]) if colors.has(slot) else Vector4.ZERO)
	sprite.set_meta("equipment_dye_appearance", appearance.duplicate(true))
	return true
