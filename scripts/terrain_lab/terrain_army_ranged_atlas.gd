extends RefCounted
## Exact unshielded weapon recipes; the historical ranged paths stay compatible.
## EquipmentAtlas retains the sole bounded texture lookup/cache owner.
const Materials = preload("res://scripts/ui/weapon_materials.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const BASE_MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/ranged/v1"
const WEAPONS := ["bow_01", "crossbow_01"]
const FRAME_COUNT := 584
const EXTRA_SOURCES := ["res://scripts/tools/bake_terrain_army_ranged.gd", "res://scripts/terrain_lab/terrain_army_ranged_atlas.gd"]
static var _root_path := ROOT
static var _base := {}
static var _sources := {}
static var _recipes := {}
static var _rejected := {}

static func fingerprints() -> Dictionary:
	var result := Plan.fingerprints()
	if result.is_empty():
		return {}
	for path: String in EXTRA_SOURCES:
		var digest := FileAccess.get_md5(path)
		if digest.length() != 32:
			return {}
		result[path] = digest
	return result

static func set_root_path(path: String) -> bool:
	var clean := path.simplify_path().trim_suffix("/")
	if clean != ROOT and not clean.begins_with("res://output/"):
		return false
	_root_path = clean
	_recipes.clear()
	_rejected.clear()
	_sources.clear()
	return true

static func plan(weapon: String, baseline: Dictionary) -> Dictionary:
	if not supports_weapon(weapon) or not baseline.get("appearance") is Dictionary or not baseline.get("clips") is Array or not baseline.get("directions") is Array:
		return {}
	var appearance: Dictionary = baseline.appearance.duplicate(true)
	if appearance.get("body") != 0 or appearance.get("mounted") != false or not appearance.get("parts") is Dictionary:
		return {}
	for slot: String in ["armor", "outfit", "boots"]:
		if appearance.parts.get(slot) != {"armor": "armor_light_leather_01", "outfit": "outfit_underlayer_01", "boots": "boots_leather_01"}[slot]:
			return {}
	appearance.parts.weapon = weapon
	appearance.parts.shield = "none"
	var wanted: Array = Plan.COMMON_CLIPS.duplicate()
	wanted.append("attack_unarmed")
	wanted.append(str(Materials.ATTACKS[Materials.family(StringName(weapon))]))
	var clips: Array[Dictionary] = []
	var total := 0
	for clip: Dictionary in baseline.clips:
		if str(clip.get("id", "")) not in wanted:
			continue
		var selected := clip.duplicate(true)
		selected.erase("weapon")
		selected.erase("shield")
		if reference_clip(weapon, str(clip.id)) != str(clip.id):
			selected.pose = guard_pose(weapon, str(clip.id))
		clips.append(selected)
		total += int(selected.samples) * 4
	if clips.size() != wanted.size() or total != FRAME_COUNT or baseline.directions.size() != 4:
		return {}
	var ids: Array[String] = []
	for direction: Dictionary in baseline.directions:
		ids.append(str(direction.get("id", "")))
	if ids != ["down", "left", "up", "right"]:
		return {}
	return {"key": "standard_soldier_ranged_v1/" + weapon, "appearance": appearance,
		"clips": clips, "directions": baseline.directions.duplicate(true), "recipe_total": total}

static func supports_weapon(weapon: String) -> bool:
	for option: Dictionary in Materials.OPTIONS:
		if option.id == weapon: return weapon != "none"
	return false

static func guard_pose(weapon: String, clip: String) -> String:
	if not clip.begins_with("guard") or Materials.is_ranged(StringName(weapon)): return clip
	return clip.replace("guard", "guard_polearm" if Materials.is_polearm(StringName(weapon)) else "guard_weapon")

static func reference_clip(weapon: String, clip: String) -> String:
	var pose := guard_pose(weapon, clip)
	if pose == "guard_weapon": return "guard_unshielded"
	if pose == "guard_polearm": return "guard_spear"
	return pose

static func recipe(appearance: Dictionary) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(appearance) or not DyeAtlas.supports(appearance): return {}
	appearance = DyeAtlas.Dye.geometry_appearance(appearance)
	if not appearance.get("parts") is Dictionary:
		return {}
	var weapon := str(appearance.parts.get("weapon", ""))
	if not supports_weapon(weapon) or not _load_base():
		return {}
	var expected := plan(weapon, _base)
	if expected.is_empty() or appearance != expected.appearance:
		return {}
	if _recipes.has(weapon):
		return _recipes[weapon]
	if _rejected.has(weapon):
		return {}
	_rejected[weapon] = true
	var directory := _root_path + "/" + weapon + "/"
	var path := directory + "manifest.json"
	if not FileAccess.file_exists(path):
		return {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary:
		return {}
	var batches: Array[Dictionary] = []
	if manifest.get("kind") == "terrain_army_ranged_batch":
		batches.append(manifest)
	elif manifest.get("kind") == "terrain_army_ranged_recipe" and manifest.get("schema_version") == 1 and manifest.get("weapon") == weapon and manifest.get("batches") is Array:
		if manifest.batches.is_empty() or manifest.batches.size() > 8:
			return {}
		for batch_path: Variant in manifest.batches:
			if not batch_path is String or not _inside(batch_path, directory) or not FileAccess.file_exists(batch_path):
				return {}
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(batch_path))
			if not parsed is Dictionary:
				return {}
			batches.append(parsed)
	var admitted := validate_batches(weapon, batches, directory)
	if not admitted.is_empty():
		_recipes[weapon] = admitted
		_rejected.erase(weapon)
	return admitted

static func validate_batches(weapon: String, batches: Array[Dictionary], directory: String) -> Dictionary:
	if batches.is_empty() or batches.size() > 8 or not _load_base():
		return {}
	var expected_plan := plan(weapon, _base)
	if expected_plan.is_empty():
		return {}
	if _sources.is_empty():
		_sources = fingerprints()
	if _sources.is_empty():
		return {}
	var expected := {}
	var references := {}
	for source: Dictionary in _base.frames:
		references["%s|%s|%d" % [source.clip, source.direction, int(source.frame)]] = source
	for clip: Dictionary in expected_plan.clips:
		for direction: Dictionary in expected_plan.directions:
			for index: int in int(clip.samples):
				expected["%s|%s|%d" % [clip.id, direction.id, index]] = {"clip": clip, "index": expected.size()}
	var seen := {}
	for batch: Dictionary in batches:
		if batch.get("schema_version") != 1 or batch.get("kind") != "terrain_army_ranged_batch" or batch.get("recipe_key") != expected_plan.key or batch.get("appearance") != expected_plan.appearance or batch.get("source_manifest_md5") != FileAccess.get_md5(BASE_MANIFEST) or batch.get("source_fingerprints") != _sources:
			return {}
		if batch.get("clips") != expected_plan.clips or batch.get("directions") != expected_plan.directions or not batch.get("frames") is Array or not batch.get("pages") is Array or batch.pages.size() != 1 or not batch.get("batch") is Dictionary:
			return {}
		var selection: Dictionary = batch.batch
		if selection.get("recipe_total") != FRAME_COUNT or selection.get("selected_total") != FRAME_COUNT or not _integer(selection.get("first"), 0, FRAME_COUNT - 1) or not _integer(selection.get("count"), 1, FRAME_COUNT) or selection.count != batch.frames.size() or int(selection.first) + int(selection.count) > FRAME_COUNT:
			return {}
		if not _number(batch.get("map_scale")) or not is_equal_approx(float(batch.map_scale), float(_base.map_scale)):
			return {}
		var metrics: Variant = batch.get("metrics")
		if not metrics is Dictionary or str(metrics.get("pixel_sha256", "")).length() != 64 or metrics.get("pixel_sha256") != metrics.get("png_decoded_sha256") or metrics.get("pixel_sha256") != metrics.get("resource_decoded_sha256"):
			return {}
		var page: Variant = batch.pages[0]
		if not page is Dictionary or page.get("page") != 0 or not _integer(page.get("width"), 1, 16384) or not _integer(page.get("height"), 1, 16384):
			return {}
		if not _inside(str(page.get("path", "")), directory) or not _inside(str(page.get("resource_path", "")), directory) or not FileAccess.file_exists(page.path) or not FileAccess.file_exists(page.resource_path):
			return {}
		for value: Variant in batch.frames:
			if not value is Dictionary or not _integer(value.get("frame"), 0, 32) or value.get("page") != 0:
				return {}
			var key := "%s|%s|%d" % [str(value.get("clip", "")), str(value.get("direction", "")), int(value.frame)]
			if not expected.has(key) or seen.has(key) or value.get("selection_index") != expected[key].index or int(value.selection_index) < int(selection.first) or int(value.selection_index) >= int(selection.first) + int(selection.count):
				return {}
			var reference_key := "%s|%s|%d" % [reference_clip(weapon, str(value.clip)), value.direction, int(value.frame)]
			var reference_frame: Dictionary = references.get(reference_key, {})
			var clip: Dictionary = expected[key].clip
			if reference_frame.is_empty() or not _number(value.get("duration")) or not _number(value.get("sample_time")) or absf(float(value.duration) - float(reference_frame.duration)) > 0.000001 or absf(float(value.sample_time) - float(reference_frame.sample_time)) > 0.000001 or value.get("resolved_pose") != str(clip.get("pose", clip.id)):
				return {}
			var rect: Variant = value.get("rect")
			var anchor: Variant = value.get("anchor_offset")
			if not rect is Dictionary or not anchor is Dictionary or not _integer(rect.get("x"), 0, int(page.width)) or not _integer(rect.get("y"), 0, int(page.height)) or not _integer(rect.get("w"), 1, int(page.width)) or not _integer(rect.get("h"), 1, int(page.height)) or int(rect.x) + int(rect.w) > int(page.width) or int(rect.y) + int(rect.h) > int(page.height) or not _number(anchor.get("x")) or not _number(anchor.get("y")):
				return {}
			var selected: Dictionary = value.duplicate(true)
			selected._page = page
			seen[key] = selected
	if seen.size() != FRAME_COUNT:
		return {}
	var sequences := {}
	for clip: Dictionary in expected_plan.clips:
		for direction: Dictionary in expected_plan.directions:
			var sequence: Array[Dictionary] = []
			for index: int in int(clip.samples):
				sequence.append(seen["%s|%s|%d" % [clip.id, direction.id, index]])
			sequences[str(clip.id) + "|" + str(direction.id)] = sequence
	return {"sequences": sequences, "map_scale": float(_base.map_scale)}

static func _load_base() -> bool:
	if not _base.is_empty():
		return true
	if not FileAccess.file_exists(BASE_MANIFEST):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_MANIFEST))
	if not parsed is Dictionary or not parsed.get("frames") is Array or not _number(parsed.get("map_scale")):
		return false
	_base = parsed
	return true

static func _inside(path: String, directory: String) -> bool:
	return path == path.simplify_path() and path.begins_with(directory) and not path.ends_with("/")

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum
