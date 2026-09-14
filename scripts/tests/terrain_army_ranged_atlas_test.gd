extends SceneTree
## Synthetic metadata verifies admission, never substitutes for baked pose QA.
const Reader = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")

func _initialize() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	var directory := Reader.BASE_MANIFEST.get_base_dir() + "/"
	var sources := Reader.fingerprints()
	assert(not sources.is_empty())
	assert(Reader.plan("longsword_01", baseline).is_empty())
	assert(not Reader.set_root_path("res://assets/unapproved"))
	assert(Reader.set_root_path("res://output/site_ranged_20260914/absent"))
	for weapon: String in Reader.WEAPONS:
		var plan := Reader.plan(weapon, baseline)
		assert(plan.recipe_total == 584 and plan.clips.size() == 19)
		assert(plan.appearance.parts.weapon == weapon and plan.appearance.parts.shield == "none")
		assert(plan.appearance.parts.armor == baseline.appearance.parts.armor)
		assert(Reader.recipe(plan.appearance).is_empty(), "An absent manifest cannot admit a ranged recipe")
		var batch := _fixture(baseline, plan, sources)
		var admitted := Reader.validate_batches(weapon, [batch], directory)
		assert(not admitted.is_empty() and admitted.sequences.size() == 76)
		assert(admitted.sequences["attack_unarmed|down"][0]._page.resource_path == baseline.atlas.resource_path)
		assert(admitted.sequences.has(("attack_bow" if weapon == "bow_01" else "attack_crossbow") + "|up"))
		assert(not admitted.sequences.has("walk_slash|down"), "Ranged melee never silently swaps to sword artwork")
		Reader._recipes[weapon] = admitted
		assert(not Reader.recipe(plan.appearance).is_empty())
		for slot: String in ["shield", "armor", "hair"]:
			var wrong: Dictionary = plan.appearance.duplicate(true)
			wrong.parts[slot] = "unapproved"
			assert(Reader.recipe(wrong).is_empty(), "Only the complete exact ranged appearance is admitted")
		var split: Array[Dictionary] = []
		for first in range(0, Reader.FRAME_COUNT, 128):
			var part := batch.duplicate(true)
			part.frames = batch.frames.slice(first, mini(first + 128, Reader.FRAME_COUNT))
			part.batch.first = first
			part.batch.count = part.frames.size()
			split.append(part)
		assert(not Reader.validate_batches(weapon, split, directory).is_empty())
		for failure in range(10):
			var wrong := batch.duplicate(true)
			match failure:
				0: wrong.frames.pop_back(); wrong.batch.count -= 1
				1: wrong.frames[1] = wrong.frames[0].duplicate(true)
				2: wrong.frames[0].sample_time = 0.125
				3: wrong.frames[0].rect.w = 20000
				4: wrong.source_fingerprints[Reader.EXTRA_SOURCES[0]] = "stale"
				5: wrong.appearance.parts.shield = "shield_heater_01"
				6: wrong.pages[0].resource_path = directory + "absent.res"
				7: wrong.pages[0].path = directory + "../escape.png"
				8: wrong.frames[0].selection_index = 1
				9: wrong.metrics.resource_decoded_sha256 = "mismatch"
			assert(Reader.validate_batches(weapon, [wrong], directory).is_empty(), "Reject malformed ranged batch %d" % failure)
	assert(Reader.set_root_path(Reader.ROOT))
	print("TERRAIN ARMY RANGED ATLAS PASS: 2 exact appearances, 584 samples each, 76 sequences, missing/mixed/duplicate/path/pixel metadata rejection; synthetic metadata only")
	quit(0)

func _fixture(baseline: Dictionary, plan: Dictionary, sources: Dictionary) -> Dictionary:
	var references := {}
	for value: Dictionary in baseline.frames:
		references["%s|%s|%d" % [value.clip, value.direction, int(value.frame)]] = value
	var frames: Array[Dictionary] = []
	for clip: Dictionary in plan.clips:
		for direction: Dictionary in plan.directions:
			for index: int in int(clip.samples):
				var value: Dictionary = references["%s|%s|%d" % [clip.id, direction.id, index]].duplicate(true)
				value.erase("collision_index")
				value.page = 0
				value.selection_index = frames.size()
				value.resolved_pose = str(clip.get("pose", clip.id))
				value.rect = {"x": 0, "y": 0, "w": 1, "h": 1}
				frames.append(value)
	var page: Dictionary = baseline.atlas.duplicate(true)
	page.page = 0
	var digest := "0".repeat(64)
	return {"schema_version": 1, "kind": "terrain_army_ranged_batch", "recipe_key": plan.key,
		"appearance": plan.appearance, "source_manifest_md5": FileAccess.get_md5(Reader.BASE_MANIFEST),
		"source_fingerprints": sources, "map_scale": baseline.map_scale, "clips": plan.clips,
		"directions": plan.directions, "pages": [page], "frames": frames,
		"batch": {"first": 0, "count": frames.size(), "selected_total": Reader.FRAME_COUNT, "recipe_total": Reader.FRAME_COUNT},
		"metrics": {"pixel_sha256": digest, "png_decoded_sha256": digest, "resource_decoded_sha256": digest}}
