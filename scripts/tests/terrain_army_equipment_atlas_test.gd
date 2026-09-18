extends SceneTree
## Synthetic metadata exercises admission/lookup, not every rendered pose.
const Reader = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const SAMPLE := "res://output/terrain_army_missing_gear_20260913/m00_down_get_up_down_000_024/manifest.json"
const DIRECTORY := "res://output/terrain_army_missing_gear_20260913/"

func _batches(mask: int, baseline: Dictionary, sample: Dictionary, iron: int = 0) -> Array[Dictionary]:
	var clips: Array[Dictionary] = []
	clips.assign(baseline.clips)
	var directions: Array[Dictionary] = []
	directions.assign(baseline.directions)
	var plan := Plan.build(PackedStringArray(["--recipe-mask=%d" % mask, "--recipe-iron=%d" % iron, "--recipe-output=" + DIRECTORY + "unused", "--recipe-clips=all", "--recipe-directions=all", "--recipe-first=0", "--recipe-count=128"]), clips, directions, baseline.appearance)
	var originals := {}
	for original: Dictionary in baseline.frames:
		originals["%s|%s|%d" % [original.clip, original.direction, int(original.frame)]] = original
	var frames: Array[Dictionary] = []
	for clip: Dictionary in plan.clips:
		for direction: Dictionary in plan.directions:
			for index: int in int(clip.samples):
				var source := str(clip.id)
				var pose := str(clip.get("pose", clip.id))
				if (mask & 3) == 1 and source.begins_with("guard"):
					source = "guard_unshielded" if source == "guard" else source.replace("guard", "guard_weapon")
					pose = pose.replace("guard", "guard_weapon")
				var value: Dictionary = originals["%s|%s|%d" % [source, direction.id, index]].duplicate(true)
				value.erase("collision_index")
				value.clip = clip.id
				value.resolved_pose = pose
				value.page = 0
				value.rect = {"x": 0, "y": 0, "w": 1, "h": 1}
				frames.append(value)
	var batches: Array[Dictionary] = []
	for first: int in range(0, frames.size(), 128):
		var batch := sample.duplicate(true)
		batch.recipe_key = Plan.recipe_key(mask, iron)
		batch.recipe_mask = mask
		batch.recipe_iron = iron
		batch.appearance = plan.appearance
		batch.frames = frames.slice(first, mini(first + 128, frames.size()))
		batch.batch.first = first
		batch.batch.count = batch.frames.size()
		batch.batch.selected_total = frames.size()
		batch.batch.recipe_total = frames.size()
		batch.batch.selection_complete = batch.frames.size() == frames.size()
		batch.batch.recipe_complete = batch.frames.size() == frames.size()
		batches.append(batch)
	return batches

func _initialize() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE))
	# This fixture deliberately constructs metadata; the 24-frame image is only
	# a tiny page resource for cache checks, not proof of all these poses.
	sample.source_fingerprints = Plan.fingerprints()
	sample.source_manifest_md5 = FileAccess.get_md5(Reader.BASE_MANIFEST)
	assert(Reader.set_catalog_path(DIRECTORY + "absent_catalog.json"))
	assert(not Reader.supports(sample.appearance), "An absent catalog or partial batch is never publishable")
	assert(Reader.validate_batches(0, [sample], DIRECTORY).is_empty())
	for mask: int in [0, 1, 31]:
		var batches := _batches(mask, baseline, sample)
		var admitted := Reader.validate_batches(mask, batches, DIRECTORY)
		assert(not admitted.is_empty() and admitted.sequences.size() == baseline.directions.size() * (Plan.COMMON_CLIPS.size() + 1))
		Reader._recipes[Plan.recipe_key(mask)] = admitted
		var appearance := Plan.appearance_for(mask, baseline.appearance)
		assert(Reader.supports(appearance))
		var first := Reader.frame(appearance, "down", "down", 0.0)
		var same := Reader.frame(appearance, "down", "down", 0.1)
		assert(first.frame == 0 and first.texture == same.texture, "AtlasTexture is shared across users of a sample")
		assert(Reader.frame(appearance, "down", "down", 999.0).frame == 11, "Nonlooping holds final sample")
		assert(Reader.frame(appearance, "idle", "down", 0.0).frame == Reader.frame(appearance, "idle", "down", float(admitted.sequences["idle|down"][0].duration)).frame)
		if mask == 1:
			assert(Reader.frame(appearance, "guard_unshielded", "down", 0.0).resolved_pose == "guard_weapon")
		assert(Reader.frame(appearance, "attack_spear", "down", 0.0).is_empty())
		assert(not Reader.frame(appearance, "attack_jump_heavy", "down", 0.0).is_empty())
		assert(Reader.frame(appearance, "down", "unknown", 0.0).is_empty())
		assert(Reader.frame(appearance, "down", "down", NAN).is_empty())
		var corrupt := batches.duplicate(true)
		corrupt.back().frames.pop_back()
		corrupt.back().batch.count -= 1
		assert(Reader.validate_batches(mask, corrupt, DIRECTORY).is_empty(), "Missing wake/rescue tail rejected")
		corrupt = batches.duplicate(true)
		corrupt[0].frames[1] = corrupt[0].frames[0].duplicate(true)
		assert(Reader.validate_batches(mask, corrupt, DIRECTORY).is_empty(), "Duplicate key rejected")
		corrupt = batches.duplicate(true)
		corrupt[0].frames[0].sample_time = 0.1
		assert(Reader.validate_batches(mask, corrupt, DIRECTORY).is_empty(), "Retimed pose rejected")
		corrupt = batches.duplicate(true)
		corrupt[0].frames[0].rect.x = 999999
		assert(Reader.validate_batches(mask, corrupt, DIRECTORY).is_empty(), "Out-of-page rectangle rejected")
		corrupt = batches.duplicate(true)
		corrupt[0].source_fingerprints[Plan.SOURCE_PATHS[0]] = "stale-source"
		assert(Reader.validate_batches(mask, corrupt, DIRECTORY).is_empty(), "Mixed original sources rejected")
	for iron in range(1, 8):
		var batches := _batches(31, baseline, sample, iron)
		var admitted := Reader.validate_batches(31, batches, DIRECTORY, iron)
		assert(not admitted.is_empty())
		Reader._recipes[Plan.recipe_key(31, iron)] = admitted
		var appearance := Plan.appearance_for(31, baseline.appearance, iron)
		assert(Reader.supports(appearance))
		assert(Reader.frame(appearance, "guard", "down", 0.1).resolved_pose == "guard")
		var wrong := batches.duplicate(true)
		wrong[0].appearance.parts.armor = "armor_steel_01"
		assert(Reader.validate_batches(31, wrong, DIRECTORY, iron).is_empty(), "Iron/steel mismatch rejected")
		wrong = batches.duplicate(true)
		wrong[0].recipe_iron = 0
		assert(Reader.validate_batches(31, wrong, DIRECTORY, iron).is_empty(), "Wrong iron identity rejected")
		wrong = batches.duplicate(true)
		wrong[0].recipe_key = Plan.recipe_key(31)
		assert(Reader.validate_batches(31, wrong, DIRECTORY, iron).is_empty(), "Original leather recipe cannot masquerade as iron")
	var altered: Dictionary = baseline.appearance.duplicate(true)
	altered.parts.weapon = "spear_01"
	assert(not Reader.supports(altered))
	assert(Reader._page_bytes == 3080192 and Reader._pages.size() == 1, "Only requested page is decoded and shared, not the whole pack")
	assert(not Reader.set_catalog_path("res://assets/unapproved/catalog.json"))
	Reader.set_catalog_path(Reader.CATALOG)
	print("TERRAIN ARMY EQUIPMENT ATLAS PASS: complete dynamic-key admission including jump heavy, exact samples, sparse shared texture lookup; synthetic metadata only")
	quit(0)
