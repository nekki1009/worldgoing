extends RefCounted
## Offline selection only. Recipes never own runtime people, items or contacts.

const SLOTS := ["weapon", "shield", "armor", "outfit", "boots"]
const MAX_BATCH_FRAMES := 128
const COMMON_CLIPS := ["idle", "combat_idle", "walk", "run", "combat_walk", "combat_run", "guard", "guard_raise", "guard_lower", "guard_break", "hit", "hit_back", "knockback", "down", "unconscious", "get_up", "rescue"]
const FLAGS := ["mask", "output", "clips", "directions", "first", "count"]
const IRON_PARTS := {"helmet": "helmet_western_iron_01", "armor": "armor_western_iron_01", "boots": "boots_western_iron_01"}
const SOURCE_PATHS := [
	"res://assets/characters/human/q35/standard_anime_male_character_pack.glb",
	"res://assets/characters/human/q35/standard_anime_female_character_pack.glb",
	"res://scripts/ui/human_character_3d_editor.gd",
	"res://scripts/ui/equipment_dye.gd",
	"res://scripts/terrain_lab/character_combat_timings.gd",
	"res://scripts/tools/bake_terrain_army_soldier.gd",
	"res://scripts/tools/terrain_army_recipe_bake_plan.gd",
]

static func fingerprints() -> Dictionary:
	var result := {}
	for path: String in SOURCE_PATHS:
		var digest := FileAccess.get_md5(path)
		if digest.length() != 32:
			return {}
		result[path] = digest
	return result

static func recipe_key(mask: int, iron: int = 0) -> String:
	return "standard_soldier_v2/" + ("iron%d/" % iron if iron != 0 else "") + "m%02d" % mask

static func appearance_for(mask: int, original: Dictionary, iron: int = 0) -> Dictionary:
	var result := original.duplicate(true)
	for bit: int in IRON_PARTS.size():
		if (iron & (1 << bit)) != 0:
			var slot: String = IRON_PARTS.keys()[bit]
			result.parts[slot] = IRON_PARTS[slot]
	for bit: int in SLOTS.size():
		if (mask & (1 << bit)) == 0:
			result.parts[SLOTS[bit]] = "none"
	return result

static func build(arguments: PackedStringArray, original_clips: Array[Dictionary], original_directions: Array[Dictionary], original_appearance: Dictionary) -> Dictionary:
	var flags := {}
	for argument: String in arguments:
		var pair := argument.split("=", true, 1)
		if pair.size() != 2 or not pair[0].begins_with("--recipe-"):
			return _error("Recipe mode accepts only explicit --recipe-name=value arguments")
		var key := pair[0].trim_prefix("--recipe-")
		if (key not in FLAGS and key != "iron") or flags.has(key) or pair[1].is_empty():
			return _error("Unknown, duplicate or empty recipe argument: " + argument)
		flags[key] = pair[1]
	if not flags.has_all(FLAGS):
		return _error("Recipe mode requires mask, output, clips, directions, first and count")
	for key: String in ["mask", "first", "count"]:
		if not str(flags[key]).is_valid_int():
			return _error("Recipe " + key + " must be an integer")
	var mask := int(flags.mask)
	var first := int(flags.first)
	var count := int(flags.count)
	if not str(flags.get("iron", "0")).is_valid_int():
		return _error("Recipe iron selection must be an integer")
	var iron := int(flags.get("iron", "0"))
	if iron < 0 or iron > 7:
		return _error("Recipe iron selection must be 0..7 (helmet, armor, boots)")
	if ((iron & 2) != 0 and (mask & 4) == 0) or ((iron & 4) != 0 and (mask & 16) == 0):
		return _error("Iron selections must name equipped parts, not removed mask slots")
	if mask < 0 or mask > 31 or first < 0 or count < 1 or count > MAX_BATCH_FRAMES:
		return _error("Recipe mask must be 0..31; batch first >=0 and count 1..128")
	var output := str(flags.output).simplify_path().trim_suffix("/")
	if not output.begins_with("res://output/") or output == "res://output":
		return _error("Recipe output must be a named staging directory under res://output/")
	if not original_appearance.get("parts", {}) is Dictionary:
		return _error("Source soldier appearance has no actual parts")
	for slot: String in SLOTS:
		if str(original_appearance.parts.get(slot, "none")) == "none":
			return _error("Source soldier recipe must contain its original " + slot)
	var allowed: Array[String] = []
	allowed.assign(COMMON_CLIPS)
	allowed.append("walk_slash" if (mask & 1) != 0 else "attack_unarmed")
	var wanted_clips := _selection(str(flags.clips), allowed)
	var direction_ids: Array[String] = []
	for direction: Dictionary in original_directions:
		direction_ids.append(str(direction.id))
	var wanted_directions := _selection(str(flags.directions), direction_ids)
	if wanted_clips.is_empty() or wanted_directions.is_empty():
		return _error("Unknown, duplicate or incompatible recipe clip/direction selection")
	var clips: Array[Dictionary] = []
	var directions: Array[Dictionary] = []
	var selected_count := 0
	var recipe_count := 0
	for clip: Dictionary in original_clips:
		if str(clip.id) in allowed:
			recipe_count += int(clip.samples) * original_directions.size()
		if str(clip.id) in wanted_clips:
			# Keep the original logical ID, sample count, pose and rate, but no
			# clip is allowed to force a missing part back into this recipe.
			var selected := clip.duplicate(true)
			selected.erase("weapon")
			selected.erase("shield")
			clips.append(selected)
			selected_count += int(clip.samples) * wanted_directions.size()
	for direction: Dictionary in original_directions:
		if str(direction.id) in wanted_directions:
			directions.append(direction.duplicate(true))
	if clips.size() != wanted_clips.size() or first + count > selected_count:
		return _error("Recipe batch exceeds selected frames or source clips are missing")
	return {"ok": true, "key": recipe_key(mask, iron), "mask": mask, "iron": iron, "output": output,
		"appearance": appearance_for(mask, original_appearance, iron), "clips": clips, "directions": directions,
		"first": first, "count": count, "selected_total": selected_count, "recipe_total": recipe_count,
		"selection_complete": first == 0 and count == selected_count,
		"recipe_complete": first == 0 and count == recipe_count and selected_count == recipe_count}

static func _selection(value: String, allowed: Array[String]) -> Array[String]:
	if value == "all":
		return allowed.duplicate()
	var result: Array[String] = []
	for id: String in value.split(","):
		if id not in allowed or id in result:
			return []
		result.append(id)
	return result

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
